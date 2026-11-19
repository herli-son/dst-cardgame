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

-- Baralhos de 20 w_comum; deck1 pode receber cartas extras no topo (fim da lista).
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

  { "Pá: mão, +1 de ataque, durabilidade 1; sem golpe não pode ser ativada", function(T)
    local g = new_game()
    local c = put(g, 1, "w_sobrev", 1)
    local e = equip(g, c, "pa")
    T.eq(e.def.slot, "mao"); T.eq(g:atk(c), 2); T.eq(e.durability, 1)
    local hand = #g.players[1].hand
    local ok, err = g:act(1, { type = "activate", creature = 1, equip = "mao" })
    T.eq(ok, false, err)
    T.eq(#g.players[1].hand, hand)
  end },

  { "Pá golpeando fica pronta; ativar fora do combate compra 1 e não gasta a vez", function(T)
    local g = new_game()
    local c = put(g, 1, "w_sobrev", 1)
    -- Durabilidade maior para a Pá sobreviver ao golpe neste caso.
    local e = g:equip(c, { id = "pa", uid = g:next_uid(), durability = 3 })
    local hand = #g.players[1].hand
    fight(g, { 1 })
    T.eq(e.pronta, g.round, "pronta depois do golpe")
    T.eq(#g.players[1].hand, hand, "o golpe por si só não compra")
    T.eq(e.durability, 2)
    -- A vez é do jogador 2 depois do combate; ele passa e volta ao dono.
    T.eq(g.active, 2)
    assert(g:act(2, { type = "pass" }))
    T.eq(g.active, 1)
    T.ok(g:act(1, { type = "activate", creature = 1, equip = "mao" }))
    T.eq(#g.players[1].hand, hand + 1, "comprou 1")
    T.eq(g.active, 1, "não gasta a vez")
    T.eq(e.pronta, nil, "a marca foi consumida")
    T.eq(e.durability, 2, "ativar não gasta durabilidade")
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
    local ok = g:act(1, { type = "activate", creature = 1, equip = "mao" })
    T.eq(ok, false, "pilha aberta")
    assert(g:act(1, { type = "pass" }))
    ok = g:act(1, { type = "activate", creature = 1, equip = "mao" })
    T.eq(ok, false, "vez do outro")
  end },

  { "Pá com durabilidade 1 quebra no golpe, mas sem dano não fica pronta", function(T)
    local g = new_game()
    local c = put(g, 1, "w_sobrev", 1)
    local e = equip(g, c, "pa")
    put(g, 2, "w_comum", 1)
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(c.equips.mao, nil, "quebrou (durabilidade 1)")
    T.eq(e.pronta, g.round, "chegou a ficar pronta, mas saiu da criatura")
    -- Portador que não causa dano: a Pá não golpeia (Golpear exige dano > 0).
    local g2 = new_game()
    local z = put(g2, 1, "w_zero", 1)
    z.can_equip = true
    local e2 = g2:equip(z, { id = "pa", uid = g2:next_uid(), durability = 3 })
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
    local e = g:equip(c, { id = "pa", uid = g:next_uid(), durability = 3 })
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
}
