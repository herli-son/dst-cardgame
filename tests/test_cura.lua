local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local function new_game()
  Cards.define{ id = "k_rato", kind = "criatura", cost = 0, atk = 1, hp = 1 }
  Cards.define{ id = "k_muro", kind = "criatura", cost = 0, atk = 1, hp = 5 }
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "k_rato" }; d2[i] = { id = "k_rato" } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function put(g, p, id, slot)
  return g:place_creature(p, { id = id, uid = g:next_uid() }, slot)
end

local function count(g, t)
  local n = 0
  for _, ev in ipairs(g.events) do if ev.t == t then n = n + 1 end end
  return n
end

return {
  { "cura tira marcadores de dano e devolve o quanto curou", function(T)
    local g = new_game()
    local c = put(g, 1, "k_muro", 1)
    g:damage_creature(c, 3, nil, "teste")
    T.eq(g:heal_creature(c, 2), 2)
    T.eq(c.damage, 1)
    T.eq(count(g, "creature_heal"), 1)
  end },

  { "cura não passa do dano que a criatura tem", function(T)
    local g = new_game()
    local c = put(g, 1, "k_muro", 1)
    g:damage_creature(c, 1, nil, "teste")
    T.eq(g:heal_creature(c, 5), 1)
    T.eq(c.damage, 0)
    T.eq(g:heal_creature(c, 5), 0, "sem dano, nada a curar")
    T.eq(count(g, "creature_heal"), 1)
  end },

  { "cura numa criatura fora de campo não faz nada", function(T)
    local g = new_game()
    local c = put(g, 1, "k_muro", 1)
    g:damage_creature(c, 2, nil, "teste")
    g:kill(c, "teste")
    T.eq(g:heal_creature(c, 2), 0)
    T.eq(count(g, "creature_heal"), 0)
  end },

  { "cura no mesmo efeito salva a criatura de dano letal", function(T)
    local g = new_game()
    local c = put(g, 1, "k_muro", 1)
    g:as_one_effect(function()
      g:damage_creature(c, 5, nil, "teste")
      g:heal_creature(c, 2)
    end)
    g:settle()
    T.eq(g.players[1].field[1], c)
    T.eq(c.damage, 3)
  end },

  { "vida do jogador não passa de 20", function(T)
    local g = new_game()
    T.eq(g:heal_player(1, 3), 0, "vida cheia")
    g:damage_player(1, 2, "teste")
    T.eq(g:heal_player(1, 5), 2)
    T.eq(g.players[1].life, Game.MAX_LIFE)
    T.eq(count(g, "player_heal"), 1)
  end },

  { "recuperar vida no mesmo efeito de um dano letal salva o jogador", function(T)
    local g = new_game()
    g:as_one_effect(function()
      g:damage_player(2, 25, "teste")
      T.eq(g:heal_player(2, 10), 10)
    end)
    T.eq(g.winner, nil)
    T.eq(g.players[2].life, 5)
  end },

  { "com a partida decidida, não recupera vida", function(T)
    local g = new_game()
    g:damage_player(2, 25, "teste")
    T.eq(g.winner, 1)
    T.eq(g:heal_player(2, 10), 0)
    T.eq(g.players[2].life, -5)
  end },
}
