-- Casos apontados na revisão de código dos PRs #61 a #78.
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local log

local function creature_target(g, p, action)
  local t = action.target
  if t == nil or g:creature_at(t.p, t.slot) == nil then return false, "escolha uma criatura" end
  return true
end

local function define_test_cards()
  log = {}
  Cards.define{ id = "r_bicho", kind = "criatura", cost = 0, atk = 1, hp = 2 }
  Cards.define{ id = "r_sobrev", kind = "criatura", cost = 0, atk = 1, hp = 2, sobrevivente = true }
  Cards.define{ id = "r_dardo", kind = "feitico", speed = "rapido", cost = 0, targets = creature_target,
    on_cast = function(g, p, a) log[#log + 1] = "dardo:" .. a.target.slot end }
  -- Resposta: abate a criatura do espaço 1 do jogador 2 e cria uma ficha no lugar.
  Cards.define{ id = "r_troca", kind = "feitico", speed = "rapido", cost = 0,
    on_cast = function(g, p)
      g:kill(g:creature_at(2, 1), "teste")
      g:create_token(2, "r_bicho", { slot = 1 })
    end }
  Cards.define{ id = "r_raio", kind = "feitico", speed = "instantaneo", cost = 0,
    on_cast = function(g, p) log[#log + 1] = "raio:" .. p end }
  Cards.define{ id = "r_casa", kind = "estrutura", cost = 0 }
  Cards.define{ id = "r_torre", kind = "estrutura", cost = 0 }
  Cards.define{ id = "r_pergunta", kind = "criatura", cost = 0, atk = 0, hp = 1,
    on_play = function(g, c)
      g:set_choice(c.owner, { reason = "teste", options = { "a", "b" },
        resolve = function(gg, idx) log[#log + 1] = "escolheu:" .. idx end })
    end }
  Cards.define{ id = "r_tocha", kind = "equipamento", slot = "mao", cost = 0,
    activation = { speed = "instantaneo", once_per_round = true },
    activate = function(g, p) log[#log + 1] = "tocha" end }
  Cards.define{ id = "r_machado", kind = "equipamento", slot = "mao", cost = 0, atk_bonus = 2, durability = 4 }
  Cards.define{ id = "r_chester", kind = "criatura", cost = 0, atk = 0, hp = 4,
    activation = { speed = "instantaneo" },
    activate = function(g, p, c) log[#log + 1] = "chester:" .. c.slot end }
  Cards.define{ id = "r_bomba", kind = "criatura", cost = 0, atk = 0, hp = 1,
    on_death = function(g, c) log[#log + 1] = "morreu:" .. c.slot end }
  Cards.define{ id = "r_meia", kind = "criatura", cost = 0, atk = 1, hp = 5,
    stats = function(g, c) return 7 end }
end

local function new_game(hand1, hand2)
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "r_bicho" }; d2[i] = { id = "r_bicho" } end
  for _, id in ipairs(hand1 or {}) do d1[#d1 + 1] = { id = id } end
  for _, id in ipairs(hand2 or {}) do d2[#d2 + 1] = { id = id } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function play(g, p, id, fields)
  local a = { type = "play" }
  local zone = g.players[p][(fields and fields.from) or "hand"]
  for i, card in ipairs(zone) do if card.id == id then a.hand_index = i; break end end
  for k, v in pairs(fields or {}) do a[k] = v end
  return g:act(p, a)
end

local function count(list, id)
  local n = 0
  for _, card in ipairs(list) do if card.id == id then n = n + 1 end end
  return n
end

return {
  { "alvo trocado por outra criatura no mesmo espaço: o feitiço perde o efeito", function(T)
    local g = new_game({ "r_dardo" }, { "r_troca" })
    g.players[2].field[1] = nil
    g:place_creature(2, { id = "r_bicho", uid = g:next_uid() }, 1)
    T.ok(play(g, 1, "r_dardo", { target = { p = 2, slot = 1 } }))
    g:act(1, { type = "pass" })
    T.ok(play(g, 2, "r_troca"))
    g:act(2, { type = "pass" })
    g:act(1, { type = "pass" })
    T.ok(g:creature_at(2, 1) ~= nil, "a ficha nova ocupa o espaço 1")
    T.eq(#log, 0, "o Dardo não acerta a ficha nova")
    Cards.remove("r_troca")
  end },

  { "uids são únicos na partida e os baralhos recebidos não são alterados", function(T)
    define_test_cards()
    local d1, d2 = {}, {}
    for i = 1, 5 do d1[i] = { id = "r_bicho", uid = i }; d2[i] = { id = "r_bicho", uid = i } end
    local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
    local seen = {}
    for p = 1, 2 do
      for _, card in ipairs(g.players[p].deck) do
        T.ok(not seen[card.uid], "uid repetido")
        seen[card.uid] = true
      end
    end
    T.ok(not seen[g:next_uid()], "o próximo uid não colide")
    T.eq(d1[1].uid, 1, "o baralho recebido não muda")
    T.ok(g.players[1].deck[1] ~= d1[1], "a partida usa cópias")
  end },

  { "estrutura não substitui outra quando há espaço livre", function(T)
    local g = new_game({ "r_casa", "r_torre" })
    play(g, 1, "r_casa"); g:act(2, { type = "pass" })
    local ok = play(g, 1, "r_torre", { slot = 1 })
    T.eq(ok, false)
    T.eq(g:structure_at(1, 1).def.id, "r_casa")
  end },

  { "ficha de estrutura com a zona cheia: o dono escolhe qual substituir", function(T)
    local g = new_game()
    g:put_structure(1, { id = "r_casa", uid = g:next_uid() }, 1)
    g:put_structure(1, { id = "r_casa", uid = g:next_uid() }, 2)
    T.eq(g:create_token(1, "r_torre"), nil)
    T.ok(g.pending_choice ~= nil and g.pending_choice.player == 1)
    T.ok(g:act(1, { type = "choose", index = 2 }))
    T.eq(g:structure_at(1, 2).def.id, "r_torre")
    T.eq(g:structure_at(1, 1).def.id, "r_casa")
  end },

  { "escolha aberta por efeito de entrada segura a vez até ser feita", function(T)
    local g = new_game({ "r_pergunta" })
    local vez = g.vez
    T.ok(play(g, 1, "r_pergunta", { slot = 1 }))
    T.eq(g.vez, vez, "a vez não avança antes da escolha")
    T.eq(g.active, 1)
    T.ok(g:act(1, { type = "choose", index = 1 }))
    T.eq(g.vez, vez + 1)
    T.eq(g.active, 2)
  end },

  { "cartas separadas podem ser jogadas", function(T)
    local g = new_game()
    local card = table.remove(g.players[1].hand)
    g.players[1].separated[1] = card
    T.ok(play(g, 1, card.id, { from = "separated", slot = 2 }))
    T.eq(#g.players[1].separated, 0)
    T.ok(g:creature_at(1, 2) ~= nil)
  end },

  { "criatura devolvida pode mandar os equipamentos para o Inventário", function(T)
    local g = new_game()
    local c = g:place_creature(1, { id = "r_sobrev", uid = g:next_uid() }, 1)
    g:equip(c, { id = "r_machado", uid = g:next_uid() })
    g:wear(c, "mao", 1)
    g:remove_creature(c, "hand", "telelocador", { equips = "inventory" })
    local inv = g.players[1].inventory
    T.eq(#inv, 1)
    T.eq(inv[1].durability, 3)
    T.eq(count(g.players[1].discard, "r_machado"), 0)
    T.eq(count(g.players[1].hand, "r_sobrev"), 1)
  end },

  { "reequipar não zera o limite de 1 vez por rodada", function(T)
    local g = new_game()
    local c = g:place_creature(1, { id = "r_sobrev", uid = g:next_uid() }, 1)
    local tocha = { id = "r_tocha", uid = g:next_uid() }
    g:equip(c, tocha)
    T.ok(g:act(1, { type = "activate", creature = 1, equip = "mao" }))
    g:equip(c, { id = "r_machado", uid = g:next_uid() })        -- a Tocha vai para o Inventário
    local inv = g.players[1].inventory
    g:equip(c, table.remove(inv, 1))                            -- e volta
    local ok = g:act(1, { type = "activate", creature = 1, equip = "mao" })
    T.eq(ok, false)
    T.eq(#log, 1)
  end },

  { "ativação 1 vez por rodada volta a valer na rodada seguinte", function(T)
    local g = new_game()
    local c = g:place_creature(1, { id = "r_sobrev", uid = g:next_uid() }, 1)
    g:equip(c, { id = "r_tocha", uid = g:next_uid() })
    T.ok(g:act(1, { type = "activate", creature = 1, equip = "mao" }))
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g.round, 2)
    T.ok(g:act(g.active, { type = "pass" }))
    T.ok(g:act(1, { type = "activate", creature = 1, equip = "mao" }))
    T.eq(#log, 2)
  end },

  { "criatura com efeito ativado próprio", function(T)
    local g = new_game()
    g:place_creature(1, { id = "r_chester", uid = g:next_uid() }, 3)
    T.ok(g:act(1, { type = "activate", creature = 3 }))
    T.eq(log[1], "chester:3")
  end },

  { "bloquear continua permitido com a fogueira em zero", function(T)
    T.eq(Game.allowed_at_zero_fogueira.block, true)
  end },

  { "ganchos de carta valem só para a partida onde foram registrados", function(T)
    local g1, g2 = new_game(), new_game()
    local fired = {}
    g1:on("round_start", function(g) fired[#fired + 1] = g end)
    g1:act(1, { type = "pass" }); g1:act(2, { type = "pass" })
    g2:act(1, { type = "pass" }); g2:act(2, { type = "pass" })
    T.eq(#fired, 1)
    T.eq(fired[1], g1)
  end },

  { "limite de mão por jogador com modificadores", function(T)
    local g = new_game()
    g.hand_limit_mods[1] = function(gg, p) return p == 1 and 2 or 0 end
    T.eq(g:hand_limit(1), Game.HAND_LIMIT + 2)
    T.eq(g:hand_limit(2), Game.HAND_LIMIT)
  end },

  { "abater dispara o efeito ao morrer e os ganchos de morte", function(T)
    local g = new_game()
    local seen
    g:on("death", function(gg, c) seen = c.def.id end)
    local c = g:place_creature(1, { id = "r_bomba", uid = g:next_uid() }, 4)
    g:kill(c, "teste")
    T.eq(log[1], "morreu:4")
    T.eq(seen, "r_bomba")
    T.eq(count(g.players[1].discard, "r_bomba"), 1)
  end },

  { "pilha que fecha na virada para a noite acende a fogueira", function(T)
    local g = new_game({ "r_dardo" })
    g:place_creature(2, { id = "r_bicho", uid = g:next_uid() }, 1)
    -- Leva a partida à vez 4 (tarde), com o jogador 2 na vez.
    g.vez, g.active = 4, 2
    g:update_period()
    T.eq(g:period(), "tarde")
    g.players[2].hand[#g.players[2].hand + 1] = { id = "r_dardo", uid = g:next_uid() }
    T.ok(play(g, 2, "r_dardo", { target = { p = 2, slot = 1 } }))
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.eq(g.vez, 5)
    T.eq(g:period(), "noite")
    T.ok(g:is_night_lit())
    T.eq(g.active, 1)
  end },

  { "Instantâneo do respondente não conta como pôr algo na pilha", function(T)
    local g = new_game({ "r_dardo" }, { "r_raio" })
    g:place_creature(2, { id = "r_bicho", uid = g:next_uid() }, 1)
    play(g, 1, "r_dardo", { target = { p = 2, slot = 1 } })
    g:act(1, { type = "pass" })
    T.ok(play(g, 2, "r_raio"))
    T.eq(log[1], "raio:2", "resolve na hora")
    g:act(2, { type = "pass" })                  -- não pôs nada na pilha: resolve
    T.eq(g:stack_open(), false)
    T.eq(log[2], "dardo:1")
  end },

  { "custo fixado na zona não acompanha a carta jogada nem descartada", function(T)
    local g = new_game({ "r_bomba" })
    local card
    for _, c in ipairs(g.players[1].hand) do if c.id == "r_bomba" then card = c end end
    card.cost_override = 0; card.cost_mod = 1
    T.ok(play(g, 1, "r_bomba", { slot = 2 }))
    T.eq(card.cost_override, nil)
    T.eq(card.cost_mod, nil)
    local c = g:creature_at(1, 2)
    card.used_round = 3
    g:remove_creature(c, "discard", "teste")
    T.eq(card.used_round, nil)
  end },

  { "evento de destruição traz id e card_uid", function(T)
    local g = new_game()
    local card = { id = "r_bicho", uid = g:next_uid() }
    g:destroy_card(1, card, "teste")
    local ev = g.events[#g.events]
    T.eq(ev.t, "destroyed")
    T.eq(ev.card_uid, card.uid)
    T.eq(ev.id, "r_bicho")
    T.eq(ev.card, nil)
  end },

  { "stats que devolve só o ataque mantém a vida impressa", function(T)
    local g = new_game()
    local c = g:place_creature(1, { id = "r_meia", uid = g:next_uid() }, 1)
    T.eq(g:atk(c), 7)
    T.eq(g:hp(c), 5)
  end },

  { "definições incompletas são recusadas no registro", function(T)
    T.eq(pcall(Cards.define, { id = "r_x", kind = "feitico", speed = "rapido" }), false, "feitiço sem on_cast")
    T.eq(pcall(Cards.define, { id = "r_y", kind = "equipamento" }), false, "equipamento sem slot")
  end },

  { "troca inicial com jogador inválido é recusada", function(T)
    define_test_cards()
    local g = Game.new{ decks = { {}, {} }, first = 1, rng = function(n) return n end }
    g:start()
    local ok = g:mulligan(3, {})
    T.eq(ok, false)
  end },

  { "alvo com formato inválido é recusado antes de qualquer gasto", function(T)
    local g = new_game({ "r_raio", "r_dardo" })
    local pl = g.players[1]
    local hand, mana = #pl.hand, pl.mana
    for _, bad in ipairs({ 2, { p = 3, slot = 1 }, { p = 1, slot = 9 }, { p = 1, slot = 1.5 },
      { p = 1, slot = 1, zone = "mar" } }) do
      local ok = play(g, 1, "r_raio", { target = bad })
      T.eq(ok, false)
      ok = play(g, 1, "r_dardo", { targets = { bad } })
      T.eq(ok, false)
    end
    T.eq(#pl.hand, hand); T.eq(pl.mana, mana)
    local c = g:place_creature(1, { id = "r_sobrev", uid = g:next_uid() }, 1)
    g:equip(c, { id = "r_tocha", uid = g:next_uid() })
    T.eq(g:act(1, { type = "activate", creature = 1, equip = "mao", target = 3 }), false)
    T.eq(g:act(1, { type = "activate", creature = 1, equip = "mao" }), true, "o uso da rodada não foi gasto")
  end },

  { "alvo de estrutura trocada perde o efeito; criatura no mesmo espaço não interfere", function(T)
    local g = new_game()
    Cards.define{ id = "r_marreta", kind = "feitico", speed = "rapido", cost = 0,
      on_cast = function(gg, p, a) log[#log + 1] = "marreta" end }
    g:put_structure(2, { id = "r_casa", uid = g:next_uid() }, 1)
    g:place_creature(2, { id = "r_bicho", uid = g:next_uid() }, 1)
    g.players[1].hand[#g.players[1].hand + 1] = { id = "r_marreta", uid = g:next_uid() }
    T.ok(play(g, 1, "r_marreta", { target = { p = 2, slot = 1, zone = "estrutura" } }))
    g:kill(g:creature_at(2, 1), "teste")       -- a criatura do espaço 1 sai
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(log[1], "marreta", "o alvo era a estrutura, que continua em campo")
    g.players[1].hand[#g.players[1].hand + 1] = { id = "r_marreta", uid = g:next_uid() }
    g.active = 1
    T.ok(play(g, 1, "r_marreta", { target = { p = 2, slot = 1, zone = "estrutura" } }))
    g:break_structure(2, 1, "teste")
    g:put_structure(2, { id = "r_torre", uid = g:next_uid() }, 1)
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(#log, 1, "estrutura trocada: perde o alvo")
  end },

  { "duas escolhas seguidas entram em fila", function(T)
    local g = new_game()
    g:put_structure(1, { id = "r_casa", uid = g:next_uid() }, 1)
    g:put_structure(1, { id = "r_casa", uid = g:next_uid() }, 2)
    local _, why1 = g:create_token(1, "r_torre")
    local _, why2 = g:create_token(1, "r_torre")
    T.eq(why1, "pendente"); T.eq(why2, "pendente")
    T.ok(g:act(1, { type = "choose", index = 1 }))
    T.ok(g.pending_choice ~= nil, "a segunda escolha abre depois da primeira")
    T.ok(g:act(1, { type = "choose", index = 2 }))
    T.eq(g:structure_at(1, 1).def.id, "r_torre")
    T.eq(g:structure_at(1, 2).def.id, "r_torre")
  end },

  { "escolha aberta no fim da rodada suspende a rodada", function(T)
    local g = new_game()
    g:on("round_end", function(gg)
      gg:set_choice(1, { reason = "teste", options = { "a" },
        resolve = function() log[#log + 1] = "fim" end })
    end)
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g.round, 1, "a rodada espera a escolha")
    T.ok(g:act(1, { type = "choose", index = 1 }))
    T.eq(log[1], "fim")
    T.eq(g.round, 2)
  end },

  { "criatura devolvida à mão cheia tem prioridade sobre os equipamentos", function(T)
    local g = new_game()
    local pl = g.players[1]
    local c = g:place_creature(1, { id = "r_sobrev", uid = g:next_uid() }, 1)
    g:equip(c, { id = "r_machado", uid = g:next_uid() })
    while g:hand_count(1) < g:hand_limit(1) - 1 do pl.hand[#pl.hand + 1] = { id = "r_bicho", uid = g:next_uid() } end
    g:remove_creature(c, "hand", "telelocador", { equips = "inventory" })
    T.eq(count(pl.hand, "r_sobrev"), 1, "a criatura voltou para a mão")
    T.eq(count(pl.destroyed, "r_machado"), 1, "sem vaga, o equipamento é destruído")
  end },

  { "ficha de estrutura com espaço indicado ocupado usa o espaço livre", function(T)
    local g = new_game()
    g:put_structure(1, { id = "r_casa", uid = g:next_uid() }, 1)
    local st = g:create_token(1, "r_torre", { slot = 1 })
    T.eq(st.slot, 2)
    T.eq(g:structure_at(1, 1).def.id, "r_casa")
  end },

  { "colocar estrutura com a zona cheia sem indicar o espaço devolve erro", function(T)
    local g = new_game()
    g:put_structure(1, { id = "r_casa", uid = g:next_uid() }, 1)
    g:put_structure(1, { id = "r_casa", uid = g:next_uid() }, 2)
    local st, err = g:put_structure(1, { id = "r_torre", uid = g:next_uid() })
    T.eq(st, nil)
    T.ok(err ~= nil)
  end },

  { "abater informa quem matou", function(T)
    local g = new_game()
    local killer_seen
    Cards.define{ id = "r_cao", kind = "criatura", cost = 0, atk = 2, hp = 2,
      on_death = function(gg, c, killer) killer_seen = killer and killer.def.id end }
    local cao = g:place_creature(1, { id = "r_cao", uid = g:next_uid() }, 1)
    local outro = g:place_creature(2, { id = "r_bicho", uid = g:next_uid() }, 1)
    g:kill(cao, "combate", outro)
    T.eq(killer_seen, "r_bicho")
    local death
    for _, ev in ipairs(g.events) do if ev.t == "death" then death = ev end end
    T.eq(death.killer_uid, outro.uid)
  end },

  { "stats que devolve só a vida mantém o ataque impresso", function(T)
    local g = new_game()
    Cards.define{ id = "r_vida", kind = "criatura", cost = 0, atk = 3, hp = 1,
      stats = function() return nil, 5 end }
    local c = g:place_creature(1, { id = "r_vida", uid = g:next_uid() }, 1)
    T.eq(g:atk(c), 3)
    T.eq(g:hp(c), 5)
  end },

  { "gancho removido durante a passada não roda", function(T)
    local g = new_game()
    local ran = {}
    local b
    g:on("round_start", function(gg) ran[#ran + 1] = "a"; gg:off("round_start", b) end)
    b = g:on("round_start", function() ran[#ran + 1] = "b" end)
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(#ran, 1)
    T.eq(ran[1], "a")
  end },

  { "o baralho recebido não muda nem nas tabelas internas", function(T)
    define_test_cards()
    local d1 = { { id = "r_bicho", markers = { n = 1 } } }
    local g = Game.new{ decks = { d1, {} }, first = 1, mulligan = false, rng = function(n) return n end }
    g.players[1].deck[1].markers.n = 5
    T.eq(d1[1].markers.n, 1)
  end },

  { "limite de mão com modificador vale ao comprar e pode ser removido", function(T)
    local g = new_game()
    local pl = g.players[1]
    local remove = g:add_hand_limit_mod(function(gg, p) return p == 1 and 2 or 0 end)
    while g:hand_count(1) < Game.HAND_LIMIT do pl.hand[#pl.hand + 1] = { id = "r_bicho", uid = g:next_uid() } end
    T.ok(g:add_to_hand(1, { id = "r_bicho", uid = g:next_uid() }), "cabe a 11ª")
    remove()
    T.eq(g:add_to_hand(1, { id = "r_bicho", uid = g:next_uid() }), false, "sem a Mochila, não cabe")
  end },

  { "eventos de campo trazem uid e card_uid; de zona, card_uid", function(T)
    local g = new_game()
    local card = { id = "r_bicho", uid = g:next_uid() }
    local c = g:place_creature(1, card, 2)
    local ev = g.events[#g.events]
    T.eq(ev.t, "summon"); T.eq(ev.uid, c.uid); T.eq(ev.card_uid, card.uid)
    g:remove_creature(c, "hand", "teste")
    local leave, to_hand = g.events[#g.events - 1], g.events[#g.events]
    T.eq(leave.t, "leave"); T.eq(leave.card_uid, card.uid)
    T.eq(to_hand.t, "to_hand"); T.eq(to_hand.card_uid, card.uid); T.eq(to_hand.private, true)
  end },

  { "com a fogueira em zero, só cartas que não gastam fogueira podem ser jogadas", function(T)
    local g = new_game()
    Cards.define{ id = "r_turf", kind = "criatura", cost = 0, atk = 0, hp = 1, no_fogueira = true }
    local pl = g.players[1]
    pl.hand[#pl.hand + 1] = { id = "r_turf", uid = g:next_uid() }
    g:light_fogueira()
    g.fogueira[1] = 0
    T.eq(play(g, 1, "r_bicho", { slot = 1 }), false, "carta comum")
    T.ok(play(g, 1, "r_turf", { slot = 2 }))
    T.eq(g.fogueira[1], 0)
  end },

  { "zona cheia: o dono pode não substituir nenhuma e a ficha não entra", function(T)
    local g = new_game()
    g:put_structure(1, { id = "r_casa", uid = g:next_uid() }, 1)
    g:put_structure(1, { id = "r_casa", uid = g:next_uid() }, 2)
    g:create_token(1, "r_torre")
    T.ok(g:act(1, { type = "choose", index = 0 }))
    T.eq(g:structure_at(1, 1).def.id, "r_casa")
    T.eq(g:structure_at(1, 2).def.id, "r_casa")
    T.eq(g.events[#g.events].t, "vanish")
  end },
}
