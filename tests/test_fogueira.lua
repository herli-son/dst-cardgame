local Game = require("duelo/core/game")

local function deck(n)
  local d = {}
  for i = 1, n do d[i] = { id = "carta" .. i } end
  return d
end

-- Ação de teste que imita jogar uma carta: gasta fogueira à noite.
-- As ações reais de ativar e atacar são substituídas aqui; o runner restaura o
-- estado global do motor depois de cada caso.
local function register_test_actions()
  Game.actions.carta = function(g, p)
    if not g:can_pay_fogueira(p) then return false, "sem fogueira" end
    g:spend_fogueira(p)
    return true
  end
  Game.actions.ativar = function() return true end
  Game.actions.activate = function() return true end
  Game.actions.attack = function() return true end
end

local function clear_test_actions()
  Game.actions.carta, Game.actions.ativar = nil, nil
end

local function new_game()
  register_test_actions()
  local g = Game.new{ decks = { deck(20), deck(20) }, first = 1, mulligan = false, rng = function() return 1 end }
  g:start()
  return g
end

-- Leva a partida até a vez 5 (noite) com ações que não gastam fogueira.
local function go_to_night(g)
  for _ = 1, 4 do g:act(g.active, { type = "ativar" }) end
end

return {
  { "de dia não há fogueira", function(T)
    local g = new_game()
    T.eq(g:is_night_lit(), false)
    T.ok(g:act(1, { type = "carta" }), "carta de dia é livre")
    clear_test_actions()
  end },

  { "a fogueira acende com 3 para cada jogador quando a noite começa", function(T)
    local g = new_game()
    go_to_night(g)
    T.eq(g:period(), "noite")
    T.eq(g.fogueira[1], 3)
    T.eq(g.fogueira[2], 3)
    clear_test_actions()
  end },

  { "cada carta jogada à noite gasta 1; ativar não gasta", function(T)
    local g = new_game()
    go_to_night(g)
    g:act(1, { type = "carta" })
    T.eq(g.fogueira[1], 2)
    g:act(2, { type = "ativar" })
    T.eq(g.fogueira[2], 3)
    clear_test_actions()
  end },

  { "com a fogueira em 0 só é possível passar, atacar ou ativar efeitos", function(T)
    local g = new_game()
    go_to_night(g)
    g.fogueira[1] = 0
    local ok = g:act(1, { type = "carta" })
    T.eq(ok, false, "jogar carta é bloqueado")
    T.ok(g:act(1, { type = "activate" }), "ativar efeito continua permitido")
    g.fogueira[2] = 0
    T.ok(g:act(2, { type = "attack" }), "atacar continua permitido")
    clear_test_actions()
  end },

  { "terminar a rodada à noite com 0 causa 2 de dano", function(T)
    local g = new_game()
    go_to_night(g)
    g.fogueira[1] = 0
    g:act(1, { type = "pass" })
    g:act(2, { type = "pass" })
    T.eq(g.players[1].life, 18)
    T.eq(g.players[2].life, 20)
    clear_test_actions()
  end },

  { "a fogueira recomeça a cada rodada", function(T)
    local g = new_game()
    go_to_night(g)
    g:act(1, { type = "carta" })
    g:act(2, { type = "pass" })
    g:act(1, { type = "pass" })
    T.eq(g.round, 2)
    T.eq(g:is_night_lit(), false, "nova rodada começa sem fogueira")
    clear_test_actions()
  end },

  { "bônus de dia fica guardado para a noite; à noite soma na hora", function(T)
    local g = new_game()
    g:fogueira_bonus(1, 1) -- ex.: Machado ao atacar de manhã
    go_to_night(g)
    T.eq(g.fogueira[1], 4)
    T.eq(g.fogueira[2], 3)
    g:fogueira_bonus(2, 1)
    T.eq(g.fogueira[2], 4)
    clear_test_actions()
  end },

  { "sem dano quando a fogueira está marcada para não causar dano (Lua cheia)", function(T)
    local g = new_game()
    go_to_night(g)
    g.fogueira[1] = 0
    g.fogueira_no_damage = true
    g:act(1, { type = "pass" })
    g:act(2, { type = "pass" })
    T.eq(g.players[1].life, 20)
    clear_test_actions()
  end },

  { "dano da fogueira pode encerrar a partida, inclusive com empate", function(T)
    local g = new_game()
    go_to_night(g)
    g.players[1].life, g.players[2].life = 2, 2
    g.fogueira[1], g.fogueira[2] = 0, 0
    g:act(1, { type = "pass" })
    g:act(2, { type = "pass" })
    T.eq(g.winner, 0)
    local ok = g:act(g.active, { type = "pass" })
    T.eq(ok, false, "nada é aceito depois do fim da partida")
    clear_test_actions()
  end },
}
