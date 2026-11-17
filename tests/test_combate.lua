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
    g:kill(rato, "teste")
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.eq(g.players[2].life, life)
  end },

  { "feitiços da resposta resolvem antes do combate", function(T)
    local g = new_game()
    put(g, 1, "c_lobo", 1)
    local pl2 = g.players[2]
    pl2.hand[#pl2.hand + 1] = { id = "c_cura", uid = g:next_uid() }
    local seen
    g:on("death", function() end)
    attack(g, { 1 }); g:act(1, { type = "pass" })
    g:act(2, { type = "play", hand_index = #pl2.hand })
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.eq(log[1], "cura:2")
    for _, ev in ipairs(g.events) do
      if ev.t == "combat_start" then seen = true end
      if ev.t == "stack_resolve" and ev.label == "c_cura" then T.ok(not seen, "a cura veio antes do combate") end
    end
    T.ok(seen)
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
}
