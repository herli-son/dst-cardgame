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
      GetTime = function() return net.relogio end,
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
local function conferir_visoes(T, s, clientes, onde)
  local g = s.Partida.jogo()
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

-- Todos os valores do campo `chave` dentro de uma tabela, em qualquer nível.
local function coletar(v, chave, out)
  if type(v) ~= "table" then return out end
  for k, x in pairs(v) do
    if k == chave and type(x) ~= "table" then out[#out + 1] = x end
    coletar(x, chave, out)
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
    for _, f in ipairs({ f2, f3 }) do
      T.eq(f.escolha.p, 1); T.eq(f.escolha.n, 2); T.eq(f.escolha.motivo, "teste")
      T.eq(f.escolha.opcoes, nil, "sem as opções")
    end
  end },

  { "todas as RPCs são registradas nos dois lados, na mesma ordem", function(T)
    local net, s, cs = mesa()
    T.eq(s.ordem, "s:acao;s:pedir_estado;c:eventos;c:estado;c:recusada;")
    for _, c in ipairs(cs) do T.eq(c.ordem, s.ordem, "mesma ordem no cliente") end
  end },

  { "partida inteira bot x bot pelas RPCs termina igual à mesma partida direto no motor", function(T)
    local net, s, cs = mesa()
    local g, passos = jogar(T, s, cs, { seed = 11, tipos = { "bot", "bot" }, a_cada = function(passo)
      if passo % 3 == 0 or passo < 30 then conferir_visoes(T, s, cs, "passo " .. passo) end
    end })
    conferir_visoes(T, s, cs, "fim")
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
    local tipos_vistos, total_ocultos = {}, 0
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
            for _, uid in ipairs(coletar(msg.m, "card_uid", {})) do
              if dono[uid] ~= lado then
                T.ok(publica[uid], "seed " .. o.seed .. ", passo " .. passo .. ": o lado " .. lado
                  .. " recebeu em \"" .. msg.tipo .. "\" a carta " .. tostring(uid) .. " do lado "
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
    cs[1].Cliente.enviar({ type = "pass" })
    T.ok(recusas(net, "KU_um")[2] ~= nil, "jogada antes da troca é recusada")
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
    T.ok(tostring(cs[2].Cliente.visao().erro):find("carta quebrada de propósito", 1, true))
    conferir_visoes(T, s, cs, "depois do erro")
    cs[2].Cliente.enviar({ type = "pass" })
    T.eq(recusas(net, "KU_dois")[1].motivo, "partida encerrada por erro")
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
