local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local log

local function define()
  log = {}
  Cards.define{ id = "s_base", kind = "criatura", cost = 0, atk = 1, hp = 9,
    on_death = function() log[#log + 1] = "morreu" end }
  Cards.define{ id = "s_nova", kind = "criatura", cost = 0, atk = 2, hp = 2,
    on_play = function(g, c) log[#log + 1] = "entrou:" .. c.slot end }
  Cards.define{ id = "s_espada", kind = "equipamento", slot = "mao", cost = 0, atk_bonus = 1 }
  Cards.define{ id = "s_sobrev", kind = "criatura", cost = 0, atk = 1, hp = 9, sobrevivente = true }
end

local function new_game()
  define()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "s_base" }; d2[i] = { id = "s_base" } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function give(g, p, id)
  local pl = g.players[p]
  pl.hand[#pl.hand + 1] = { id = id, uid = g:next_uid() }
  return #pl.hand
end

local function fill(g, p)
  local list = {}
  for s = 1, 6 do list[s] = g:place_creature(p, { id = "s_base", uid = g:next_uid() }, s) end
  return list
end

return {
  { "com espaço livre, não se substitui", function(T)
    local g = new_game()
    g:place_creature(1, { id = "s_base", uid = g:next_uid() }, 1)
    local ok, why = g:act(1, { type = "play", hand_index = give(g, 1, "s_nova"), slot = 1 })
    T.eq(ok, false)
    T.ok(why:find("campo cheio", 1, true) ~= nil)
  end },

  { "com o campo cheio, a substituída é destruída sem ao morrer", function(T)
    local g = new_game()
    local old = fill(g, 1)[3]
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "s_nova"), slot = 3 }))
    T.eq(g:creature_at(1, 3).def.id, "s_nova")
    local d = g.players[1].destroyed
    T.eq(d[#d].uid, old.card_uid)
    for _, e in ipairs(log) do T.ok(e ~= "morreu", "substituir não é morrer") end
    T.eq(log[#log], "entrou:3")
  end },

  { "os equipamentos da substituída vão para o Inventário", function(T)
    local g = new_game()
    local list = {}
    for s = 1, 6 do list[s] = g:place_creature(1, { id = "s_sobrev", uid = g:next_uid() }, s) end
    g:equip(list[2], { id = "s_espada", uid = g:next_uid() })
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "s_nova"), slot = 2 }))
    local inv = g.players[1].inventory
    T.eq(inv[#inv].id, "s_espada")
  end },
}
