-- Cartas do deck do Wilson (#20): Wilson, Máquina de Ciência, Machado, Lança,
-- Pá, Armadura de grama e Armadura de madeira.
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

-- O executor restaura o registro de cartas entre os casos, então o módulo é
-- carregado de novo a cada caso.
local function load_cartas()
  package.loaded["duelo/cartas/init"] = nil
  return require("duelo/cartas/init")
end

local function define_test_cards()
  Cards.define{ id = "w_comum", kind = "criatura", cost = 0, atk = 1, hp = 9 }
  Cards.define{ id = "w_sobrev", kind = "criatura", cost = 0, atk = 1, hp = 9, sobrevivente = true }
  Cards.define{ id = "w_zero", kind = "criatura", cost = 0, atk = 0, hp = 9 }
  Cards.define{ id = "w_casa", kind = "estrutura", cost = 0 }
end

-- Baralhos de 20 w_comum; deck1 pode receber cartas extras no topo (fim da
-- lista: a última da lista top1 fica no topo).
local function new_game(top1)
  load_cartas()
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "w_comum" }; d2[i] = { id = "w_comum" } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  for _, id in ipairs(top1 or {}) do g.players[1].deck[#g.players[1].deck + 1] = { id = id, uid = g:next_uid() } end
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

local function find(list, id)
  for i, card in ipairs(list) do if card.id == id then return card, i end end
end

local function count(list, id)
  local n = 0
  for _, card in ipairs(list) do if card.id == id then n = n + 1 end end
  return n
end

-- Leva a partida ao período pedido, sem gastar a rodada: avança as vezes com
-- jogadas que não contam como passe.
local function go_to(g, period)
  Game.actions.w_agir = function() return true end
  while g:period() ~= period do assert(g:act(g.active, { type = "w_agir" })) end
  Game.actions.w_agir = nil
end

return {
  { "o módulo registra as cartas do deck do Wilson com os números oficiais", function(T)
    load_cartas()
    local numeros = require("duelo/cartas/numeros")
    local esperado = {
      wilson = { "Wilson", "criatura", 4, 10 },
      maquina_de_ciencia = { "Máquina de Ciência", "estrutura", 4, 11 },
      machado = { "Machado", "equipamento", 2, 12 },
      lanca = { "Lança", "equipamento", 3, 13 },
      pa = { "Pá", "equipamento", 1, 14 },
      armadura_de_grama = { "Armadura de grama", "equipamento", 1, 15 },
      armadura_de_madeira = { "Armadura de madeira", "equipamento", 2, 16 },
    }
    for id, e in pairs(esperado) do
      local def = Cards.get(id)
      T.ok(def ~= nil, id .. " registrada")
      T.eq(def.name, e[1], id .. " nome")
      T.eq(def.kind, e[2], id .. " tipo")
      T.eq(def.cost, e[3], id .. " custo")
      T.eq(def.numero, e[4], id .. " número")
      T.eq(numeros[id], e[4], id .. " na lista oficial")
      T.eq(type(def.text), "string", id .. " texto")
    end
  end },

  { "Lança: mão, +3 de ataque, durabilidade 6, sem efeito", function(T)
    local g = new_game()
    local c = put(g, 1, "w_sobrev", 1)
    local e = equip(g, c, "lanca")
    T.eq(e.def.slot, "mao")
    T.eq(g:atk(c), 4)
    T.eq(e.durability, 6)
    T.eq(e.def.on_strike, nil); T.eq(e.def.on_attack, nil)
    local life = g.players[2].life
    fight(g, { 1 })
    T.eq(g.players[2].life, life - 4)
    T.eq(e.durability, 5, "gasta 1 por golpe")
  end },

  { "Machado: mão, +2 de ataque, durabilidade 4", function(T)
    local g = new_game()
    local c = put(g, 1, "w_sobrev", 1)
    local e = equip(g, c, "machado")
    T.eq(e.def.slot, "mao")
    T.eq(g:atk(c), 3)
    T.eq(e.durability, 4)
  end },

  { "Machado ao atacar de dia: a fogueira acende à noite com +1", function(T)
    local g = new_game()
    local c = put(g, 1, "w_sobrev", 1)
    equip(g, c, "machado")
    T.eq(g:period(), "manha")
    fight(g, { 1 })
    T.eq(g.fogueira_pending[1], 1, "bônus guardado para a noite")
    T.eq(g.fogueira_pending[2], 0)
    go_to(g, "noite")
    T.eq(g.fogueira[1], Game.FOGUEIRA_START + 1)
    T.eq(g.fogueira[2], Game.FOGUEIRA_START)
  end },

  { "Machado ao atacar à noite: +1 na hora, só para o dono", function(T)
    local g = new_game()
    local c = put(g, 1, "w_sobrev", 1)
    equip(g, c, "machado")
    go_to(g, "noite")
    T.eq(g.active, 1)
    local f1, f2 = g.fogueira[1], g.fogueira[2]
    assert(g:act(1, { type = "attack", attackers = { 1 } }))
    T.eq(g.fogueira[1], f1 + 1, "sobe na declaração do ataque")
    T.eq(g.fogueira[2], f2)
    local fog = events(g, "fogueira")
    T.eq(fog[#fog].reason, "bonus"); T.eq(fog[#fog].p, 1)
  end },

  { "Machado só dispara quando o portador ataca", function(T)
    local g = new_game()
    put(g, 1, "w_comum", 1)
    local c = put(g, 1, "w_sobrev", 2)
    equip(g, c, "machado")
    fight(g, { 1 })
    T.eq(g.fogueira_pending[1], 0, "outra criatura atacando não conta")
    -- Bloqueando também não conta.
    local g2 = new_game()
    put(g2, 1, "w_comum", 1)
    local d = put(g2, 2, "w_sobrev", 1)
    equip(g2, d, "machado")
    fight(g2, { 1 }, { { 1, 1 } })
    T.eq(g2.fogueira_pending[2], 0)
  end },

  { "Pá: mão, +1 de ataque, durabilidade 2; sem golpe não pode ser ativada", function(T)
    local g = new_game()
    local c = put(g, 1, "w_sobrev", 1)
    local e = equip(g, c, "pa")
    T.eq(e.def.slot, "mao"); T.eq(g:atk(c), 2); T.eq(e.durability, 2)
    local hand = #g.players[1].hand
    local ok, err = g:act(1, { type = "activate", creature = 1, equip = "mao" })
    T.eq(ok, false, err)
    T.eq(#g.players[1].hand, hand)
  end },

  { "Pá golpeando fica pronta; ativar fora do combate compra 1 e não gasta a vez", function(T)
    local g = new_game()
    local c = put(g, 1, "w_sobrev", 1)
    local e = equip(g, c, "pa")
    local hand = #g.players[1].hand
    fight(g, { 1 })
    T.eq(e.pronta, g.round, "pronta depois do golpe")
    T.eq(#g.players[1].hand, hand, "o golpe por si só não compra")
    T.eq(e.durability, 1, "o golpe gasta 1")
    -- A vez é do jogador 2 depois do combate; ele passa e volta ao dono.
    T.eq(g.active, 2)
    assert(g:act(2, { type = "pass" }))
    T.eq(g.active, 1)
    T.ok(g:act(1, { type = "activate", creature = 1, equip = "mao" }))
    T.eq(#g.players[1].hand, hand + 1, "comprou 1")
    T.eq(g.active, 1, "não gasta a vez")
    T.eq(e.pronta, nil, "a marca foi consumida")
    T.eq(e.durability, 1, "ativar não gasta durabilidade")
    local ok = g:act(1, { type = "activate", creature = 1, equip = "mao" })
    T.eq(ok, false, "só uma compra por rodada")
    T.eq(#g.players[1].hand, hand + 1)
  end },

  { "Pá não pode ser ativada com a pilha aberta nem na vez do outro", function(T)
    local g = new_game()
    local c = put(g, 1, "w_sobrev", 1)
    local e = equip(g, c, "pa")
    e.pronta = g.round
    assert(g:act(1, { type = "attack", attackers = { 1 } }))
    local ok, err = g:act(1, { type = "activate", creature = 1, equip = "mao" })
    T.eq(ok, false, "pilha aberta")
    T.eq(err, "a Pá só é ativada fora do combate, com a pilha vazia")
    -- Pilha fechada, mas na vez do adversário.
    local g2 = new_game()
    local c2 = put(g2, 1, "w_sobrev", 1)
    equip(g2, c2, "pa").pronta = g2.round
    assert(g2:act(1, { type = "pass" }))
    T.eq(g2.active, 2); T.eq(g2:stack_open(), false)
    ok, err = g2:act(1, { type = "activate", creature = 1, equip = "mao" })
    T.eq(ok, false, "vez do outro")
    T.eq(err, "não é a sua vez")
  end },

  { "Pá com 1 de durabilidade restante quebra no golpe e não compra; sem dano não fica pronta", function(T)
    local g = new_game()
    local c = put(g, 1, "w_sobrev", 1)
    local e = g:equip(c, { id = "pa", uid = g:next_uid(), durability = 1 })
    put(g, 2, "w_comum", 1)
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(c.equips.mao, nil, "quebrou no golpe")
    T.eq(e.pronta, g.round, "chegou a ficar pronta, mas saiu da criatura")
    assert(g:act(2, { type = "pass" }))
    T.eq(g:act(1, { type = "activate", creature = 1, equip = "mao" }), false, "sem a Pá, não compra")
    -- Portador que não causa dano: a Pá não golpeia (Golpear exige dano > 0).
    local g2 = new_game()
    local z = put(g2, 1, "w_zero", 1)
    z.can_equip = true
    local e2 = equip(g2, z, "pa")
    T.eq(g2:atk(z), 1)
    local d = put(g2, 2, "w_sobrev", 1)
    Cards.define{ id = "w_madeira_teste", kind = "equipamento", slot = "peito", cost = 0, damage_reduction = 1 }
    g2:equip(d, { id = "w_madeira_teste", uid = g2:next_uid() })
    fight(g2, { 1 }, { { 1, 1 } })
    T.eq(d.damage, 0)
    T.eq(e2.pronta, nil, "golpe de dano zero não deixa a Pá pronta")
    Cards.remove("w_madeira_teste")
  end },

  { "a marca da Pá some na rodada seguinte e ao sair da criatura", function(T)
    local g = new_game()
    local c = put(g, 1, "w_sobrev", 1)
    local e = equip(g, c, "pa")
    e.pronta = g.round
    local round = g.round
    while g.round == round do assert(g:act(g.active, { type = "pass" })) end
    T.eq(g.active, 2, "o jogador 2 tem o token na rodada 2")
    assert(g:act(2, { type = "pass" }))
    T.eq(g.active, 1)
    local ok, err = g:act(1, { type = "activate", creature = 1, equip = "mao" })
    T.eq(ok, false, "a marca da rodada anterior não vale")
    T.eq(err, "a Pá precisa ter golpeado nesta rodada")
    -- Troca de equipamento: a Pá vai ao Inventário e volta sem a marca.
    e.pronta = g.round
    equip(g, c, "lanca")
    local card, idx = find(g.players[1].inventory, "pa")
    T.ok(card ~= nil)
    g.players[1].mana = 1
    T.ok(g:act(1, { type = "play", hand_index = idx, from = "inventory", target = 1 }))
    T.eq(c.equips.mao.def.id, "pa")
    T.eq(c.equips.mao.pronta, nil, "reequipada sem a marca")
  end },

  { "Armadura de grama: peito, +2 de vida, durabilidade 2, gasta 1 por golpe recebido", function(T)
    local g = new_game()
    put(g, 1, "w_comum", 1)
    local d = put(g, 2, "w_sobrev", 1)
    local e = equip(g, d, "armadura_de_grama")
    T.eq(e.def.slot, "peito"); T.eq(g:hp(d), 11); T.eq(e.durability, 2)
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(d.damage, 1, "sem redução de dano")
    T.eq(e.durability, 1)
    T.eq(g:creature_at(1, 1).damage, 1, "golpear de volta não gasta a própria armadura")
  end },

  { "Armadura de grama quebra no segundo golpe e a vida extra some", function(T)
    local g = new_game()
    Cards.define{ id = "w_tres", kind = "criatura", cost = 0, atk = 3, hp = 1, sobrevivente = true }
    put(g, 1, "w_comum", 1); put(g, 1, "w_comum", 2)
    local d = put(g, 2, "w_tres", 1)
    equip(g, d, "armadura_de_grama")
    T.eq(g:hp(d), 3)
    -- O primeiro golpe recebido fica por conta do desgaste direto.
    g:wear(d, "peito", 1)
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(d.equips.peito, nil, "quebrou")
    T.eq(g:creature_at(2, 1), nil, "com 1 de dano e 1 de vida, morreu quando a armadura saiu")
    T.eq(g.players[2].discard[#g.players[2].discard - 1].id, "armadura_de_grama")
    Cards.remove("w_tres")
  end },

  { "Armadura de madeira: peito, +1 de vida, durabilidade 3, 1 de dano a menos de cada fonte", function(T)
    local g = new_game()
    Cards.define{ id = "w_dois", kind = "criatura", cost = 0, atk = 2, hp = 9 }
    put(g, 1, "w_dois", 1)
    local d = put(g, 2, "w_sobrev", 1)
    local e = equip(g, d, "armadura_de_madeira")
    T.eq(e.def.slot, "peito"); T.eq(g:hp(d), 10); T.eq(e.durability, 3)
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(d.damage, 1, "2 de dano vira 1")
    T.eq(e.durability, 2)
    T.eq(g:damage_creature(d, 1, nil, "teste"), 0, "1 vira 0")
    T.eq(g:damage_creature(d, 3, nil, "teste"), 2, "cada fonte perde 1")
    T.eq(d.damage, 3)
    Cards.remove("w_dois")
  end },

  { "Armadura de madeira: golpe reduzido a zero ainda gasta a durabilidade", function(T)
    local g = new_game()
    put(g, 1, "w_comum", 1)
    local d = put(g, 2, "w_sobrev", 1)
    local e = equip(g, d, "armadura_de_madeira")
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(d.damage, 0)
    T.eq(e.durability, 2)
    local strikes = events(g, "strike")
    T.ok(#strikes >= 1, "o golpe aconteceu")
  end },

  { "Máquina de Ciência: olha 5, o dono escolhe 1 equipamento, as outras 4 voltam", function(T)
    -- Do topo para baixo: w_comum, machado, w_comum, lanca, w_comum.
    local g = new_game({ "w_comum", "lanca", "w_comum", "machado", "w_comum" })
    local st = g:put_structure(1, { id = "maquina_de_ciencia", uid = g:next_uid() }, 1)
    local deck, hand = #g.players[1].deck, #g.players[1].hand
    local mana = g.players[1].mana
    T.ok(g:act(1, { type = "activate", structure = 1 }))
    local ch = g.pending_choice
    T.ok(ch ~= nil, "escolha aberta")
    T.eq(ch.player, 1); T.eq(ch.reason, "maquina_de_ciencia"); T.eq(ch.allow_none, true)
    T.eq(#ch.options, 2)
    T.eq(ch.options[1].id, "machado", "da mais próxima do topo para baixo")
    T.eq(ch.options[2].id, "lanca")
    local look = events(g, "look")
    T.eq(#look, 1); T.eq(look[1].p, 1); T.eq(look[1].private, true); T.eq(look[1].uid, st.uid)
    T.eq(#look[1].cards, 5); T.eq(look[1].cards[2].id, "machado")
    T.eq(#g.players[1].deck, deck, "as cartas ficam no baralho enquanto a escolha está aberta")
    T.ok(g:act(1, { type = "choose", index = 2 }))
    T.eq(#g.players[1].hand, hand + 1)
    T.eq(g.players[1].hand[#g.players[1].hand].id, "lanca")
    T.eq(#g.players[1].deck, deck - 1, "as outras 4 voltaram")
    T.eq(count(g.players[1].deck, "machado"), 1)
    local th = events(g, "to_hand")
    T.eq(th[#th].source, "maquina"); T.eq(th[#th].private, true)
    T.eq(g.pending_choice, nil)
    T.eq(g.active, 1, "não gasta a vez")
    T.eq(g.players[1].mana, mana, "sem custo")
  end },

  { "Máquina de Ciência: o dono pode não comprar; as 5 voltam", function(T)
    local g = new_game({ "lanca", "w_comum", "w_comum", "w_comum", "w_comum" })
    g:put_structure(1, { id = "maquina_de_ciencia", uid = g:next_uid() }, 1)
    local deck, hand = #g.players[1].deck, #g.players[1].hand
    local mana = g.players[1].mana
    T.ok(g:act(1, { type = "activate", structure = 1 }))
    T.eq(#g.pending_choice.options, 1)
    T.ok(g:act(1, { type = "choose" }))
    T.eq(#g.players[1].hand, hand)
    T.eq(#g.players[1].deck, deck)
    T.eq(count(g.players[1].deck, "lanca"), 1)
    T.eq(g.players[1].mana, mana, "grátis")
    T.eq(g.active, 1)
  end },

  { "Máquina de Ciência sem equipamento entre as 5: nada vai para a mão, só embaralha", function(T)
    -- A Lança é a sexta do topo: fora do alcance.
    local g = new_game({ "lanca", "w_comum", "w_comum", "w_comum", "w_comum", "w_comum" })
    local deck = g.players[1].deck
    local sexta = deck[#deck - 5]
    T.eq(sexta.id, "lanca")
    g:put_structure(1, { id = "maquina_de_ciencia", uid = g:next_uid() }, 1)
    -- rng que inverte: cada troca pega o primeiro, para o embaralhar ser visível.
    g.rng = function(n) return 1 end
    local n, hand = #deck, #g.players[1].hand
    T.ok(g:act(1, { type = "activate", structure = 1 }))
    T.eq(g.pending_choice, nil, "sem escolha")
    T.eq(#g.players[1].hand, hand)
    T.eq(#deck, n)
    T.ok(deck[#deck - 5] ~= sexta, "embaralhou")
    T.eq(#events(g, "look"), 1, "o dono viu as 5")
    T.eq(g.active, 1)
  end },

  { "Máquina de Ciência: uma vez por rodada", function(T)
    local g = new_game({ "lanca", "lanca" })
    g:put_structure(1, { id = "maquina_de_ciencia", uid = g:next_uid() }, 1)
    T.ok(g:act(1, { type = "activate", structure = 1 }))
    T.ok(g:act(1, { type = "choose", index = 1 }))
    local ok, err = g:act(1, { type = "activate", structure = 1 })
    T.eq(ok, false); T.eq(err, "já ativada nesta rodada")
    local round = g.round
    while g.round == round do assert(g:act(g.active, { type = "pass" })) end
    assert(g:act(2, { type = "pass" }))
    T.ok(g:act(1, { type = "activate", structure = 1 }), "rodada nova")
  end },

  { "Máquina de Ciência com menos de 5 cartas no baralho olha as que houver", function(T)
    local g = new_game()
    local deck = g.players[1].deck
    while #deck > 2 do table.remove(deck, 1) end
    deck[#deck + 1] = { id = "machado", uid = g:next_uid() }
    g:put_structure(1, { id = "maquina_de_ciencia", uid = g:next_uid() }, 1)
    T.ok(g:act(1, { type = "activate", structure = 1 }))
    T.eq(#events(g, "look")[1].cards, 3)
    T.eq(#g.pending_choice.options, 1)
    T.ok(g:act(1, { type = "choose", index = 1 }))
    T.eq(g.players[1].hand[#g.players[1].hand].id, "machado")
    T.eq(#deck, 2)
    -- Baralho vazio: nada acontece.
    local g2 = new_game()
    g2.players[1].deck = {}
    g2:put_structure(1, { id = "maquina_de_ciencia", uid = g2:next_uid() }, 1)
    T.ok(g2:act(1, { type = "activate", structure = 1 }))
    T.eq(g2.pending_choice, nil)
    T.eq(#events(g2, "look")[1].cards, 0)
  end },

  { "Máquina de Ciência pode ser ativada com a pilha aberta (Instantâneo)", function(T)
    local g = new_game({ "lanca" })
    g:put_structure(1, { id = "maquina_de_ciencia", uid = g:next_uid() }, 1)
    put(g, 1, "w_comum", 1)
    assert(g:act(1, { type = "attack", attackers = { 1 } }))
    T.ok(g:act(1, { type = "activate", structure = 1 }))
    T.ok(g:act(1, { type = "choose", index = 1 }))
    T.eq(g.players[1].hand[#g.players[1].hand].id, "lanca")
    T.ok(g:stack_open(), "a pilha continua aberta")
  end },

  { "Wilson: Campeão Sobrevivente 1/3 por 4, usa equipamentos", function(T)
    load_cartas()
    local def = Cards.get("wilson")
    T.eq(def.atk, 1); T.eq(def.hp, 3)
    T.eq(def.sobrevivente, true); T.eq(def.campeao, true); T.eq(def.nivel, 1)
    local g = new_game()
    g.players[1].mana = 4
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "wilson"), slot = 1 }))
    local c = g:creature_at(1, 1)
    T.eq(c.def.id, "wilson")
    T.eq(g.players[1].mana, 0)
    T.ok(g:can_equip(c))
  end },

  { "Wilson busca a Máquina de Ciência no baralho, mostra, põe em jogo e embaralha", function(T)
    local g = new_game({ "maquina_de_ciencia", "w_comum", "w_comum" })
    local deck = g.players[1].deck
    local n = #deck
    local maq = deck[n - 2]
    T.eq(maq.id, "maquina_de_ciencia")
    local topo_antes = deck[n]
    g.rng = function(k) return 1 end
    g.players[1].mana = 4
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "wilson"), slot = 1 }))
    local st = g:structure_at(1, 1)
    T.ok(st ~= nil and st.def.id == "maquina_de_ciencia", "a Máquina entrou em jogo")
    T.eq(st.card, maq, "a mesma carta que estava no baralho")
    T.eq(st.ficha, false, "não é ficha")
    T.eq(#deck, n - 1)
    T.eq(count(deck, "maquina_de_ciencia"), 0)
    local rev = events(g, "reveal")
    T.eq(#rev, 1); T.eq(rev[1].id, "maquina_de_ciencia"); T.eq(rev[1].p, 1)
    T.eq(rev[1].private, nil, "mostrar é público")
    T.eq(rev[1].card_uid, maq.uid)
    T.ok(deck[#deck] ~= topo_antes, "baralho embaralhado")
    T.eq(g.pending_choice, nil)
    -- A Máquina já funciona nesta rodada, assim que a vez voltar ao dono.
    assert(g:act(2, { type = "pass" }))
    T.ok(g:act(1, { type = "activate", structure = 1 }))
  end },

  { "Wilson sem Máquina no baralho: nada acontece e o baralho não é embaralhado", function(T)
    local g = new_game({ "lanca", "machado" })
    local deck = g.players[1].deck
    local before = {}
    for i, card in ipairs(deck) do before[i] = card end
    g.rng = function(k) return 1 end
    g.players[1].mana = 4
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "wilson"), slot = 1 }))
    T.eq(g:structure_at(1, 1), nil); T.eq(g:structure_at(1, 2), nil)
    T.eq(#deck, #before)
    for i, card in ipairs(before) do T.eq(deck[i], card, "ordem do baralho mantida") end
    T.eq(#events(g, "reveal"), 0)
    T.eq(g.pending_choice, nil)
  end },

  { "Wilson com uma Máquina já em jogo não busca outra", function(T)
    local g = new_game({ "maquina_de_ciencia" })
    g:put_structure(1, { id = "maquina_de_ciencia", uid = g:next_uid() }, 1)
    local deck = g.players[1].deck
    local n = #deck
    g.players[1].mana = 4
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "wilson"), slot = 1 }))
    T.eq(#deck, n, "a do baralho ficou lá")
    T.eq(g:structure_at(1, 2), nil)
    T.eq(#events(g, "reveal"), 0)
  end },

  { "Wilson só busca no baralho (não na mão nem no descarte)", function(T)
    local g = new_game()
    give(g, 1, "maquina_de_ciencia")
    g.players[1].discard[#g.players[1].discard + 1] = { id = "maquina_de_ciencia", uid = g:next_uid() }
    g.players[1].mana = 4
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "wilson"), slot = 1 }))
    T.eq(g:structure_at(1, 1), nil)
    T.eq(count(g.players[1].hand, "maquina_de_ciencia"), 1)
    T.eq(count(g.players[1].discard, "maquina_de_ciencia"), 1)
  end },

  { "Wilson com a zona de estruturas cheia: o dono escolhe qual substituir", function(T)
    local g = new_game({ "maquina_de_ciencia" })
    g:put_structure(1, { id = "w_casa", uid = g:next_uid() }, 1)
    local torre = g:put_structure(1, { id = "w_casa", uid = g:next_uid() }, 2)
    local deck = g.players[1].deck
    local n = #deck
    g.players[1].mana = 4
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "wilson"), slot = 1 }))
    local ch = g.pending_choice
    T.ok(ch ~= nil, "escolha aberta")
    T.eq(ch.reason, "substituir_estrutura"); T.eq(ch.player, 1); T.eq(ch.allow_none, true)
    T.eq(#ch.options, 2)
    T.eq(#deck, n - 1, "a Máquina já saiu do baralho")
    T.eq(#events(g, "reveal"), 1)
    T.ok(g:act(1, { type = "choose", index = 2 }))
    T.eq(g:structure_at(1, 2).def.id, "maquina_de_ciencia")
    T.eq(g:structure_at(1, 1).def.id, "w_casa")
    local d = g.players[1].destroyed
    T.eq(d[#d].uid, torre.card_uid, "a substituída foi destruída")
    T.eq(g.pending_choice, nil)
  end },

  { "Wilson com a zona cheia: sem substituir, a Máquina vai para o descarte", function(T)
    local g = new_game({ "maquina_de_ciencia" })
    g:put_structure(1, { id = "w_casa", uid = g:next_uid() }, 1)
    g:put_structure(1, { id = "w_casa", uid = g:next_uid() }, 2)
    g.players[1].mana = 4
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "wilson"), slot = 1 }))
    T.ok(g.pending_choice ~= nil)
    T.ok(g:act(1, { type = "choose" }))
    T.eq(g:structure_at(1, 1).def.id, "w_casa"); T.eq(g:structure_at(1, 2).def.id, "w_casa")
    T.eq(count(g.players[1].discard, "maquina_de_ciencia"), 1)
    T.eq(count(g.players[1].deck, "maquina_de_ciencia"), 0)
  end },

  { "Wilson colocado em campo por efeito também busca a Máquina", function(T)
    local g = new_game({ "maquina_de_ciencia" })
    put(g, 1, "wilson", 3)
    T.eq(g:structure_at(1, 1).def.id, "maquina_de_ciencia")
  end },
}
