-- Registro e reprodução de partidas (US #82): o motor guarda semente, baralhos
-- e ações aceitas; Replay.run chega ao mesmo estado e aos mesmos eventos,
-- inclusive numa partida encerrada por erro; o registro vai e volta de texto.
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")
local Rng = require("duelo/core/rng")
local Replay = require("duelo/core/replay")
local Simulador = require("duelo/sim/simulador")
local CartasSim = require("cartas_sim")

local function deck(id, n)
  local d = {}
  for i = 1, n do d[i] = { id = id } end
  return d
end

local function simple_game(extra)
  CartasSim.define()
  local o = { decks = { deck("sim_rato", 20), deck("sim_lobo", 20) }, first = 1, mulligan = false, seed = 11 }
  for k, v in pairs(extra or {}) do o[k] = v end
  local g = Game.new(o)
  assert(g:start())
  return g
end

local function event_types(g)
  local ts = {}
  for i, ev in ipairs(g.events) do ts[i] = ev.t end
  return table.concat(ts, ",")
end

local function real_decks()
  local Decks = require("duelo/decks/init")
  local d1, e1 = Decks.build("wilson")
  local d2, e2 = Decks.build("webber")
  return { decks = { d1, d2 }, extra_decks = { e1, e2 } }
end

return {
  { "o registro guarda semente, baralhos (ids na ordem dada) e opções", function(T)
    CartasSim.define()
    local d1 = { { id = "sim_rato" }, { id = "sim_lobo" }, { id = "sim_urso" } }
    local g = Game.new{ decks = { d1, deck("sim_cao", 2) }, extra_decks = { deck("sim_totem", 1), {} },
      seed = 5, first = 2, mulligan = true }
    T.eq(g.log.seed, 5)
    T.eq(g.log.first, 2)
    T.eq(g.log.mulligan, true)
    T.eq(table.concat(g.log.decks[1], ","), "sim_rato,sim_lobo,sim_urso")
    T.eq(table.concat(g.log.decks[2], ","), "sim_cao,sim_cao")
    T.eq(table.concat(g.log.extra_decks[1], ","), "sim_totem")
    T.eq(#g.log.extra_decks[2], 0)
    T.eq(#g.log.actions, 0)
    -- Sem first nem mulligan: o registro diz que foram sorteado e ligado.
    local h = Game.new{ decks = { d1, d1 }, seed = 1 }
    T.eq(h.log.first, nil)
    T.eq(h.log.mulligan, true)
  end },

  { "só as ações aceitas entram no registro, com cópia", function(T)
    local g = simple_game()
    -- Recusada: não é a vez do jogador 2.
    local ok = g:act(2, { type = "pass" })
    T.eq(ok, false)
    T.eq(#g.log.actions, 0)
    -- Recusada: ação desconhecida.
    ok = g:act(1, { type = "dancar" })
    T.eq(ok, false)
    T.eq(#g.log.actions, 0)
    -- Aceita, e a tabela do chamador pode ser alterada depois.
    local a = { type = "play", hand_index = 1, slot = 3 }
    ok = g:act(1, a)
    T.eq(ok, true)
    T.eq(#g.log.actions, 1)
    T.eq(g.log.actions[1].p, 1)
    T.eq(g.log.actions[1].action.type, "play")
    T.eq(g.log.actions[1].action.slot, 3)
    T.ok(g.log.actions[1].action ~= a, "a ação registrada é uma cópia")
    a.slot = 6
    a.type = "attack"
    T.eq(g.log.actions[1].action.slot, 3)
    T.eq(g.log.actions[1].action.type, "play")
    T.eq(g:act(2, { type = "pass" }), true)
    T.eq(#g.log.actions, 2)
    T.eq(g.log.actions[2].p, 2)
    T.eq(g.log.actions[2].action.type, "pass")
  end },

  { "a troca inicial entra no registro como ação mulligan", function(T)
    local g = simple_game{ mulligan = true }
    T.eq(g.phase, "mulligan")
    T.eq(g:mulligan(1, { 1, 3 }), true)
    T.eq(g:mulligan(1, {}), false) -- já feita: não entra
    T.eq(g:mulligan(2, {}), true)
    T.eq(#g.log.actions, 2)
    T.eq(g.log.actions[1].action.type, "mulligan")
    T.eq(table.concat(g.log.actions[1].action.indices, ","), "1,3")
    T.eq(g.log.actions[2].p, 2)
    T.eq(#g.log.actions[2].action.indices, 0)
    T.eq(g.phase, "playing")
    -- E a reprodução refaz a troca: mesma mão.
    local g2 = Replay.run(g.log)
    local ok, diff = Replay.same_state(g, g2)
    T.ok(ok, tostring(diff))
  end },

  { "o rng com semente é determinístico e a mesma semente dá a mesma partida", function(T)
    local a, b = Rng.make(123), Rng.make(123)
    for _ = 1, 50 do T.eq(a(1000), b(1000)) end
    local c = Rng.make(124)
    local same = true
    for _ = 1, 20 do if Rng.make(123)(1000000) ~= c(1000000) then same = false end end
    T.ok(not same, "sementes diferentes dão sequências diferentes")
    for _ = 1, 100 do
      local v = a(7)
      T.ok(v >= 1 and v <= 7 and v % 1 == 0, "rng(n) fica entre 1 e n")
    end
    -- Duas partidas com a mesma semente embaralham igual.
    CartasSim.define()
    local opts = { decks = CartasSim.decks(), extra_decks = CartasSim.extra_decks(), mulligan = false }
    local function hand(seed)
      local o = {}
      for k, v in pairs(opts) do o[k] = v end
      o.seed = seed
      local g = Game.new(o)
      g:start()
      local ids = {}
      for i, card in ipairs(g.players[1].hand) do ids[i] = card.id end
      return table.concat(ids, ","), g.first
    end
    local h1, f1 = hand(9)
    local h2, f2 = hand(9)
    T.eq(h1, h2)
    T.eq(f1, f2)
    local different = false
    for seed = 10, 15 do if hand(seed) ~= h1 then different = true end end
    T.ok(different, "outra semente embaralha diferente")
  end },

  { "sem seed nem rng, o motor sorteia uma semente e a partida continua reproduzível", function(T)
    CartasSim.define()
    local g = Game.new{ decks = CartasSim.decks(), extra_decks = CartasSim.extra_decks(), mulligan = false }
    T.eq(type(g.log.seed), "number")
    g:start()
    g:act(g.active, { type = "pass" })
    local g2 = Replay.run(g.log)
    local ok, diff = Replay.same_state(g, g2)
    T.ok(ok, tostring(diff))
  end },

  { "partida com rng explícito não é reproduzível", function(T)
    CartasSim.define()
    local g = Game.new{ decks = CartasSim.decks(), first = 1, mulligan = false, rng = function(n) return n end }
    T.eq(g.log.seed, nil)
    g:start()
    T.eq(g:act(1, { type = "pass" }), true)
    T.eq(#g.log.actions, 1) -- as ações continuam registradas
    local ok, err = pcall(Replay.run, g.log)
    T.eq(ok, false)
    T.ok(tostring(err):find("não é reproduzível", 1, true) ~= nil, tostring(err))
  end },

  { "a reprodução de uma partida bot x bot chega ao mesmo estado e aos mesmos eventos", function(T)
    local o = real_decks()
    o.seed = 3
    o.players = { "bot", "bot" }
    local rep, g = Simulador.run_game(o)
    T.ok(rep.resultado == "vitoria" or rep.resultado == "empate" or rep.resultado == "limite_rodadas", rep.resultado)
    T.ok(#g.log.actions > 20, "partida com jogadas")
    T.eq(rep.log, nil) -- sem falha e sem log = true, o relatório não traz o registro
    local g2 = Game.replay(g.log)
    T.eq(g2.phase, g.phase)
    T.eq(g2.winner, g.winner)
    T.eq(g2.round, g.round)
    T.eq(#g2.events, #g.events)
    T.eq(event_types(g2), event_types(g))
    for p = 1, 2 do T.eq(g2.players[p].life, g.players[p].life, "vida do jogador " .. p) end
    local ok, diff = Replay.same_state(g, g2)
    T.ok(ok, tostring(diff))
    -- A reprodução gera o mesmo registro.
    T.eq(Replay.log_to_string(g2.log), Replay.log_to_string(g.log))
  end },

  { "a reprodução de uma partida ao acaso com troca inicial chega ao mesmo estado", function(T)
    local o = real_decks()
    o.seed = 8
    o.mulligan = true
    o.log = true
    local rep, g = Simulador.run_game(o)
    T.ok(rep.log == g.log, "com log = true, o relatório traz o registro")
    T.eq(rep.log.actions[1].action.type, "mulligan")
    local g2 = Replay.run(rep.log)
    local ok, diff = Replay.same_state(g, g2)
    T.ok(ok, tostring(diff))
  end },

  { "same_state aponta a primeira diferença entre partidas", function(T)
    local g = simple_game()
    local h = simple_game()
    T.eq(Replay.same_state(g, h), true)
    h.players[2].life = 7
    local ok, diff = Replay.same_state(g, h)
    T.eq(ok, false)
    T.ok(tostring(diff):find("players.2.life", 1, true) ~= nil, tostring(diff))
    local snap = Replay.snapshot(g)
    T.eq(snap.players[1].life, Game.START_LIFE)
    T.eq(#snap.players[1].hand, Game.START_HAND + Game.DRAW_PER_ROUND)
    T.eq(#snap.events, #g.events)
    -- O snapshot é serializável: sem funções nem ciclos.
    T.eq(type(Replay.serialize(snap)), "string")
  end },

  { "uma partida encerrada por erro é reproduzida até o erro", function(T)
    CartasSim.define()
    Cards.define{ id = "reg_bug", kind = "criatura", cost = 0, atk = 1, hp = 1,
      on_play = function() error("bug de registro") end }
    local d = {}
    for i = 1, 20 do d[i] = { id = (i % 4 == 0) and "reg_bug" or "sim_rato" } end
    local rep, g = Simulador.run_game{ decks = { d, d }, seed = 2, players = { "random", "random" } }
    T.eq(rep.resultado, "erro")
    T.eq(g.phase, "error")
    T.ok(rep.log ~= nil and rep.log == g.log, "o relatório de falha traz o registro")
    T.ok(#g.log.actions >= 1, "a ação que errou está registrada")
    T.eq(g.log.actions[#g.log.actions].action.type, "play")
    T.eq(rep.passo, #g.log.actions)
    local g2 = Replay.run(g.log)
    T.eq(g2.phase, "error")
    T.eq(g2.error.message, g.error.message)
    T.ok(tostring(g2.error.message):find("bug de registro", 1, true) ~= nil, tostring(g2.error.message))
    T.eq(#g2.log.actions, #g.log.actions)
    T.eq(event_types(g2), event_types(g))
    local ok, diff = Replay.same_state(g, g2)
    T.ok(ok, tostring(diff))
    -- Depois do erro, nada mais entra no registro.
    T.eq(g2:act(1, { type = "pass" }), false)
    T.eq(#g2.log.actions, #g.log.actions)
  end },

  { "uma ação recusada na reprodução dá erro com o índice", function(T)
    local g = simple_game()
    T.eq(g:act(1, { type = "pass" }), true)
    T.eq(g:act(2, { type = "pass" }), true)
    T.eq(g:act(2, { type = "pass" }), true)
    local log = Game.deep_copy(g.log)
    log.actions[2].p = 1 -- não é a vez do jogador 1
    local ok, err = pcall(Replay.run, log)
    T.eq(ok, false)
    T.ok(tostring(err):find("ação 2", 1, true) ~= nil, tostring(err))
    T.ok(tostring(err):find("não é a sua vez", 1, true) ~= nil, tostring(err))
  end },

  { "o registro vai para texto e volta igual", function(T)
    local o = real_decks()
    o.seed = 4
    o.players = { "bot", "random" }
    local _, g = Simulador.run_game(o)
    local s = Replay.log_to_string(g.log)
    T.eq(type(s), "string")
    T.ok(#s > 100, "texto com conteúdo")
    T.ok(s:find('["seed"]=4', 1, true) ~= nil, "a semente aparece no texto")
    local log = Replay.log_from_string(s)
    T.eq(log.seed, 4)
    T.eq(#log.actions, #g.log.actions)
    T.eq(table.concat(log.decks[1], ","), table.concat(g.log.decks[1], ","))
    T.eq(Replay.log_to_string(log), s)
    local g2 = Replay.run(log)
    local ok, diff = Replay.same_state(g, g2)
    T.ok(ok, tostring(diff))
  end },

  { "a serialização preserva tipos simples e recusa o resto", function(T)
    local v = { 1, -2, 2.5, "a\"b\n\\c", true, false, { x = { 1, 2 }, ["k y"] = "z" }, [10] = 1e300 }
    local s = Replay.serialize(v)
    local back = Replay.deserialize(s)
    T.eq(back[1], 1)
    T.eq(back[2], -2)
    T.eq(back[3], 2.5)
    T.eq(back[4], "a\"b\n\\c")
    T.eq(back[5], true)
    T.eq(back[6], false)
    T.eq(back[7].x[2], 2)
    T.eq(back[7]["k y"], "z")
    T.eq(back[10], 1e300)
    T.eq(Replay.serialize(back), s)
    -- Chaves em ordem: a mesma tabela dá sempre o mesmo texto.
    T.eq(Replay.serialize({ b = 1, a = 2 }), '{["a"]=2,["b"]=1}')
    -- Funções, ciclos e NaN são erro, com o caminho.
    local ok, err = pcall(Replay.serialize, { actions = { { action = { f = function() end } } } })
    T.eq(ok, false)
    T.ok(tostring(err):find("não serializável", 1, true) ~= nil, tostring(err))
    T.ok(tostring(err):find('["actions"][1]["action"]["f"]', 1, true) ~= nil, tostring(err))
    local c = {}
    c.self = c
    ok, err = pcall(Replay.serialize, c)
    T.eq(ok, false)
    T.ok(tostring(err):find("cíclica", 1, true) ~= nil, tostring(err))
    ok, err = pcall(Replay.serialize, { 0 / 0 })
    T.eq(ok, false)
    -- Texto que não é um registro: erro, sem rodar código.
    ok, err = pcall(Replay.log_from_string, "os.exit(1)")
    T.eq(ok, false)
    ok, err = pcall(Replay.log_from_string, '{["a"]=1}')
    T.eq(ok, false)
    T.ok(tostring(err):find("não é um registro", 1, true) ~= nil, tostring(err))
    ok, err = pcall(Replay.deserialize, '{["a"]=1')
    T.eq(ok, false)
  end },

  { "o simulador usa o rng do motor e traz o registro nas falhas de run_many", function(T)
    T.eq(Simulador.make_rng, Rng.make)
    CartasSim.define()
    Cards.define{ id = "reg_bug2", kind = "criatura", cost = 0, atk = 1, hp = 1, on_play = function() error("x") end }
    local d = deck("reg_bug2", 10)
    local agg = Simulador.run_many{ n = 2, seed_base = 30, decks = { d, d } }
    T.eq(#agg.falhas, 2)
    T.eq(agg.falhas[1].log.seed, 31)
    T.ok(#agg.falhas[1].log.actions >= 1, "registro com a ação que errou")
    local g = Replay.run(agg.falhas[1].log)
    T.eq(g.phase, "error")
    T.eq(g.error.message, agg.falhas[1].erro.message)
  end },
}
