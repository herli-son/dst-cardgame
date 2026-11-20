-- Testes da US #41: o servidor decide as jogadas.
--
-- O jogo não roda aqui. Um transporte falso em memória faz o papel das RPCs
-- de mod (AddModRPCHandler, SendModRPCToServer, AddClientModRPCHandler,
-- SendModRPCToClient, GetModRPC, GetClientModRPC) e liga várias "máquinas":
-- um servidor (dedicado ou host) e os clientes. Cada máquina carrega cópias
-- novas de duelo/mod/rede.lua, partida_servidor.lua e partida_cliente.lua
-- (os módulos guardam estado em locais do arquivo), com um GLOBAL falso
-- (TheNet, ThePlayer, AllPlayers). As RPCs são entregues na hora, na ordem.
--
-- Quem escolhe as jogadas nos testes é o bot (ou o sorteio) do simulador,
-- olhando a partida do servidor; a jogada escolhida sai sempre pelo cliente
-- daquele lado, como texto, pela RPC falsa.

local Game = require("duelo/core/game")
local Replay = require("duelo/core/replay")
local Serial = require("duelo/core/serial")
local Simulador = require("duelo/sim/simulador")
local Jogadas = require("duelo/bot/jogadas")
local Bot = require("duelo/bot/bot")
local Decks = require("duelo/decks/init")
local Visao = require("duelo/mod/visao")

local RAIZ = "./"

local function carregar(nome)
  local fn, err = loadfile(RAIZ .. "scripts/duelo/mod/" .. nome .. ".lua")
  assert(fn, err)
  return fn()
end

----------------------------------------------------------------------------
-- Transporte falso
----------------------------------------------------------------------------

local function nova_rede()
  local net = {
    maquinas = {},      -- todas, na ordem de criação
    servidor = nil,     -- a máquina que é servidor
    jogadores = {},     -- AllPlayers do servidor
    relogio = 0,
    perder = nil,       -- fn(userid, tipo, id, i, total) -> true: o pedaço some
    mensagens = {},     -- userid -> lista de { tipo = , m = tabela } recebidas
    pedacos = {},       -- todos os pedaços enviados: { userid, tipo, bytes }
    rpcs_servidor = {}, -- nome -> quantas chegaram ao servidor
    _juntando = {},
  }

  local function observar(userid, tipo, id, i, total, pedaco)
    net.pedacos[#net.pedacos + 1] = { userid = userid, tipo = tipo, bytes = #pedaco }
    local chave = userid .. "/" .. tipo
    if i == 1 then net._juntando[chave] = {} end
    local partes = net._juntando[chave]
    partes[i] = pedaco
    if i == total then
      net.mensagens[userid] = net.mensagens[userid] or {}
      table.insert(net.mensagens[userid], { tipo = tipo, m = Serial.deserialize(table.concat(partes)) })
    end
  end

  -- opts.servidor: roda a partida; opts.userid: tem jogador local (cliente
  -- ou host); opts.lado: valor da netvar duelo_lado do jogador.
  function net:maquina(opts)
    local m = { net = net, userid = opts.userid, logs = {}, srv = {}, cli = {} }
    local jogador = nil
    if opts.userid then
      jogador = { userid = opts.userid }
      if opts.lado then jogador.duelo_lado = { value = function() return opts.lado end } end
      function jogador:ListenForEvent(nome, fn) self.eventos = self.eventos or {}; self.eventos[nome] = fn end
      net.jogadores[#net.jogadores + 1] = jogador
    end
    m.jogador = jogador
    m.GLOBAL = {
      TheNet = { GetIsServer = function() return opts.servidor == true end },
      ThePlayer = jogador,
      AllPlayers = opts.servidor and net.jogadores or {},
      -- O relógio da simulação fica parado (servidor pausado): a taxa e as
      -- retentativas usam o tempo real.
      GetTime = function() return 0 end,
      GetTimeRealSeconds = function() return net.relogio end,
      print = function(s) m.logs[#m.logs + 1] = tostring(s) end,
    }
    local ctx = {
      GLOBAL = m.GLOBAL,
      AddModRPCHandler = function(ns, nome, fn) m.srv[nome] = fn; m.ordem = (m.ordem or "") .. "s:" .. nome .. ";" end,
      AddClientModRPCHandler = function(ns, nome, fn) m.cli[nome] = fn; m.ordem = (m.ordem or "") .. "c:" .. nome .. ";" end,
      GetModRPC = function(ns, nome) assert(m.srv[nome], "RPC não registrada: " .. nome); return { namespace = ns, id = nome } end,
      GetClientModRPC = function(ns, nome) assert(m.cli[nome], "RPC não registrada: " .. nome); return { namespace = ns, id = nome } end,
      SendModRPCToServer = function(rpc, ...)
        assert(not opts.servidor, "o servidor não manda RPC para si mesmo")
        net.rpcs_servidor[rpc.id] = (net.rpcs_servidor[rpc.id] or 0) + 1
        net.servidor.srv[rpc.id](jogador, ...)
      end,
      SendModRPCToClient = function(rpc, users, id, i, total, pedaco)
        assert(opts.servidor, "só o servidor manda RPC de cliente")
        if type(users) ~= "table" then users = { users } end
        for _, userid in ipairs(users) do
          assert(userid ~= m.userid, "o host não manda RPC para o próprio jogador")
          observar(userid, rpc.id, id, i, total, pedaco)
          if not (net.perder and net.perder(userid, rpc.id, id, i, total)) then
            for _, outra in ipairs(net.maquinas) do
              if outra.userid == userid and outra ~= m then outra.cli[rpc.id](id, i, total, pedaco) end
            end
          end
        end
      end,
    }
    m.ctx = ctx
    m.Rede = carregar("rede").instalar(ctx)
    if opts.servidor then
      m.Partida = carregar("partida_servidor").instalar({ rede = m.Rede, GLOBAL = m.GLOBAL })
      net.servidor = m
    end
    if opts.userid then
      m.Cliente = carregar("partida_cliente").instalar({ rede = m.Rede, GLOBAL = m.GLOBAL })
    end
    net.maquinas[#net.maquinas + 1] = m
    return m
  end

  return net
end

-- Servidor dedicado, dois jogadores e um espectador.
local function mesa(opts)
  opts = opts or {}
  local net = nova_rede()
  local s = net:maquina{ servidor = true }
  local c1 = net:maquina{ userid = "KU_um", lado = 1 }
  local c2 = net:maquina{ userid = "KU_dois", lado = 2 }
  local c3 = net:maquina{ userid = "KU_tres", lado = 3 }
  if opts.fragmento then s.Rede.LIMITES.FRAGMENTO = opts.fragmento end
  return net, s, { c1, c2, c3 }
end

local function decks_reais()
  local d1, e1 = Decks.build("wilson")
  local d2, e2 = Decks.build("webber")
  return { d1, d2 }, { e1, e2 }
end

local function iniciar(s, extra)
  local decks, extras = decks_reais()
  local o = { decks = decks, extra_decks = extras, seed = 7, jogadores = { "KU_um", "KU_dois" } }
  for k, v in pairs(extra or {}) do o[k] = v end
  local ok, err = s.Partida.iniciar(o)
  assert(ok, tostring(err))
  return s.Partida.jogo()
end

local function igual(a, b)
  return Serial.serialize(a) == Serial.serialize(b)
end

-- A visão de cada cliente é igual à fotografia que o servidor tiraria agora.
-- `conta` (opcional) soma as conferências feitas com escolha pendente e com
-- a pilha aberta, para o teste afirmar que essas situações foram comparadas.
local function conferir_visoes(T, s, clientes, onde, conta)
  local g = s.Partida.jogo()
  if conta then
    conta.total = (conta.total or 0) + 1
    if g.pending_choice then conta.escolha = (conta.escolha or 0) + 1 end
    if #(g.stack or {}) > 0 then conta.pilha = (conta.pilha or 0) + 1 end
  end
  for lado, c in ipairs(clientes) do
    local esperado = Visao.estado_para(g, lado)
    local d = Replay.first_diff(c.Cliente.visao(), esperado, "visao")
    T.ok(d == nil, "visão do lado " .. lado .. " diferente da do servidor (" .. onde .. "): " .. tostring(d))
    T.eq(c.Cliente.lado(), lado, "lado do cliente")
  end
end

local function quem_age(g)
  return g.pending_choice and g.pending_choice.player or g.active
end

local function jogador_bot(rng)
  local bot = Bot.new{ rng = rng }
  return function(g, p, jogadas)
    local ok, a = pcall(bot.choose, bot, g, p, jogadas)
    if ok then return a end
    for _, j in ipairs(jogadas) do if j.type == "pass" then return j end end
  end
end

local function jogador_sorteio(rng)
  return function(g, p, jogadas) return jogadas[rng(#jogadas)] end
end

-- Joga uma partida inteira pelas RPCs falsas, com as mesmas escolhas do
-- simulador (mesmos sorteios). a_cada(passo, g) roda depois de cada ação.
local function jogar(T, s, clientes, o)
  local g = iniciar(s, { seed = o.seed, mulligan = o.mulligan })
  local fabrica = { bot = jogador_bot, random = jogador_sorteio }
  local escolher = {
    fabrica[o.tipos[1]](Simulador.make_rng(o.seed + 1)),
    fabrica[o.tipos[2]](Simulador.make_rng(o.seed + 2)),
  }
  if o.a_cada then o.a_cada(0, g) end
  if g.phase == "mulligan" then
    for p = 1, 2 do
      local n = clientes[p].Cliente.enviar({ type = "mulligan", indices = o.troca and o.troca[p] or {} })
      T.ok(n, "troca enviada")
      if o.a_cada then o.a_cada(0, g) end
    end
  end
  local passo = 0
  while g.winner == nil and g.phase == "playing" and g.round <= (o.max_rounds or 60) do
    local p = quem_age(g)
    local a = escolher[p](g, p, Jogadas.list(g, p))
    T.ok(a ~= nil, "há jogada para escolher")
    local antes = #g.log.actions
    -- O relógio anda: os testes de partida inteira não são sobre a taxa.
    s.net.relogio = s.net.relogio + 1
    T.ok(clientes[p].Cliente.enviar(a), "ação enviada")
    passo = passo + 1
    T.eq(#g.log.actions, antes + 1, "ação " .. passo .. " aceita pelo servidor (" .. Simulador.describe_action(a) .. ")")
    if o.a_cada then o.a_cada(passo, g) end
  end
  return g, passo
end

-- Todos os números guardados em chaves que apontam uma carta ou um objeto
-- (`uid`, `card_uid`, `target_uid`, qualquer `*uid`, e `objeto`), em qualquer
-- nível. Os uids de carta e de objeto em campo saem do mesmo contador do
-- motor: um número igual ao uid de uma carta escondida é essa carta.
-- Devolve uma lista de { uid = número, chave = nome }.
local function coletar_uids(v, out)
  if type(v) ~= "table" then return out end
  for k, x in pairs(v) do
    if type(k) == "string" and (k:find("uid$") or k == "objeto") and type(x) == "number" then
      out[#out + 1] = { uid = x, chave = k }
    end
    coletar_uids(x, out)
  end
  return out
end

local function tem_chave(v, chave)
  if type(v) ~= "table" then return false end
  for k, x in pairs(v) do
    if k == chave or tem_chave(x, chave) then return true end
  end
  return false
end

local function recusas(net, userid)
  local out = {}
  for _, msg in ipairs(net.mensagens[userid] or {}) do
    if msg.tipo == "recusada" then out[#out + 1] = msg.m end
  end
  return out
end

-- Conta as chamadas ao motor a partir daqui.
local function vigiar(g)
  local conta = { act = 0, can_act = 0, mulligan = 0 }
  for nome in pairs(conta) do
    local original = g[nome]
    g[nome] = function(...)
      conta[nome] = conta[nome] + 1
      return original(...)
    end
  end
  return conta
end

-- Manda um texto cru pela RPC "acao", como um cliente adulterado faria. O
-- relógio anda antes, para o limite de ações por segundo não entrar na conta.
local function manda_texto(net, c, texto, n)
  net.relogio = net.relogio + 2
  c.ctx.SendModRPCToServer(c.ctx.GetModRPC("duelo", "acao"), texto, n)
end

----------------------------------------------------------------------------
-- Casos
----------------------------------------------------------------------------

return {
  { "evento público vai inteiro e em cópia; to_hand do outro vai sem a carta", function(T)
    local ev = { t = "summon", p = 1, slot = 2, uid = 9, card_uid = 4, id = "aranha", ficha = false }
    for lado = 1, 3 do
      local c = Visao.evento_para(ev, lado)
      T.ok(c ~= ev, "é uma cópia")
      T.ok(igual(c, ev), "cópia inteira para o lado " .. lado)
    end
    local compra = { t = "to_hand", p = 1, card_uid = 12, id = "lanca", source = "baralho", private = true }
    T.ok(igual(Visao.evento_para(compra, 1), compra), "o dono recebe a carta")
    for _, lado in ipairs({ 2, 3 }) do
      local c = Visao.evento_para(compra, lado)
      T.eq(c.t, "to_hand"); T.eq(c.p, 1); T.eq(c.source, "baralho"); T.eq(c.oculto, true)
      T.eq(c.id, nil, "sem id"); T.eq(c.card_uid, nil, "sem card_uid"); T.eq(c.private, nil)
    end
  end },

  { "look só vai para o dono; reveal é público; privado nunca vai para o outro", function(T)
    local look = { t = "look", p = 2, id = "maquina_de_ciencia", uid = 30, private = true,
      cards = { { card_uid = 50, id = "lanca" } } }
    T.ok(igual(Visao.evento_para(look, 2), look), "o dono vê as cartas")
    T.eq(Visao.evento_para(look, 1), nil, "o adversário não recebe")
    T.eq(Visao.evento_para(look, 3), nil, "o espectador não recebe")
    -- Mesmo sem a marca de privado, a regra do tipo vale.
    look.private = nil
    T.eq(Visao.evento_para(look, 1), nil)
    local reveal = { t = "reveal", p = 1, card_uid = 8, id = "maquina_de_ciencia", source = "baralho", by = "wilson" }
    T.ok(igual(Visao.evento_para(reveal, 2), reveal), "reveal é público")
    -- Um tipo público marcado como privado só vai para o dono.
    local priv = { t = "play", p = 1, card_uid = 3, id = "x", cost = 1, private = true }
    T.eq(Visao.evento_para(priv, 2), nil)
    T.ok(Visao.evento_para(priv, 1) ~= nil)
  end },

  { "evento de tipo desconhecido vai para os outros sem campos e avisa no log", function(T)
    local avisos = {}
    local function avisar(s) avisos[#avisos + 1] = s end
    local ev = { t = "espiar_teste_us41", p = 1, id = "carta_secreta", card_uid = 77, cards = { "a", "b" } }
    T.ok(igual(Visao.evento_para(ev, 1, avisar), ev), "o dono recebe inteiro")
    for _, lado in ipairs({ 2, 3 }) do
      local c = Visao.evento_para(ev, lado, avisar)
      T.ok(igual(c, { t = "espiar_teste_us41", p = 1, desconhecido = true }), "só tipo e jogador para o lado " .. lado)
    end
    T.eq(#avisos, 1, "um aviso por tipo")
    T.ok(avisos[1]:find("espiar_teste_us41", 1, true), "o aviso diz o tipo")
    T.eq(Visao.evento_para({ t = "outro_teste_us41", p = 1, private = true, id = "x" }, 2, avisar), nil,
      "desconhecido e privado: não vai")
    -- Sem dono: ninguém recebe os campos, nem um jogador.
    local sem = Visao.evento_para({ t = "terceiro_teste_us41", id = "x" }, 1, avisar)
    T.ok(igual(sem, { t = "terceiro_teste_us41", desconhecido = true }))
  end },

  { "diferença entre fotografias: aplicar as mudanças dá a fotografia nova", function(T)
    local a = { x = 1, lista = { { id = "a" }, { id = "b" }, { id = "c" } }, some = { 1 }, f = false, t = { u = { v = 1 } } }
    local b = { x = 2, lista = { { id = "a" }, { id = "c" } }, novo = { k = "v" }, f = { 3 }, t = { u = false } }
    local m = Visao.diferenca(a, b)
    local c = Visao.aplicar(Visao.copiar(a), Serial.deserialize(Serial.serialize(m)))
    T.ok(igual(c, b), "depois de aplicar")
    T.eq(#Visao.diferenca(b, b), 0, "fotografias iguais: nenhuma mudança")
    local ok = pcall(Visao.aplicar, {}, { { c = { "nao", "existe" }, v = 1 } })
    T.eq(ok, false, "caminho que não existe é erro")
  end },

  { "a fotografia esconde a mão e o baralho do outro e as opções de quem não escolhe", function(T)
    local decks, extras = decks_reais()
    local g = Game.new{ decks = decks, extra_decks = extras, seed = 3, mulligan = false, first = 1 }
    g:start()
    local f1, f2, f3 = Visao.estado_para(g, 1), Visao.estado_para(g, 2), Visao.estado_para(g, 3)
    T.eq(#f1.jogadores[1].mao, #g.players[1].hand, "a própria mão")
    T.eq(f1.jogadores[1].mao[1].id, g.players[1].hand[1].id)
    T.eq(f1.jogadores[1].mao[1].card_uid, g.players[1].hand[1].uid)
    T.eq(f1.jogadores[2].mao, nil, "sem a mão do outro")
    T.eq(f1.jogadores[2].mao_n, #g.players[2].hand, "só o tamanho")
    T.eq(f1.jogadores[2].baralho_n, #g.players[2].deck)
    T.eq(f2.jogadores[1].mao, nil); T.ok(f2.jogadores[2].mao ~= nil)
    T.eq(f3.jogadores[1].mao, nil, "espectador sem mão nenhuma"); T.eq(f3.jogadores[2].mao, nil)
    T.eq(f1.rodada, 1); T.eq(f1.ativo, 1); T.eq(f1.periodo, "manha"); T.eq(f1.fase, "playing")
    T.eq(f1.jogadores[1].vida, Game.START_LIFE); T.eq(f1.jogadores[1].mana, 1)
    T.eq(#f1.jogadores[1].campo, 6); T.eq(#f1.jogadores[1].estruturas, 2)
    T.ok(Serial.serialize(f1) ~= nil, "serializável")
    -- Escolha com cartas do baralho como opções: só quem escolhe as vê.
    local carta = g.players[1].deck[#g.players[1].deck]
    g.pending_choice = { player = 1, reason = "teste", allow_none = true, options = { carta, 2 } }
    f1, f2, f3 = Visao.estado_para(g, 1), Visao.estado_para(g, 2), Visao.estado_para(g, 3)
    T.eq(f1.escolha.opcoes[1].carta, carta.id); T.eq(f1.escolha.opcoes[1].card_uid, carta.uid)
    T.eq(f1.escolha.opcoes[2].valor, 2); T.eq(f1.escolha.nenhuma, true)
    T.eq(f1.escolha.n, 2, "quem escolhe sabe quantas opções há")
    for _, f in ipairs({ f2, f3 }) do
      T.eq(f.escolha.p, 1); T.eq(f.escolha.motivo, "teste")
      T.eq(f.escolha.opcoes, nil, "sem as opções")
      T.eq(f.escolha.n, nil, "sem a quantidade de opções"); T.eq(f.escolha.nenhuma, nil)
    end
  end },

  { "sem resultado, o vencedor na visão é false (não some)", function(T)
    local net, s, cs = mesa()
    local g = iniciar(s)
    T.eq(Visao.estado_para(g, 1).vencedor, false, "false na fotografia")
    for lado, c in ipairs(cs) do T.eq(c.Cliente.visao().vencedor, false, "false no cliente do lado " .. lado) end
    local achou = false
    for _, linha in ipairs(cs[1].Cliente.resumo()) do
      if linha:find("vencedor", 1, true) then achou = true end
    end
    T.ok(not achou, "o resumo do cliente não fala de vencedor antes do fim")
    g.winner = 0
    T.eq(Visao.estado_para(g, 1).vencedor, 0, "o empate é 0")
  end },

  { "o resumo do servidor diz fogueira apagada de dia, não nil", function(T)
    local net, s = mesa()
    iniciar(s)
    local resumo = table.concat(s.Partida.resumo(), "\n")
    T.ok(resumo:find("fogueira apagada", 1, true), "de dia a fogueira está apagada")
    T.ok(not resumo:find("fogueira nil", 1, true))
  end },

  { "todas as RPCs são registradas nos dois lados, na mesma ordem", function(T)
    local net, s, cs = mesa()
    T.eq(s.ordem, "s:acao;s:pedir_estado;c:eventos;c:estado;c:recusada;")
    for _, c in ipairs(cs) do T.eq(c.ordem, s.ordem, "mesma ordem no cliente") end
  end },

  { "partida inteira bot x bot pelas RPCs termina igual à mesma partida direto no motor", function(T)
    local net, s, cs = mesa()
    local conta = {}
    local g, passos = jogar(T, s, cs, { seed = 11, tipos = { "bot", "bot" }, a_cada = function(passo)
      conferir_visoes(T, s, cs, "passo " .. passo, conta)
    end })
    conferir_visoes(T, s, cs, "fim")
    T.ok((conta.escolha or 0) > 0, "as visões foram comparadas com uma escolha pendente: " .. tostring(conta.escolha))
    T.ok((conta.pilha or 0) > 0, "as visões foram comparadas com a pilha aberta: " .. tostring(conta.pilha))
    local decks, extras = decks_reais()
    local rep, ref = Simulador.run_game{ decks = decks, extra_decks = extras, seed = 11, players = { "bot", "bot" } }
    T.ok(passos > 20, "a partida teve jogadas: " .. passos)
    T.eq(rep.jogadas, passos, "mesmo número de jogadas")
    local ok, d = Replay.same_state(ref, g)
    T.ok(ok, "estado final diferente: " .. tostring(d))
    T.eq(Serial.serialize(g.log), Serial.serialize(ref.log), "mesmo registro de partida")
    if ref.winner ~= nil then
      T.eq(cs[1].Cliente.visao().vencedor, ref.winner, "o cliente sabe quem venceu")
      T.eq(cs[3].Cliente.visao().fase, "over")
    end
    -- Cada cliente recebeu um lote por ação, mais o do início.
    for _, c in ipairs(cs) do T.eq(c.Cliente.seq(), passos + 1, "lotes recebidos") end
    T.eq(net.rpcs_servidor.pedir_estado, nil, "ninguém precisou pedir o estado")
  end },

  { "os eventos chegam aos ouvintes na ordem, filtrados para o lado de cada um", function(T)
    local net, s, cs = mesa()
    local vistos = { {}, {}, {} }
    local visao_errada = false
    for lado, c in ipairs(cs) do
      c.Cliente.quando_evento(function(ev, visao)
        if visao ~= c.Cliente.visao() then visao_errada = true end
        table.insert(vistos[lado], ev)
      end)
    end
    local g = jogar(T, s, cs, { seed = 5, tipos = { "bot", "bot" }, max_rounds = 4 })
    for lado = 1, 3 do
      local esperado = {}
      for _, ev in ipairs(g.events) do
        local c = Visao.evento_para(ev, lado)
        if c then esperado[#esperado + 1] = c end
      end
      T.eq(#vistos[lado], #esperado, "quantidade de eventos do lado " .. lado)
      T.ok(igual(vistos[lado], esperado), "mesmos eventos, na ordem, para o lado " .. lado)
    end
    T.ok(#vistos[1] > 30, "houve eventos")
    T.ok(not visao_errada, "o ouvinte recebe a visão local")
  end },

  { "segredo: nenhuma carta da mão ou do baralho de um jogador chega ao outro em partidas inteiras", function(T)
    local partidas = {
      { seed = 21, tipos = { "bot", "bot" } },
      { seed = 22, tipos = { "random", "random" }, mulligan = true, troca = { { 1, 3 }, { 2 } } },
      { seed = 23, tipos = { "bot", "random" } },
      { seed = 24, tipos = { "random", "bot" }, mulligan = true, troca = { {}, { 1, 2, 3, 4 } } },
      { seed = 25, tipos = { "random", "random" } },
    }
    -- Eventos do motor que tornam a carta pública (ela vai para a mesa, o
    -- descarte, as destruídas, o Inventário, o baralho extra, ou é mostrada).
    local ENTRADA = { play = true, summon = true, structure = true, equip = true, reveal = true,
      destroyed = true, vanish = true, inventory = true }
    local tipos_vistos, total_ocultos, escolhas_alheias = {}, 0, 0
    for _, o in ipairs(partidas) do
      local net, s, cs = mesa()
      local dono, publica = {}, {}
      local lidos = { 0, 0, 0 }
      local eventos_lidos = 0
      local ids = { "KU_um", "KU_dois", "KU_tres" }
      o.a_cada = function(passo, g)
        if passo == 0 and next(dono) == nil then
          for p = 1, 2 do
            for _, zona in ipairs({ "hand", "deck", "extra" }) do
              for _, c in ipairs(g.players[p][zona]) do dono[c.uid] = p end
            end
          end
        end
        for i = eventos_lidos + 1, #g.events do
          local ev = g.events[i]
          tipos_vistos[ev.t] = true
          if ENTRADA[ev.t] and ev.card_uid then publica[ev.card_uid] = true end
        end
        eventos_lidos = #g.events
        for p = 1, 2 do
          local pl = g.players[p]
          for _, zona in ipairs({ "discard", "destroyed", "inventory", "separated" }) do
            for _, c in ipairs(pl[zona]) do publica[c.uid] = true end
          end
          for _, c in pairs(pl.field) do
            publica[c.card_uid] = true
            for _, e in pairs(c.equips) do publica[e.card_uid] = true end
          end
          for _, st in pairs(pl.structures) do publica[st.card_uid] = true end
        end
        -- O que cada um recebeu desde a última conferência.
        for lado = 1, 3 do
          local msgs = net.mensagens[ids[lado]] or {}
          for i = lidos[lado] + 1, #msgs do
            local msg = msgs[i]
            for _, achado in ipairs(coletar_uids(msg.m, {})) do
              local uid = achado.uid
              -- Um card_uid é sempre de carta (as fichas, sem dono inicial,
              -- têm de ser públicas); nas outras chaves o número pode ser de
              -- um objeto em campo, e só conta se for o uid de uma carta.
              if dono[uid] ~= lado and (dono[uid] ~= nil or achado.chave == "card_uid") then
                T.ok(publica[uid], "seed " .. o.seed .. ", passo " .. passo .. ": o lado " .. lado
                  .. " recebeu em \"" .. msg.tipo .. "\", na chave " .. achado.chave .. ", a carta "
                  .. tostring(uid) .. " do lado "
                  .. tostring(dono[uid]) .. ", que nunca saiu da mão ou do baralho")
              end
            end
            for _, ev in ipairs(msg.m.eventos or {}) do
              T.ok(ev.t ~= "look" or ev.p == lado, "look só para o dono")
              if ev.t == "to_hand" and ev.p ~= lado then
                total_ocultos = total_ocultos + 1
                T.ok(ev.id == nil and ev.card_uid == nil and ev.oculto == true, "compra do outro sem a carta")
              end
              T.ok(not ev.desconhecido, "tipo de evento fora de Visao.TIPOS: " .. tostring(ev.t))
              if ev.t == "choice" and ev.p ~= lado then
                escolhas_alheias = escolhas_alheias + 1
                T.ok(igual(ev, { t = "choice", p = ev.p, reason = ev.reason }), "escolha do outro só com jogador e motivo")
              end
            end
            T.ok(not tem_chave(msg.m, "cards") or lado ~= 3, "espectador sem cartas olhadas")
            -- Na fotografia e nas mudanças, a mão só existe no próprio lado.
            if msg.tipo == "estado" and msg.m.estado then
              for p = 1, 2 do
                T.ok(p == lado or msg.m.estado.jogadores[p].mao == nil, "fotografia sem a mão do outro")
              end
              T.ok(msg.m.estado.jogadores[1].baralho == nil and msg.m.estado.jogadores[2].baralho == nil,
                "fotografia sem o conteúdo dos baralhos")
            end
            for _, mud in ipairs(msg.m.mudancas or {}) do
              if mud.c[1] == "jogadores" and mud.c[3] == "mao" then
                T.eq(mud.c[2], lado, "mudança na mão só para o dono")
              end
            end
          end
          lidos[lado] = #msgs
        end
      end
      local g = jogar(T, s, cs, o)
      T.ok(#g.events > 50, "a partida aconteceu")
      conferir_visoes(T, s, cs, "seed " .. o.seed)
    end
    T.ok(total_ocultos > 20, "houve compras escondidas: " .. total_ocultos)
    T.ok(escolhas_alheias > 0, "houve escolhas do outro lado: " .. escolhas_alheias)
    for t in pairs(tipos_vistos) do
      T.ok(Visao.TIPOS[t] ~= nil, "tipo de evento do motor fora de Visao.TIPOS: " .. t)
    end
  end },

  { "ação de quem não tem a vez é recusada, com o motivo só para quem enviou", function(T)
    local net, s, cs = mesa()
    local g = iniciar(s, { first = 1 })
    local ouvidas = {}
    cs[2].Cliente.quando_recusada(function(motivo, n) ouvidas[#ouvidas + 1] = { motivo = motivo, n = n } end)
    local antes, eventos = #g.log.actions, #g.events
    local n = cs[2].Cliente.enviar({ type = "pass" })
    T.eq(n, 1, "número da ação")
    T.eq(#g.log.actions, antes, "nada entrou no registro")
    T.eq(#g.events, eventos, "nenhum evento")
    T.eq(#ouvidas, 1); T.eq(ouvidas[1].motivo, "não é a sua vez"); T.eq(ouvidas[1].n, 1)
    T.eq(#recusas(net, "KU_dois"), 1)
    T.eq(#recusas(net, "KU_um"), 0, "o outro jogador não fica sabendo")
    T.eq(#recusas(net, "KU_tres"), 0, "nem o espectador")
    T.eq(cs[1].Cliente.seq(), 1, "nenhum lote novo"); T.eq(cs[2].Cliente.seq(), 1)
    -- Dizer que é o outro jogador não adianta: o lado vem do userid da RPC.
    cs[2].Cliente.enviar({ type = "pass", p = 1, player = 1, userid = "KU_um", lado = 1 })
    T.eq(#g.log.actions, antes); T.eq(ouvidas[2].motivo, "não é a sua vez"); T.eq(ouvidas[2].n, 2)
    -- A do jogador da vez entra, e todos recebem o lote.
    T.ok(cs[1].Cliente.enviar({ type = "pass" }))
    T.eq(#g.log.actions, antes + 1)
    T.eq(g.log.actions[#g.log.actions].p, 1)
    for _, c in ipairs(cs) do T.eq(c.Cliente.seq(), 2) end
    T.eq(#recusas(net, "KU_um"), 0)
    -- Recusa do motor (carta que não existe na mão) também volta só a quem enviou.
    cs[2].Cliente.enviar({ type = "play", hand_index = 99 })
    T.eq(ouvidas[3].motivo, "carta não está na mão")
    T.eq(#g.log.actions, antes + 1)
  end },

  { "ação malformada, gigante ou de espectador é recusada sem tocar no motor", function(T)
    local net, s, cs = mesa()
    local g = iniciar(s, { first = 1 })
    local conta = vigiar(g)
    local eventos = #g.events
    local function ultima(userid)
      local r = recusas(net, userid)
      return r[#r] and r[#r].motivo
    end
    -- Espectador.
    cs[3].Cliente.enviar({ type = "pass" })
    T.eq(ultima("KU_tres"), "só os dois jogadores jogam")
    -- Texto que não é um valor serializado: nada é executado.
    _G.DUELO_TESTE_INVADIDO = nil
    for _, texto in ipairs({
      "_G.DUELO_TESTE_INVADIDO = true",
      "(function() _G.DUELO_TESTE_INVADIDO = true end)()",
      "{[\"type\"]=(function() _G.DUELO_TESTE_INVADIDO = true return \"pass\" end)()}",
      "{[\"type\"]=\"pass\"} _G.DUELO_TESTE_INVADIDO = true",
      "return {type='pass'}", "{type=\"pass\"}", "", "{", "\"\\999\"", "{[\"type\"]=\"pass\"",
    }) do
      manda_texto(net, cs[1], texto, 5)
      T.eq(ultima("KU_um"), "ação inválida", "texto recusado: " .. texto)
    end
    T.eq(_G.DUELO_TESTE_INVADIDO, nil, "nenhum código do cliente rodou")
    -- Valores que são texto válido, mas não são uma ação.
    for _, v in ipairs({ 5, "pass", true, {}, { type = 3 }, { type = { "pass" } }, { "pass" } }) do
      manda_texto(net, cs[1], Serial.serialize(v), 6)
      local m = ultima("KU_um")
      T.ok(m == "ação inválida" or m == "ação sem tipo", "forma recusada: " .. tostring(m))
    end
    -- Argumento que não é texto.
    manda_texto(net, cs[1], 12345, 7)
    T.eq(ultima("KU_um"), "ação inválida")
    manda_texto(net, cs[1], nil, 7)
    T.eq(ultima("KU_um"), "ação inválida")
    -- Gigante: o texto passa do limite da rede.
    manda_texto(net, cs[1], Serial.serialize({ type = "pass", lixo = string.rep("x", 2000) }), 8)
    T.eq(ultima("KU_um"), "ação grande demais")
    T.eq(cs[1].Cliente.enviar({ type = "pass", lixo = string.rep("x", 2000) }), nil, "o cliente nem envia")
    -- Dentro do limite de bytes, mas fora da forma: valores demais, funda
    -- demais, texto comprido, número que não é número.
    local muitos = { type = "attack", attackers = {} }
    for i = 1, 100 do muitos.attackers[i] = i end
    manda_texto(net, cs[1], Serial.serialize(muitos), 9)
    T.eq(ultima("KU_um"), "ação grande demais")
    manda_texto(net, cs[1], Serial.serialize({ type = "play", a = { b = { c = { d = { e = 1 } } } } }), 10)
    T.eq(ultima("KU_um"), "ação funda demais")
    manda_texto(net, cs[1], Serial.serialize({ type = "play", from = string.rep("y", 100) }), 11)
    T.eq(ultima("KU_um"), "texto grande demais na ação")
    -- Número não finito: o leitor do texto já recusa.
    manda_texto(net, cs[1], "{[\"hand_index\"]=1e999,[\"type\"]=\"play\"}", 12)
    T.eq(ultima("KU_um"), "ação inválida")
    -- O número da ação volta na recusa; lixo no lugar dele não quebra nada.
    T.eq(recusas(net, "KU_um")[#recusas(net, "KU_um")].n, 12)
    manda_texto(net, cs[1], "{", "x")
    T.eq(recusas(net, "KU_um")[#recusas(net, "KU_um")].n, false)

    T.eq(conta.act, 0, "Game:act não foi chamado")
    T.eq(conta.can_act, 0, "Game:can_act não foi chamado")
    T.eq(conta.mulligan, 0, "Game:mulligan não foi chamado")
    T.eq(#g.events, eventos, "nenhum evento")
    T.eq(#g.log.actions, 0, "registro vazio")
    T.eq(#recusas(net, "KU_dois"), 0, "as recusas não vão para o outro jogador")

    -- Ação bem formada e inválida para o motor: só a pergunta (can_act) roda,
    -- e a partida continua de pé.
    net.relogio = net.relogio + 5
    for _, a in ipairs({ { type = "attack", attackers = "x" }, { type = "block", blocks = 3 },
      { type = "choose", index = "a" }, { type = "nada" }, { type = "activate", structure = {} },
      { type = "play", hand_index = 1.5, slot = "z", target = { uid = "q" }, sacrifice = 4 } }) do
      cs[1].Cliente.enviar(a)
      T.ok(g.phase == "playing", "a partida não foi encerrada por " .. Simulador.describe_action(a))
    end
    T.eq(conta.act, 0, "nenhuma chegou a Game:act")
    T.eq(#g.log.actions, 0)
  end },

  { "sem partida, a ação é recusada e o cliente fica sem visão", function(T)
    local net, s, cs = mesa()
    cs[1].Cliente.enviar({ type = "pass" })
    T.eq(recusas(net, "KU_um")[1].motivo, "não há partida em curso")
    cs[1].Cliente.pedir_estado()
    T.eq(cs[1].Cliente.visao(), nil); T.eq(cs[1].Cliente.em_partida(), false)
    iniciar(s)
    T.ok(cs[1].Cliente.em_partida())
    local fim = 0
    cs[2].Cliente.quando_estado(function(v) if v == nil then fim = fim + 1 end end)
    T.ok(s.Partida.encerrar())
    T.eq(fim, 1, "o cliente é avisado do fim")
    for _, c in ipairs(cs) do T.eq(c.Cliente.visao(), nil, "visão apagada") end
    T.eq(s.Partida.em_curso(), false)
    T.eq(s.Partida.iniciar{ decks = {}, jogadores = { "KU_um", "KU_dois" } }, false, "sem baralhos")
    local decks = decks_reais()
    T.eq(s.Partida.iniciar{ decks = decks, jogadores = { "KU_um" } }, false, "sem o segundo jogador")
  end },

  { "taxa: o excesso de ações por segundo é descartado com um aviso só", function(T)
    local net, s, cs = mesa()
    local g = iniciar(s, { first = 1 })
    local conta = vigiar(g)
    local max = s.Rede.LIMITES.ACOES_POR_SEGUNDO
    net.relogio = 100
    -- O jogador sem a vez dispara ações: as primeiras chegam à partida (e são
    -- recusadas pelo motor); o resto nem chega.
    for _ = 1, max + 15 do cs[2].Cliente.enviar({ type = "pass" }) end
    T.eq(conta.can_act, max, "só " .. max .. " chegaram à partida")
    local r = recusas(net, "KU_dois")
    T.eq(#r, max + 1, "uma recusa por ação que chegou e um aviso só pelo excesso")
    T.eq(r[#r].motivo, "ações demais por segundo")
    local avisos = 0
    for _, linha in ipairs(s.logs) do
      if linha:find("ações demais de KU_dois", 1, true) then avisos = avisos + 1 end
    end
    T.eq(avisos, 1, "um aviso no log do servidor")
    -- O limite é por jogador: o da vez joga normalmente.
    T.ok(cs[1].Cliente.enviar({ type = "pass" }))
    T.eq(conta.act, 1, "a ação do outro jogador entrou")
    -- No segundo seguinte a janela reabre.
    net.relogio = 101.5
    T.ok(cs[2].Cliente.enviar({ type = "pass" }))
    T.eq(conta.act, 2, "depois de 1 s as ações voltam a entrar")
  end },

  { "buraco na sequência: o cliente pede o estado e volta a acompanhar", function(T)
    local net, s, cs = mesa()
    local g = iniciar(s, { first = 1 })
    local eventos2, estados2 = 0, 0
    cs[2].Cliente.quando_evento(function() eventos2 = eventos2 + 1 end)
    cs[2].Cliente.quando_estado(function() estados2 = estados2 + 1 end)
    -- O lote da próxima ação some no caminho para o jogador 2.
    net.perder = function(userid, tipo) return userid == "KU_dois" and tipo == "eventos" end
    T.ok(cs[1].Cliente.enviar({ type = "pass" }))
    net.perder = nil
    T.eq(cs[1].Cliente.seq(), 2); T.eq(cs[2].Cliente.seq(), 1, "o jogador 2 ficou para trás")
    T.eq(net.rpcs_servidor.pedir_estado, nil)
    -- O lote seguinte chega com seq 3: buraco.
    net.relogio = 10
    T.ok(cs[2].Cliente.enviar({ type = "pass" }))
    T.eq(net.rpcs_servidor.pedir_estado, 1, "pediu o estado uma vez")
    T.eq(cs[2].Cliente.seq(), 3, "voltou a ficar em dia")
    T.eq(estados2, 1, "avisou a tela para se refazer")
    T.eq(eventos2, 0, "os eventos do lote perdido e do lote com buraco não são repassados")
    conferir_visoes(T, s, cs, "depois do buraco")
    -- Segue normalmente, sem novos pedidos.
    local p = quem_age(g)
    T.ok(cs[p].Cliente.enviar({ type = "pass" }))
    T.eq(cs[2].Cliente.seq(), 4); T.ok(eventos2 > 0)
    T.eq(net.rpcs_servidor.pedir_estado, 1)
    conferir_visoes(T, s, cs, "seguindo")
    -- Lote repetido ou velho é ignorado.
    local visao = Serial.serialize(cs[2].Cliente.visao())
    cs[2].Cliente.receber("eventos", { partida = 1, seq = 4, eventos = { { t = "pass", p = 1 } },
      mudancas = { { c = { "rodada" }, v = 99 } } })
    T.eq(Serial.serialize(cs[2].Cliente.visao()), visao, "lote repetido não muda nada")
    -- Lote de outra partida: pede o estado em vez de aplicar.
    net.relogio = 20
    cs[2].Cliente.receber("eventos", { partida = 9, seq = 5, eventos = {}, mudancas = { { c = { "rodada" }, v = 99 } } })
    T.eq(net.rpcs_servidor.pedir_estado, 2)
    T.eq(Serial.serialize(cs[2].Cliente.visao()), visao)
  end },

  { "quem entra no meio da partida recebe a fotografia do seu lado", function(T)
    local net, s, cs = mesa()
    local g = jogar(T, s, cs, { seed = 31, tipos = { "bot", "bot" }, max_rounds = 3 })
    local novo = net:maquina{ userid = "KU_quatro" }
    T.eq(novo.Cliente.visao(), nil)
    novo.Cliente.pedir_estado()
    T.eq(novo.Cliente.lado(), 3, "entra como espectador")
    T.ok(igual(novo.Cliente.visao(), Visao.estado_para(g, 3)), "com a fotografia pública")
    -- O jogador 2 "reconecta": uma máquina nova com o mesmo userid.
    local volta = net:maquina{ userid = "KU_dois" }
    net.relogio = 50
    volta.Cliente.pedir_estado()
    T.eq(volta.Cliente.lado(), 2)
    T.ok(igual(volta.Cliente.visao(), Visao.estado_para(g, 2)), "com a própria mão")
    T.ok(#volta.Cliente.visao().jogadores[2].mao > 0)
    -- E acompanha os lotes seguintes.
    local p = quem_age(g)
    T.ok(cs[p].Cliente.enviar({ type = "pass" }))
    T.ok(igual(volta.Cliente.visao(), Visao.estado_para(g, 2)))
    T.ok(igual(novo.Cliente.visao(), Visao.estado_para(g, 3)))
  end },

  { "mensagens grandes saem em pedaços e são remontadas; pedaço perdido pede o estado", function(T)
    local net, s, cs = mesa({ fragmento = 64 })
    local g = iniciar(s, { first = 1 })
    conferir_visoes(T, s, cs, "início em pedaços")
    local maior, varios = 0, false
    for _, p in ipairs(net.pedacos) do
      if p.bytes > maior then maior = p.bytes end
    end
    T.ok(maior <= 64, "nenhum pedaço passa do limite: " .. maior)
    T.ok(#net.pedacos > 20, "a fotografia saiu em vários pedaços: " .. #net.pedacos)
    -- Some o segundo pedaço do próximo lote do jogador 1.
    net.relogio = 30
    local sumiu = false
    net.perder = function(userid, tipo, id, i)
      if userid == "KU_um" and tipo == "eventos" and i == 2 and not sumiu then sumiu = true; return true end
    end
    T.ok(cs[1].Cliente.enviar({ type = "pass" }))
    net.perder = nil
    T.ok(sumiu, "um pedaço sumiu")
    T.eq(net.rpcs_servidor.pedir_estado, 1, "o cliente pediu o estado")
    conferir_visoes(T, s, cs, "depois do pedaço perdido")
    local achou = false
    for _, linha in ipairs(cs[1].logs) do
      if linha:find("fora de ordem", 1, true) then achou = true end
    end
    T.ok(achou, "o descarte fica no log do cliente")
    -- Com o limite padrão, o tamanho dos pedaços também é respeitado.
    T.eq(carregar("rede").LIMITES.FRAGMENTO, 1000)
  end },

  { "troca inicial pelas RPCs: cada jogador faz a sua, uma vez", function(T)
    local net, s, cs = mesa()
    local g = iniciar(s, { mulligan = true })
    T.eq(g.phase, "mulligan")
    T.eq(cs[1].Cliente.visao().fase, "mulligan")
    local mao = Serial.serialize(cs[2].Cliente.visao().jogadores[2].mao)
    T.ok(cs[2].Cliente.enviar({ type = "mulligan", indices = { 1, 2 } }))
    T.eq(g.players[2].mulligan_done, true)
    T.ok(Serial.serialize(cs[2].Cliente.visao().jogadores[2].mao) ~= mao, "a mão mudou")
    T.eq(cs[1].Cliente.visao().jogadores[2].troca_feita, true, "o outro sabe que a troca foi feita")
    cs[2].Cliente.enviar({ type = "mulligan", indices = {} })
    T.eq(recusas(net, "KU_dois")[1].motivo, "troca já feita")
    cs[1].Cliente.enviar({ type = "mulligan", indices = "x" })
    T.eq(recusas(net, "KU_um")[1].motivo, "troca inválida")
    -- Lista com buraco, índice fracionário ou campo a mais: recusada, e a
    -- troca única do jogador não é gasta.
    for _, torta in ipairs({
      { type = "mulligan", indices = { [2] = 1, [3] = 2 } },
      { type = "mulligan", indices = { 1.5 } },
      { type = "mulligan", indices = { 1 }, target = 5 },
    }) do
      local antes = #recusas(net, "KU_um")
      cs[1].Cliente.enviar(torta)
      local r = recusas(net, "KU_um")
      T.eq(#r, antes + 1); T.eq(r[#r].motivo, "troca inválida")
      T.eq(g.players[1].mulligan_done ~= true, true, "a troca não foi gasta")
    end
    local feitas = #recusas(net, "KU_um")
    cs[1].Cliente.enviar({ type = "pass" })
    T.eq(#recusas(net, "KU_um"), feitas + 1, "jogada antes da troca é recusada")
    T.ok(cs[1].Cliente.enviar({ type = "mulligan" }))
    T.eq(g.phase, "playing")
    conferir_visoes(T, s, cs, "depois da troca")
    T.eq(g.log.actions[1].action.type, "mulligan"); T.eq(g.log.actions[1].p, 2)
  end },

  { "erro do motor numa carta: a partida encerra, todos são avisados e o remetente recebe a recusa", function(T)
    local Cards = require("duelo/core/cards")
    Cards.define{ id = "us41_quebrada", name = "Quebrada", kind = "feitico", cost = 0, speed = "instantaneo",
      on_cast = function() error("carta quebrada de propósito") end }
    local net, s, cs = mesa()
    local d1, d2 = {}, {}
    for i = 1, 12 do d1[i] = { id = "us41_quebrada" }; d2[i] = { id = "us41_quebrada" } end
    T.ok(s.Partida.iniciar{ decks = { d1, d2 }, extra_decks = { {}, {} }, seed = 2, first = 1,
      jogadores = { "KU_um", "KU_dois" } })
    local g = s.Partida.jogo()
    local erros = 0
    cs[3].Cliente.quando_evento(function(ev) if ev.t == "engine_error" then erros = erros + 1 end end)
    cs[1].Cliente.enviar({ type = "play", hand_index = 1 })
    T.eq(g.phase, "error")
    T.eq(erros, 1, "o espectador recebe o evento de erro")
    T.eq(recusas(net, "KU_um")[1].motivo, "erro no motor: partida encerrada")
    T.eq(cs[2].Cliente.visao().fase, "error")
    T.eq(cs[2].Cliente.visao().erro, Visao.ERRO_GENERICO, "os clientes recebem o texto genérico")
    conferir_visoes(T, s, cs, "depois do erro")
    cs[2].Cliente.enviar({ type = "pass" })
    T.eq(recusas(net, "KU_dois")[1].motivo, "partida encerrada por erro")
  end },

  { "alvo que não é tabela: recusado antes do motor ou pelo motor, e a partida continua", function(T)
    local net, s, cs = mesa()
    local g = iniciar(s, { first = 1 })
    local conta = vigiar(g)
    local function ultima()
      local r = recusas(net, "KU_um")
      return r[#r] and r[#r].motivo
    end
    local enviadas = 0
    local function manda(a)
      net.relogio = net.relogio + 1
      enviadas = enviadas + 1
      T.ok(cs[1].Cliente.enviar(a), "ação enviada")
      T.eq(#recusas(net, "KU_um"), enviadas, "recusada: " .. Simulador.describe_action(a))
      T.eq(g.phase, "playing", "a partida continua de pé")
    end
    -- Forma errada: nem chega ao motor.
    for _, extra in ipairs({ { target = "1" }, { target = true }, { targets = "1" }, { targets = 1 },
      { targets = { 1 } }, { targets = { "x" } }, { targets = { [2] = {} } }, { targets = { a = {} } } }) do
      local a = { type = "play", from = "hand", hand_index = 1, slot = 5 }
      for k, v in pairs(extra) do a[k] = v end
      manda(a)
      T.ok(ultima() == "alvo inválido" or ultima() == "lista de alvos inválida", "motivo: " .. tostring(ultima()))
    end
    T.eq(conta.can_act, 0, "a forma errada não chega ao motor")
    -- Forma certa onde não cabe alvo (ou número, que só vale para equipar):
    -- o motor recusa em can_act, para todas as cartas da mão.
    for i = 1, #g.players[1].hand do
      for _, extra in ipairs({ { target = 1 }, { target = {} }, { targets = {} }, { targets = { {} } },
        { target = { p = 9 } }, { targets = { { p = 1, zone = "jogador" }, { p = 1, slot = 1.5 } } } }) do
        local a = { type = "play", from = "hand", hand_index = i, slot = 5 }
        for k, v in pairs(extra) do a[k] = v end
        manda(a)
      end
    end
    T.ok(conta.can_act > 0, "essas chegaram à pergunta")
    T.eq(conta.act, 0, "nenhuma chegou a Game:act")
    T.eq(#g.log.actions, 0)
    T.eq(s.Partida.validar_alvos({ target = { p = 1, slot = 1 }, targets = { { p = 2, zone = "jogador" } } }), true)
    T.eq(s.Partida.validar_alvos({ target = 3 }), true, "número: o espaço da criatura a equipar")
  end },

  { "número da ação não finito ou torto volta como false, e nenhum handler propaga erro", function(T)
    local net, s, cs = mesa()
    local g = iniciar(s, { first = 1 })
    local function ultimo_n()
      local r = recusas(net, "KU_um")
      return r[#r].n
    end
    local total = 0
    for _, n in ipairs({ math.huge, -math.huge, 0 / 0, -1, 1.5, 2 ^ 31, 2 ^ 60, "7", true, {} }) do
      manda_texto(net, cs[1], "{", n)
      total = total + 1
      T.eq(#recusas(net, "KU_um"), total, "a recusa saiu com n = " .. tostring(n))
      T.eq(ultimo_n(), false, "n = " .. tostring(n) .. " vira false")
    end
    manda_texto(net, cs[1], "{", nil)
    T.eq(ultimo_n(), false, "sem número")
    for _, n in ipairs({ 0, 1, 2 ^ 31 - 1 }) do
      manda_texto(net, cs[1], "{", n)
      T.eq(ultimo_n(), n, "inteiro finito volta igual")
    end
    -- Ação recusada pelo motor com n infinito: a recusa também sai.
    manda_texto(net, cs[2], Serial.serialize({ type = "pass" }), math.huge)
    T.eq(recusas(net, "KU_dois")[1].motivo, "não é a sua vez"); T.eq(recusas(net, "KU_dois")[1].n, false)
    for _, linha in ipairs(s.logs) do
      T.ok(not linha:find("erro ao tratar", 1, true), "nenhum handler estourou: " .. linha)
    end
    -- Um erro dentro do handler do servidor não sobe para a fila de RPCs.
    local original = s.Partida.receber_acao
    s.Partida.receber_acao = function() error("partida quebrada de propósito") end
    manda_texto(net, cs[1], Serial.serialize({ type = "pass" }), 3)
    s.Partida.receber_acao = original
    local original_estado = s.Partida.pedir_estado
    s.Partida.pedir_estado = function() error("estado quebrado de propósito") end
    net.relogio = net.relogio + 5
    cs[1].ctx.SendModRPCToServer(cs[1].ctx.GetModRPC("duelo", "pedir_estado"))
    s.Partida.pedir_estado = original_estado
    local avisos = 0
    for _, linha in ipairs(s.logs) do
      if linha:find("erro ao tratar", 1, true) then avisos = avisos + 1 end
    end
    T.eq(avisos, 2, "os dois erros ficaram no log do servidor")
    -- Nem o do cliente.
    local receber = cs[1].Cliente.receber
    cs[1].Cliente.receber = function() error("cliente quebrado de propósito") end
    net.relogio = net.relogio + 5
    T.ok(cs[1].Cliente.enviar({ type = "pass" }), "o lote sai mesmo com o cliente 1 quebrado")
    cs[1].Cliente.receber = receber
    local achou = false
    for _, linha in ipairs(cs[1].logs) do
      if linha:find("erro ao tratar", 1, true) and linha:find("cliente quebrado de propósito", 1, true) then achou = true end
    end
    T.ok(achou, "o erro ficou no log do cliente")
    T.eq(cs[2].Cliente.seq(), 2, "os outros receberam o lote")
    T.eq(g.phase, "playing")
  end },

  { "o leitor do serial recusa número não finito e respeita os limites de profundidade e de valores", function(T)
    for _, texto in ipairs({ "1e999", "-1e999", "{[1]=1e999}", "{[\"n\"]=-1e9999}",
      "{[" .. string.rep("9", 400) .. "]=1}" }) do
      T.eq(pcall(Serial.deserialize, texto), false, "recusado: " .. texto)
    end
    T.eq(Serial.deserialize("1e3"), 1000, "número finito com expoente continua valendo")
    local function funda(n)
      return string.rep("{[1]=", n) .. "1" .. string.rep("}", n)
    end
    local P = Serial.LIMITES.PROFUNDIDADE
    T.ok(pcall(Serial.deserialize, funda(P)), "no limite de profundidade")
    T.eq(pcall(Serial.deserialize, funda(P + 1)), false, "acima do limite de profundidade")
    T.eq(pcall(Serial.deserialize, funda(5000)), false, "muito funda: erro, sem estourar a pilha")
    T.ok(pcall(Serial.deserialize, funda(3), { profundidade = 3 }))
    T.eq(pcall(Serial.deserialize, funda(4), { profundidade = 3 }), false, "limite por leitura")
    local lista = {}
    for i = 1, 10 do lista[i] = i end
    local texto = Serial.serialize(lista) -- 11 valores: a tabela e os 10 números
    T.ok(pcall(Serial.deserialize, texto, { elementos = 11 }))
    T.eq(pcall(Serial.deserialize, texto, { elementos = 10 }), false, "valores demais")
    -- A fotografia de uma partida cabe com folga nos limites padrão.
    local decks, extras = decks_reais()
    local g = Game.new{ decks = decks, extra_decks = extras, seed = 3, mulligan = false }
    g:start()
    local foto = Visao.estado_para(g, 1)
    T.ok(igual(Serial.deserialize(Serial.serialize(foto)), foto))
    T.ok(igual(Serial.deserialize(Serial.serialize(g.log)), g.log), "e o registro da partida")
  end },

  { "Máquina de Ciência: a quantidade de opções da escolha só chega a quem escolhe", function(T)
    local net, s, cs = mesa()
    local g = iniciar(s, { first = 1 })
    -- A Máquina em campo e exatamente dois equipamentos entre as 5 do topo.
    g:put_structure(1, { id = "maquina_de_ciencia", uid = g:next_uid() }, 1)
    local deck = g.players[1].deck
    local equips, outras = {}, {}
    for _, c in ipairs(deck) do
      if g:def_of(c).kind == "equipamento" then equips[#equips + 1] = c else outras[#outras + 1] = c end
    end
    T.ok(#equips >= 2 and #outras >= 3, "o baralho tem equipamentos e outras cartas")
    local topo = { outras[1], equips[1], outras[2], equips[2], outras[3] }
    local no_topo = {}
    for _, c in ipairs(topo) do no_topo[c] = true end
    local novo = {}
    for _, c in ipairs(deck) do if not no_topo[c] then novo[#novo + 1] = c end end
    for _, c in ipairs(topo) do novo[#novo + 1] = c end
    g.players[1].deck = novo
    net.relogio = net.relogio + 1
    local antes = { #(net.mensagens.KU_dois or {}), #(net.mensagens.KU_tres or {}) }
    T.ok(cs[1].Cliente.enviar({ type = "activate", structure = 1 }))
    T.ok(g.pending_choice ~= nil and #g.pending_choice.options == 2, "a escolha abriu com duas opções")
    -- Quem escolhe vê tudo.
    local minha = cs[1].Cliente.visao().escolha
    T.eq(minha.n, 2); T.eq(#minha.opcoes, 2); T.eq(minha.nenhuma, true)
    -- Os outros: só que há uma escolha do lado 1 e o motivo, na fotografia e nos eventos.
    for i, userid in ipairs({ "KU_dois", "KU_tres" }) do
      local visao = cs[i + 1].Cliente.visao()
      T.ok(igual(visao.escolha, { p = 1, motivo = "maquina_de_ciencia" }), "fotografia do lado " .. (i + 1))
      local msgs = net.mensagens[userid]
      local viu = false
      for k = antes[i] + 1, #msgs do
        local texto = Serial.serialize(msgs[k].m)
        T.ok(not texto:find("count", 1, true), "sem a quantidade no que o lado " .. (i + 1) .. " recebeu")
        T.ok(not texto:find("opcoes", 1, true) and not texto:find("\"n\"", 1, true), "sem opções nem n")
        for _, ev in ipairs(msgs[k].m.eventos or {}) do
          T.ok(ev.t ~= "look", "sem as cartas olhadas")
          if ev.t == "choice" then
            viu = true
            T.ok(igual(ev, { t = "choice", p = 1, reason = "maquina_de_ciencia" }), "evento reduzido")
          end
        end
      end
      T.ok(viu, "o lado " .. (i + 1) .. " soube que há uma escolha")
    end
    -- Direto no filtro: o dono recebe o evento inteiro; privado não vai a ninguém mais.
    local ev = { t = "choice", p = 1, reason = "x", count = 3 }
    T.ok(igual(Visao.evento_para(ev, 1), ev))
    T.ok(igual(Visao.evento_para(ev, 2), { t = "choice", p = 1, reason = "x" }))
    T.ok(igual(Visao.evento_para(ev, 3), { t = "choice", p = 1, reason = "x" }))
    ev.private = true
    T.eq(Visao.evento_para(ev, 2), nil)
    conferir_visoes(T, s, cs, "com a escolha aberta")
    -- A escolha é feita e as visões continuam em dia.
    net.relogio = net.relogio + 1
    T.ok(cs[1].Cliente.enviar({ type = "choose", index = 1 }))
    T.eq(g.pending_choice, nil)
    T.eq(cs[2].Cliente.visao().escolha, false)
    conferir_visoes(T, s, cs, "depois da escolha")
  end },

  { "erro do motor: os clientes recebem só o texto genérico; o detalhe fica no servidor", function(T)
    local Cards = require("duelo/core/cards")
    Cards.define{ id = "us41_segredo", name = "Segredo", kind = "feitico", cost = 0, speed = "instantaneo",
      on_cast = function() error("detalhe que não pode sair") end }
    local net, s, cs = mesa()
    local d1, d2 = {}, {}
    for i = 1, 12 do d1[i] = { id = "us41_segredo" }; d2[i] = { id = "us41_segredo" } end
    T.ok(s.Partida.iniciar{ decks = { d1, d2 }, extra_decks = { {}, {} }, seed = 2, first = 1,
      jogadores = { "KU_um", "KU_dois" } })
    local g = s.Partida.jogo()
    local antes = {}
    for _, userid in ipairs({ "KU_um", "KU_dois", "KU_tres" }) do antes[userid] = #net.mensagens[userid] end
    cs[1].Cliente.enviar({ type = "play", hand_index = 1 })
    T.eq(g.phase, "error")
    T.ok(g.error.message:find("detalhe que não pode sair", 1, true), "o motor guarda a mensagem inteira")
    for lado, userid in ipairs({ "KU_um", "KU_dois", "KU_tres" }) do
      local msgs = net.mensagens[userid]
      local viu = false
      for k = antes[userid] + 1, #msgs do
        local texto = Serial.serialize(msgs[k].m)
        T.ok(not texto:find("detalhe que não pode sair", 1, true), "sem a mensagem crua para o lado " .. lado)
        T.ok(not texto:find(".lua", 1, true), "sem caminho de arquivo para o lado " .. lado)
        T.ok(not texto:find("context", 1, true), "sem o contexto do motor para o lado " .. lado)
        for _, ev in ipairs(msgs[k].m.eventos or {}) do
          if ev.t == "engine_error" then
            viu = true
            T.ok(igual(ev, { t = "engine_error", message = Visao.ERRO_GENERICO }), "evento de erro genérico")
          end
        end
      end
      T.ok(viu, "o lado " .. lado .. " foi avisado do erro")
      T.eq(cs[lado].Cliente.visao().erro, Visao.ERRO_GENERICO)
      T.eq(Visao.estado_para(g, lado).erro, Visao.ERRO_GENERICO)
    end
    T.eq(Visao.ERRO_GENERICO, "erro interno do jogo; a partida foi encerrada")
    -- No servidor: o log e o resumo do console trazem a mensagem e a carta.
    local log = table.concat(s.logs, "\n")
    T.ok(log:find("detalhe que não pode sair", 1, true), "a mensagem está no log do servidor")
    T.ok(log:find("us41_segredo", 1, true), "com a carta que rodava")
    local _, vezes = log:gsub("ERRO DO MOTOR", "")
    T.eq(vezes, 1, "registrado uma vez")
    local resumo = table.concat(s.Partida.resumo(), "\n")
    T.ok(resumo:find("detalhe que não pode sair", 1, true) and resumo:find("us41_segredo", 1, true),
      "DUELO.Partida.estado() mostra o detalhe")
  end },

  { "host: ação mandada de dentro de um ouvinte de eventos não embaralha a ordem dos lotes", function(T)
    local net = nova_rede()
    local h = net:maquina{ servidor = true, userid = "KU_host", lado = 1 }
    local c = net:maquina{ userid = "KU_amigo", lado = 3 }
    -- O ouvinte do host passa a vez no primeiro evento dos dois primeiros lotes.
    local reagiu, ultimo_lote = 0, 0
    h.Cliente.quando_evento(function()
      local seq = h.Cliente.seq()
      if seq ~= ultimo_lote and reagiu < 2 then
        ultimo_lote = seq
        reagiu = reagiu + 1
        T.ok(h.Cliente.enviar({ type = "pass" }), "ação enviada de dentro do ouvinte")
      end
    end)
    local lotes_do_amigo = {}
    c.Cliente.quando_evento(function() lotes_do_amigo[#lotes_do_amigo + 1] = c.Cliente.seq() end)
    local decks, extras = decks_reais()
    -- O host joga pelos dois lados; o amigo assiste.
    T.ok(h.Partida.iniciar{ decks = decks, extra_decks = extras, seed = 5, first = 1,
      jogadores = { "KU_host", "KU_host" } })
    local g = h.Partida.jogo()
    T.eq(reagiu, 2, "o ouvinte reagiu a dois lotes")
    T.eq(#g.log.actions, 2, "as duas ações foram aplicadas")
    T.eq(h.Cliente.seq(), 3); T.eq(c.Cliente.seq(), 3, "o cliente remoto recebeu os lotes 1, 2 e 3")
    T.eq(net.rpcs_servidor.pedir_estado, nil, "sem pedir a fotografia")
    -- Em ordem: os números de lote vistos pelo amigo nunca voltam, e ele viu os três.
    local vistos = {}
    for i, seq in ipairs(lotes_do_amigo) do
      T.ok(i == 1 or seq >= lotes_do_amigo[i - 1], "lotes em ordem")
      vistos[seq] = true
    end
    T.ok(vistos[1] and vistos[2] and vistos[3], "os eventos dos três lotes chegaram")
    local ordem = {}
    for _, msg in ipairs(net.mensagens.KU_amigo) do
      if msg.tipo == "eventos" then ordem[#ordem + 1] = msg.m.seq end
    end
    T.eq(table.concat(ordem, ","), "1,2,3", "ordem de envio ao cliente remoto")
    T.ok(igual(c.Cliente.visao(), Visao.estado_para(g, 3)), "visão do amigo em dia")
    T.ok(igual(h.Cliente.visao(), Visao.estado_para(g, 1)), "visão do host em dia")
    -- Uma ação recusada depois de esperar na fila volta ao remetente com o número dela.
    local recusadas = {}
    h.Cliente.quando_recusada(function(motivo, n) recusadas[#recusadas + 1] = { motivo = motivo, n = n } end)
    local cancelar
    cancelar = h.Cliente.quando_evento(function()
      cancelar()
      h.Cliente.enviar({ type = "play", hand_index = 99 })
    end)
    T.ok(h.Cliente.enviar({ type = "pass" }))
    T.eq(#recusadas, 1, "a recusa da ação adiada chegou")
    T.eq(recusadas[1].motivo, "carta não está na mão"); T.eq(recusadas[1].n, 4)
    T.eq(c.Cliente.seq(), 4)
  end },

  { "pedido de fotografia perdido é repetido por tempo, dentro do limite do servidor", function(T)
    local net, s, cs = mesa()
    local g = iniciar(s, { first = 1 })
    local c = cs[2]
    net.relogio = 100
    -- O lote da próxima ação some para o jogador 2, e as fotografias também.
    net.perder = function(userid, tipo) return userid == "KU_dois" and (tipo == "eventos" or tipo == "estado") end
    T.ok(cs[1].Cliente.enviar({ type = "pass" }))
    net.perder = function(userid, tipo) return userid == "KU_dois" and tipo == "estado" end
    net.relogio = 101
    T.ok(cs[2].Cliente.enviar({ type = "pass" }))
    T.eq(net.rpcs_servidor.pedir_estado, 1, "buraco: pediu a fotografia")
    T.eq(c.Cliente.esperando_estado(), true, "e ela não chegou")
    T.eq(c.Cliente.seq(), 1)
    -- Antes de 1 s nada é repetido, por mais que o tique rode.
    for _, t in ipairs({ 101.1, 101.25, 101.5, 101.75, 101.99 }) do
      net.relogio = t
      T.eq(c.Cliente.tique(), false, "cedo demais em t = " .. t)
    end
    T.eq(net.rpcs_servidor.pedir_estado, 1)
    -- Passado 1 s, repete; a resposta se perde de novo.
    net.relogio = 102
    T.eq(c.Cliente.tique(), true, "repetiu o pedido")
    T.eq(net.rpcs_servidor.pedir_estado, 2)
    net.relogio = 102.5
    T.eq(c.Cliente.tique(), false)
    -- Na terceira vez a fotografia chega e o cliente volta a ficar em dia.
    net.perder = nil
    net.relogio = 103.01
    T.eq(c.Cliente.tique(), true)
    T.eq(net.rpcs_servidor.pedir_estado, 3)
    T.eq(c.Cliente.esperando_estado(), false, "a fotografia chegou")
    T.eq(c.Cliente.seq(), 3)
    conferir_visoes(T, s, cs, "depois das retentativas")
    -- Sem pedido no ar, o tique não faz nada.
    for _, t in ipairs({ 104, 105, 110 }) do
      net.relogio = t
      T.eq(c.Cliente.tique(), false)
    end
    T.eq(net.rpcs_servidor.pedir_estado, 3, "sem pedidos à toa")
    -- Nenhum pedido foi ignorado pelo limite do servidor: os três foram respondidos.
    local respostas = 0
    for _, msg in ipairs(net.mensagens.KU_dois) do
      if msg.tipo == "estado" and msg.m.seq and msg.m.seq >= 2 then respostas = respostas + 1 end
    end
    T.eq(respostas, 3, "o servidor respondeu a todos os pedidos")
    T.eq(c.Cliente.ESPERA_PEDIDO, 1)
    T.ok(1 / c.Cliente.ESPERA_PEDIDO <= s.Rede.LIMITES.ESTADOS_POR_SEGUNDO, "dentro do limite do servidor")
  end },

  { "o jogador local, ao ativar, pede a fotografia e liga a tarefa periódica das retentativas", function(T)
    local relogio = 50
    local pedidos, tarefas, eventos = 0, {}, {}
    local jogador = { userid = "KU_x" }
    function jogador:ListenForEvent(nome, fn) eventos[nome] = fn end
    function jogador:DoStaticPeriodicTask(intervalo, fn) tarefas[#tarefas + 1] = { intervalo = intervalo, fn = fn }; return {} end
    function jogador:DoPeriodicTask() error("a tarefa tem de ser a estática, que roda na pausa") end
    local outro = { userid = "KU_y" }
    function outro:ListenForEvent(nome, fn) self.ativar = fn end
    local rede = { pedir_estado = function() pedidos = pedidos + 1 end, enviar_acao = function() return true end }
    local Cliente = carregar("partida_cliente").instalar({
      rede = rede,
      GLOBAL = { ThePlayer = jogador, GetTime = function() error("relógio da simulação não serve") end },
      AddPlayerPostInit = function(fn) fn(jogador); fn(outro) end,
      agora = function() return relogio end,
    })
    outro.ativar()
    T.eq(pedidos, 0, "outro jogador ativando não pede nada")
    eventos.playeractivated()
    T.eq(pedidos, 1, "pediu a fotografia ao ativar")
    T.eq(#tarefas, 1, "ligou a tarefa periódica")
    T.eq(tarefas[1].intervalo, Cliente.INTERVALO_TIQUE)
    eventos.playeractivated()
    T.eq(#tarefas, 1, "uma tarefa só, mesmo ativando de novo")
    -- A tarefa repete o pedido quando passa o tempo, pelo relógio injetado.
    relogio = 50.5
    tarefas[1].fn()
    T.eq(pedidos, 1)
    relogio = 51.2
    tarefas[1].fn()
    T.eq(pedidos, 2, "repetiu depois de 1 s")
    Cliente.receber("estado", { partida = false })
    relogio = 60
    tarefas[1].fn()
    T.eq(pedidos, 2, "com a resposta recebida, para de pedir")
  end },

  { "taxa: usa o tempo real (não para na pausa) e esquece as janelas vencidas e de quem saiu", function(T)
    local net, s, cs = mesa()
    local g = iniciar(s, { first = 1 })
    local conta = vigiar(g)
    local max = s.Rede.LIMITES.ACOES_POR_SEGUNDO
    -- O relógio da simulação (GLOBAL.GetTime) está parado em 0 nesta mesa:
    -- se a taxa o usasse, a janela aberta aqui nunca venceria.
    T.eq(s.GLOBAL.GetTime(), 0)
    net.relogio = 500
    for _ = 1, max + 5 do cs[2].Cliente.enviar({ type = "pass" }) end
    T.eq(conta.can_act, max, "a janela encheu")
    net.relogio = 501.2
    cs[2].Cliente.enviar({ type = "pass" })
    T.eq(conta.can_act, max + 1, "com o servidor pausado, a janela vence pelo tempo real")
    -- As janelas vencidas somem quando chega o próximo pedido, de quem for.
    cs[1].Cliente.pedir_estado()
    cs[3].Cliente.pedir_estado()
    T.eq(s.Rede.janelas(), 3, "três jogadores com janela aberta")
    net.relogio = 510
    cs[1].Cliente.pedir_estado()
    T.eq(s.Rede.janelas(), 1, "as vencidas foram apagadas")
    -- Quem sai é esquecido na hora.
    s.Rede.esquecer("KU_um")
    T.eq(s.Rede.janelas(), 0)
    -- E a ligação com o jogo: ms_playerleft no TheWorld, só no servidor.
    local function instalar_com_mundo(servidor)
      local ouvintes, posts = {}, {}
      local mundo = { ListenForEvent = function(_, nome, fn) ouvintes[nome] = fn end }
      local relogio = 7
      local ctx = {
        GLOBAL = { TheNet = { GetIsServer = function() return servidor end }, TheWorld = mundo, AllPlayers = {},
          GetTime = function() error("relógio da simulação não serve") end },
        AddModRPCHandler = function(_, nome, fn) posts[nome] = fn end,
        AddClientModRPCHandler = function() end,
        GetModRPC = function() end, GetClientModRPC = function(_, nome) return nome end,
        SendModRPCToServer = function() end, SendModRPCToClient = function() end,
        AddSimPostInit = function(fn) posts.sim = fn end,
        agora = function() return relogio end,
      }
      local R = carregar("rede").instalar(ctx)
      posts.sim()
      return R, ouvintes, posts
    end
    local R, ouvintes, posts = instalar_com_mundo(true)
    T.eq(type(ouvintes.ms_playerleft), "function", "o servidor escuta ms_playerleft")
    R.ligar_servidor({ pedir_estado = function() end, receber_acao = function() return { ok = true } end })
    posts.pedir_estado({ userid = "KU_sai" })
    posts.pedir_estado({ userid = "KU_fica" })
    T.eq(R.janelas(), 2)
    ouvintes.ms_playerleft(nil, { userid = "KU_sai" })
    T.eq(R.janelas(), 1, "a janela de quem saiu foi apagada")
    ouvintes.ms_playerleft(nil, nil)
    T.eq(R.janelas(), 1, "evento sem jogador não quebra nada")
    local _, no_cliente = instalar_com_mundo(false)
    T.eq(no_cliente.ms_playerleft, nil, "o cliente não escuta")
  end },

  { "host sozinho: iniciar_teste põe o jogador nos dois lados e as ações valem para quem age", function(T)
    local net = nova_rede()
    local h = net:maquina{ servidor = true, userid = "KU_host", lado = 1 }
    local recebidos = 0
    h.Cliente.quando_evento(function() recebidos = recebidos + 1 end)
    T.ok(h.Partida.iniciar_teste(9))
    local g = h.Partida.jogo()
    T.eq(g.log.seed, 9)
    T.eq(h.Partida.jogadores()[1], "KU_host"); T.eq(h.Partida.jogadores()[2], "KU_host")
    T.eq(h.Cliente.lado(), 1, "a visão é a do lado 1")
    T.ok(recebidos > 5, "os eventos do início chegaram ao cliente do host")
    T.ok(igual(h.Cliente.visao(), Visao.estado_para(g, 1)))
    T.eq(#g.log.decks[1], 40); T.eq(#g.log.decks[2], 40)
    -- Passa pelos dois lados: cada ação vale para o lado que tem de agir.
    for i = 1, 4 do
      local p = quem_age(g)
      T.ok(h.Cliente.enviar({ type = "pass" }))
      T.eq(g.log.actions[i].p, p, "ação " .. i .. " do lado " .. p)
    end
    T.eq(#g.log.actions, 4)
    T.ok(igual(h.Cliente.visao(), Visao.estado_para(g, 1)))
    T.eq(net.rpcs_servidor.acao, nil, "no host nada passa pela RPC")
    -- Os comandos de console imprimem um resumo.
    h.logs = {}; h.GLOBAL.print = function(s) h.logs[#h.logs + 1] = tostring(s) end
    h.Partida.estado()
    T.ok(#h.logs >= 5, "resumo do servidor")
    T.ok(table.concat(h.logs, "\n"):find("mão: 1:", 1, true), "com as mãos")
    h.logs = {}
    h.Cliente.imprimir()
    local texto = table.concat(h.logs, "\n")
    T.ok(texto:find("eu sou lado 1", 1, true), "resumo do cliente")
    T.ok(texto:find("mão: escondida", 1, true), "a mão do lado 2 não aparece no cliente")
    T.ok(texto:find("últimos eventos", 1, true))
    h.Partida.encerrar()
    h.logs = {}
    h.Cliente.imprimir()
    T.ok(h.logs[1]:find("sem partida", 1, true))
  end },

  { "host com um cliente: iniciar_teste usa os lados da mesa e cada um vê só a própria mão", function(T)
    local net = nova_rede()
    local h = net:maquina{ servidor = true, userid = "KU_host", lado = 2 }
    local c = net:maquina{ userid = "KU_amigo", lado = 1 }
    T.ok(h.Partida.iniciar_teste(4))
    local g = h.Partida.jogo()
    T.eq(h.Partida.jogadores()[1], "KU_amigo", "lado 1 pela netvar da mesa")
    T.eq(h.Partida.jogadores()[2], "KU_host")
    T.eq(h.Cliente.lado(), 2); T.eq(c.Cliente.lado(), 1)
    T.ok(igual(h.Cliente.visao(), Visao.estado_para(g, 2)))
    T.ok(igual(c.Cliente.visao(), Visao.estado_para(g, 1)))
    T.eq(c.Cliente.visao().jogadores[2].mao, nil)
    T.eq(h.Cliente.visao().jogadores[1].mao, nil)
    c.logs = {}
    c.Cliente.imprimir()
    local texto = table.concat(c.logs, "\n")
    local _, escondidas = texto:gsub("mão: escondida", "")
    T.eq(escondidas, 1, "o cliente vê uma mão só")
    -- Cada um joga pelo seu canal: o host direto, o cliente pela RPC.
    for _ = 1, 4 do
      local p = quem_age(g)
      local quem = p == 1 and c or h
      T.ok(quem.Cliente.enviar({ type = "pass" }))
    end
    T.eq(#g.log.actions, 4)
    T.eq(net.rpcs_servidor.acao, 2, "só as do cliente passam pela RPC")
    T.ok(igual(h.Cliente.visao(), Visao.estado_para(g, 2)))
    T.ok(igual(c.Cliente.visao(), Visao.estado_para(g, 1)))
    -- O host fora da vez também é recusado, e só ele fica sabendo.
    local fora = quem_age(g) == 1 and h or c
    local ouviu = 0
    fora.Cliente.quando_recusada(function() ouviu = ouviu + 1 end)
    fora.Cliente.enviar({ type = "pass" })
    T.eq(ouviu, 1); T.eq(#g.log.actions, 4)
  end },

  { "modmain.lua liga a rede, a partida só no servidor e o cliente só onde há tela", function(T)
    local function rodar_modmain(servidor, dedicado)
      local rpcs = {}
      local env = {
        GLOBAL = {
          require = require,
          TheNet = { GetIsServer = function() return servidor end, IsDedicated = function() return dedicado end },
          print = function() end,
        },
        GetModConfigData = function() return nil end,
        AddPlayerPostInit = function() end,
        AddComponentPostInit = function() end,
        AddPrefabPostInit = function() end,
        AddSimPostInit = function() end,
        AddModRPCHandler = function(ns, nome) rpcs[#rpcs + 1] = "s:" .. ns .. "." .. nome end,
        AddClientModRPCHandler = function(ns, nome) rpcs[#rpcs + 1] = "c:" .. ns .. "." .. nome end,
        SendModRPCToServer = function() end, SendModRPCToClient = function() end,
        GetModRPC = function() end, GetClientModRPC = function() end,
      }
      local fn = assert(loadfile(RAIZ .. "modmain.lua"))
      setfenv(fn, env)
      fn()
      return env.DUELO, table.concat(rpcs, " ")
    end
    local ORDEM = "s:duelo.acao s:duelo.pedir_estado c:duelo.eventos c:duelo.estado c:duelo.recusada"
    local dedicado, r1 = rodar_modmain(true, true)
    T.eq(r1, ORDEM, "RPCs no servidor dedicado")
    T.eq(type(dedicado.Partida.iniciar_teste), "function", "DUELO.Partida no servidor")
    T.eq(type(dedicado.Partida.estado), "function")
    T.eq(dedicado.Cliente, nil, "sem cliente no servidor dedicado")
    local host, r2 = rodar_modmain(true, false)
    T.eq(r2, ORDEM, "RPCs no host")
    T.ok(host.Partida ~= nil and host.Cliente ~= nil, "no host os dois convivem")
    -- No cliente, o módulo do servidor (e com ele o motor) nem é pedido.
    local pedidos, original = {}, require
    _G.require = function(nome) pedidos[nome] = true; return original(nome) end
    local ok, cliente, r3 = pcall(rodar_modmain, false, false)
    _G.require = original
    T.ok(ok, tostring(cliente))
    T.eq(r3, ORDEM, "RPCs no cliente, na mesma ordem")
    T.eq(cliente.Partida, nil, "sem partida no cliente")
    T.eq(type(cliente.Cliente.enviar), "function", "DUELO.Cliente")
    T.eq(type(cliente.Cliente.imprimir), "function")
    T.ok(pedidos["duelo/mod/partida_cliente"], "o cliente pede o módulo do cliente")
    for nome in pairs(pedidos) do
      T.ok(nome ~= "duelo/mod/partida_servidor" and not nome:find("^duelo/core/game"),
        "o modmain do cliente pediu " .. nome)
    end
  end },

  { "o cliente não carrega o motor", function(T)
    local CLIENTE = { "duelo/core/serial", "duelo/mod/visao", "duelo/mod/rede", "duelo/mod/partida_cliente" }
    local PROIBIDOS = { "^duelo/core/", "^duelo/cartas", "^duelo/decks", "^duelo/bot", "^duelo/sim",
      "^duelo/terminal", "^duelo/mod/partida_servidor$" }
    local function proibido(nome)
      if nome == "duelo/core/serial" then return false end
      for _, padrao in ipairs(PROIBIDOS) do
        if nome:find(padrao) then return true end
      end
      return false
    end
    -- Estático: nenhum arquivo do cliente pede um módulo proibido.
    for _, nome in ipairs(CLIENTE) do
      local f = assert(io.open(RAIZ .. "scripts/" .. nome .. ".lua", "r"))
      local fonte = f:read("*a")
      f:close()
      for pedido in fonte:gmatch("require%s*%(?%s*[\"']([^\"']+)[\"']") do
        T.ok(not proibido(pedido), nome .. " dá require em " .. pedido)
      end
    end
    -- Dinâmico: com um require que falha para o motor, os módulos do cliente
    -- carregam do zero e acompanham uma partida.
    local guardados, original = {}, require
    for nome, mod in pairs(package.loaded) do
      if type(nome) == "string" and nome:find("^duelo/") then guardados[nome] = mod; package.loaded[nome] = nil end
    end
    local pedidos = {}
    _G.require = function(nome)
      pedidos[#pedidos + 1] = nome
      if proibido(nome) then error("o cliente tentou carregar " .. nome, 2) end
      return original(nome)
    end
    local ok, err = pcall(function()
      local RedeC = require("duelo/mod/rede")
      local ClienteC = require("duelo/mod/partida_cliente")
      local SerialC = require("duelo/core/serial")
      local enviadas = {}
      local ctx = {
        GLOBAL = { TheNet = { GetIsServer = function() return false end }, ThePlayer = { userid = "KU_x" } },
        AddModRPCHandler = function() end,
        AddClientModRPCHandler = function() end,
        GetModRPC = function(ns, nome) return { namespace = ns, id = nome } end,
        GetClientModRPC = function(ns, nome) return { namespace = ns, id = nome } end,
        SendModRPCToServer = function(rpc, ...) enviadas[#enviadas + 1] = { rpc.id, ... } end,
        SendModRPCToClient = function() error("cliente não manda RPC de cliente") end,
      }
      RedeC.instalar(ctx)
      ClienteC.instalar({ rede = RedeC, GLOBAL = ctx.GLOBAL })
      ClienteC.receber("estado", { partida = 1, seq = 0, lado = 1, estado = { rodada = 0, jogadores = { {}, {} } } })
      ClienteC.receber("eventos", { partida = 1, seq = 1, eventos = { { t = "round_start", round = 1 } },
        mudancas = { { c = { "rodada" }, v = 1 } } })
      assert(ClienteC.visao().rodada == 1, "lote aplicado")
      assert(ClienteC.enviar({ type = "pass" }) == 1, "ação enviada")
      assert(enviadas[1][1] == "acao" and SerialC.deserialize(enviadas[1][2]).type == "pass", "texto da ação")
      ClienteC.imprimir = ClienteC.imprimir
      assert(#ClienteC.resumo() > 0)
    end)
    _G.require = original
    local carregados = {}
    for nome in pairs(package.loaded) do
      if type(nome) == "string" and nome:find("^duelo/") then carregados[nome] = true; package.loaded[nome] = nil end
    end
    for nome, mod in pairs(guardados) do package.loaded[nome] = mod end
    T.ok(ok, tostring(err))
    for nome in pairs(carregados) do
      T.ok(not proibido(nome), "o cliente carregou " .. nome)
    end
    T.ok(carregados["duelo/mod/partida_cliente"] and carregados["duelo/mod/rede"] and carregados["duelo/core/serial"],
      "os módulos do cliente foram carregados do zero")
    T.eq(carregados["duelo/core/game"], nil, "o motor não foi carregado")
    -- E o inverso: o módulo do servidor é quem carrega o motor.
    local fonte = assert(io.open(RAIZ .. "scripts/duelo/mod/partida_servidor.lua", "r")):read("*a")
    T.ok(fonte:find("require(\"duelo/core/game\")", 1, true), "partida_servidor carrega o motor")
  end },
}
