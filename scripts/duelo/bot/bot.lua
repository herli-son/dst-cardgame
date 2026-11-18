-- Bot com jogadas válidas e estratégia simples. Lua 5.1 puro.
--
-- Interface:
--   local Bot = require("duelo/bot/bot")
--   local bot = Bot.new{ rng = function(n) ... end }   rng(n) devolve um inteiro
--                                                     de 1 a n; padrão math.random
--   bot:choose(g, p, jogadas) -> ação ou nil   escolhe entre as jogadas listadas
--                                              por Jogadas.list(g, p)
--   bot:act(g, p) -> o que g:act devolver     lista, escolhe e joga
--
-- O bot tem a mesma interface de um jogador humano: só lê o estado da partida
-- e joga por Game:act. Dado o mesmo rng e o mesmo estado, escolhe sempre a
-- mesma jogada; os desempates saem do rng.
--
-- Estratégia, nesta ordem:
--   1. escolha pendente: uma opção pelo rng;
--   2. bloqueio: se o dano sem bloqueio mata, o conjunto que deixa passar menos
--      dano (desempate: mais bloqueadores que sobrevivem, mais atacantes
--      mortos); senão, só bloqueios em que todos os bloqueadores sobrevivem;
--   3. jogar a carta mais cara que cabe na mana (desempate pelo rng; espaços e
--      alvos pelo rng); jogadas que substituem uma criatura sua ficam de fora;
--   4. ativar efeitos limitados por rodada ou período (os sem limite ficam de
--      fora, para o bot não ativar o mesmo efeito sem parar);
--   5. atacar com todas as criaturas quando a soma de ataque delas supera a do
--      adversário ou ele não tem quem bloqueie;
--   6. passar.

local Jogadas = require("duelo/bot/jogadas")

local Bot = {}
Bot.__index = Bot

function Bot.new(opts)
  opts = opts or {}
  local b = setmetatable({}, Bot)
  b.rng = opts.rng or function(n) return math.random(n) end
  return b
end

-- Um elemento da lista pelo rng (nil se vazia).
function Bot:pick(list)
  if #list == 0 then return nil end
  if #list == 1 then return list[1] end
  return list[self.rng(#list)]
end

local function by_type(jogadas)
  local groups = {}
  for _, a in ipairs(jogadas) do
    groups[a.type] = groups[a.type] or {}
    table.insert(groups[a.type], a)
  end
  return groups
end

local function sum_atk(g, list, filter)
  local total = 0
  for _, c in ipairs(list) do
    if filter == nil or filter(c) then total = total + g:atk(c) end
  end
  return total
end

----------------------------------------------------------------------------
-- Bloqueio
----------------------------------------------------------------------------

-- Simula o duelo entre atacante e bloqueador como o motor resolve: fase rápida
-- (velocidade 2 e 3), mortos saem, fase normal (velocidade 1 e 3) entre os que
-- sobraram. Devolve se o atacante morre e se o bloqueador morre.
local function duel(g, a, d)
  local va, vd = g:speed(a, "attack"), g:speed(d, "block")
  local atk_a, atk_d = g:atk(a), g:atk(d)
  local hp_a, hp_d = g:hp(a) - a.damage, g:hp(d) - d.damage
  local to_a, to_d = 0, 0
  if va >= 2 then to_d = to_d + atk_a end
  if vd >= 2 then to_a = to_a + atk_d end
  local a_dead, d_dead = to_a >= hp_a, to_d >= hp_d
  if not a_dead and not d_dead then
    if va == 1 or va == 3 then to_d = to_d + atk_a end
    if vd == 1 or vd == 3 then to_a = to_a + atk_d end
    a_dead, d_dead = to_a >= hp_a, to_d >= hp_d
  end
  return a_dead, d_dead
end

-- Avalia um conjunto de bloqueios: dano que chega ao jogador, bloqueadores que
-- sobrevivem e atacantes que morrem.
local function evaluate_block(g, p, cb, action)
  local blocked = {}
  local survivors, kills = 0, 0
  for _, b in ipairs(action.blocks) do
    local a = g:creature_at(cb.attacker, b.attacker)
    local d = g:creature_at(p, b.blocker)
    blocked[a] = true
    local a_dies, d_dies = duel(g, a, d)
    if not d_dies then survivors = survivors + 1 end
    if a_dies then kills = kills + 1 end
  end
  local through = 0
  for _, a in ipairs(cb.attackers) do
    if g.players[cb.attacker].field[a.slot] == a and not blocked[a] then through = through + g:atk(a) end
  end
  return { through = through, survivors = survivors, kills = kills, n = #action.blocks }
end

local function better_block(x, y)
  if x.through ~= y.through then return x.through < y.through end
  if x.survivors ~= y.survivors then return x.survivors > y.survivors end
  if x.kills ~= y.kills then return x.kills > y.kills end
  return x.n < y.n
end

local function same_block(x, y)
  return x.through == y.through and x.survivors == y.survivors and x.kills == y.kills and x.n == y.n
end

-- Devolve o bloqueio escolhido, ou nil para seguir com as outras prioridades.
function Bot:choose_block(g, p, blocks)
  local cb = g.combat
  if cb == nil or #blocks == 0 then return nil end
  local none = evaluate_block(g, p, cb, { blocks = {} })
  local lethal = g.players[p].life - none.through <= 0
  local best, best_list = nil, {}
  for _, a in ipairs(blocks) do
    local ev = evaluate_block(g, p, cb, a)
    local ok = lethal or ev.survivors == ev.n
    if ok then
      if best == nil or better_block(ev, best) then
        best, best_list = ev, { a }
      elseif same_block(ev, best) then
        best_list[#best_list + 1] = a
      end
    end
  end
  if best == nil or best.n == 0 then return nil end
  return self:pick(best_list)
end

----------------------------------------------------------------------------
-- Jogar
----------------------------------------------------------------------------

function Bot:choose_play(g, p, plays)
  local pl = g.players[p]
  local by_card, order = {}, {}
  local max_cost
  for _, a in ipairs(plays) do
    local card = pl[a.from or "hand"][a.hand_index]
    local def = g:def_of(card)
    -- Substituir uma criatura sua fica de fora.
    local replaces = def and def.kind == "criatura" and not def.sacrifice and g:creature_at(p, a.slot) ~= nil
    if not replaces then
      local key = (a.from or "hand") .. ":" .. a.hand_index
      if by_card[key] == nil then
        by_card[key] = { cost = g:card_cost(p, card), actions = {} }
        order[#order + 1] = key
        if max_cost == nil or by_card[key].cost > max_cost then max_cost = by_card[key].cost end
      end
      table.insert(by_card[key].actions, a)
    end
  end
  if max_cost == nil then return nil end
  local tied = {}
  for _, key in ipairs(order) do
    if by_card[key].cost == max_cost then tied[#tied + 1] = key end
  end
  return self:pick(by_card[self:pick(tied)].actions)
end

----------------------------------------------------------------------------
-- Ativar e atacar
----------------------------------------------------------------------------

local function source_def(g, p, a)
  if a.structure then
    local st = g:structure_at(p, a.structure)
    return st and st.def
  end
  local c = g:creature_at(p, a.creature)
  if c == nil then return nil end
  if a.equip == nil then return c.def end
  return c.equips[a.equip] and c.equips[a.equip].def
end

function Bot:choose_activate(g, p, list)
  local limited = {}
  for _, a in ipairs(list) do
    local def = source_def(g, p, a)
    local spec = def and def.activation
    if spec and (spec.once_per_round or spec.once_per_period) then limited[#limited + 1] = a end
  end
  return self:pick(limited)
end

function Bot:choose_attack(g, p, attacks)
  if #attacks == 0 then return nil end
  local o = g.other(p)
  local mine = sum_atk(g, g:creatures(p), function(c) return not c.def.no_attack end)
  local theirs = sum_atk(g, g:creatures(o))
  local blockers = 0
  for _, c in ipairs(g:creatures(o)) do
    if not c.def.no_block then blockers = blockers + 1 end
  end
  if not (blockers == 0 or mine > theirs) then return nil end
  local best = attacks[1]
  for _, a in ipairs(attacks) do
    if #a.attackers > #best.attackers then best = a end
  end
  return best
end

----------------------------------------------------------------------------
-- Escolha e jogada
----------------------------------------------------------------------------

function Bot:choose(g, p, jogadas)
  if #jogadas == 0 then return nil end
  local groups = by_type(jogadas)
  if groups.choose then return self:pick(groups.choose) end
  local a = self:choose_block(g, p, groups.block or {})
  if a then return a end
  a = self:choose_play(g, p, groups.play or {})
  if a then return a end
  a = self:choose_activate(g, p, groups.activate or {})
  if a then return a end
  a = self:choose_attack(g, p, groups.attack or {})
  if a then return a end
  if groups.pass then return groups.pass[1] end
  return jogadas[1]
end

-- Um erro de carta durante a avaliação (ex.: def.stats com bug) não derruba o
-- bot: ele passa, e o erro aparece quando a jogada rodar pelo motor.
function Bot:act(g, p)
  local jogadas = Jogadas.list(g, p)
  local ok, a = pcall(self.choose, self, g, p, jogadas)
  if not ok then
    a = nil
    for _, j in ipairs(jogadas) do if j.type == "pass" then a = j end end
  end
  if a == nil then return false, "nenhuma jogada disponível" end
  return g:act(p, a)
end

return Bot
