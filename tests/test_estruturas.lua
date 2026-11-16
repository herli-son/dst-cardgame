local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local log
local IDS = { "t_casa", "t_torre", "t_poco", "t_maquina", "t_tambor", "t_fraca" }

local function define_test_cards()
  log = {}
  Cards.define{ id = "t_casa", kind = "estrutura", cost = 1 }
  Cards.define{ id = "t_torre", kind = "estrutura", cost = 1 }
  Cards.define{ id = "t_poco", kind = "estrutura", cost = 1,
    on_break = function(g, st) log[#log + 1] = "quebrou:" .. st.def.id end }
  -- Ativação 1 vez por rodada, sem gastar a vez, com escolha.
  Cards.define{ id = "t_maquina", kind = "estrutura", cost = 1,
    activation = { once_per_round = true, passes_turn = false },
    activate = function(g, p, st)
      g:set_choice(p, { reason = "teste", options = { "a", "b" }, allow_none = true,
        resolve = function(gg, idx) log[#log + 1] = "escolheu:" .. tostring(idx) end })
    end }
  -- Ativação comum: gasta a vez.
  Cards.define{ id = "t_tambor", kind = "estrutura", cost = 1,
    activate = function(g, p, st) log[#log + 1] = "tambor" end }
  Cards.define{ id = "t_fraca", kind = "criatura", cost = 0, atk = 0, hp = 1 }
end

local function clear_test_cards()
  for _, id in ipairs(IDS) do Cards.remove(id) end
end

local function new_game(hand1)
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "t_fraca" }; d2[i] = { id = "t_fraca" } end
  for _, id in ipairs(hand1 or {}) do d1[#d1 + 1] = { id = id } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  g.players[1].mana = 10
  return g
end

local function idx(g, p, id)
  for i, card in ipairs(g.players[p].hand) do if card.id == id then return i end end
end

local function play(g, p, id, slot)
  return g:act(p, { type = "play", hand_index = idx(g, p, id), slot = slot })
end

local function pass(g) g:act(g.active, { type = "pass" }) end

return {
  { "estrutura vai para o primeiro espaço livre", function(T)
    local g = new_game({ "t_casa" })
    T.ok(play(g, 1, "t_casa"))
    T.eq(g:structure_at(1, 1).def.id, "t_casa")
    T.ok(g:has_structure(1, "t_casa"))
    clear_test_cards()
  end },

  { "com a zona cheia, é preciso escolher qual substituir; a antiga é quebrada e vai ao descarte", function(T)
    local g = new_game({ "t_poco", "t_casa", "t_torre" })
    play(g, 1, "t_poco"); pass(g)
    play(g, 1, "t_casa"); pass(g)
    local ok = play(g, 1, "t_torre")
    T.eq(ok, false, "sem indicar o espaço com a zona cheia")
    T.ok(play(g, 1, "t_torre", 1))
    T.eq(g:structure_at(1, 1).def.id, "t_torre")
    T.eq(log[1], "quebrou:t_poco")
    local d = g.players[1].discard
    T.eq(d[#d].id, "t_poco", "estrutura quebrada vai para o descarte")
    clear_test_cards()
  end },

  { "estrutura que é ficha deixa de existir ao ser quebrada", function(T)
    local g = new_game({})
    g:put_structure(1, { id = "t_casa", ficha = true }, 1)
    local before = #g.players[1].discard
    g:break_structure(1, 1)
    T.eq(g:structure_at(1, 1), nil)
    T.eq(#g.players[1].discard, before)
    clear_test_cards()
  end },

  { "ativação comum gasta a vez", function(T)
    local g = new_game({ "t_tambor" })
    play(g, 1, "t_tambor"); pass(g)
    T.ok(g:act(1, { type = "activate", structure = 1 }))
    T.eq(log[1], "tambor")
    T.eq(g.active, 2)
    clear_test_cards()
  end },

  { "ativação com escolha: só a escolha é aceita até ser resolvida, e não gasta a vez", function(T)
    local g = new_game({ "t_maquina" })
    play(g, 1, "t_maquina"); pass(g)
    T.ok(g:act(1, { type = "activate", structure = 1 }))
    T.eq(g.active, 1)
    local ok = g:act(1, { type = "pass" })
    T.eq(ok, false, "passar com escolha pendente é recusado")
    ok = g:act(1, { type = "choose", index = 5 })
    T.eq(ok, false, "opção inválida")
    T.ok(g:act(1, { type = "choose", index = 2 }))
    T.eq(log[1], "escolheu:2")
    T.eq(g.active, 1, "Máquina não gasta a vez")
    clear_test_cards()
  end },

  { "ativação 1 vez por rodada recomeça na rodada seguinte", function(T)
    local g = new_game({ "t_maquina" })
    play(g, 1, "t_maquina"); pass(g)
    g:act(1, { type = "activate", structure = 1 }); g:act(1, { type = "choose", index = 0 })
    local ok = g:act(1, { type = "activate", structure = 1 })
    T.eq(ok, false, "segunda ativação na mesma rodada")
    pass(g); pass(g) -- jogador 1 passa, jogador 2 passa: nova rodada
    T.eq(g.round, 2)
    T.ok(g:act(g.active == 1 and 1 or 2, { type = "pass" }))
    clear_test_cards()
  end },

  { "ativar efeito continua permitido com a fogueira em zero", function(T)
    local g = new_game({ "t_tambor" })
    play(g, 1, "t_tambor"); pass(g)
    g.fogueira[1], g.fogueira[2] = 0, 0
    T.ok(g:act(1, { type = "activate", structure = 1 }))
    clear_test_cards()
  end },
}
