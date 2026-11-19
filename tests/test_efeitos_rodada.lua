-- Efeitos de início e fim de rodada e de início de período das cartas em campo
-- (US #90): ordem fixa pelo campo, retomada depois de escolhas, vitória no meio
-- e compatibilidade com os ganchos genéricos (Game:on).
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local function new_game(first)
  Cards.define{ id = "r_w", kind = "criatura", cost = 0, atk = 1, hp = 5 }
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "r_w" }; d2[i] = { id = "r_w" } end
  local g = Game.new{ decks = { d1, d2 }, first = first or 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function put(g, p, id, slot)
  return g:place_creature(p, { id = id, uid = g:next_uid() }, slot)
end

local function put_st(g, p, id, slot)
  return g:put_structure(p, { id = id, uid = g:next_uid() }, slot)
end

-- Ação que não faz nada e passa a vez: avança o período sem terminar a rodada.
local function install_agir()
  Game.actions.agir = function() return true end
  Game.validators.agir = function() return true end
end

-- Define criaturas e estruturas de teste que anotam em log, nos três momentos,
-- "<nome>:<momento>[:<período>]".
local function define_loggers(log)
  local function logger(id, kind)
    Cards.define{ id = id, kind = kind, cost = 0, atk = 1, hp = 5,
      on_round_start = function(g, obj) log[#log + 1] = id .. ":inicio" end,
      on_round_end = function(g, obj) log[#log + 1] = id .. ":fim" end,
      on_period_start = function(g, obj, per) log[#log + 1] = id .. ":" .. per end,
    }
  end
  for _, id in ipairs({ "a1", "a2", "a3", "a4", "a5", "a6", "b1", "b2", "b6" }) do logger(id, "criatura") end
  for _, id in ipairs({ "sa1", "sa2", "sb1", "sb2" }) do logger(id, "estrutura") end
end

local function only(log, suffix)
  local list = {}
  for _, e in ipairs(log) do
    if e:sub(-#suffix) == suffix then list[#list + 1] = e:sub(1, -#suffix - 1) end
  end
  return table.concat(list, " ")
end

return {
  { "ordem completa: atacante, espaços 1..6, estruturas 1..2, depois o outro", function(T)
    local log = {}
    define_loggers(log)
    install_agir()
    local g = new_game(1)
    -- Jogador 2 (atacante na rodada 2) preenchido fora de ordem, para a ordem
    -- vir do campo e não da entrada.
    put(g, 2, "b6", 6); put(g, 2, "b2", 2); put(g, 2, "b1", 1)
    put_st(g, 2, "sb2", 2); put_st(g, 2, "sb1", 1)
    put(g, 1, "a6", 6); put(g, 1, "a3", 3); put(g, 1, "a1", 1); put(g, 1, "a5", 5)
    put(g, 1, "a2", 2); put(g, 1, "a4", 4)
    put_st(g, 1, "sa2", 2); put_st(g, 1, "sa1", 1)
    -- Rodada 1: o jogador 1 tem o token. Fim da rodada por dois passes.
    for k in pairs(log) do log[k] = nil end
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g.round, 2)
    T.eq(g.attacker, 2)
    T.eq(only(log, ":fim"), "a1 a2 a3 a4 a5 a6 sa1 sa2 b1 b2 b6 sb1 sb2", "fim da rodada 1: jogador 1 primeiro")
    T.eq(only(log, ":inicio"), "b1 b2 b6 sb1 sb2 a1 a2 a3 a4 a5 a6 sa1 sa2", "início da rodada 2: jogador 2 primeiro")
    T.eq(only(log, ":manha"), "b1 b2 b6 sb1 sb2 a1 a2 a3 a4 a5 a6 sa1 sa2", "manhã da rodada 2")
    -- Os três momentos saem na ordem fim, início, manhã.
    T.eq(log[1], "a1:fim"); T.eq(log[14], "b1:inicio"); T.eq(log[27], "b1:manha")
    T.eq(#log, 39)
  end },

  { "início de período passa o período certo: manhã, tarde e noite", function(T)
    local log = {}
    define_loggers(log)
    install_agir()
    local g = new_game(1)
    put(g, 1, "a1", 1); put(g, 2, "b1", 1); put_st(g, 2, "sb1", 1)
    for k in pairs(log) do log[k] = nil end
    for _ = 1, 4 do T.ok(g:act(g.active, { type = "agir" })) end
    T.eq(g:period(), "noite")
    T.eq(only(log, ":tarde"), "a1 b1 sb1")
    T.eq(only(log, ":noite"), "a1 b1 sb1")
    T.eq(#log, 6, "só tarde e noite nesta rodada (a manhã veio antes de as cartas entrarem)")
    -- A rodada seguinte começa de manhã com a ordem do novo atacante.
    for k in pairs(log) do log[k] = nil end
    g:act(g.active, { type = "pass" }); g:act(g.active, { type = "pass" })
    T.eq(only(log, ":manha"), "b1 sb1 a1")
  end },

  { "mudança de período por advance_vez roda os efeitos com a fogueira já acesa", function(T)
    local seen
    Cards.define{ id = "r_noite", kind = "criatura", cost = 0, atk = 1, hp = 5,
      on_period_start = function(g, c, per) if per == "noite" then seen = g:is_night_lit() end end }
    install_agir()
    local g = new_game(1)
    put(g, 1, "r_noite", 1)
    for _ = 1, 4 do g:act(g.active, { type = "agir" }) end
    T.eq(g.vez, 5)
    T.eq(seen, true, "as regras do motor do período vêm antes dos efeitos das cartas")
  end },

  { "efeito que abre escolha segura o resto da passada e a manhã", function(T)
    local log = {}
    define_loggers(log)
    Cards.define{ id = "r_esc", kind = "criatura", cost = 0, atk = 1, hp = 5,
      on_round_start = function(g, c)
        log[#log + 1] = "esc:inicio"
        g:set_choice(c.owner, { reason = "teste", options = { "x" },
          resolve = function() log[#log + 1] = "escolhido" end })
      end }
    local g = new_game(1)
    put(g, 2, "b1", 1); put(g, 2, "r_esc", 2); put(g, 2, "b6", 6); put_st(g, 2, "sb1", 1)
    put(g, 1, "a1", 1)
    local generic = 0
    g:on("round_start", function() generic = generic + 1; log[#log + 1] = "gancho" end)
    for k in pairs(log) do log[k] = nil end
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g.round, 2)
    T.ok(g.pending_choice ~= nil, "a escolha está aberta")
    T.eq(table.concat(log, " "), "a1:fim b1:fim b6:fim sb1:fim b1:inicio esc:inicio",
      "a passada parou na criatura que abriu a escolha")
    T.eq(g.current_period, nil, "a manhã espera a escolha")
    T.eq(generic, 0, "os ganchos genéricos também esperam")
    T.ok(g:act(2, { type = "choose", index = 1 }))
    T.eq(table.concat(log, " ", 7), "escolhido b6:inicio sb1:inicio a1:inicio gancho b1:manha b6:manha sb1:manha a1:manha")
    T.eq(g:period(), "manha")
    T.eq(g.active, 2, "a escolha não passa a vez do início da rodada")
    T.eq(g.pending_choice, nil)
  end },

  { "escolha no fim da rodada segura o resto da passada e a rodada nova", function(T)
    local log = {}
    define_loggers(log)
    Cards.define{ id = "r_esc_fim", kind = "estrutura", cost = 0,
      on_round_end = function(g, st)
        log[#log + 1] = "esc:fim"
        g:set_choice(st.owner, { reason = "teste", options = { "x" }, resolve = function() end })
      end }
    local g = new_game(1)
    put(g, 1, "a1", 1); put_st(g, 1, "r_esc_fim", 1); put_st(g, 1, "sa2", 2)
    put(g, 2, "b1", 1)
    for k in pairs(log) do log[k] = nil end
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g.round, 1, "a rodada nova espera a escolha")
    T.eq(table.concat(log, " "), "a1:fim esc:fim")
    T.ok(g:act(1, { type = "choose", index = 1 }))
    T.eq(g.round, 2)
    T.eq(only(log, ":fim"), "a1 esc sa2 b1")
    T.eq(only(log, ":inicio"), "b1 a1 sa2", "a estrutura de teste não tem on_round_start")
  end },

  { "criatura que sai de campo no meio da passada não roda; a que entra também não", function(T)
    local log = {}
    define_loggers(log)
    Cards.define{ id = "r_mata", kind = "criatura", cost = 0, atk = 1, hp = 5,
      on_round_end = function(g, c)
        log[#log + 1] = "mata:fim"
        g:kill(g:creature_at(1, 2), "teste")
        g:damage_creature(g:creature_at(1, 3), 9, nil, "teste")
        g:place_creature(1, { id = "a5", uid = g:next_uid() }, 5)
      end }
    local g = new_game(1)
    put(g, 1, "r_mata", 1); put(g, 1, "a2", 2); put(g, 1, "a3", 3); put(g, 1, "a4", 4)
    for k in pairs(log) do log[k] = nil end
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(only(log, ":fim"), "mata a4", "a abatida, a com dano letal e a recém-chegada não rodam")
    T.eq(g:creature_at(1, 3), nil, "o dano letal é resolvido entre os efeitos")
    T.ok(g:creature_at(1, 5) ~= nil)
    T.eq(only(log, ":inicio"), "a4 a5", "na rodada seguinte, a nova criatura já roda")
  end },

  { "vitória por efeito interrompe o resto da passada", function(T)
    local log = {}
    define_loggers(log)
    Cards.define{ id = "r_letal", kind = "criatura", cost = 0, atk = 1, hp = 5,
      on_round_start = function(g, c) log[#log + 1] = "letal"; g:damage_player(2, 99, "teste") end }
    local g = new_game(1)
    put(g, 1, "a1", 1); put(g, 1, "r_letal", 2); put(g, 1, "a3", 3); put_st(g, 1, "sa1", 1)
    put(g, 2, "b1", 1)
    g.players[2].life = 1
    local generic = false
    g:on("round_start", function() generic = true end)
    for k in pairs(log) do log[k] = nil end
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g.winner, 1)
    T.eq(table.concat(log, " "), "a1:fim a3:fim sa1:fim b1:fim b1:inicio a1:inicio letal")
    T.eq(generic, false)
  end },

  { "equipamento roda os mesmos ganchos com o portador, logo depois dele", function(T)
    local log = {}
    Cards.define{ id = "r_sob", kind = "criatura", cost = 0, atk = 1, hp = 5, sobrevivente = true,
      on_round_start = function(g, c) log[#log + 1] = "sob" end }
    Cards.define{ id = "r_cap", kind = "equipamento", slot = "cabeca", cost = 0,
      on_round_start = function(g, c, e) log[#log + 1] = "cabeca:" .. c.def.id .. ":" .. e.def.id end,
      on_period_start = function(g, c, e, per) log[#log + 1] = "cabeca:" .. per end }
    Cards.define{ id = "r_mao", kind = "equipamento", slot = "mao", cost = 0,
      on_round_start = function(g, c, e) log[#log + 1] = "mao" end }
    Cards.define{ id = "r_dep", kind = "criatura", cost = 0, atk = 1, hp = 5,
      on_round_start = function(g, c) log[#log + 1] = "dep" end }
    local g = new_game(1)
    local c = put(g, 1, "r_sob", 1); put(g, 1, "r_dep", 2)
    g:equip(c, { id = "r_cap", uid = g:next_uid() }); g:equip(c, { id = "r_mao", uid = g:next_uid() })
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(table.concat(log, " "), "sob mao cabeca:r_sob:r_cap dep cabeca:manha")
  end },

  { "escolha aberta pela criatura segura os equipamentos dela; portador com dano letal não os roda", function(T)
    local log = {}
    Cards.define{ id = "r_esc2", kind = "criatura", cost = 0, atk = 1, hp = 5, sobrevivente = true,
      on_round_start = function(g, c)
        log[#log + 1] = "esc"
        g:set_choice(c.owner, { reason = "teste", options = { "x" },
          resolve = function() log[#log + 1] = "escolhido" end })
      end }
    Cards.define{ id = "r_suic", kind = "criatura", cost = 0, atk = 1, hp = 5, sobrevivente = true,
      on_round_start = function(g, c) log[#log + 1] = "suic"; g:damage_creature(c, 9, nil, "teste") end }
    Cards.define{ id = "r_mao2", kind = "equipamento", slot = "mao", cost = 0,
      on_round_start = function(g, c, e) log[#log + 1] = "mao:" .. c.def.id end }
    local g = new_game(1)
    local a = put(g, 1, "r_esc2", 1); g:equip(a, { id = "r_mao2", uid = g:next_uid() })
    local b = put(g, 1, "r_suic", 2); g:equip(b, { id = "r_mao2", uid = g:next_uid() })
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(table.concat(log, " "), "esc", "o equipamento espera a escolha da criatura")
    T.ok(g:act(1, { type = "choose", index = 1 }))
    T.eq(table.concat(log, " "), "esc escolhido mao:r_esc2 suic", "o portador morto não roda o equipamento")
    T.eq(g:creature_at(1, 2), nil)
  end },

  { "fim de rodada de um jogador que mata criatura do outro antes da vez dela", function(T)
    local log = {}
    define_loggers(log)
    Cards.define{ id = "r_mata2", kind = "criatura", cost = 0, atk = 1, hp = 5,
      on_round_end = function(g, c) log[#log + 1] = "mata:fim"; g:kill(g:creature_at(2, 1), "teste") end }
    local g = new_game(1)
    put(g, 1, "r_mata2", 1); put(g, 2, "b1", 1); put(g, 2, "b2", 2)
    for k in pairs(log) do log[k] = nil end
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(only(log, ":fim"), "mata b2", "a criatura do outro jogador que morreu não roda")
  end },

  { "vitória por efeito na passada retomada depois de uma escolha", function(T)
    local log = {}
    define_loggers(log)
    Cards.define{ id = "r_esc3", kind = "criatura", cost = 0, atk = 1, hp = 5,
      on_round_start = function(g, c)
        g:set_choice(c.owner, { reason = "teste", options = { "x" }, resolve = function() end })
      end }
    Cards.define{ id = "r_letal2", kind = "criatura", cost = 0, atk = 1, hp = 5,
      on_round_start = function(g, c) log[#log + 1] = "letal"; g:damage_player(2, 99, "teste") end }
    local g = new_game(1)
    put(g, 1, "r_esc3", 1); put(g, 1, "r_letal2", 2); put(g, 1, "a3", 3)
    put(g, 2, "b1", 1)
    g.players[2].life = 1
    for k in pairs(log) do log[k] = nil end
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g.winner, nil); T.ok(g.pending_choice ~= nil)
    T.ok(g:act(1, { type = "choose", index = 1 }))
    T.eq(g.winner, 1)
    -- Na rodada 2 o jogador 2 tem o token: b1 roda antes da escolha; a3 nunca roda.
    T.eq(table.concat(log, " "), "a3:fim b1:fim b1:inicio letal", "ninguém depois do efeito letal roda")
  end },

  { "ganchos genéricos continuam rodando, depois da passada pelo campo", function(T)
    local log = {}
    define_loggers(log)
    local g = new_game(1)
    put(g, 1, "a1", 1); put(g, 2, "b1", 1)
    g:on("round_end", function(gg) log[#log + 1] = "g:fim" end)
    g:on("round_start", function(gg) log[#log + 1] = "g:inicio" end)
    g:on("period", function(gg, per) log[#log + 1] = "g:" .. per end)
    for k in pairs(log) do log[k] = nil end
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(table.concat(log, " "), "a1:fim b1:fim g:fim b1:inicio a1:inicio g:inicio b1:manha a1:manha g:manha")
  end },

  { "contexto de erro aponta a carta e o momento", function(T)
    Cards.define{ id = "r_bug", kind = "estrutura", cost = 0,
      on_period_start = function() error("BUG_NO_PERIODO") end }
    install_agir()
    local g = new_game(1)
    put_st(g, 1, "r_bug", 1)
    g:act(1, { type = "agir" }); g:act(2, { type = "agir" })
    T.eq(g.phase, "error")
    T.eq(g.error.context.kind, "inicio_periodo")
    T.eq(g.error.context.id, "r_bug")
  end },
}
