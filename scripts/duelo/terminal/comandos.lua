-- Interpretação dos comandos do terminal. Lua 5.1 puro.
--
-- Interface:
--   local Comandos = require("duelo/terminal/comandos")
--   Comandos.parse(g, p, linha) -> action | nil, erro
--   Comandos.help() -> string
--   Comandos.alvo(p, token) -> alvo do motor | nil, erro
--
-- O parse não executa nada: só lê a linha e devolve a ação no formato que
-- Game:act aceita (type, hand_index, from, slot, target, replace, sacrifice,
-- attackers, blocks, structure, creature, equip, index). Ele consulta o estado
-- (g, p) só para saber o tipo da carta e completar o que der: o espaço livre
-- de uma criatura, por exemplo. Quando falta algo, o erro diz o que falta.
--
-- Comandos que não são jogadas do motor voltam com type próprio, para a camada
-- de cima tratar: { type = "jogadas" }, { type = "ajuda" }, { type = "sair" }.
-- "j <n>" devolve a n-ésima jogada de Jogadas.list(g, p).
--
-- Alvos: c1..c6 (minhas criaturas), o1..o6 (criaturas do oponente), e1/e2 e
-- oe1/oe2 (estruturas), eu e ele (jogadores).

local Game = require("duelo/core/game")
local Jogadas = require("duelo/bot/jogadas")

local Comandos = {}

local AJUDA = [[
Comandos:
  jogar <n> [em <espaco>] [em <alvo>] [sacrificando <espacos>] [substituindo <espaco>]
      joga a carta n da mao; criatura sem "em" entra no primeiro espaco livre
  inv <n> ...           joga a carta n do Inventario (ou: jogar inv <n>)
  sep <n> ...           joga a carta n das separadas
  atacar <espacos...>   ataca com as criaturas (ex.: atacar c1 c3); atacar todos
  bloquear <atacante>=<bloqueador> ...   ex.: bloquear o1=c2 o3=c1; bloquear nada
  ativar <estrutura> [em <alvo>]         ex.: ativar e1
  ativar <criatura> [mao|peito|cabeca] [em <alvo>]   efeito da criatura ou do equipamento
  escolher <n>          responde a escolha pendente; escolher nada
  passar                passa a vez (com a pilha aberta: pronto)
  jogadas               lista as jogadas validas numeradas; j <n> executa uma
  ajuda                 mostra esta lista
  sair                  encerra a partida
Alvos: c1..c6 minhas criaturas, o1..o6 do oponente, e1/e2 e oe1/oe2 estruturas,
eu e ele os jogadores.]]

function Comandos.help()
  return AJUDA
end

----------------------------------------------------------------------------
-- Leitura
----------------------------------------------------------------------------

local function tokens(linha)
  local list = {}
  for w in tostring(linha or ""):gmatch("%S+") do list[#list + 1] = w:lower() end
  return list
end

local function inteiro(tok)
  if tok == nil then return nil end
  local n = tonumber(tok)
  if n == nil or n % 1 ~= 0 then return nil end
  return n
end

-- Espaço de criatura: "c3", "o3" ou "3". Devolve número e lado ("c" | "o" | nil).
local function espaco_criatura(tok)
  if tok == nil then return nil end
  local lado, n = tok:match("^([co]?)(%d+)$")
  if lado == nil then return nil end
  n = tonumber(n)
  if n < 1 or n > Game.FIELD_SLOTS then return nil end
  if lado == "" then lado = nil end
  return n, lado
end

-- Espaço de estrutura: "e1", "oe1" ou "1".
local function espaco_estrutura(tok)
  if tok == nil then return nil end
  local lado, n = tok:match("^(o?e?)(%d+)$")
  if lado == nil then return nil end
  n = tonumber(n)
  if n < 1 or n > Game.STRUCTURE_SLOTS then return nil end
  return n, lado
end

-- Alvo no formato do motor a partir de um token (c1, o1, e1, oe1, eu, ele).
function Comandos.alvo(p, tok)
  if tok == nil then return nil, "falta o alvo" end
  local o = Game.other(p)
  if tok == "eu" then return { p = p, zone = "jogador" } end
  if tok == "ele" then return { p = o, zone = "jogador" } end
  local lado, n = tok:match("^([co])(%d+)$")
  if lado then
    n = tonumber(n)
    if n < 1 or n > Game.FIELD_SLOTS then return nil, "espaço de criatura inválido: " .. tok end
    return { p = lado == "c" and p or o, slot = n, zone = "criatura" }
  end
  lado, n = tok:match("^(o?e)(%d+)$")
  if lado == nil then
    return nil, "alvo inválido: " .. tok .. " (use c1..c6, o1..o6, e1, e2, oe1, oe2, eu ou ele)"
  end
  n = tonumber(n)
  if n < 1 or n > Game.STRUCTURE_SLOTS then return nil, "espaço de estrutura inválido: " .. tok end
  return { p = lado == "e" and p or o, slot = n, zone = "estrutura" }
end

-- Lê os modificadores "em", "sacrificando" e "substituindo" a partir de toks[i].
-- Devolve { em = { tokens... }, sacrificando = { tokens... }, substituindo = tok }.
local function modificadores(toks, i)
  local m = { em = {}, sacrificando = {} }
  local atual
  while i <= #toks do
    local t = toks[i]
    if t == "em" or t == "no" or t == "na" then
      atual = "em"
    elseif t == "sacrificando" or t == "sacrificar" then
      atual = "sacrificando"
    elseif t == "substituindo" or t == "substituir" then
      atual = "substituindo"
    elseif atual == "em" then
      m.em[#m.em + 1] = t
    elseif atual == "sacrificando" then
      m.sacrificando[#m.sacrificando + 1] = t
    elseif atual == "substituindo" then
      if m.substituindo then return nil, "só uma substituição por jogada" end
      m.substituindo = t
    else
      return nil, "não entendi \"" .. t .. "\""
    end
    i = i + 1
  end
  return m
end

----------------------------------------------------------------------------
-- Jogar
----------------------------------------------------------------------------

local ZONAS = { hand = "na mão", inventory = "no Inventário", separated = "nas separadas" }

local function parse_jogar(g, p, toks, i, from)
  local n = inteiro(toks[i])
  if n == nil then return nil, "falta o número da carta (jogar <n>)" end
  local card = g.players[p][from][n]
  if card == nil then return nil, "não há carta " .. n .. " " .. ZONAS[from] end
  local def = g:def_of(card)
  if def == nil then return nil, "carta desconhecida: " .. tostring(card.id) end
  local m, err = modificadores(toks, i + 1)
  if m == nil then return nil, err end
  local action = { type = "play", hand_index = n, from = from }

  -- Cada "em X": número puro é espaço da própria carta; token com prefixo é alvo.
  local espaco, alvo_tok
  for _, t in ipairs(m.em) do
    if inteiro(t) then
      if espaco then return nil, "só um espaço por jogada" end
      espaco = inteiro(t)
    else
      if alvo_tok then return nil, "só um alvo por jogada" end
      alvo_tok = t
    end
  end
  local mira = def.targets ~= nil or def.play_targets ~= nil

  if def.kind == "criatura" then
    if def.sacrifice then
      if #m.sacrificando == 0 then
        return nil, "falta o sacrifício: sacrificando <" .. def.sacrifice.count .. " espaço(s)>"
      end
      action.sacrifice = {}
      for _, t in ipairs(m.sacrificando) do
        local s = espaco_criatura(t)
        if s == nil then return nil, "espaço de sacrifício inválido: " .. t end
        action.sacrifice[#action.sacrifice + 1] = s
      end
    end
    if m.substituindo then
      local s = espaco_criatura(m.substituindo)
      if s == nil then return nil, "espaço a substituir inválido: " .. m.substituindo end
      espaco = s
    end
    if espaco == nil and alvo_tok and not mira then
      -- "jogar 1 em c3": o alvo é o próprio espaço.
      local s, lado = espaco_criatura(alvo_tok)
      if s and lado == "c" then espaco, alvo_tok = s, nil end
    end
    if espaco == nil then
      local livres = g:free_slots(p)
      if action.sacrifice and #action.sacrifice > 0 then
        espaco = livres[1] or action.sacrifice[1]
      elseif #livres > 0 then
        espaco = livres[1]
      else
        return nil, "campo cheio: falta o espaço a substituir (substituindo c1..c6)"
      end
    end
    action.slot = espaco
  elseif def.kind == "estrutura" then
    if m.substituindo then
      local s = espaco_estrutura(m.substituindo)
      if s == nil then return nil, "espaço a substituir inválido: " .. m.substituindo end
      espaco = s
    end
    if espaco == nil and alvo_tok and not mira then
      local s, lado = espaco_estrutura(alvo_tok)
      if s and lado == "e" then espaco, alvo_tok = s, nil end
    end
    if espaco == nil and Game.first_free_structure(g, p) == nil then
      return nil, "zona de estruturas cheia: falta o espaço a substituir (substituindo e1 ou e2)"
    end
    action.slot = espaco
  elseif def.kind == "equipamento" then
    local s
    if espaco then s = espaco end
    if alvo_tok then
      local n2, lado = espaco_criatura(alvo_tok)
      if n2 == nil or lado == "o" then return nil, "o equipamento vai numa criatura sua (em c1..c6)" end
      s = n2
    end
    if s == nil then return nil, "falta a criatura que vai usar o equipamento (em c1..c6)" end
    action.target = s
    return action
  elseif def.kind == "feitico" then
    if def.creates_structure and Game.first_free_structure(g, p) == nil then
      local s = espaco_estrutura(m.substituindo or "")
      if s == nil then return nil, "zona de estruturas cheia: falta a estrutura a substituir (substituindo e1 ou e2)" end
      action.replace = s
    end
    if espaco and alvo_tok == nil then
      return nil, "o alvo de um feitiço precisa do lado (c" .. espaco .. " ou o" .. espaco .. ")"
    end
  end

  if mira then
    if alvo_tok == nil then
      return nil, "falta o alvo (em c1..c6, o1..o6, e1, e2, oe1, oe2, eu ou ele)"
    end
    local t, err2 = Comandos.alvo(p, alvo_tok)
    if t == nil then return nil, err2 end
    action.target = t
  elseif alvo_tok then
    return nil, "essa carta não tem alvo; para escolher o espaço use em c1..c6 (criatura) ou em e1, e2 (estrutura)"
  end
  return action
end

----------------------------------------------------------------------------
-- Combate
----------------------------------------------------------------------------

local function parse_atacar(g, p, toks)
  if toks[2] == nil then return nil, "falta quem ataca (atacar c1 c2 ... ou atacar todos)" end
  local attackers = {}
  if toks[2] == "todos" or toks[2] == "todas" then
    for _, c in ipairs(g:creatures(p)) do
      if not c.def.no_attack then attackers[#attackers + 1] = c.slot end
    end
    if #attackers == 0 then return nil, "você não tem criaturas que ataquem" end
    return { type = "attack", attackers = attackers }
  end
  for i = 2, #toks do
    local s, lado = espaco_criatura(toks[i])
    if s == nil or lado == "o" then return nil, "espaço inválido para atacar: " .. toks[i] .. " (use c1..c6)" end
    attackers[#attackers + 1] = s
  end
  return { type = "attack", attackers = attackers }
end

local function parse_bloquear(g, p, toks)
  if toks[2] == nil then
    return nil, "falta o bloqueio (bloquear o1=c2 ... ou bloquear nada)"
  end
  local blocks = {}
  if toks[2] == "nada" or toks[2] == "nenhum" then return { type = "block", blocks = blocks } end
  for i = 2, #toks do
    local a, b = toks[i]:match("^([^=]+)=([^=]+)$")
    if a == nil then return nil, "bloqueio inválido: " .. toks[i] .. " (use <atacante>=<bloqueador>, ex.: o1=c2)" end
    local sa, la = espaco_criatura(a)
    local sb, lb = espaco_criatura(b)
    if sa == nil or la == "c" then return nil, "atacante inválido: " .. a .. " (use o1..o6)" end
    if sb == nil or lb == "o" then return nil, "bloqueador inválido: " .. b .. " (use c1..c6)" end
    blocks[#blocks + 1] = { attacker = sa, blocker = sb }
  end
  return { type = "block", blocks = blocks }
end

----------------------------------------------------------------------------
-- Ativar e escolher
----------------------------------------------------------------------------

local function parse_ativar(g, p, toks)
  local fonte = toks[2]
  if fonte == nil then return nil, "falta o que ativar (ativar e1, ativar c1 ou ativar c1 mao)" end
  local action = { type = "activate" }
  local i = 3
  local lado, n = fonte:match("^([co]?e?)(%d+)$")
  if lado == nil then return nil, "fonte inválida: " .. fonte .. " (use e1, e2 ou c1..c6)" end
  if lado == "e" or lado == "" then
    local s = espaco_estrutura(fonte)
    if s == nil then return nil, "espaço de estrutura inválido: " .. fonte end
    action.structure = s
  elseif lado == "c" then
    local s = espaco_criatura(fonte)
    if s == nil then return nil, "espaço de criatura inválido: " .. fonte end
    action.creature = s
    if Game.EQUIP_SLOTS[toks[3] or ""] then
      action.equip = toks[3]
      i = 4
    end
  else
    return nil, "só se ativa o que é seu (e1, e2 ou c1..c6)"
  end
  local m, err = modificadores(toks, i)
  if m == nil then return nil, err end
  if #m.em > 1 then return nil, "só um alvo por ativação" end
  if m.em[1] then
    local t, err2 = Comandos.alvo(p, m.em[1])
    if t == nil then return nil, err2 end
    action.target = t
  end
  return action
end

local function parse_escolher(g, p, toks)
  if toks[2] == nil then return nil, "falta a opção (escolher <n> ou escolher nada)" end
  if toks[2] == "nada" or toks[2] == "nenhuma" or toks[2] == "nenhum" then
    return { type = "choose", index = 0 }
  end
  local n = inteiro(toks[2])
  if n == nil then return nil, "opção inválida: " .. toks[2] end
  return { type = "choose", index = n }
end

----------------------------------------------------------------------------
-- Entrada
----------------------------------------------------------------------------

local ZONA_DO_COMANDO = { inv = "inventory", inventario = "inventory", sep = "separated", separadas = "separated" }

function Comandos.parse(g, p, linha)
  local toks = tokens(linha)
  local cmd = toks[1]
  if cmd == nil then return nil, "digite um comando (ajuda para a lista)" end
  if cmd == "jogar" then
    if ZONA_DO_COMANDO[toks[2] or ""] then return parse_jogar(g, p, toks, 3, ZONA_DO_COMANDO[toks[2]]) end
    return parse_jogar(g, p, toks, 2, "hand")
  end
  if ZONA_DO_COMANDO[cmd] then return parse_jogar(g, p, toks, 2, ZONA_DO_COMANDO[cmd]) end
  if cmd == "atacar" then return parse_atacar(g, p, toks) end
  if cmd == "bloquear" then return parse_bloquear(g, p, toks) end
  if cmd == "ativar" then return parse_ativar(g, p, toks) end
  if cmd == "escolher" then return parse_escolher(g, p, toks) end
  if cmd == "passar" or cmd == "pronto" then return { type = "pass" } end
  if cmd == "jogadas" then return { type = "jogadas" } end
  if cmd == "ajuda" or cmd == "help" or cmd == "?" then return { type = "ajuda" } end
  if cmd == "sair" then return { type = "sair" } end
  if cmd == "j" then
    local n = inteiro(toks[2])
    if n == nil then return nil, "falta o número da jogada (j <n>; veja: jogadas)" end
    local lista = Jogadas.list(g, p)
    if lista[n] == nil then return nil, "não há jogada " .. tostring(n) .. " (veja: jogadas)" end
    return lista[n]
  end
  return nil, "comando desconhecido: " .. cmd .. " (ajuda para a lista)"
end

return Comandos
