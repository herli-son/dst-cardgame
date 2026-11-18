local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local IDS = { "t_coelho", "t_sobrev", "t_rocha", "t_machado" }

local function define_test_cards()
  Cards.define{ id = "t_coelho", kind = "criatura", cost = 1, atk = 1, hp = 1 }
  Cards.define{ id = "t_sobrev", kind = "criatura", cost = 0, atk = 1, hp = 3, sobrevivente = true }
  Cards.define{ id = "t_rocha", kind = "estrutura", cost = 0 }
  Cards.define{ id = "t_machado", kind = "equipamento", slot = "mao", cost = 0, atk_bonus = 2 }
end

local function clear_test_cards()
  for _, id in ipairs(IDS) do Cards.remove(id) end
end

-- Baralho extra com cópias das cartas que os testes criam.
local function extra_deck(ids, n)
  local list = {}
  for _, id in ipairs(ids) do
    for _ = 1, n do list[#list + 1] = { id = id } end
  end
  return list
end

local function new_game()
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "t_coelho" }; d2[i] = { id = "t_coelho" } end
  local extra = { "t_coelho", "t_rocha" }
  local g = Game.new{ decks = { d1, d2 }, extra_decks = { extra_deck(extra, 10), extra_deck(extra, 10) },
    first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

return {
  { "ficha de criatura tem os mesmos atributos da carta de mesmo nome", function(T)
    local g = new_game()
    local c = g:create_token(1, "t_coelho", { slot = 4 })
    T.ok(c ~= nil)
    T.eq(c.slot, 4)
    T.eq(c.ficha, true)
    T.eq(g:atk(c), 1)
    T.eq(g:hp(c), 1)
    clear_test_cards()
  end },

  { "ficha vai para o primeiro espaço livre; sem espaço, não é criada", function(T)
    local g = new_game()
    for s = 1, 5 do g:create_token(1, "t_coelho", { slot = s }) end
    local c = g:create_token(1, "t_coelho", { slot = 1 })
    T.eq(c.slot, 6, "espaço ocupado: usa o primeiro livre")
    T.eq(g:create_token(1, "t_coelho"), nil)
    clear_test_cards()
  end },

  { "ficha que sai de campo deixa de existir em qualquer destino", function(T)
    local g = new_game()
    local pl = g.players[1]
    local hand, discard, destroyed, deck = #pl.hand, #pl.discard, #pl.destroyed, #pl.deck
    for _, dest in ipairs({ "discard", "hand", "deck", "destroyed" }) do
      local c = g:create_token(1, "t_coelho")
      g:remove_creature(c, dest, "teste")
      T.eq(g:creature_at(1, c.slot), nil)
    end
    T.eq(#pl.hand, hand); T.eq(#pl.discard, discard)
    T.eq(#pl.destroyed, destroyed); T.eq(#pl.deck, deck)
    clear_test_cards()
  end },

  { "criatura normal que sai de campo vai para o destino e leva os equipamentos ao descarte", function(T)
    local g = new_game()
    local c = g:place_creature(1, { id = "t_sobrev", uid = g:next_uid() }, 2)
    g:equip(c, { id = "t_machado", uid = g:next_uid() })
    g:remove_creature(c, "discard", "abatida")
    local d = g.players[1].discard
    T.eq(#d, 2)
    T.eq(d[1].id, "t_machado")
    T.eq(d[2].id, "t_sobrev")
    clear_test_cards()
  end },

  { "ficha criada na mão com o limite cheio deixa de existir, não vai para as destruídas", function(T)
    local g = new_game()
    local pl = g.players[1]
    T.ok(g:create_token(1, "t_rocha", { zone = "hand" }) ~= nil)
    while g:hand_count(1) < Game.HAND_LIMIT do pl.hand[#pl.hand + 1] = { id = "t_coelho", uid = g:next_uid() } end
    T.eq(g:create_token(1, "t_rocha", { zone = "hand" }), nil)
    T.eq(#pl.destroyed, 0)
    clear_test_cards()
  end },

  { "ficha de estrutura quebrada deixa de existir", function(T)
    local g = new_game()
    local st = g:create_token(1, "t_rocha")
    T.eq(st.ficha, true)
    g:break_structure(1, st.slot)
    T.eq(#g.players[1].discard, 0)
    clear_test_cards()
  end },
}
