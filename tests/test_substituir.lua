local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local log

local function define()
  log = {}
  Cards.define{ id = "s_base", kind = "criatura", cost = 0, atk = 1, hp = 9,
    on_death = function() log[#log + 1] = "morreu" end }
  Cards.define{ id = "s_nova", kind = "criatura", cost = 0, atk = 2, hp = 2,
    on_play = function(g, c) log[#log + 1] = "entrou:" .. c.slot end }
  Cards.define{ id = "s_espada", kind = "equipamento", slot = "mao", cost = 0, atk_bonus = 1 }
  Cards.define{ id = "s_sobrev", kind = "criatura", cost = 0, atk = 1, hp = 9, sobrevivente = true }
  Cards.define{ id = "s_casa", kind = "estrutura", cost = 0 }
  Cards.define{ id = "s_obra", kind = "estrutura", cost = 0 }
  Cards.define{ id = "s_construir", kind = "feitico", speed = "rapido", cost = 0, creates_structure = true,
    on_cast = function(g, p, action) g:create_token(p, "s_obra", { slot = action.replace }) end }
end

local function new_game()
  define()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "s_base" }; d2[i] = { id = "s_base" } end
  local extra = {}
  for i = 1, 3 do extra[i] = { id = "s_obra" } end
  local g = Game.new{ decks = { d1, d2 }, extra_decks = { extra, {} },
    first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function give(g, p, id)
  local pl = g.players[p]
  pl.hand[#pl.hand + 1] = { id = id, uid = g:next_uid() }
  return #pl.hand
end

local function fill(g, p)
  local list = {}
  for s = 1, 6 do list[s] = g:place_creature(p, { id = "s_base", uid = g:next_uid() }, s) end
  return list
end

return {
  { "com espaço livre, não se substitui", function(T)
    local g = new_game()
    g:place_creature(1, { id = "s_base", uid = g:next_uid() }, 1)
    local ok, why = g:act(1, { type = "play", hand_index = give(g, 1, "s_nova"), slot = 1 })
    T.eq(ok, false)
    T.ok(why:find("campo cheio", 1, true) ~= nil)
  end },

  { "com o campo cheio, a substituída é destruída sem ao morrer", function(T)
    local g = new_game()
    local old = fill(g, 1)[3]
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "s_nova"), slot = 3 }))
    T.eq(g:creature_at(1, 3).def.id, "s_nova")
    local d = g.players[1].destroyed
    T.eq(d[#d].uid, old.card_uid)
    for _, e in ipairs(log) do T.ok(e ~= "morreu", "substituir não é morrer") end
    T.eq(log[#log], "entrou:3")
  end },

  { "os equipamentos da substituída vão para o Inventário", function(T)
    local g = new_game()
    local list = {}
    for s = 1, 6 do list[s] = g:place_creature(1, { id = "s_sobrev", uid = g:next_uid() }, s) end
    g:equip(list[2], { id = "s_espada", uid = g:next_uid() })
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "s_nova"), slot = 2 }))
    local inv = g.players[1].inventory
    T.eq(inv[#inv].id, "s_espada")
  end },

  { "alvo de entrada é escolhido na jogada e conferido nela", function(T)
    local g = new_game()
    Cards.define{ id = "s_mira", kind = "criatura", cost = 0, atk = 1, hp = 1,
      play_targets = function(gg, p, action, objects)
        if objects[1] == nil then return false, "escolha uma criatura" end
        return true
      end,
      on_play = function(gg, c, objects) log[#log + 1] = "mira:" .. objects[1].slot end }
    g:place_creature(2, { id = "s_base", uid = g:next_uid() }, 4)
    local ok = g:act(1, { type = "play", hand_index = give(g, 1, "s_mira"), slot = 1 })
    T.eq(ok, false, "sem alvo")
    ok = g:act(1, { type = "play", hand_index = #g.players[1].hand, slot = 1, target = { p = 2, slot = 5 } })
    T.eq(ok, false, "espaço vazio")
    T.ok(g:act(1, { type = "play", hand_index = #g.players[1].hand, slot = 1, target = { p = 2, slot = 4 } }))
    T.eq(log[#log], "mira:4")
  end },

  { "alvo de entrada que era a substituída se perde", function(T)
    local g = new_game()
    Cards.define{ id = "s_mira2", kind = "criatura", cost = 0, atk = 1, hp = 1,
      play_targets = function(gg, p, action, objects) return objects[1] ~= nil end,
      on_play = function() log[#log + 1] = "mira2" end }
    fill(g, 1)
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "s_mira2"), slot = 2, target = { p = 1, slot = 2 } }))
    for _, e in ipairs(log) do T.ok(e ~= "mira2", "alvo perdido") end
    local fizzled = false
    for _, ev in ipairs(g.events) do if ev.t == "fizzle" and ev.id == "s_mira2" then fizzled = true end end
    T.ok(fizzled)
    T.eq(g:creature_at(1, 2).def.id, "s_mira2", "a criatura entra mesmo assim")
  end },

  { "estrutura com alvo de entrada recebe os objetos da jogada", function(T)
    local g = new_game()
    Cards.define{ id = "s_torre", kind = "estrutura", cost = 0,
      play_targets = function(gg, p, action, objects) return objects[1] ~= nil end,
      on_play = function(gg, st, objects) log[#log + 1] = "torre:" .. objects[1].def.id end }
    g:place_creature(2, { id = "s_base", uid = g:next_uid() }, 1)
    T.eq(g:act(1, { type = "play", hand_index = give(g, 1, "s_torre") }), false)
    T.ok(g:act(1, { type = "play", hand_index = #g.players[1].hand, target = { p = 2, slot = 1 } }))
    T.eq(log[#log], "torre:s_base")
  end },

  { "feitiço que cria estrutura com a zona cheia escolhe a substituída na jogada", function(T)
    local g = new_game()
    g:put_structure(1, { id = "s_casa", uid = g:next_uid() }, 1)
    g:put_structure(1, { id = "s_casa", uid = g:next_uid() }, 2)
    local ok, why = g:act(1, { type = "play", hand_index = give(g, 1, "s_construir") })
    T.eq(ok, false)
    T.ok(why:find("substituir", 1, true) ~= nil)
    T.ok(g:act(1, { type = "play", hand_index = #g.players[1].hand, replace = 2 }))
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g:structure_at(1, 1).def.id, "s_casa")
    T.eq(g:structure_at(1, 2).def.id, "s_obra")
    T.eq(g.pending_choice, nil, "nenhuma escolha na resolução")
  end },

  { "se abrir vaga até a resolução, a nova estrutura entra na vaga", function(T)
    local g = new_game()
    g:put_structure(1, { id = "s_casa", uid = g:next_uid() }, 1)
    g:put_structure(1, { id = "s_casa", uid = g:next_uid() }, 2)
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "s_construir"), replace = 2 }))
    g:break_structure(1, 1, "teste")
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g:structure_at(1, 1).def.id, "s_obra")
    T.eq(g:structure_at(1, 2).def.id, "s_casa", "a escolhida não é substituída")
  end },

  { "com vaga na jogada, o feitiço não exige a escolha", function(T)
    local g = new_game()
    g:put_structure(1, { id = "s_casa", uid = g:next_uid() }, 1)
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "s_construir") }))
  end },
}
