local Game = require("duelo/core/game")

local function deck(n)
  local d = {}
  for i = 1, n do d[i] = { id = "carta" .. i } end
  return d
end

local function new_game(first)
  local g = Game.new{ decks = { deck(40), deck(40) }, first = first, rng = function(n) return 1 end }
  g:start()
  return g
end

return {
  { "mão inicial de 4 cartas", function(T)
    local g = new_game(1)
    T.eq(#g.players[1].hand, 4)
    T.eq(#g.players[2].hand, 4)
    T.eq(#g.players[1].deck, 36)
  end },

  { "quem tem o token age primeiro", function(T)
    local g = new_game(2)
    T.eq(g.round, 1)
    T.eq(g.attacker, 2)
    T.eq(g.active, 2)
    T.eq(g.vez, 1)
  end },

  { "jogar fora da vez é recusado", function(T)
    local g = new_game(1)
    local ok, err = g:act(2, { type = "pass" })
    T.eq(ok, false)
    T.ok(err ~= nil)
  end },

  { "passar entrega a vez ao outro jogador", function(T)
    local g = new_game(1)
    T.ok(g:act(1, { type = "pass" }))
    T.eq(g.active, 2)
    T.eq(g.vez, 2)
  end },

  { "dois passes seguidos encerram a rodada e o token alterna", function(T)
    local g = new_game(1)
    g:act(1, { type = "pass" })
    g:act(2, { type = "pass" })
    T.eq(g.round, 2)
    T.eq(g.attacker, 2)
    T.eq(g.active, 2)
    T.eq(g.vez, 1)
  end },

  { "uma ação entre os passes zera a contagem", function(T)
    Game.actions.teste = function() return true end
    local g = new_game(1)
    g:act(1, { type = "pass" })
    g:act(2, { type = "teste" })
    g:act(1, { type = "pass" })
    T.eq(g.round, 1, "um passe depois de uma ação não encerra a rodada")
    g:act(2, { type = "pass" })
    T.eq(g.round, 2)
    Game.actions.teste = nil
  end },

  { "ação que não passa a vez mantém o jogador", function(T)
    Game.actions.sem_vez = function() return true, nil, false end
    local g = new_game(1)
    T.ok(g:act(1, { type = "sem_vez" }))
    T.eq(g.active, 1)
    T.eq(g.vez, 1)
    Game.actions.sem_vez = nil
  end },

  { "ação desconhecida é recusada", function(T)
    local g = new_game(1)
    local ok = g:act(1, { type = "voar" })
    T.eq(ok, false)
    T.eq(g.active, 1)
  end },
}
