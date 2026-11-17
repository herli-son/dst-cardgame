local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local log

local function define_test_cards()
  log = {}
  Cards.define{ id = "c_lobo", kind = "criatura", cost = 0, atk = 3, hp = 2 }
  Cards.define{ id = "c_muro", kind = "criatura", cost = 0, atk = 1, hp = 5 }
  Cards.define{ id = "c_rato", kind = "criatura", cost = 0, atk = 1, hp = 1 }
  Cards.define{ id = "c_tentaculo", kind = "criatura", cost = 0, atk = 0, hp = 6, no_attack = true }
  Cards.define{ id = "c_ghost", kind = "criatura", cost = 0, atk = 1, hp = 1, no_block = true }
  Cards.define{ id = "c_cura", kind = "feitico", speed = "rapido", cost = 0,
    on_cast = function(g, p) log[#log + 1] = "cura:" .. p end }
end

local function new_game()
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "c_rato" }; d2[i] = { id = "c_rato" } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function put(g, p, id, slot)
  return g:place_creature(p, { id = id, uid = g:next_uid() }, slot)
end

local function attack(g, slots) return g:act(g.attacker, { type = "attack", attackers = slots }) end

return {
  { "atacante sem bloqueio causa dano ao jogador e a vez vai para o defensor", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1)
    local life = g.players[2].life
    T.ok(attack(g, { 1 }))
    T.ok(g:stack_open(), "o ataque abre a pilha")
    T.ok(g:act(1, { type = "pass" }))          -- pronto
    T.eq(g.active, 2)
    T.ok(g:act(2, { type = "pass" }))          -- sem bloqueio: resolve
    T.eq(g.players[2].life, life - 3)
    T.eq(g:stack_open(), false)
    T.eq(g.active, 2, "a vez é de quem não abriu a pilha")
  end },

  { "só quem tem o token ataca, e uma vez por rodada", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1); put(g, 2, "c_lobo", 1)
    g:act(1, { type = "pass" })
    T.eq(g:act(2, { type = "attack", attackers = { 1 } }), false, "sem o token")
    g:act(2, { type = "pass" })
    g = new_game()
    put(g, 1, "c_lobo", 1)
    attack(g, { 1 }); g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    g:act(2, { type = "pass" })
    T.eq(g.active, 1)
    T.eq(attack(g, { 1 }), false, "segundo ataque na rodada")
  end },

  { "criatura que entrou nesta rodada pode atacar", function(T)
    local g = new_game()
    local pl = g.players[1]
    pl.hand[#pl.hand + 1] = { id = "c_lobo", uid = g:next_uid() }
    T.ok(g:act(1, { type = "play", hand_index = #pl.hand, slot = 2 }))
    g:act(2, { type = "pass" })
    T.ok(attack(g, { 2 }))
  end },

  { "declaração de ataque inválida é recusada", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1); put(g, 1, "c_tentaculo", 2)
    T.eq(attack(g, {}), false)
    T.eq(attack(g, { 3 }), false, "espaço vazio")
    T.eq(attack(g, { 1, 1 }), false, "repetida")
    T.eq(attack(g, { 2 }), false, "não ataca")
    T.eq(g.attacked_round, nil, "nada foi gasto")
  end },

  { "bloqueio troca dano entre atacante e bloqueador; o excesso não passa ao jogador", function(T)
    local g = new_game()
    local lobo = put(g, 1, "c_lobo", 1)
    local rato = put(g, 2, "c_rato", 4)
    local life = g.players[2].life
    attack(g, { 1 }); g:act(1, { type = "pass" })
    T.ok(g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 4 } } }))
    T.eq(g.active, 2, "declarar bloqueios não passa a vez")
    T.ok(g:act(2, { type = "pass" }))          -- pronto: volta ao atacante
    T.eq(g.active, 1)
    T.ok(g:act(1, { type = "pass" }))          -- resolve
    T.eq(g:creature_at(2, 4), nil, "o rato morreu")
    T.eq(lobo.damage, 1)
    T.eq(g.players[2].life, life)
    T.eq(g.active, 2)
  end },

  { "dano fica marcado e a criatura morre quando chega à vida", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1)
    local muro = put(g, 2, "c_muro", 1)
    attack(g, { 1 }); g:act(1, { type = "pass" })
    g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 } } })
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.eq(muro.damage, 3)
    T.ok(g:creature_at(2, 1) == muro, "5 de vida, 3 de dano: vive")
  end },

  { "bloqueios só na primeira resposta do defensor", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1); put(g, 2, "c_rato", 1)
    local pl2 = g.players[2]
    pl2.hand[#pl2.hand + 1] = { id = "c_cura", uid = g:next_uid() }
    local pl1 = g.players[1]
    pl1.hand[#pl1.hand + 1] = { id = "c_cura", uid = g:next_uid() }
    attack(g, { 1 }); g:act(1, { type = "pass" })
    T.ok(g:act(2, { type = "play", hand_index = #pl2.hand }), "Rápido na primeira resposta")
    T.ok(g:act(2, { type = "pass" }))          -- pronto sem bloquear
    T.ok(g:act(1, { type = "play", hand_index = #pl1.hand }))
    T.ok(g:act(1, { type = "pass" }))
    T.eq(g.active, 2)
    local ok = g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 } } })
    T.eq(ok, false, "segunda resposta: não bloqueia mais")
    local life = g.players[2].life
    g:act(2, { type = "pass" })
    T.eq(g.players[2].life, life - 3, "sem bloqueio, o lobo acerta o jogador")
  end },

  { "bloqueios inválidos são recusados", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1); put(g, 1, "c_rato", 2)
    put(g, 2, "c_rato", 1); put(g, 2, "c_ghost", 2)
    attack(g, { 1 }); g:act(1, { type = "pass" })
    T.eq(g:act(2, { type = "block", blocks = { { attacker = 2, blocker = 1 } } }), false, "não está atacando")
    T.eq(g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 5 } } }), false, "sem bloqueador")
    T.eq(g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 2 } } }), false, "não bloqueia")
    T.eq(g:act(1, { type = "block", blocks = {} }), false, "não é o defensor")
  end },

  { "cada atacante tem um bloqueador e cada bloqueador um atacante", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1); put(g, 1, "c_lobo", 2)
    put(g, 2, "c_muro", 1); put(g, 2, "c_muro", 2)
    attack(g, { 1, 2 }); g:act(1, { type = "pass" })
    T.eq(g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 }, { attacker = 1, blocker = 2 } } }), false)
    T.eq(g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 }, { attacker = 2, blocker = 1 } } }), false)
    T.ok(g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 }, { attacker = 2, blocker = 2 } } }))
  end },

  { "bloqueador que sai de campo antes: o atacante continua bloqueado", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1)
    local rato = put(g, 2, "c_rato", 1)
    local life = g.players[2].life
    attack(g, { 1 }); g:act(1, { type = "pass" })
    g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 } } })
    local lobo = g:creature_at(1, 1)
    g:kill(rato, "teste")
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.eq(g.players[2].life, life)
    T.eq(lobo.damage, 0)
  end },

  { "feitiços da resposta resolvem antes do combate", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1)
    local pl2 = g.players[2]
    pl2.hand[#pl2.hand + 1] = { id = "c_cura", uid = g:next_uid() }
    attack(g, { 1 }); g:act(1, { type = "pass" })
    g:act(2, { type = "play", hand_index = #pl2.hand })
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.eq(log[1], "cura:2")
    local cura_at, combat_at
    for i, ev in ipairs(g.events) do
      if ev.t == "stack_resolve" and ev.label == "c_cura" then cura_at = i end
      if ev.t == "combat_start" then combat_at = i end
    end
    T.ok(cura_at ~= nil and combat_at ~= nil)
    T.ok(cura_at < combat_at, "a cura veio antes do combate")
  end },

  { "atacar continua permitido com a fogueira em zero e não gasta fogueira", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1)
    g:light_fogueira()
    g.fogueira[1] = 0
    T.ok(attack(g, { 1 }))
    T.eq(g.fogueira[1], 0)
  end },

  { "dano de combate pode vencer a partida", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1)
    g.players[2].life = 3
    attack(g, { 1 }); g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g.winner, 1)
  end },

  { "lista de bloqueios vazia: o pass seguinte resolve", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1); put(g, 2, "c_rato", 1)
    local life = g.players[2].life
    attack(g, { 1 }); g:act(1, { type = "pass" })
    T.ok(g:act(2, { type = "block", blocks = {} }))
    g:act(2, { type = "pass" })
    T.eq(g:stack_open(), false)
    T.eq(g.players[2].life, life - 3)
  end },

  { "atacante que sai de campo antes de resolver não golpeia nem é golpeado", function(T)
    local g = new_game()
    local lobo = put(g, 1, "c_lobo", 1)
    local muro = put(g, 2, "c_muro", 1)
    local life = g.players[2].life
    attack(g, { 1 }); g:act(1, { type = "pass" })
    g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 } } })
    g:remove_creature(lobo, "hand", "teste")
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.eq(muro.damage, 0)
    T.eq(g.players[2].life, life)
  end },

  { "atacante que sai e volta é outra instância e fica fora do combate", function(T)
    local g = new_game()
    local lobo = put(g, 1, "c_lobo", 1)
    local life = g.players[2].life
    attack(g, { 1 }); g:act(1, { type = "pass" })
    g:remove_creature(lobo, "hand", "teste")
    put(g, 1, "c_lobo", 1)
    g:act(2, { type = "pass" })
    T.eq(g.players[2].life, life)
  end },

  { "criatura que muda de dono sai do combate", function(T)
    local g = new_game()
    local lobo = put(g, 1, "c_lobo", 1)
    local life1, life2 = g.players[1].life, g.players[2].life
    attack(g, { 1 }); g:act(1, { type = "pass" })
    g.players[1].field[1] = nil
    g.players[2].field[3] = lobo
    lobo.owner, lobo.slot = 2, 3
    g:act(2, { type = "pass" })
    T.eq(g.players[2].life, life2)
    T.eq(g.players[1].life, life1)
  end },

  { "morte em combate: motivo combate, quem matou, e morte mútua simultânea", function(T)
    local g = new_game()
    local seen = {}
    g:on("death", function(gg, c, killer)
      seen[#seen + 1] = { c.def.id, killer and killer.def.id, killer and gg:find_creature(killer.uid) ~= nil }
    end)
    put(g, 1, "c_rato", 1); put(g, 2, "c_rato", 1)
    attack(g, { 1 }); g:act(1, { type = "pass" })
    g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 } } })
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.eq(#seen, 2)
    T.eq(seen[1][2], "c_rato"); T.eq(seen[2][2], "c_rato")
    T.eq(seen[1][3], false, "na morte mútua, o matador também já saiu de campo")
    local deaths = 0
    for _, ev in ipairs(g.events) do
      if ev.t == "death" then deaths = deaths + 1; T.eq(ev.reason, "combate"); T.ok(ev.killer_uid ~= nil) end
    end
    T.eq(deaths, 2)
  end },

  { "vários atacantes: bloqueados e livres, um golpe ao jogador por atacante", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1); put(g, 1, "c_lobo", 2); put(g, 1, "c_rato", 3)
    put(g, 2, "c_muro", 1)
    local life = g.players[2].life
    attack(g, { 1, 2, 3 }); g:act(1, { type = "pass" })
    g:act(2, { type = "block", blocks = { { attacker = 2, blocker = 1 } } })
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.eq(g.players[2].life, life - 4)
    local hits = 0
    for _, ev in ipairs(g.events) do
      if ev.t == "player_damage" and ev.source == "combate" then hits = hits + 1; T.ok(ev.from_uid ~= nil) end
    end
    T.eq(hits, 2)
    T.eq(g.combat, nil)
  end },

  { "vitória é verificada antes das mortes: o efeito ao morrer não decide a partida", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1); put(g, 1, "c_lobo", 2)
    put(g, 2, "c_rato", 1)
    g.players[1].life = 1
    g.players[2].life = 3
    g:on("death", function(gg) gg:damage_player(1, 1, "teste") end)
    attack(g, { 1, 2 }); g:act(1, { type = "pass" })
    g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 } } })
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.eq(g.winner, 1)
    T.eq(g.players[1].life, 1, "o efeito de morte não rodou depois da vitória")
  end },

  { "golpe com dano zero também é registrado", function(T)
    local g = new_game()
    Cards.define{ id = "c_zero", kind = "criatura", cost = 0, atk = 0, hp = 3 }
    put(g, 1, "c_zero", 1); put(g, 2, "c_muro", 1)
    attack(g, { 1 }); g:act(1, { type = "pass" })
    g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 } } })
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    local strikes = 0
    for _, ev in ipairs(g.events) do if ev.t == "strike" then strikes = strikes + 1 end end
    T.eq(strikes, 2)
  end },

  { "partida vencida no meio da pilha limpa o combate", function(T)
    local g = new_game()
    Cards.define{ id = "c_fim", kind = "feitico", speed = "rapido", cost = 0,
      on_cast = function(gg) gg:damage_player(1, 99, "teste") end }
    put(g, 1, "c_lobo", 1)
    local pl2 = g.players[2]
    pl2.hand[#pl2.hand + 1] = { id = "c_fim", uid = g:next_uid() }
    attack(g, { 1 }); g:act(1, { type = "pass" })
    g:act(2, { type = "play", hand_index = #pl2.hand }); g:act(2, { type = "pass" })
    g:act(1, { type = "pass" })
    T.eq(g.winner, 2)
    T.eq(g.combat, nil)
  end },

  { "formatos inválidos de ataque e bloqueio são recusados sem gastar nada", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1); put(g, 2, "c_rato", 1)
    for _, bad in ipairs({ "1", { "1" }, { 0 / 0 }, { 1.5 }, { 7 }, { [2] = 1 }, { 1, x = 2 } }) do
      T.eq(attack(g, bad), false)
    end
    T.eq(g.attacked_round, nil)
    attack(g, { 1 }); g:act(1, { type = "pass" })
    for _, bad in ipairs({ "x", { [2] = { attacker = 1, blocker = 1 } }, { { attacker = "1", blocker = 1 } },
      { { attacker = 1, blocker = 0 / 0 } } }) do
      T.eq(g:act(2, { type = "block", blocks = bad }), false)
    end
    T.ok(g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 } } }), "a janela continua aberta")
  end },

  { "ataque à noite: o período não avança no meio do combate", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1)
    g.vez, g.active = 5, 1
    g:update_period()
    attack(g, { 1 }); g:act(1, { type = "pass" })
    T.eq(g.vez, 5)
    g:act(2, { type = "pass" })
    T.eq(g.vez, 6)
    T.eq(g.active, 2)
  end },

  { "golpes da mesma fase usam os valores de antes de qualquer dano", function(T)
    local g = new_game()
    Cards.define{ id = "c_raiva", kind = "criatura", cost = 0, atk = 1, hp = 9,
      stats = function(gg, c) return 1 + c.damage end }
    local lobo = put(g, 1, "c_lobo", 1)
    put(g, 2, "c_raiva", 1)
    attack(g, { 1 }); g:act(1, { type = "pass" })
    g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 } } })
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.eq(lobo.damage, 1, "o bloqueador golpeia com 1, não com 4")
  end },

  { "efeitos de morte param quando a partida é decidida", function(T)
    local g = new_game()
    put(g, 1, "c_rato", 1); put(g, 1, "c_rato", 2)
    put(g, 2, "c_rato", 1); put(g, 2, "c_rato", 2)
    g.players[2].life = 1
    g:on("death", function(gg) gg:damage_player(2, 1, "teste") end)
    attack(g, { 1, 2 }); g:act(1, { type = "pass" })
    g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 }, { attacker = 2, blocker = 2 } } })
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.eq(g.winner, 1)
    T.eq(g.players[2].life, 0, "só o primeiro efeito rodou")
  end },

  { "criatura com dano letal fora do combate morre depois da ação", function(T)
    local g = new_game()
    Cards.define{ id = "c_sobrev", kind = "criatura", cost = 0, atk = 1, hp = 2, sobrevivente = true }
    Cards.define{ id = "c_armadura", kind = "equipamento", slot = "peito", cost = 0, hp_bonus = 3 }
    Cards.define{ id = "c_capa", kind = "equipamento", slot = "peito", cost = 0 }
    local c = put(g, 1, "c_sobrev", 1)
    g:equip(c, { id = "c_armadura", uid = g:next_uid() })
    c.damage = 3
    local pl = g.players[1]
    pl.hand[#pl.hand + 1] = { id = "c_capa", uid = g:next_uid() }
    T.ok(g:act(1, { type = "play", hand_index = #pl.hand, target = 1 }))
    T.eq(g:creature_at(1, 1), nil, "sem a armadura, 3 de dano em 2 de vida")
  end },

  { "golpe fora de uma fase verifica a vitória na hora", function(T)
    local g = new_game()
    local lobo = put(g, 1, "c_lobo", 1)
    g.players[2].life = 2
    g:strike(lobo, { player = 2 })
    T.eq(g.winner, 1)
  end },

  { "kill_many não mata a mesma criatura duas vezes", function(T)
    local g = new_game()
    local rato = put(g, 1, "c_rato", 1)
    local n = 0
    g:on("death", function() n = n + 1 end)
    g:kill_many({ { rato }, { rato } }, "teste")
    T.eq(n, 1)
  end },

  { "janela de bloqueio funciona depois de outra pilha na mesma rodada", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1); put(g, 2, "c_rato", 1)
    local pl1 = g.players[1]
    pl1.hand[#pl1.hand + 1] = { id = "c_cura", uid = g:next_uid() }
    g:act(1, { type = "play", hand_index = #pl1.hand })
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })   -- a pilha da cura resolve
    g:act(2, { type = "pass" })                                -- volta ao atacante
    T.ok(attack(g, { 1 }))
    g:act(1, { type = "pass" })
    T.ok(g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 } } }))
  end },

  { "morte causada por outra morte também é verificada", function(T)
    local g = new_game()
    Cards.define{ id = "c_bomba", kind = "criatura", cost = 0, atk = 0, hp = 2,
      on_death = function(gg) gg:damage_creature(gg:creature_at(1, 2), 1, nil, "teste") end }
    Cards.define{ id = "c_dano2", kind = "feitico", speed = "instantaneo", cost = 0,
      on_cast = function(gg) gg:damage_creature(gg:creature_at(1, 1), 2, nil, "teste") end }
    put(g, 1, "c_bomba", 1); put(g, 1, "c_rato", 2)
    local pl = g.players[1]
    pl.hand[#pl.hand + 1] = { id = "c_dano2", uid = g:next_uid() }
    T.ok(g:act(1, { type = "play", hand_index = #pl.hand }))
    T.eq(g:creature_at(1, 1), nil)
    T.eq(g:creature_at(1, 2), nil, "o rato morreu pelo efeito da bomba")
  end },

  { "vida que cai na troca de período é verificada", function(T)
    local g = new_game()
    Cards.define{ id = "c_diurna", kind = "criatura", cost = 0, atk = 1, hp = 3,
      stats = function(gg) if gg:period() == "noite" then return 1, 1 end return 1, 3 end }
    local c = put(g, 1, "c_diurna", 1)
    c.damage = 2
    g.vez, g.active = 4, 2
    g:update_period()
    T.ok(g:act(2, { type = "pass" }))           -- vez 5: noite
    T.eq(g:period(), "noite")
    T.eq(g:creature_at(1, 1), nil)
  end },

  { "com uma escolha pendente, a criatura espera o efeito terminar", function(T)
    local g = new_game()
    Cards.define{ id = "c_dano_cura", kind = "feitico", speed = "instantaneo", cost = 0,
      on_cast = function(gg)
        local alvo = gg:creature_at(1, 1)
        gg:damage_creature(alvo, 2, nil, "teste")
        gg:set_choice(1, { reason = "curar", options = { "sim" },
          resolve = function() alvo.damage = 0 end })
      end }
    put(g, 1, "c_lobo", 1)
    local pl = g.players[1]
    pl.hand[#pl.hand + 1] = { id = "c_dano_cura", uid = g:next_uid() }
    T.ok(g:act(1, { type = "play", hand_index = #pl.hand }))
    T.ok(g:creature_at(1, 1) ~= nil, "ainda em campo durante a escolha")
    T.ok(g:act(1, { type = "choose", index = 1 }))
    T.ok(g:creature_at(1, 1) ~= nil, "curado a tempo")
  end },

  { "estado estável entre o fim de uma rodada e o início da seguinte", function(T)
    local g = new_game()
    local seen
    put(g, 2, "c_rato", 1)
    g:on("round_end", function(gg) gg:damage_creature(gg:creature_at(2, 1), 5, nil, "teste") end)
    g:on("round_start", function(gg) seen = gg:creature_at(2, 1) end)
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g.round, 2)
    T.eq(seen, nil, "a rodada nova já não vê a criatura morta")
  end },

  { "erro numa entrada pública ainda estabiliza o estado", function(T)
    local g = new_game()
    local c = put(g, 1, "c_rato", 1)
    g:set_choice(1, { reason = "x", options = { "a" }, resolve = function(gg)
      gg:damage_creature(c, 5, nil, "teste")
      error("falha")
    end })
    local ok = pcall(g.act, g, 1, { type = "choose", index = 1 })
    T.eq(ok, false)
    T.eq(g:creature_at(1, 1), nil)
  end },
}
