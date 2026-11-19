local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

-- Cartas de teste, registradas só para estes testes.
local log
local function define_test_cards()
  log = {}
  Cards.define{ id = "t_bicho", name = "Bicho", kind = "criatura", cost = 1, atk = 2, hp = 1 }
  Cards.define{ id = "t_caro", name = "Caro", kind = "criatura", cost = 5, atk = 5, hp = 5 }
  Cards.define{ id = "t_entrada", name = "Entrada", kind = "criatura", cost = 0, atk = 0, hp = 1,
    on_play = function(g, c) log[#log + 1] = "on_play:" .. c.slot end }
  Cards.define{ id = "t_vigia", name = "Vigia", kind = "criatura", cost = 0, atk = 0, hp = 1,
    on_any_enter = function(g, c, nova) log[#log + 1] = "viu:" .. nova.def.id end }
  Cards.define{ id = "t_noturno", name = "Noturno", kind = "criatura", cost = 0, atk = 0, hp = 1,
    stats = function(g, c) if g:period() == "noite" then return 3, 2 end return 1, 1 end }
end

local function clear_test_cards()
  for _, id in ipairs({ "t_bicho", "t_caro", "t_entrada", "t_vigia", "t_noturno" }) do Cards.remove(id) end
end

local function deck(ids)
  local d = {}
  for i, id in ipairs(ids) do d[i] = { id = id } end
  return d
end

-- Mão controlada: o baralho tem 20 cartas e o topo (fim da lista) vira a mão.
local function new_game(hand1, hand2)
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "t_bicho" }; d2[i] = { id = "t_bicho" } end
  for _, id in ipairs(hand1 or {}) do d1[#d1 + 1] = { id = id } end
  for _, id in ipairs(hand2 or {}) do d2[#d2 + 1] = { id = id } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function hand_index(g, p, id)
  for i, card in ipairs(g.players[p].hand) do if card.id == id then return i end end
end

return {
  { "jogar criatura num espaço livre paga a mana e passa a vez", function(T)
    local g = new_game({ "t_bicho" })
    local i = hand_index(g, 1, "t_bicho")
    T.ok(g:act(1, { type = "play", hand_index = i, slot = 3 }))
    local c = g:creature_at(1, 3)
    T.ok(c ~= nil, "a criatura está no espaço 3")
    T.eq(c.def.id, "t_bicho")
    T.eq(c.owner, 1)
    T.eq(c.damage, 0)
    T.eq(g.players[1].mana, 0)
    T.eq(g.active, 2)
    clear_test_cards()
  end },

  { "espaço ocupado ou inválido é recusado", function(T)
    local g = new_game({ "t_entrada", "t_entrada" })
    g.players[1].mana = 5
    T.ok(g:act(1, { type = "play", hand_index = hand_index(g, 1, "t_entrada"), slot = 1 }))
    g:act(2, { type = "pass" })
    local ok = g:act(1, { type = "play", hand_index = hand_index(g, 1, "t_entrada"), slot = 1 })
    T.eq(ok, false, "ocupado")
    ok = g:act(1, { type = "play", hand_index = hand_index(g, 1, "t_entrada"), slot = 7 })
    T.eq(ok, false, "fora do campo")
    ok = g:act(1, { type = "play", hand_index = hand_index(g, 1, "t_entrada") })
    T.eq(ok, false, "sem espaço")
    clear_test_cards()
  end },

  { "mana insuficiente é recusada e a carta fica na mão", function(T)
    local g = new_game({ "t_caro" })
    local before = #g.players[1].hand
    local ok = g:act(1, { type = "play", hand_index = hand_index(g, 1, "t_caro"), slot = 1 })
    T.eq(ok, false)
    T.eq(#g.players[1].hand, before)
    T.eq(g.active, 1, "jogada recusada não passa a vez")
    clear_test_cards()
  end },

  { "à noite, jogar criatura gasta 1 de fogueira", function(T)
    local g = new_game({ "t_entrada" })
    Game.actions.ativar_teste = function() return true end
    for _ = 1, 4 do g:act(g.active, { type = "ativar_teste" }) end
    T.eq(g:period(), "noite")
    g:act(1, { type = "play", hand_index = hand_index(g, 1, "t_entrada"), slot = 2 })
    T.eq(g.fogueira[1], 2)
    Game.actions.ativar_teste = nil
    clear_test_cards()
  end },

  { "efeito de entrada da carta dispara", function(T)
    local g = new_game({ "t_entrada" })
    g:act(1, { type = "play", hand_index = hand_index(g, 1, "t_entrada"), slot = 4 })
    T.eq(log[1], "on_play:4")
    clear_test_cards()
  end },

  { "criaturas em campo reagem à entrada de outra, inclusive do adversário", function(T)
    local g = new_game({ "t_vigia" }, { "t_entrada" })
    g:act(1, { type = "play", hand_index = hand_index(g, 1, "t_vigia"), slot = 1 })
    T.eq(#log, 0, "não reage à própria entrada")
    g:act(2, { type = "play", hand_index = hand_index(g, 2, "t_entrada"), slot = 1 })
    T.eq(log[1], "on_play:1")
    T.eq(log[2], "viu:t_entrada")
    clear_test_cards()
  end },

  { "atributos podem depender do estado (ex.: período)", function(T)
    local g = new_game({ "t_noturno" })
    g:act(1, { type = "play", hand_index = hand_index(g, 1, "t_noturno"), slot = 1 })
    local c = g:creature_at(1, 1)
    T.eq(g:atk(c), 1)
    Game.actions.ativar_teste = function() return true end
    for _ = 1, 3 do g:act(g.active, { type = "ativar_teste" }) end
    T.eq(g:period(), "noite")
    T.eq(g:atk(c), 3)
    T.eq(g:hp(c), 2)
    Game.actions.ativar_teste = nil
    clear_test_cards()
  end },

  { "cada carta recebe um identificador único", function(T)
    local g = new_game({ "t_bicho" })
    local seen = {}
    for p = 1, 2 do
      for _, card in ipairs(g.players[p].deck) do
        T.ok(card.uid ~= nil)
        T.ok(not seen[card.uid], "uid repetido")
        seen[card.uid] = true
      end
    end
    clear_test_cards()
  end },
}
