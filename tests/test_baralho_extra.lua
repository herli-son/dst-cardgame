local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local function define()
  Cards.define{ id = "x_coelho", kind = "criatura", cost = 0, atk = 1, hp = 1 }
  Cards.define{ id = "x_casa", kind = "estrutura", cost = 0 }
  Cards.define{ id = "x_base", kind = "criatura", cost = 0, atk = 1, hp = 9 }
end

local function copies(id, n)
  local list = {}
  for i = 1, n do list[i] = { id = id } end
  return list
end

local function new_game(extra1)
  define()
  local d1, d2 = copies("x_base", 20), copies("x_base", 20)
  local g = Game.new{ decks = { d1, d2 }, extra_decks = { extra1 or {}, {} },
    first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function count(list, id)
  local n = 0
  for _, c in ipairs(list) do if c.id == id then n = n + 1 end end
  return n
end

return {
  { "criar uma ficha tira a cópia do baralho extra", function(T)
    local g = new_game(copies("x_coelho", 2))
    local c = g:create_token(1, "x_coelho")
    T.ok(c ~= nil)
    T.eq(c.ficha, true)
    T.eq(count(g.players[1].extra, "x_coelho"), 1)
  end },

  { "sem cópia no baralho extra, a criação não acontece", function(T)
    local g = new_game(copies("x_coelho", 1))
    T.ok(g:create_token(1, "x_coelho") ~= nil)
    local c, why = g:create_token(1, "x_coelho")
    T.eq(c, nil)
    T.eq(why, "sem_copia")
    T.eq(g.events[#g.events].t, "no_copy")
    T.eq(#g:creatures(1), 1)
  end },

  { "o baralho extra de um jogador não serve ao outro", function(T)
    local g = new_game(copies("x_coelho", 1))
    local c, why = g:create_token(2, "x_coelho")
    T.eq(c, nil)
    T.eq(why, "sem_copia")
  end },

  { "sem espaço em campo, a cópia fica no baralho extra", function(T)
    local g = new_game(copies("x_coelho", 1))
    for s = 1, 6 do g:place_creature(1, { id = "x_base", uid = g:next_uid() }, s) end
    local c, why = g:create_token(1, "x_coelho")
    T.eq(c, nil)
    T.eq(why, "sem_espaco")
    T.eq(count(g.players[1].extra, "x_coelho"), 1)
  end },

  { "estrutura criada que não entra volta para o baralho extra", function(T)
    local g = new_game(copies("x_casa", 3))
    g:create_token(1, "x_casa"); g:create_token(1, "x_casa")
    local _, why = g:create_token(1, "x_casa")
    T.eq(why, "pendente")
    T.eq(count(g.players[1].extra, "x_casa"), 0)
    T.ok(g:act(1, { type = "choose", index = nil }))
    T.eq(count(g.players[1].extra, "x_casa"), 1)
  end },
}
