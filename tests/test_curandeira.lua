-- Curandeira (US #129, deck do Webber): +1 de vida para as aranhas do dono e
-- cura 2 numa aranha sua que sobreviver a dano.
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

-- O executor restaura o registro de cartas entre os casos, então o módulo é
-- carregado de novo a cada caso.
local function load_cartas()
  package.loaded["duelo/cartas/init"] = nil
  package.loaded["duelo/cartas/numeros"] = nil
  return require("duelo/cartas/init"), require("duelo/cartas/numeros")
end

local function define_test_cards()
  Cards.define{ id = "cu_comum", kind = "criatura", cost = 0, atk = 1, hp = 9 }
  Cards.define{ id = "cu_um", kind = "criatura", cost = 0, atk = 1, hp = 9 }
  Cards.define{ id = "cu_dois", kind = "criatura", cost = 0, atk = 2, hp = 9 }
  Cards.define{ id = "cu_tres", kind = "criatura", cost = 0, atk = 3, hp = 9 }
  Cards.define{ id = "cu_urso", kind = "criatura", cost = 0, atk = 5, hp = 9 }
end

local function new_game()
  load_cartas()
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "cu_comum" }; d2[i] = { id = "cu_comum" } end
  local g = Game.new{ decks = { d1, d2 }, extra_decks = { { { id = "aranha" } }, { { id = "aranha" } } },
    first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function put(g, p, id, slot)
  return g:place_creature(p, { id = id, uid = g:next_uid() }, slot)
end

local function give(g, p, id)
  local pl = g.players[p]
  pl.hand[#pl.hand + 1] = { id = id, uid = g:next_uid() }
  return #pl.hand
end

local function equip(g, c, id)
  return g:equip(c, { id = id, uid = g:next_uid() })
end

-- Ataque do jogador 1 com bloqueios do jogador 2 ({ { atacante, bloqueador }, ... }),
-- resolvido até o fim.
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

return {
  { "a Curandeira está registrada com os atributos e o número oficial", function(T)
    local _, numeros = load_cartas()
    local d = Cards.get("curandeira")
    T.ok(d ~= nil, "registrada")
    T.eq(d.name, "Curandeira"); T.eq(d.kind, "criatura")
    T.eq(d.cost, 4); T.eq(d.atk, 0); T.eq(d.hp, 4)
    T.eq(d.types.aranha, true)
    T.eq(d.numero, 23); T.eq(numeros.curandeira, 23)
    T.eq(type(d.text), "string")
  end },

  { "as aranhas do dono têm +1 de vida; as do adversário e as não aranhas, não", function(T)
    local g = new_game()
    local aranha = put(g, 1, "aranha", 1)
    local guerreira = put(g, 1, "aranha_guerreira", 2)
    local webber = put(g, 1, "webber", 3)
    local comum = put(g, 1, "cu_comum", 5)
    local alheia = put(g, 2, "aranha", 1)
    T.eq(g:hp(aranha), 1)
    local cur = put(g, 1, "curandeira", 6)
    T.eq(g:hp(aranha), 2)
    T.eq(g:hp(guerreira), 5)
    T.eq(g:hp(webber), 4, "o Webber é aranha")
    T.eq(g:hp(cur), 5, "a própria Curandeira fica 0/5")
    T.eq(g:atk(cur), 0)
    T.eq(g:hp(comum), 9, "não aranha")
    T.eq(g:hp(alheia), 1, "aranha do adversário")
  end },

  { "Curandeira jogada da mão custa 4 e entra como 0/5", function(T)
    local g = new_game()
    g.players[1].mana = 4
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "curandeira"), slot = 1 }))
    T.eq(g.players[1].mana, 0)
    local c = g:creature_at(1, 1)
    T.eq(c.def.id, "curandeira")
    T.eq(g:hp(c), 5)
  end },

  { "aranha com 1 de dano em 2 de vida sobrevive e é curada: o dano volta a 0", function(T)
    local g = new_game()
    put(g, 1, "cu_um", 1)
    local aranha = put(g, 2, "aranha", 1)
    put(g, 2, "curandeira", 2)
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(g:creature_at(2, 1), aranha, "sobreviveu")
    T.eq(aranha.damage, 0, "curada")
    local heals = events(g, "creature_heal")
    T.eq(#heals, 1)
    T.eq(heals[1].amount, 1, "a cura de 2 tira só o dano que havia")
    T.eq(heals[1].uid, aranha.uid)
    T.eq(heals[1].reason, "curandeira")
  end },

  { "a cura de 2 tira até 2 de dano", function(T)
    local g = new_game()
    local guerreira = put(g, 1, "aranha_guerreira", 1)
    put(g, 1, "curandeira", 2)
    g:damage_creature(guerreira, 2, nil, "teste")
    T.eq(guerreira.damage, 0)
    g:damage_creature(guerreira, 4, nil, "teste")
    T.eq(guerreira.damage, 2, "4 de dano em 5 de vida: sobrevive e cura 2")
    g:settle()
    T.eq(g:creature_at(1, 1), guerreira)
  end },

  { "dano letal não dispara a cura", function(T)
    local g = new_game()
    put(g, 1, "cu_dois", 1)
    put(g, 2, "aranha", 1)
    put(g, 2, "curandeira", 2)
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(g:creature_at(2, 1), nil, "2 de dano em 2 de vida: morreu")
    T.eq(#events(g, "creature_heal"), 0)
  end },

  { "a própria Curandeira é curada quando sobrevive", function(T)
    local g = new_game()
    put(g, 1, "cu_tres", 1)
    local cur = put(g, 2, "curandeira", 1)
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(cur.damage, 1, "3 de dano em 5 de vida, curada em 2")
  end },

  { "quando a Curandeira sai de campo, a aranha com dano igual à vida base morre", function(T)
    local g = new_game()
    local aranha = put(g, 1, "aranha", 1)
    -- O dano é marcado antes de a Curandeira entrar (sem cura): 1 em 1 de vida.
    g:damage_creature(aranha, 1, nil, "teste")
    local cur = put(g, 1, "curandeira", 2)
    g:settle()
    T.eq(g:creature_at(1, 1), aranha, "com a Curandeira, 1 de dano em 2 de vida: vive")
    g:remove_creature(cur, "hand", "teste")
    g:settle()
    T.eq(g:creature_at(1, 1), nil, "sem a Curandeira, 1 de dano em 1 de vida mata")
    local deaths = events(g, "death")
    T.eq(#deaths, 1); T.eq(deaths[1].reason, "dano")
  end },

  { "a Curandeira morrendo em combate leva junto a aranha que só vivia pelo bônus", function(T)
    local g = new_game()
    put(g, 1, "cu_urso", 1)
    local guerreira = put(g, 2, "aranha_guerreira", 1)
    g:damage_creature(guerreira, 4, nil, "teste")
    put(g, 2, "curandeira", 2)
    g:settle()
    T.eq(g:creature_at(2, 1), guerreira, "com a Curandeira, 4 de dano em 5 de vida: vive")
    fight(g, { 1 }, { { 1, 2 } })
    T.eq(g:creature_at(2, 2), nil, "a Curandeira morreu com 5 de dano")
    T.eq(g:creature_at(2, 1), nil, "a guerreira morreu junto, sem outro dano")
    T.eq(g.players[2].life, Game.START_LIFE)
  end },

  { "duas Curandeiras dão +2 de vida e curam 4", function(T)
    local g = new_game()
    local guerreira = put(g, 1, "aranha_guerreira", 1)
    local c1 = put(g, 1, "curandeira", 2)
    local c2 = put(g, 1, "curandeira", 3)
    T.eq(g:hp(guerreira), 6)
    T.eq(g:hp(c1), 6); T.eq(g:hp(c2), 6)
    g:damage_creature(guerreira, 5, nil, "teste")
    T.eq(guerreira.damage, 1, "5 de dano em 6 de vida, curada em 4")
    T.eq(#events(g, "creature_heal"), 2)
  end },

  { "aranha do adversário não é curada", function(T)
    local g = new_game()
    put(g, 1, "cu_um", 1)
    put(g, 1, "curandeira", 2)
    local alheia = put(g, 2, "aranha_guerreira", 1)
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(alheia.damage, 1)
    T.eq(#events(g, "creature_heal"), 0)
  end },

  { "não aranha do dono não é curada", function(T)
    local g = new_game()
    put(g, 1, "cu_um", 1)
    local comum = put(g, 2, "cu_comum", 1)
    put(g, 2, "curandeira", 2)
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(comum.damage, 1)
    T.eq(#events(g, "creature_heal"), 0)
  end },

  { "dano absorvido pela Armadura de madeira não dispara a cura", function(T)
    local g = new_game()
    put(g, 1, "cu_um", 1)
    local webber = put(g, 2, "webber", 1)
    put(g, 2, "curandeira", 3)
    equip(g, webber, "armadura_de_madeira")
    T.eq(g:hp(webber), 5, "3 + 1 da armadura + 1 da Curandeira")
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(webber.damage, 0)
    T.eq(#events(g, "damage_absorbed"), 1)
    T.eq(#events(g, "creature_heal"), 0)
    -- Dano que passa da redução conta normalmente.
    g:damage_creature(webber, 3, nil, "teste")
    T.eq(webber.damage, 0, "2 marcados, 2 curados")
    T.eq(#events(g, "creature_heal"), 1)
  end },
}
