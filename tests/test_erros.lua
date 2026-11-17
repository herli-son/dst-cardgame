-- Erro no código de uma carta encerra a partida com estado de erro.
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local function define_test_cards()
  Cards.define{ id = "e_bicho", kind = "criatura", cost = 0, atk = 1, hp = 1 }
  Cards.define{ id = "e_bug", kind = "feitico", speed = "instantaneo", cost = 0,
    on_cast = function() error("BUG_NO_FEITICO") end }
  Cards.define{ id = "e_bug_rapido", kind = "feitico", speed = "rapido", cost = 0,
    on_cast = function() error("BUG_NA_PILHA") end }
  Cards.define{ id = "e_entrada", kind = "criatura", cost = 0, atk = 0, hp = 1,
    on_play = function() error("BUG_AO_ENTRAR") end }
  Cards.define{ id = "e_escolha", kind = "criatura", cost = 0, atk = 0, hp = 1,
    on_play = function(g, c)
      g:set_choice(c.owner, { reason = "escolha_com_bug", options = { "a" },
        resolve = function() error("BUG_NA_ESCOLHA") end })
    end }
end

local function new_game(hand1)
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "e_bicho" }; d2[i] = { id = "e_bicho" } end
  for _, id in ipairs(hand1 or {}) do d1[#d1 + 1] = { id = id } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function play(g, id, fields)
  local a = { type = "play" }
  for i, card in ipairs(g.players[1].hand) do if card.id == id then a.hand_index = i; break end end
  for k, v in pairs(fields or {}) do a[k] = v end
  return g:act(1, a)
end

local function last_event(g, t)
  for i = #g.events, 1, -1 do if g.events[i].t == t then return g.events[i] end end
end

return {
  { "erro num feitiço encerra a partida com estado de erro", function(T)
    local g = new_game({ "e_bug" })
    local ok, err = play(g, "e_bug")
    T.eq(ok, false)
    T.ok(err ~= nil)
    T.eq(g.phase, "error")
    T.ok(g.error.message:find("BUG_NO_FEITICO") ~= nil)
    T.ok(g.error.traceback:find("traceback") ~= nil, "guarda o traceback")
    T.eq(g.error.context.id, "e_bug")
    local ev = last_event(g, "engine_error")
    T.ok(ev ~= nil)
    T.eq(ev.context.id, "e_bug")
  end },

  { "depois do erro, nenhuma ação é aceita", function(T)
    local g = new_game({ "e_bug" })
    play(g, "e_bug")
    local ok, err = g:act(1, { type = "pass" })
    T.eq(ok, false)
    T.eq(err, "partida encerrada por erro")
    T.eq(g:mulligan(1, {}), false)
  end },

  { "erro ao resolver a pilha registra o efeito que estava resolvendo", function(T)
    local g = new_game({ "e_bug_rapido" })
    T.ok(play(g, "e_bug_rapido"))
    g:act(1, { type = "pass" })
    local ok = g:act(2, { type = "pass" })
    T.eq(ok, false)
    T.eq(g.phase, "error")
    T.eq(g.error.context.kind, "resolver")
    T.eq(g.error.context.id, "e_bug_rapido")
  end },

  { "erro no efeito de entrada registra a carta", function(T)
    local g = new_game({ "e_entrada" })
    T.eq(play(g, "e_entrada", { slot = 1 }), false)
    T.eq(g.error.context.kind, "entrar")
    T.eq(g.error.context.id, "e_entrada")
  end },

  { "erro ao resolver uma escolha registra a escolha", function(T)
    local g = new_game({ "e_escolha" })
    T.ok(play(g, "e_escolha", { slot = 1 }))
    T.eq(g:act(1, { type = "choose", index = 1 }), false)
    T.eq(g.error.context.kind, "escolher")
    T.eq(g.error.context.id, "escolha_com_bug")
  end },

  { "erro num gancho durante o início da partida também encerra", function(T)
    define_test_cards()
    local d = {}
    for i = 1, 20 do d[i] = { id = "e_bicho" } end
    local g = Game.new{ decks = { d, d }, first = 1, mulligan = false, rng = function(n) return n end }
    g:on("round_start", function() error("BUG_NO_GANCHO") end, "e_gancho")
    local ok = g:start()
    T.eq(ok, false)
    T.eq(g.phase, "error")
    T.eq(g.error.context.kind, "gancho:round_start")
    T.eq(g.error.context.id, "e_gancho")
  end },

  { "erro que não é texto fica guardado como veio", function(T)
    local g = new_game()
    local code = { code = "X" }
    g:set_choice(1, { reason = "x", options = { "a" }, resolve = function() error(code) end })
    T.eq(g:act(1, { type = "choose", index = 1 }), false)
    T.eq(g.error.value, code)
  end },

  { "jogadas sem erro devolvem os mesmos resultados de antes", function(T)
    local g = new_game()
    local ok, err = g:act(2, { type = "pass" })
    T.eq(ok, false)
    T.eq(err, "não é a sua vez")
    T.eq(g.phase, "playing")
    T.eq(g:act(1, { type = "pass" }), true)
  end },

  { "feitiço que mata uma criatura e depois falha aponta o feitiço", function(T)
    local g = new_game()
    Cards.define{ id = "e_morre_ok", kind = "criatura", cost = 0, atk = 0, hp = 1,
      on_death = function() end }
    Cards.define{ id = "e_feit_bug", kind = "feitico", speed = "instantaneo", cost = 0,
      on_cast = function(gg)
        gg:kill(gg:creature_at(2, 1), "teste")
        error("BUG_DO_FEITICO")
      end }
    g:place_creature(2, { id = "e_morre_ok", uid = g:next_uid() }, 1)
    g.players[1].hand[#g.players[1].hand + 1] = { id = "e_feit_bug", uid = g:next_uid() }
    T.eq(play(g, "e_feit_bug"), false)
    T.eq(g.error.context.id, "e_feit_bug")
  end },

  { "erro num modificador de limite de mão aponta a carta dona", function(T)
    local g = new_game()
    g:add_hand_limit_mod(function() error("BUG_NA_MOCHILA") end, "e_mochila")
    g:act(1, { type = "pass" })
    T.eq(g:act(2, { type = "pass" }), false)
    T.eq(g.error.context.kind, "limite_mao")
    T.eq(g.error.context.id, "e_mochila")
  end },

  { "erro em tabela: mensagem estável e traceback guardado", function(T)
    local g = new_game()
    g:set_choice(1, { reason = "x", options = { "a" }, resolve = function() error({ code = "X" }) end })
    g:act(1, { type = "choose", index = 1 })
    T.eq(g.error.message, "erro do tipo table")
    T.ok(g.error.traceback ~= nil)
    local ev = last_event(g, "engine_error")
    T.eq(ev.message, "erro do tipo table")
  end },

  { "falha ao emitir o evento de erro não escapa do act", function(T)
    local g = new_game({ "e_bug" })
    g.emit = function(self, ev)
      if ev.t == "engine_error" then error("emit quebrou") end
      Game.emit(self, ev)
    end
    local ok = play(g, "e_bug")
    T.eq(ok, false)
    T.eq(g.phase, "error")
    T.ok(g.error ~= nil and g.error.message:find("BUG_NO_FEITICO") ~= nil)
  end },

  { "start devolve true quando dá certo", function(T)
    define_test_cards()
    local d = {}
    for i = 1, 20 do d[i] = { id = "e_bicho" } end
    local g = Game.new{ decks = { d, d }, first = 1, mulligan = false, rng = function(n) return n end }
    T.eq(g:start(), true)
  end },

  { "continuação que falha aponta a carta que a pediu", function(T)
    local g = new_game()
    Cards.define{ id = "e_continua", kind = "criatura", cost = 0, atk = 0, hp = 1,
      on_play = function(gg, c)
        gg:set_choice(c.owner, { reason = "x", options = { "a" }, resolve = function() end })
        gg:after_choices(function() error("BUG_NA_CONTINUACAO") end)
      end }
    g.players[1].hand[#g.players[1].hand + 1] = { id = "e_continua", uid = g:next_uid() }
    T.ok(play(g, "e_continua", { slot = 1 }))
    T.eq(g:act(1, { type = "choose", index = 1 }), false)
    T.eq(g.error.context.id, "e_continua")
  end },

  { "erro do motor numa jogada aponta a carta jogada", function(T)
    local g = new_game({ "e_bug" })
    g.spend_mana = function() error("BUG_NO_MOTOR") end
    T.eq(play(g, "e_bug"), false)
    T.eq(g.error.context.kind, "jogar")
    T.eq(g.error.context.id, "e_bug")
  end },

  { "o contexto da jogada termina com ela", function(T)
    local g = new_game()
    T.eq(play(g, "e_bicho", { slot = 1 }), true)
    T.eq(g.context, nil, "jogada aceita")
    g:act(2, { type = "pass" })
    T.eq(play(g, "e_bicho", { slot = 9 }), false)
    T.eq(g.context, nil, "jogada recusada pelo handler")
  end },

  { "gancho registrado de novo durante a passada só roda na próxima", function(T)
    local g = new_game()
    local ran = 0
    local b = function() ran = ran + 1 end
    local done = false
    g:on("round_start", function(gg)
      if done then return end
      done = true
      gg:off("round_start", b); gg:on("round_start", b)
    end)
    g:on("round_start", b)
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(ran, 0)
    g:act(g.active, { type = "pass" }); g:act(g.active, { type = "pass" })
    T.eq(ran, 1)
  end },
}
