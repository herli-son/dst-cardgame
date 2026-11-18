local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local function new_game()
  Cards.define{ id = "lm_bicho", kind = "criatura", cost = 1, atk = 1, hp = 1 }
  Cards.define{ id = "lm_espada", kind = "equipamento", slot = "mao", cost = 1, atk_bonus = 1 }
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "lm_bicho" }; d2[i] = { id = "lm_bicho" } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function card(g, id) return { id = id or "lm_bicho", uid = g:next_uid() } end

local function end_round(g)
  g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
end

return {
  { "sem cartas a mais, nada está em risco e o fim da rodada não destrói nada", function(T)
    local g = new_game()
    T.eq(#g:hand_overflow(1), 0)
    end_round(g)
    T.eq(#g.players[1].destroyed, 0)
  end },

  { "as cartas em risco são as que entraram por último, em qualquer zona", function(T)
    local g = new_game()
    local remove = g:add_hand_limit_mod(function() return 3 end)
    while g:hand_count(1) < Game.HAND_LIMIT - 1 do g:add_to_hand(1, card(g)) end
    local a = card(g); g:add_to_hand(1, a)             -- 10ª
    local b = card(g, "lm_espada"); g:add_to_inventory(1, b) -- 11ª, no Inventário
    local c = card(g); g:add_to_hand(1, c)             -- 12ª
    remove()
    local risk = g:hand_overflow(1)
    T.eq(#risk, 2)
    T.eq(risk[1].card, c, "a última a entrar vem primeiro")
    T.eq(risk[2].card, b, "depois a do Inventário, que entrou antes")
    T.eq(risk[2].zone, "inventory")
    end_round(g)
    local pl = g.players[1]
    T.eq(#pl.inventory, 0)
    T.eq(g:hand_count(1), Game.HAND_LIMIT)
    T.eq(pl.destroyed[1], c); T.eq(pl.destroyed[2], b)
    local reasons = {}
    for _, ev in ipairs(g.events) do
      if ev.t == "destroyed" and ev.reason == "limite_de_mao_fim_rodada" then reasons[#reasons + 1] = ev.card_uid end
    end
    T.eq(reasons[1], c.uid, "os eventos saem na ordem de chegada invertida")
    T.eq(reasons[2], b.uid)
    local found = false
    for _, x in ipairs(pl.hand) do if x == a then found = true end end
    T.ok(found, "a 10ª fica")
  end },

  { "usar a carta em risco antes do fim da rodada evita a destruição", function(T)
    local g = new_game()
    local remove = g:add_hand_limit_mod(function() return 1 end)
    while g:hand_count(1) < Game.HAND_LIMIT + 1 do g:add_to_hand(1, card(g)) end
    remove()
    T.eq(#g:hand_overflow(1), 1)
    T.ok(g:act(1, { type = "play", hand_index = #g.players[1].hand, slot = 1 }))
    T.eq(#g:hand_overflow(1), 0)
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.eq(#g.players[1].destroyed, 1, "só a compra da rodada nova, com a mão cheia")
  end },

  { "o fim da rodada só mexe na mão de quem passou do limite", function(T)
    local g = new_game()
    local remove = g:add_hand_limit_mod(function(gg, p) return p == 2 and 2 or 0 end)
    while g:hand_count(2) < Game.HAND_LIMIT + 2 do g:add_to_hand(2, card(g)) end
    remove()
    end_round(g)
    T.eq(#g.players[1].destroyed, 0)
    T.eq(#g.players[2].destroyed, 2 + 1)
  end },

  { "o limite vale sobre o estado estável: a Mochila que cai com uma morte no fim da rodada já conta", function(T)
    local g = new_game()
    local remove = g:add_hand_limit_mod(function() return 2 end)
    Cards.define{ id = "lm_portador", kind = "criatura", cost = 0, atk = 0, hp = 1,
      on_death = function() remove() end }
    while g:hand_count(1) < Game.HAND_LIMIT + 2 do g:add_to_hand(1, card(g)) end
    local v = g:place_creature(1, { id = "lm_portador", uid = g:next_uid() }, 1)
    g:on("round_end", function(gg) gg:damage_creature(v, 1, nil, "teste") end)
    T.eq(#g:hand_overflow(1), 0, "antes do fim da rodada, nada em risco")
    end_round(g)
    -- A morte no fim da rodada tira o modificador; o excesso (2) é destruído
    -- antes da rodada nova, e a compra nova, com a mão cheia, também.
    T.eq(g.round, 2)
    T.eq(g:hand_count(1), Game.HAND_LIMIT)
    T.eq(#g.players[1].destroyed, 3)
  end },
}
