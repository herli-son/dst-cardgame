-- Registro e reprodução de partidas (US #82). Lua 5.1 puro.
--
-- O motor guarda em g.log tudo o que basta para repetir a partida:
--   {
--     seed = n | nil,          semente do sorteio (nil: a partida recebeu um rng
--                              de fora e não é reproduzível)
--     first = 1 | 2 | nil,     quem começou, como pedido em Game.new (nil: sorteado)
--     mulligan = boolean,      se a troca inicial faz parte da partida
--     decks = { ids, ids },    baralho principal de cada jogador: lista de ids,
--                              na ordem dada a Game.new (antes de embaralhar)
--     extra_decks = { ids, ids },
--     actions = { { p = 1 | 2, action = {...} }, ... }   as ações aceitas, na
--                              ordem, com cópia; a troca inicial entra como
--                              { type = "mulligan", indices = {...} }. Uma ação
--                              que encerrou a partida por erro também entra, por
--                              último.
--   }
--
-- Interface:
--   local Replay = require("duelo/core/replay")
--   Replay.run(log) -> g            cria uma partida nova com a mesma semente e os
--                                   mesmos baralhos e reaplica as ações. As cartas
--                                   dos ids precisam estar registradas (Cards.define).
--                                   Erro com o índice se uma ação for recusada na
--                                   reprodução. Se a partida original terminou por
--                                   erro, a reprodução para no mesmo ponto, com
--                                   g.phase == "error" e a mesma mensagem.
--   Replay.snapshot(g) -> tabela    o estado observável da partida, sem referências
--                                   cíclicas nem funções: fase, rodada, vez, vida,
--                                   mana, zonas (ids e uids), campo, fogueira,
--                                   escolha pendente, erro e os eventos.
--   Replay.same_state(a, b) -> ok, diferença   compara duas partidas por snapshot;
--                                   a diferença diz o primeiro ponto que mudou.
--   Replay.log_to_string(log) -> s  serializa o registro num texto (tabela Lua).
--                                   Erro se houver algo que não seja número,
--                                   string, boolean ou tabela sem ciclo.
--   Replay.log_from_string(s) -> log   o caminho de volta; erro se o texto não
--                                   for um registro serializado por este módulo.
--   Replay.serialize(v) / Replay.deserialize(s)   as mesmas funções, para
--                                   qualquer valor simples (chaves ordenadas: o
--                                   mesmo valor dá sempre o mesmo texto). São
--                                   as de duelo/core/serial, que não depende
--                                   do motor.

local Game = require("duelo/core/game")
local Serial = require("duelo/core/serial")

local Replay = {}

----------------------------------------------------------------------------
-- Serialização
----------------------------------------------------------------------------

-- As funções moram em duelo/core/serial (sem dependência do motor), para os
-- clientes do mod poderem usá-las sem carregar o motor (US #41).
local sort_keys = Serial.sort_keys
Replay.serialize = Serial.serialize
Replay.deserialize = Serial.deserialize

function Replay.log_to_string(log)
  assert(type(log) == "table" and type(log.actions) == "table", "registro inválido")
  return Replay.serialize(log)
end

function Replay.log_from_string(s)
  local log = Replay.deserialize(s)
  if type(log) ~= "table" or type(log.actions) ~= "table" or type(log.decks) ~= "table" then
    error("o texto não é um registro de partida", 0)
  end
  return log
end

----------------------------------------------------------------------------
-- Reprodução
----------------------------------------------------------------------------

local function ids_to_deck(ids)
  local deck = {}
  for i, id in ipairs(ids or {}) do deck[i] = { id = id } end
  return deck
end

function Replay.run(log)
  assert(type(log) == "table" and type(log.actions) == "table", "registro inválido")
  if log.seed == nil then error("registro sem semente: a partida não é reproduzível", 0) end
  local g = Game.new{
    seed = log.seed, first = log.first, mulligan = log.mulligan,
    decks = { ids_to_deck(log.decks and log.decks[1]), ids_to_deck(log.decks and log.decks[2]) },
    extra_decks = { ids_to_deck(log.extra_decks and log.extra_decks[1]), ids_to_deck(log.extra_decks and log.extra_decks[2]) },
  }
  local n = #log.actions
  local ok, err = g:start()
  if not ok then
    if g.phase == "error" and n == 0 then return g end
    error("reprodução: início recusado: " .. tostring(err), 0)
  end
  for i, entry in ipairs(log.actions) do
    local action = Game.deep_copy(entry.action)
    if type(action) == "table" and action.type == "mulligan" then
      ok, err = g:mulligan(entry.p, action.indices)
    else
      ok, err = g:act(entry.p, action)
    end
    if not ok then
      -- Só a última ação, e só quando o registro diz que a original também
      -- encerrou a partida por erro; qualquer outra recusa é divergência.
      if g.phase == "error" and i == n and log.error then return g end
      error("reprodução: ação " .. i .. " recusada (" .. tostring(err) .. ")", 0)
    end
  end
  return g
end


----------------------------------------------------------------------------
-- Estado observável, para comparar partidas
----------------------------------------------------------------------------

-- Campos que ligam um objeto a outros (ou a definições com funções): ficam fora.
local SKIP = { card = true, def = true, link = true, holder = true }

-- Cópia simples de um valor: só números, strings, booleans e tabelas, sem os
-- campos de ligação e sem funções. Ciclos são erro.
local function plain(v, seen)
  if type(v) ~= "table" then
    if type(v) == "function" or type(v) == "userdata" or type(v) == "thread" then return nil end
    return v
  end
  seen = seen or {}
  if seen[v] then error("referência cíclica no estado") end
  seen[v] = true
  local c = {}
  for k, x in pairs(v) do
    if not SKIP[k] then c[k] = plain(x, seen) end
  end
  seen[v] = nil
  return c
end

local function card_ids(list)
  local out = {}
  for i, card in ipairs(list) do out[i] = { id = card.id, uid = card.uid } end
  return out
end

local function object_state(o)
  if o == nil then return false end
  local s = plain(o)
  s.id = o.def and o.def.id or o.id
  if o.card then s.card_id = o.card.id end
  return s
end

local function slots(list, n)
  local out = {}
  for i = 1, n do out[i] = object_state(list[i]) end
  return out
end

-- Itens da pilha: dono, rótulo e uids das cartas/alvos travados (campos simples).
local function stack_state(g)
  local out = {}
  for i, e in ipairs(g.stack or {}) do
    out[i] = { owner = e.owner, label = e.label, card = e.card and e.card.uid or false,
      source = e.source and e.source.uid or false }
  end
  return out
end

local function uids(list)
  local out = {}
  for i, c in ipairs(list or {}) do out[i] = c.uid or false end
  return out
end

function Replay.snapshot(g)
  local s = {
    phase = g.phase, round = g.round, vez = g.vez, active = g.active, attacker = g.attacker,
    first = g.first, winner = g.winner, passes = g.passes, period = g.current_period,
    fogueira = { g.fogueira[1] or false, g.fogueira[2] or false },
    fogueira_pending = { g.fogueira_pending[1], g.fogueira_pending[2] },
    pending_choice = g.pending_choice and { player = g.pending_choice.player, reason = g.pending_choice.reason,
      count = #(g.pending_choice.options or {}), options = plain(g.pending_choice.options) } or false,
    stack = stack_state(g),
    combat = g.combat and plain({ attacker = g.combat.attacker, defender = g.combat.defender,
      attackers = uids(g.combat.attackers), blocks_declared = g.combat.blocks_declared }) or false,
    error = g.error and { message = g.error.message, context = plain(g.error.context) } or false,
    players = {},
    events = plain(g.events),
  }
  for p = 1, 2 do
    local pl = g.players[p]
    s.players[p] = {
      life = pl.life, mana = pl.mana, max_mana = pl.max_mana, fome = pl.fome, mulligan_done = pl.mulligan_done,
      hand = card_ids(pl.hand), deck = card_ids(pl.deck), extra = card_ids(pl.extra),
      discard = card_ids(pl.discard), destroyed = card_ids(pl.destroyed),
      inventory = card_ids(pl.inventory), separated = card_ids(pl.separated),
      field = slots(pl.field, Game.FIELD_SLOTS or 6),
      structures = slots(pl.structures, Game.STRUCTURE_SLOTS or 2),
    }
  end
  return s
end

-- Primeiro caminho em que dois valores simples diferem (nil se forem iguais).
local function first_diff(a, b, path)
  if type(a) ~= type(b) then return path .. ": " .. tostring(a) .. " ~= " .. tostring(b) end
  if type(a) ~= "table" then
    if a ~= b then return path .. ": " .. tostring(a) .. " ~= " .. tostring(b) end
    return nil
  end
  local keys, seen = {}, {}
  for k in pairs(a) do keys[#keys + 1] = k; seen[k] = true end
  for k in pairs(b) do if not seen[k] then keys[#keys + 1] = k end end
  table.sort(keys, sort_keys)
  for _, k in ipairs(keys) do
    local d = first_diff(a[k], b[k], path .. "." .. tostring(k))
    if d then return d end
  end
  return nil
end
Replay.first_diff = first_diff

function Replay.same_state(a, b)
  local d = first_diff(Replay.snapshot(a), Replay.snapshot(b), "estado")
  return d == nil, d
end

return Replay
