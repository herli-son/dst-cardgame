local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local function new_game()
  Cards.define{ id = "e_w", kind = "criatura", cost = 0, atk = 1, hp = 5 }
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "e_w" }; d2[i] = { id = "e_w" } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function put(g, p, id, slot)
  return g:place_creature(p, { id = id, uid = g:next_uid() }, slot)
end

return {
  { "escolha aberta na fase rápida segura a fase normal", function(T)
    local g = new_game()
    Cards.define{ id = "e_rapida", kind = "criatura", cost = 0, atk = 2, hp = 2, speed = 2 }
    Cards.define{ id = "e_z", kind = "criatura", cost = 0, atk = 1, hp = 3 }
    Cards.define{ id = "e_y", kind = "criatura", cost = 0, atk = 0, hp = 2,
      on_death = function(gg, c)
        gg:set_choice(c.owner, { reason = "dano", options = { "z" }, resolve = function(g2)
          local z = g2:creature_at(1, 2)
          if z then g2:damage_creature(z, 3, nil, "teste") end
        end })
      end }
    put(g, 1, "e_rapida", 1); put(g, 1, "e_z", 2)
    put(g, 2, "e_y", 1); local w = put(g, 2, "e_w", 2)
    T.ok(g:act(1, { type = "attack", attackers = { 1, 2 } })); g:act(1, { type = "pass" })
    T.ok(g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 }, { attacker = 2, blocker = 2 } } }))
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.ok(g.pending_choice ~= nil)
    T.eq(w.damage, 0, "a fase normal espera a escolha")
    T.ok(g:act(2, { type = "choose", index = 1 }))
    T.eq(g:creature_at(1, 2), nil, "Z morreu antes de golpear")
    T.eq(w.damage, 0)
    T.eq(g:stack_open(), false)
    local ends = 0
    for _, ev in ipairs(g.events) do if ev.t == "combat_end" then ends = ends + 1 end end
    T.eq(ends, 1)
  end },

  { "escolha aberta no fim da rodada segura o começo da próxima", function(T)
    local g = new_game()
    local opened_at, resolved_at
    Cards.define{ id = "e_y1", kind = "criatura", cost = 0, atk = 0, hp = 1,
      on_death = function(gg, c)
        gg:set_choice(c.owner, { reason = "ao morrer", options = { "a" },
          resolve = function(g2) resolved_at = g2.round end })
      end }
    local y = put(g, 2, "e_y1", 1)
    g:on("round_end", function(gg) gg:damage_creature(y, 1, nil, "teste") end)
    g:on("round_start", function(gg) opened_at = gg.pending_choice ~= nil end)
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g.round, 1, "a rodada nova espera a escolha")
    T.ok(g:act(2, { type = "choose", index = 1 }))
    T.eq(resolved_at, 1)
    T.eq(g.round, 2)
    T.eq(opened_at, false)
  end },
}
