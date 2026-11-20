-- A partida no servidor (US #41): o servidor decide as jogadas.
--
-- Este é o único módulo do mod que carrega o motor (duelo/core/game) e ele só
-- é carregado no servidor (modmain.lua). Os jogadores só mandam ações; aqui
-- elas são conferidas e aplicadas no motor, e o que acontece volta para cada
-- lado já filtrado por duelo/mod/visao (ninguém recebe a mão nem o baralho
-- do outro).
--
-- Uma partida por mundo. Lua puro: o que é do jogo chega por `ctx` em
-- `instalar`, e os testes (tests/test_mod_partida.lua) usam um transporte
-- falso em memória.
--
-- Interface:
--   Partida.instalar{ rede = Rede, GLOBAL = GLOBAL, log = fn } -> Partida
--       rede.enviar(userids, tipo, tabela) entrega uma mensagem aos clientes
--       e rede.usuarios() lista os userids conectados (duelo/mod/rede.lua).
--   Partida.iniciar{ decks = { d1, d2 }, extra_decks = { e1, e2 }, seed = n,
--                    jogadores = { [1] = userid, [2] = userid },
--                    first = 1 | 2 | nil, mulligan = false } -> ok, erro
--       cria o Game e começa a partida (encerra a anterior, se houver). Os
--       baralhos são listas de { id = ... }, como em Game.new, e as cartas
--       já precisam estar registradas (Decks.build registra). Sem `mulligan
--       = true` não há troca inicial. O mesmo userid nos dois lados é aceito
--       (teste sozinho): as ações dele valem para o lado que tem de agir e
--       ele recebe a visão do lado 1.
--   Partida.receber_acao(userid, action) -> { ok = bool, erro = texto }
--       acha o lado do userid (quem não joga é recusado), confere a forma da
--       ação, pergunta ao motor se ela vale (Game:can_act, que não muda nada)
--       e só então a aplica (Game:act; a troca inicial, { type = "mulligan",
--       indices = {...} }, vai por Game:mulligan). Depois de uma ação aceita,
--       os eventos novos e as mudanças do estado saem para todos.
--   Partida.pedir_estado(userid)   manda a fotografia do lado dele só a ele.
--   Partida.encerrar()             esquece a partida e avisa os clientes.
--   Partida.em_curso() -> bool     Partida.jogo() -> o Game (ou nil)
--   Partida.lado_de(userid) -> 1 | 2 | 3 (visão que ele recebe)
--   Partida.validar_forma(action) -> ok, erro
--
-- Console do host (DUELO.Partida no modmain.lua), enquanto a US #42 não chega:
--   DUELO.Partida.iniciar_teste([seed])  Wilson (lado 1) x Webber (lado 2) com
--       os jogadores dos lados 1 e 2 da mesa (duelo/mod/camera.lua); se só
--       houver um jogador, ele fica nos dois lados.
--   DUELO.Partida.estado()               imprime um resumo (com as duas mãos:
--       é o console do servidor).
--
-- Mensagens para os clientes (tabelas; a rede as serializa):
--   "estado"   { partida = n, seq = n, lado = 1 | 2 | 3, estado = fotografia }
--              ou { partida = false } quando não há partida.
--   "eventos"  { partida = n, seq = n, eventos = { ... }, mudancas = { ... } }
--              um lote por ação aceita: os eventos novos como aquele lado os
--              vê e as mudanças da fotografia dele (Visao.diferenca). `seq`
--              cresce de 1 em 1 em cada partida, igual para todos os lados; a
--              fotografia de `seq = n` é o estado depois do lote n.
--   A recusa ("recusada") é mandada pela rede, só a quem enviou a ação.

local Game = require("duelo/core/game")
local Visao = require("duelo/mod/visao")

local Partida = {}

Partida.LIMITES = {
  NOS = 64,          -- valores na ação inteira (contando tabelas e folhas)
  PROFUNDIDADE = 4,  -- tabelas dentro de tabelas
  TEXTO = 64,        -- caracteres de cada string (valor ou chave)
}

local LADOS = { 1, 2, 3 }

local estado = {
  rede = nil,
  GLOBAL = nil,
  log = nil,
  g = nil,            -- a partida em curso
  id = 0,             -- número da partida (cresce a cada iniciar)
  jogadores = nil,    -- { [1] = userid, [2] = userid }
  seq = 0,            -- último lote enviado
  enviados = 0,       -- quantos eventos de g.events já saíram
  fotos = nil,        -- última fotografia enviada a cada lado
}

local function log(msg)
  if estado.log then estado.log("[duelo] partida: " .. tostring(msg)) end
end

----------------------------------------------------------------------------
-- Forma da ação
----------------------------------------------------------------------------

local function forma(v, nivel, conta)
  conta.n = conta.n + 1
  if conta.n > Partida.LIMITES.NOS then return false, "ação grande demais" end
  local tv = type(v)
  if tv == "boolean" then return true end
  if tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return false, "número inválido na ação" end
    return true
  end
  if tv == "string" then
    if #v > Partida.LIMITES.TEXTO then return false, "texto grande demais na ação" end
    return true
  end
  if tv ~= "table" then return false, "valor inválido na ação" end
  if nivel > Partida.LIMITES.PROFUNDIDADE then return false, "ação funda demais" end
  if getmetatable(v) ~= nil then return false, "valor inválido na ação" end
  for k, x in pairs(v) do
    local tk = type(k)
    if tk == "string" then
      if #k > Partida.LIMITES.TEXTO then return false, "chave grande demais na ação" end
    elseif tk ~= "number" or k ~= k or k % 1 ~= 0 then
      return false, "chave inválida na ação"
    end
    local ok, err = forma(x, nivel + 1, conta)
    if not ok then return false, err end
  end
  return true
end

-- A ação é uma tabela pequena de números, strings, booleans e listas (a
-- mesma regra do serializador), com `type` em texto.
function Partida.validar_forma(action)
  if type(action) ~= "table" then return false, "ação inválida" end
  if type(action.type) ~= "string" then return false, "ação sem tipo" end
  return forma(action, 1, { n = 0 })
end

----------------------------------------------------------------------------
-- Lados
----------------------------------------------------------------------------

local function userid_valido(userid)
  return type(userid) == "string" and userid ~= ""
end

-- A visão que o userid recebe: o lado dele, ou espectador.
function Partida.lado_de(userid)
  local j = estado.jogadores
  if j and userid_valido(userid) then
    if j[1] == userid then return 1 end
    if j[2] == userid then return 2 end
  end
  return Visao.ESPECTADOR
end

-- Quem tem de agir agora: quem ainda não fez a troca inicial, quem tem uma
-- escolha aberta, senão quem tem a vez.
local function quem_age(g)
  if g.phase == "mulligan" then
    for p = 1, 2 do
      if not g.players[p].mulligan_done then return p end
    end
    return nil
  end
  if g.pending_choice then return g.pending_choice.player end
  return g.active
end

-- O lado pelo qual o userid joga (nil para quem não joga). Com o mesmo userid
-- nos dois lados, é o lado que tem de agir.
local function lado_de_jogo(userid)
  local j = estado.jogadores
  if not j or not userid_valido(userid) then return nil end
  local um, dois = j[1] == userid, j[2] == userid
  if um and dois then return quem_age(estado.g) or 1 end
  if um then return 1 end
  if dois then return 2 end
  return nil
end

----------------------------------------------------------------------------
-- Distribuição
----------------------------------------------------------------------------

-- Userids conectados separados pela visão que recebem.
local function destinos()
  local por_lado = { {}, {}, {} }
  local vistos = {}
  for _, userid in ipairs(estado.rede.usuarios() or {}) do
    if userid_valido(userid) and not vistos[userid] then
      vistos[userid] = true
      local lista = por_lado[Partida.lado_de(userid)]
      lista[#lista + 1] = userid
    end
  end
  return por_lado
end

local function mensagem_estado(lado)
  if estado.g == nil then return { partida = false } end
  return { partida = estado.id, seq = estado.seq, lado = lado, estado = estado.fotos[lado] }
end

-- Manda a todos o que aconteceu desde o último lote: os eventos novos,
-- filtrados para cada lado, e as mudanças da fotografia de cada lado.
local function distribuir()
  local g = estado.g
  local de = estado.enviados + 1
  local ate = #g.events
  estado.enviados = ate
  estado.seq = estado.seq + 1
  local por_lado = destinos()
  for _, lado in ipairs(LADOS) do
    local eventos = {}
    for i = de, ate do
      local ev = Visao.evento_para(g.events[i], lado, log)
      if ev ~= nil then eventos[#eventos + 1] = ev end
    end
    local foto = Visao.estado_para(g, lado)
    local msg = { partida = estado.id, seq = estado.seq, eventos = eventos,
      mudancas = Visao.diferenca(estado.fotos[lado], foto) }
    estado.fotos[lado] = foto
    if #por_lado[lado] > 0 then estado.rede.enviar(por_lado[lado], "eventos", msg) end
  end
end

local function enviar_estado_a_todos()
  local por_lado = destinos()
  for _, lado in ipairs(LADOS) do
    if #por_lado[lado] > 0 then estado.rede.enviar(por_lado[lado], "estado", mensagem_estado(lado)) end
  end
end

function Partida.pedir_estado(userid)
  if not userid_valido(userid) or estado.rede == nil then return false end
  estado.rede.enviar({ userid }, "estado", mensagem_estado(Partida.lado_de(userid)))
  return true
end

----------------------------------------------------------------------------
-- Partida
----------------------------------------------------------------------------

function Partida.em_curso() return estado.g ~= nil end
function Partida.jogo() return estado.g end
function Partida.jogadores() return estado.jogadores end

function Partida.iniciar(opts)
  opts = opts or {}
  if estado.rede == nil then return false, "o módulo não foi instalado" end
  local j = opts.jogadores or {}
  if not userid_valido(j[1]) or not userid_valido(j[2]) then
    return false, "é preciso o userid dos dois jogadores"
  end
  if type(opts.decks) ~= "table" or type(opts.decks[1]) ~= "table" or type(opts.decks[2]) ~= "table" then
    return false, "é preciso o baralho dos dois jogadores"
  end
  if estado.g ~= nil then Partida.encerrar() end
  local g = Game.new{
    decks = opts.decks, extra_decks = opts.extra_decks, seed = opts.seed,
    first = opts.first, mulligan = opts.mulligan == true,
  }
  estado.g = g
  estado.id = estado.id + 1
  estado.jogadores = { j[1], j[2] }
  estado.seq = 0
  estado.enviados = 0
  estado.fotos = {}
  for _, lado in ipairs(LADOS) do estado.fotos[lado] = Visao.estado_para(g, lado) end
  -- A fotografia de antes do início (seq 0) e, em seguida, o início como o
  -- primeiro lote: as compras da mão inicial chegam como eventos.
  enviar_estado_a_todos()
  local ok, err = g:start()
  distribuir()
  if not ok then
    log("o motor recusou o início: " .. tostring(err))
    return false, err
  end
  log("partida " .. estado.id .. " iniciada (semente " .. tostring(g.log.seed) .. "): lado 1 = "
    .. j[1] .. ", lado 2 = " .. j[2])
  return true
end

function Partida.encerrar()
  if estado.g == nil then return false end
  estado.g = nil
  estado.jogadores = nil
  estado.fotos = nil
  estado.seq = 0
  estado.enviados = 0
  enviar_estado_a_todos()
  log("partida " .. estado.id .. " encerrada")
  return true
end

local function recusa(erro)
  return { ok = false, erro = erro }
end

function Partida.receber_acao(userid, action)
  local g = estado.g
  if g == nil then return recusa("não há partida em curso") end
  local lado = lado_de_jogo(userid)
  if lado == nil then return recusa("só os dois jogadores jogam") end
  local ok, err = Partida.validar_forma(action)
  if not ok then return recusa(err) end

  if action.type == "mulligan" then
    if action.indices ~= nil and type(action.indices) ~= "table" then return recusa("troca inválida") end
    for _, i in ipairs(action.indices or {}) do
      if type(i) ~= "number" then return recusa("troca inválida") end
    end
    ok, err = g:mulligan(lado, action.indices)
  else
    -- Primeiro a pergunta, que não muda nada e não encerra a partida se a
    -- ação vier torta; só uma ação válida chega a Game:act.
    ok, err = g:can_act(lado, action)
    if ok then ok, err = g:act(lado, action) end
  end
  -- Toda ação aceita gera um lote, mesmo sem evento (o estado pode ter
  -- mudado). Um erro do motor encerra a partida e gera evento: o lote sai
  -- mesmo com a ação recusada.
  if ok or #g.events > estado.enviados then distribuir() end
  if not ok then return recusa(tostring(err or "ação recusada")) end
  return { ok = true }
end

----------------------------------------------------------------------------
-- Console do host (até a US #42)
----------------------------------------------------------------------------

-- Jogadores dos lados 1 e 2 da mesa (netvar duelo_lado de camera.lua); sem
-- ela, os dois primeiros de AllPlayers. Com um só, ele fica nos dois lados.
local function jogadores_da_mesa()
  local G = estado.GLOBAL or {}
  local por_lado, ordem = {}, {}
  for _, jogador in ipairs(G.AllPlayers or {}) do
    if userid_valido(jogador.userid) then
      ordem[#ordem + 1] = jogador.userid
      local lado = jogador.duelo_lado ~= nil and jogador.duelo_lado:value() or nil
      if (lado == 1 or lado == 2) and por_lado[lado] == nil then por_lado[lado] = jogador.userid end
    end
  end
  local um = por_lado[1] or ordem[1]
  local dois = por_lado[2]
  if dois == nil then
    for _, userid in ipairs(ordem) do
      if userid ~= um then dois = userid; break end
    end
  end
  return um, dois or um
end

function Partida.iniciar_teste(seed)
  local um, dois = jogadores_da_mesa()
  if um == nil then
    log("iniciar_teste: nenhum jogador conectado")
    return false, "nenhum jogador conectado"
  end
  local Decks = require("duelo/decks/init")
  local d1, e1 = Decks.build("wilson")
  local d2, e2 = Decks.build("webber")
  if um == dois then log("iniciar_teste: um jogador só, nos dois lados") end
  return Partida.iniciar{
    decks = { d1, d2 }, extra_decks = { e1, e2 }, seed = seed,
    jogadores = { um, dois },
  }
end

local function ids(lista)
  local out = {}
  for i, c in ipairs(lista) do out[i] = i .. ":" .. tostring(c.id) end
  return table.concat(out, " ")
end

local function campo(g, p)
  local out = {}
  for s = 1, Game.FIELD_SLOTS do
    local c = g.players[p].field[s]
    if c then out[#out + 1] = "c" .. s .. "=" .. tostring(c.def.id) .. "(uid " .. c.uid .. ")" end
  end
  for s = 1, Game.STRUCTURE_SLOTS do
    local st = g.players[p].structures[s]
    if st then out[#out + 1] = "e" .. s .. "=" .. tostring(st.def.id) end
  end
  return table.concat(out, " ")
end

-- Resumo em linhas (Partida.estado as imprime).
function Partida.resumo()
  local g = estado.g
  if g == nil then return { "[duelo] sem partida em curso" } end
  local linhas = {}
  local function add(s) linhas[#linhas + 1] = "[duelo] " .. s end
  add("partida " .. estado.id .. ": fase " .. tostring(g.phase) .. ", rodada " .. g.round .. ", vez " .. g.vez
    .. " (" .. tostring(g.current_period) .. "), age o lado " .. tostring(quem_age(g))
    .. ", lote " .. estado.seq .. ", " .. #g.events .. " eventos")
  if g.winner ~= nil then add("vencedor: " .. tostring(g.winner) .. " (0 = empate)") end
  if g.error then add("erro do motor: " .. tostring(g.error.message)) end
  if g.pending_choice then
    add("escolha pendente do lado " .. tostring(g.pending_choice.player) .. " (" .. tostring(g.pending_choice.reason)
      .. "), " .. #(g.pending_choice.options or {}) .. " opções")
  end
  for p = 1, 2 do
    local pl = g.players[p]
    add("lado " .. p .. " (" .. tostring(estado.jogadores[p]) .. "): vida " .. pl.life .. ", mana " .. pl.mana .. "/"
      .. pl.max_mana .. ", fogueira " .. tostring(g.fogueira[p]) .. ", baralho " .. #pl.deck)
    add("  mão: " .. ids(pl.hand))
    add("  campo: " .. campo(g, p))
  end
  return linhas
end

function Partida.estado()
  local imprimir = (estado.GLOBAL and estado.GLOBAL.print) or print
  for _, linha in ipairs(Partida.resumo()) do imprimir(linha) end
end

-- Liga o módulo.
--   ctx.rede: duelo/mod/rede.lua já instalado (enviar e usuarios);
--   ctx.GLOBAL: ambiente global do jogo (AllPlayers e print, para o console);
--   ctx.log: função de log (padrão: GLOBAL.print).
function Partida.instalar(ctx)
  estado.rede = ctx.rede
  estado.GLOBAL = ctx.GLOBAL
  estado.log = ctx.log or (ctx.GLOBAL and ctx.GLOBAL.print) or nil
  estado.g = nil
  estado.jogadores = nil
  estado.fotos = nil
  estado.seq = 0
  estado.enviados = 0
  if ctx.rede and ctx.rede.ligar_servidor then ctx.rede.ligar_servidor(Partida) end
  return Partida
end

return Partida
