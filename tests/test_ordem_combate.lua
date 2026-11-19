-- Combate resolvido par a par, na ordem dos espaços dos atacantes (#121):
-- ordem, mortes e efeitos entre pares, Velocidade dentro do par e Guarda.
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local log

local function define_test_cards()
  log = {}
  Cards.define{ id = "o_comum", kind = "criatura", cost = 0, atk = 1, hp = 9 }
  Cards.define{ id = "o_lobo", kind = "criatura", cost = 0, atk = 3, hp = 2 }
  Cards.define{ id = "o_rato", kind = "criatura", cost = 0, atk = 1, hp = 1 }
  Cards.define{ id = "o_rapida", kind = "criatura", cost = 0, atk = 2, hp = 2, speed = 2 }
  Cards.define{ id = "o_tres", kind = "criatura", cost = 0, atk = 1, hp = 9, speed = 3 }
  -- Golpear: registra o próprio espaço.
  Cards.define{ id = "o_marca", kind = "criatura", cost = 0, atk = 1, hp = 9,
    on_strike = function(g, c) log[#log + 1] = "golpe:" .. c.slot end }
  -- Guarda com 2 de ataque e vida para sobreviver a vários pares.
  Cards.define{ id = "o_guarda", kind = "criatura", cost = 0, atk = 2, hp = 9, kw = { guarda = true } }
end

local function new_game()
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "o_comum" }; d2[i] = { id = "o_comum" } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function put(g, p, id, slot)
  return g:place_creature(p, { id = id, uid = g:next_uid() }, slot)
end

-- Ataque do jogador 1 com bloqueios do jogador 2 ({ { atacante, bloqueador }, ... }),
-- resolvido até o fim (ou até uma escolha abrir).
local function fight(g, attackers, blocks)
  assert(g:act(1, { type = "attack", attackers = attackers }))
  assert(g:act(1, { type = "pass" }))
  if blocks then
    local list = {}
    for i, pr in ipairs(blocks) do list[i] = { attacker = pr[1], blocker = pr[2] } end
    assert(g:act(2, { type = "block", blocks = list }))
  end
  assert(g:act(2, { type = "pass" }))
  if blocks and #blocks > 0 then assert(g:act(1, { type = "pass" })) end
end

local function events(g, t)
  local list = {}
  for _, ev in ipairs(g.events) do if ev.t == t then list[#list + 1] = ev end end
  return list
end

-- Os saltos da Guarda: { { attacker = uid, blocker = uid }, ... }.
local function guard_jumps(g)
  local list = {}
  for _, ev in ipairs(events(g, "block")) do
    if ev.auto == "guarda" then
      for _, b in ipairs(ev.blocks) do list[#list + 1] = b end
    end
  end
  return list
end

-- Criatura que, ao morrer, mata a criatura do jogador p no espaço slot.
local function define_bomba(id, p, slot)
  Cards.define{ id = id, kind = "criatura", cost = 0, atk = 0, hp = 1,
    on_death = function(g)
      local alvo = g:creature_at(p, slot)
      if alvo then g:kill(alvo, "bomba") end
    end }
end

return {
  { "os pares resolvem na ordem dos espaços, não na ordem declarada", function(T)
    local g = new_game()
    put(g, 1, "o_marca", 1); put(g, 1, "o_marca", 3); put(g, 1, "o_marca", 5)
    fight(g, { 5, 1, 3 })
    T.eq(table.concat(log, ","), "golpe:1,golpe:3,golpe:5")
    local phases = events(g, "strike_phase")
    T.eq(#phases, 3, "uma fase por par")
    T.eq(phases[1].attacker_uid, g:creature_at(1, 1).uid)
    T.eq(phases[3].attacker_uid, g:creature_at(1, 5).uid)
    T.eq(phases[1].blocker_uid, nil)
  end },

  { "o evento da fase traz o par: atacante e bloqueador", function(T)
    local g = new_game()
    local a = put(g, 1, "o_comum", 2)
    local d = put(g, 2, "o_comum", 4)
    fight(g, { 2 }, { { 2, 4 } })
    local phases = events(g, "strike_phase")
    T.eq(#phases, 1)
    T.eq(phases[1].phase, "normal")
    T.eq(phases[1].attacker_uid, a.uid)
    T.eq(phases[1].blocker_uid, d.uid)
  end },

  { "ao morrer do par 1 mata o bloqueador do par 2: o atacante 2 não golpeia ninguém", function(T)
    local g = new_game()
    define_bomba("o_bomba", 2, 2)
    put(g, 1, "o_lobo", 1); local a2 = put(g, 1, "o_lobo", 2)
    put(g, 2, "o_bomba", 1); local d2 = put(g, 2, "o_comum", 2)
    local life = g.players[2].life
    fight(g, { 1, 2 }, { { 1, 1 }, { 2, 2 } })
    T.eq(g:creature_at(2, 2), nil, "o bloqueador morreu pela bomba")
    T.eq(d2.damage, 0, "e não foi golpeado")
    T.eq(a2.damage, 0)
    T.eq(g.players[2].life, life, "o bloqueio declarado vale: nada passa ao jogador")
    local phases = events(g, "strike_phase")
    T.eq(#phases, 1, "o par 2 não teve fase")
  end },

  { "ao morrer do par 1 mata o atacante do par 2: o par é pulado", function(T)
    local g = new_game()
    define_bomba("o_bomba2", 1, 2)
    put(g, 1, "o_lobo", 1); put(g, 1, "o_lobo", 2)
    put(g, 2, "o_bomba2", 1); local d2 = put(g, 2, "o_comum", 2)
    fight(g, { 1, 2 }, { { 1, 1 }, { 2, 2 } })
    T.eq(g:creature_at(1, 2), nil)
    T.eq(d2.damage, 0, "o bloqueador do par pulado não foi golpeado")
    T.eq(#events(g, "strike_phase"), 1)
  end },

  { "ao morrer do par 1 mata o atacante sem bloqueio do par 2: o jogador não sofre o golpe", function(T)
    local g = new_game()
    define_bomba("o_bomba3", 1, 2)
    put(g, 1, "o_lobo", 1); put(g, 1, "o_lobo", 2)
    put(g, 2, "o_bomba3", 1)
    local life = g.players[2].life
    fight(g, { 1, 2 }, { { 1, 1 } })
    T.eq(g.players[2].life, life)
  end },

  { "o Golpear do par 1 acontece antes do par 2", function(T)
    local g = new_game()
    Cards.define{ id = "o_compra", kind = "criatura", cost = 0, atk = 1, hp = 9,
      on_strike = function(gg, c) gg:draw(c.owner, 1) end }
    local seen
    Cards.define{ id = "o_olha", kind = "criatura", cost = 0, atk = 1, hp = 9,
      on_strike = function(gg, c) seen = gg:hand_count(c.owner) end }
    put(g, 1, "o_compra", 1); put(g, 1, "o_olha", 2)
    local hand = g:hand_count(1)
    fight(g, { 2, 1 })
    T.eq(seen, hand + 1, "a carta comprada no par 1 já está na mão no par 2")
  end },

  { "escolha aberta no par 1 segura o par 2, que continua depois dela", function(T)
    local g = new_game()
    Cards.define{ id = "o_escolhe", kind = "criatura", cost = 0, atk = 0, hp = 1,
      on_death = function(gg, c)
        gg:set_choice(c.owner, { reason = "x", options = { "a" }, resolve = function() log[#log + 1] = "escolhido" end })
      end }
    put(g, 1, "o_lobo", 1); put(g, 1, "o_marca", 2)
    put(g, 2, "o_escolhe", 1); local d2 = put(g, 2, "o_comum", 2)
    fight(g, { 1, 2 }, { { 1, 1 }, { 2, 2 } })
    T.ok(g.pending_choice ~= nil)
    T.eq(d2.damage, 0, "o par 2 espera a escolha")
    T.eq(#log, 0)
    T.ok(g:stack_open(), "o resto do combate está na pilha")
    T.ok(g:act(2, { type = "choose", index = 1 }))
    T.eq(table.concat(log, ","), "escolhido,golpe:2")
    T.eq(d2.damage, 1)
    T.eq(g:stack_open(), false)
    T.eq(#events(g, "combat_end"), 1)
    T.eq(#events(g, "combat_start"), 1)
  end },

  { "escolha aberta no último par não deixa o combate pendurado", function(T)
    local g = new_game()
    Cards.define{ id = "o_escolhe2", kind = "criatura", cost = 0, atk = 0, hp = 1,
      on_death = function(gg, c)
        gg:set_choice(c.owner, { reason = "x", options = { "a" }, resolve = function() end })
      end }
    put(g, 1, "o_marca", 1); put(g, 1, "o_lobo", 2)
    put(g, 2, "o_escolhe2", 2)
    fight(g, { 1, 2 }, { { 2, 2 } })
    T.ok(g.pending_choice ~= nil)
    T.eq(#events(g, "combat_end"), 1, "o par 2 era o último: o combate já acabou")
    T.ok(g:act(2, { type = "choose", index = 1 }))
    T.eq(g:stack_open(), false)
  end },

  { "Velocidade dentro do par: 2 contra 1 mata sem revide, mesmo com outro par antes", function(T)
    local g = new_game()
    put(g, 1, "o_comum", 1)
    local rapida = put(g, 1, "o_rapida", 2)
    put(g, 2, "o_comum", 1); put(g, 2, "o_rapida", 2)
    fight(g, { 1, 2 }, { { 1, 1 }, { 2, 2 } })
    T.eq(g:creature_at(1, 1).damage, 1); T.eq(g:creature_at(2, 1).damage, 1)
    T.eq(g:creature_at(1, 2), nil, "iguais morrem juntas")
    T.eq(g:creature_at(2, 2), nil)
    g = new_game()
    put(g, 1, "o_comum", 1); rapida = put(g, 1, "o_rapida", 2)
    put(g, 2, "o_comum", 1); local lenta = put(g, 2, "o_rapida", 2)
    g:add_speed_mod(lenta, { set = 1 })
    fight(g, { 1, 2 }, { { 1, 1 }, { 2, 2 } })
    T.eq(g:creature_at(2, 2), nil, "a de velocidade 1 morre na fase rápida")
    T.eq(rapida.damage, 0, "sem revide")
  end },

  { "Velocidade 3 golpeia nas duas fases do par e uma vez no jogador", function(T)
    local g = new_game()
    put(g, 1, "o_tres", 1); put(g, 1, "o_tres", 2)
    local d = put(g, 2, "o_comum", 1)
    local life = g.players[2].life
    fight(g, { 1, 2 }, { { 1, 1 } })
    T.eq(d.damage, 2)
    T.eq(g.players[2].life, life - 1)
    local phases = events(g, "strike_phase")
    T.eq(#phases, 3)
    T.eq(phases[1].phase, "rapida"); T.eq(phases[2].phase, "normal"); T.eq(phases[3].phase, "rapida")
  end },

  { "quem morre na fase rápida do par não golpeia na normal; o par seguinte não é afetado", function(T)
    local g = new_game()
    local rapida = put(g, 1, "o_rapida", 1); put(g, 1, "o_comum", 2)
    put(g, 2, "o_comum", 1); local d2 = put(g, 2, "o_comum", 2)
    g.players[2].field[1].damage = 7   -- 2 de vida restante: morre na fase rápida
    fight(g, { 1, 2 }, { { 1, 1 }, { 2, 2 } })
    T.eq(g:creature_at(2, 1), nil)
    T.eq(rapida.damage, 0)
    T.eq(d2.damage, 1); T.eq(g:creature_at(1, 2).damage, 1)
  end },

  { "Guarda salta para o próximo atacante sem bloqueador à direita", function(T)
    local g = new_game()
    local a1 = put(g, 1, "o_comum", 1); local a2 = put(g, 1, "o_comum", 2); local a3 = put(g, 1, "o_comum", 3)
    local porco = put(g, 2, "o_guarda", 1)
    local life = g.players[2].life
    fight(g, { 1, 2, 3 }, { { 1, 1 } })
    local jumps = guard_jumps(g)
    T.eq(#jumps, 1)
    T.eq(jumps[1].attacker, a2.uid); T.eq(jumps[1].blocker, porco.uid)
    T.eq(a1.damage, 2); T.eq(a2.damage, 2, "o par do salto resolve normalmente"); T.eq(a3.damage, 0)
    T.eq(porco.damage, 2, "a Guarda leva o revide dos dois pares")
    T.eq(g.players[2].life, life - 1, "só o terceiro atacante passa")
    T.eq(g.combat, nil)
  end },

  { "Guarda não salta para a esquerda nem quando ataca", function(T)
    local g = new_game()
    put(g, 1, "o_comum", 1); local a3 = put(g, 1, "o_comum", 3)
    put(g, 2, "o_guarda", 1)
    local life = g.players[2].life
    fight(g, { 1, 3 }, { { 3, 1 } })
    T.eq(#guard_jumps(g), 0)
    T.eq(g.players[2].life, life - 1)
    T.eq(a3.damage, 2)
    -- Atacando, a Guarda não faz nada de especial.
    g = new_game()
    put(g, 1, "o_guarda", 1); put(g, 1, "o_comum", 2)
    put(g, 2, "o_comum", 1); put(g, 2, "o_comum", 2)
    fight(g, { 1, 2 }, { { 1, 1 } })
    T.eq(#guard_jumps(g), 0)
  end },

  { "Guarda que morreu no par dela não salta", function(T)
    local g = new_game()
    put(g, 1, "o_lobo", 1); put(g, 1, "o_comum", 2)
    local porco = put(g, 2, "o_guarda", 1)
    porco.damage = 7
    local life = g.players[2].life
    fight(g, { 1, 2 }, { { 1, 1 } })
    T.eq(g:creature_at(2, 1), nil)
    T.eq(#guard_jumps(g), 0)
    T.eq(g.players[2].life, life - 1)
  end },

  { "Guarda não salta para o atacante que perdeu o bloqueador", function(T)
    local g = new_game()
    -- O Golpear do atacante 1 mata o bloqueador do atacante 2 antes da vez dele.
    Cards.define{ id = "o_mata_rato", kind = "criatura", cost = 0, atk = 1, hp = 9,
      on_strike = function(gg) local r = gg:creature_at(2, 2); if r then gg:kill(r, "teste") end end }
    local a1 = put(g, 1, "o_mata_rato", 1); local a2 = put(g, 1, "o_comum", 2); local a3 = put(g, 1, "o_comum", 3)
    put(g, 2, "o_guarda", 1); put(g, 2, "o_rato", 2)
    local life = g.players[2].life
    fight(g, { 1, 2, 3 }, { { 1, 1 }, { 2, 2 } })
    T.eq(g:creature_at(2, 2), nil, "o rato morreu no par 1")
    local jumps = guard_jumps(g)
    T.eq(#jumps, 1)
    T.eq(jumps[1].attacker, a3.uid, "a Guarda pula o atacante 2, que já teve bloqueador")
    T.eq(a2.damage, 0, "o atacante 2 não golpeia nem é golpeado")
    T.eq(a3.damage, 2)
    T.eq(a1.damage, 2)
    T.eq(g.players[2].life, life)
  end },

  { "Guarda salta uma vez só por combate", function(T)
    local g = new_game()
    put(g, 1, "o_comum", 1); put(g, 1, "o_comum", 2); local a3 = put(g, 1, "o_comum", 3)
    put(g, 2, "o_guarda", 1)
    local life = g.players[2].life
    fight(g, { 1, 2, 3 }, { { 1, 1 } })
    T.eq(#guard_jumps(g), 1)
    T.eq(a3.damage, 0)
    T.eq(g.players[2].life, life - 1)
  end },

  { "duas Guardas: cada uma pega o próximo atacante livre", function(T)
    local g = new_game()
    put(g, 1, "o_comum", 1); local a2 = put(g, 1, "o_comum", 2)
    local a3 = put(g, 1, "o_comum", 3); local a4 = put(g, 1, "o_comum", 4)
    local p1 = put(g, 2, "o_guarda", 1); local p2 = put(g, 2, "o_guarda", 2)
    local life = g.players[2].life
    fight(g, { 1, 2, 3, 4 }, { { 1, 1 }, { 2, 2 } })
    local jumps = guard_jumps(g)
    T.eq(#jumps, 2)
    T.eq(jumps[1].blocker, p1.uid); T.eq(jumps[1].attacker, a3.uid)
    T.eq(jumps[2].blocker, p2.uid); T.eq(jumps[2].attacker, a4.uid)
    T.eq(a2.damage, 2); T.eq(a3.damage, 2); T.eq(a4.damage, 2)
    T.eq(p1.damage, 2); T.eq(p2.damage, 2)
    T.eq(g.players[2].life, life)
  end },

  { "com duas Guardas elegíveis, salta a do menor espaço, não a do par anterior", function(T)
    local g = new_game()
    put(g, 1, "o_comum", 1); put(g, 1, "o_comum", 2)
    local a3 = put(g, 1, "o_comum", 3); local a4 = put(g, 1, "o_comum", 4)
    -- A Guarda do espaço 5 bloqueia o atacante 1 (par que resolve antes); a do
    -- espaço 2 bloqueia o atacante 2. Na vez do atacante 3, as duas estão
    -- elegíveis: salta a do espaço 2.
    local p5 = put(g, 2, "o_guarda", 5); local p2 = put(g, 2, "o_guarda", 2)
    fight(g, { 1, 2, 3, 4 }, { { 1, 5 }, { 2, 2 } })
    local jumps = guard_jumps(g)
    T.eq(#jumps, 2)
    T.eq(jumps[1].attacker, a3.uid); T.eq(jumps[1].blocker, p2.uid, "menor espaço primeiro")
    T.eq(jumps[2].attacker, a4.uid); T.eq(jumps[2].blocker, p5.uid)
  end },

  { "Guarda cujo par acabou numa escolha salta depois dela", function(T)
    local g = new_game()
    Cards.define{ id = "o_morre_escolhe", kind = "criatura", cost = 0, atk = 1, hp = 2,
      on_death = function(gg, c)
        gg:set_choice(c.owner, { reason = "x", options = { "a" }, resolve = function() end })
      end }
    put(g, 1, "o_morre_escolhe", 1); local a2 = put(g, 1, "o_comum", 2)
    local porco = put(g, 2, "o_guarda", 1)
    local life = g.players[2].life
    fight(g, { 1, 2 }, { { 1, 1 } })
    T.ok(g.pending_choice ~= nil)
    T.eq(#guard_jumps(g), 0, "ainda não saltou: a morte do par 1 espera a escolha")
    T.ok(g:act(1, { type = "choose", index = 1 }))
    T.eq(#guard_jumps(g), 1)
    T.eq(a2.damage, 2)
    T.eq(porco.damage, 2)
    T.eq(g.players[2].life, life)
  end },

  { "Guarda não salta para um atacante que já saiu de campo", function(T)
    local g = new_game()
    -- O Golpear da Guarda mata o atacante 2 no par 1.
    Cards.define{ id = "o_guarda_mata", kind = "criatura", cost = 0, atk = 2, hp = 9, kw = { guarda = true },
      on_strike = function(gg) local b = gg:creature_at(1, 2); if b then gg:kill(b, "teste") end end }
    put(g, 1, "o_comum", 1); put(g, 1, "o_comum", 2); local a3 = put(g, 1, "o_comum", 3)
    put(g, 2, "o_guarda_mata", 1)
    local life = g.players[2].life
    fight(g, { 1, 2, 3 }, { { 1, 1 } })
    T.eq(g:creature_at(1, 2), nil)
    local jumps = guard_jumps(g)
    T.eq(#jumps, 1)
    T.eq(jumps[1].attacker, a3.uid)
    T.eq(a3.damage, 2)
    T.eq(g.players[2].life, life)
  end },

  { "vitória no meio do combate para os pares seguintes", function(T)
    local g = new_game()
    put(g, 1, "o_lobo", 1); put(g, 1, "o_marca", 2)
    local d2 = put(g, 2, "o_comum", 2)
    g.players[2].life = 3
    fight(g, { 1, 2 }, { { 2, 2 } })
    T.eq(g.winner, 1)
    T.eq(d2.damage, 0)
    T.eq(#log, 0)
    T.eq(#events(g, "combat_end"), 0)
    T.eq(g.combat, nil)
  end },

  { "vitória pelo ao morrer de um par para os pares seguintes", function(T)
    local g = new_game()
    Cards.define{ id = "o_vinga", kind = "criatura", cost = 0, atk = 0, hp = 1,
      on_death = function(gg) gg:damage_player(1, 99, "teste") end }
    put(g, 1, "o_lobo", 1); put(g, 1, "o_marca", 2)
    put(g, 2, "o_vinga", 1)
    fight(g, { 1, 2 }, { { 1, 1 } })
    T.eq(g.winner, 2)
    T.eq(#log, 0, "o par 2 não golpeou")
  end },

  { "a ordem dos pares é a dos espaços no momento da resolução", function(T)
    local g = new_game()
    local a = put(g, 1, "o_marca", 3)
    put(g, 1, "o_marca", 4)
    assert(g:act(1, { type = "attack", attackers = { 3, 4 } }))
    -- Antes de resolver, a criatura do espaço 3 muda para o 6.
    g.players[1].field[3] = nil
    g.players[1].field[6] = a
    a.slot = 6
    assert(g:act(1, { type = "pass" })); assert(g:act(2, { type = "pass" }))
    T.eq(table.concat(log, ","), "golpe:4,golpe:6")
  end },
}
