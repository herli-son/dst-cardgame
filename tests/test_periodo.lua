local Game = require("duelo/core/game")

local function new_game()
  local g = Game.new{ decks = { {}, {} }, first = 1, rng = function() return 1 end }
  g:start()
  return g
end

local function periods(g)
  local list = {}
  for _, ev in ipairs(g.events) do
    if ev.t == "period" then list[#list + 1] = ev.period end
  end
  return list
end

return {
  { "vezes 1 e 2 de manhã, 3 e 4 à tarde, 5 em diante à noite", function(T)
    T.eq(Game.period_of(1), "manha")
    T.eq(Game.period_of(2), "manha")
    T.eq(Game.period_of(3), "tarde")
    T.eq(Game.period_of(4), "tarde")
    T.eq(Game.period_of(5), "noite")
    T.eq(Game.period_of(9), "noite")
  end },

  { "a rodada começa de manhã", function(T)
    local g = new_game()
    T.eq(g:period(), "manha")
    T.eq(periods(g)[1], "manha")
  end },

  { "o período avança com as vezes e emite um evento por mudança", function(T)
    Game.actions.agir = function() return true end
    local g = new_game()
    for _ = 1, 4 do g:act(g.active, { type = "agir" }) end
    T.eq(g.vez, 5)
    T.eq(g:period(), "noite")
    local p = periods(g)
    T.eq(#p, 3)
    T.eq(p[2], "tarde")
    T.eq(p[3], "noite")
    Game.actions.agir = nil
  end },

  { "rodada que termina antes da noite não chega à noite", function(T)
    local g = new_game()
    g:act(1, { type = "pass" })
    g:act(2, { type = "pass" })
    for _, per in ipairs(periods(g)) do T.ok(per ~= "noite", "a noite não deveria ter chegado") end
    T.eq(g:period(), "manha", "a nova rodada começa de manhã")
  end },

  { "ação que não passa a vez não avança o período", function(T)
    Game.actions.sem_vez = function() return true, nil, false end
    local g = new_game()
    g:act(1, { type = "sem_vez" })
    T.eq(g:period(), "manha")
    T.eq(#periods(g), 1)
    Game.actions.sem_vez = nil
  end },

  { "hooks de período são chamados na mudança", function(T)
    local seen = {}
    local hook = function(_, per) seen[#seen + 1] = per end
    table.insert(Game.period_hooks, hook)
    Game.actions.agir = function() return true end
    local g = new_game()
    g:act(1, { type = "agir" })
    g:act(2, { type = "agir" })
    T.eq(seen[1], "manha")
    T.eq(seen[2], "tarde")
    table.remove(Game.period_hooks)
    Game.actions.agir = nil
  end },
}
