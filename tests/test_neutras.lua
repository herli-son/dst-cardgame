-- Criaturas neutras do MVP (#22): Porco, Porco guarda, Sapo, Morcego, Pássaro,
-- Borboleta e Cão de caça.
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

-- O executor restaura o registro de cartas entre os casos, então o módulo é
-- carregado de novo a cada caso.
local function load_neutras()
  package.loaded["duelo/cartas/neutras"] = nil
  return require("duelo/cartas/neutras")
end

local function define_test_cards()
  Cards.define{ id = "n_comum", kind = "criatura", cost = 0, atk = 1, hp = 9 }
  Cards.define{ id = "n_sobrev", kind = "criatura", cost = 0, atk = 1, hp = 9, sobrevivente = true }
  Cards.define{ id = "n_espada", kind = "equipamento", slot = "mao", cost = 3, atk_bonus = 1, durability = 3 }
  Cards.define{ id = "n_capa", kind = "equipamento", slot = "peito", cost = 2 }
  Cards.define{ id = "n_chapeu", kind = "equipamento", slot = "cabeca", cost = 2 }
end

local function new_game()
  load_neutras()
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "n_comum" }; d2[i] = { id = "n_comum" } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
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

-- Leva a partida ao período pedido, sem gastar a rodada: avança as vezes com
-- jogadas que não contam como passe.
local function go_to(g, period)
  Game.actions.n_agir = function() return true end
  while g:period() ~= period do assert(g:act(g.active, { type = "n_agir" })) end
  Game.actions.n_agir = nil
end

return {
  { "o módulo registra as 7 cartas com os números do documento", function(T)
    local ids = load_neutras()
    T.eq(#ids, 7)
    local esperado = {
      porco = { "Porco", 4, 4, 5 },
      porco_guarda = { "Porco guarda", 5, 2, 7 },
      sapo = { "Sapo", 1, 1, 2 },
      morcego = { "Morcego", 1, 0, 1 },
      passaro = { "Pássaro", 1, 0, 1 },
      borboleta = { "Borboleta", 1, 0, 1 },
      cao_de_caca = { "Cão de caça", 2, 2, 2 },
    }
    for _, id in ipairs(ids) do
      local e = esperado[id]
      T.ok(e ~= nil, "carta inesperada: " .. id)
      local def = Cards.get(id)
      T.ok(def ~= nil, id .. " registrada")
      T.eq(def.kind, "criatura", id)
      T.eq(def.name, e[1], id .. " nome")
      T.eq(def.cost, e[2], id .. " custo")
      T.eq(def.atk, e[3], id .. " ataque")
      T.eq(def.hp, e[4], id .. " vida")
      T.eq(type(def.text), "string", id .. " texto")
      esperado[id] = nil
    end
    T.eq(next(esperado), nil, "todas as cartas foram registradas")
  end },

  { "palavras-chave, tipos e velocidade", function(T)
    load_neutras()
    T.eq(Cards.get("porco").types.porco, true)
    T.eq(Cards.get("porco_guarda").types.porco, true)
    T.eq(Cards.get("porco_guarda").kw.guarda, true)
    T.eq(Cards.get("sapo").kw.agressivo, true)
    T.eq(Cards.get("morcego").kw.agressivo, true)
    T.eq(Cards.get("morcego").speed, 2)
    T.eq(Cards.get("passaro").kw.fragil, true)
    T.eq(Cards.get("borboleta").kw.fragil, true)
    T.eq(Cards.get("cao_de_caca").kw.agressivo, true)
    T.eq(Cards.get("cao_de_caca").on_strike, nil, "Cão de caça ainda sem efeito")
    T.eq(Cards.get("porco").on_strike, nil, "Porco sem efeito")
  end },

  { "Porco: 4/5 jogado da mão por 4 de mana", function(T)
    local g = new_game()
    g.players[1].mana = 4
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "porco"), slot = 1 }))
    local c = g:creature_at(1, 1)
    T.eq(c.def.id, "porco")
    T.eq(g:atk(c), 4); T.eq(g:hp(c), 5)
    T.eq(g.players[1].mana, 0)
  end },

  { "Porco guarda bloqueia, sobrevive e salta para o atacante sem bloqueador", function(T)
    local g = new_game()
    local a1 = put(g, 1, "n_comum", 1); local a2 = put(g, 1, "n_comum", 2)
    local porco = put(g, 2, "porco_guarda", 1)
    local life = g.players[2].life
    fight(g, { 1, 2 }, { { 1, 1 } })
    local jumps = {}
    for _, ev in ipairs(events(g, "block")) do
      if ev.auto == "guarda" then jumps[#jumps + 1] = ev.blocks[1] end
    end
    T.eq(#jumps, 1)
    T.eq(jumps[1].attacker, a2.uid); T.eq(jumps[1].blocker, porco.uid)
    T.eq(a1.damage, 2); T.eq(a2.damage, 2, "o Porco guarda revida nos dois pares")
    T.eq(porco.damage, 2, "leva 1 de cada atacante")
    T.eq(g.players[2].life, life, "nada chega ao jogador")
  end },

  { "Porco guarda atacando não faz nada de especial", function(T)
    local g = new_game()
    put(g, 1, "porco_guarda", 1); put(g, 1, "n_comum", 2)
    put(g, 2, "n_comum", 1)
    local life = g.players[2].life
    fight(g, { 1, 2 }, { { 1, 1 } })
    T.eq(g.players[2].life, life - 1)
  end },

  { "Sapo golpeando criatura sem equipamento não faz nada", function(T)
    local g = new_game()
    put(g, 1, "sapo", 1)
    put(g, 2, "n_comum", 1)
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(#g.players[2].inventory, 0)
    T.eq(g.pending_choice, nil)
    T.eq(g:creature_at(2, 1).damage, 1)
  end },

  { "Sapo golpeando o jogador não faz nada", function(T)
    local g = new_game()
    put(g, 1, "sapo", 1)
    local life = g.players[2].life
    fight(g, { 1 })
    T.eq(g.players[2].life, life - 1)
    T.eq(g.pending_choice, nil)
  end },

  { "Sapo com 1 equipamento: vai direto para o Inventário do dono, custando 1 lá", function(T)
    local g = new_game()
    put(g, 1, "sapo", 1)
    local alvo = put(g, 2, "n_sobrev", 1)
    g:equip(alvo, { id = "n_espada", uid = g:next_uid() })
    g:wear(alvo, "mao", 1)
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(g.pending_choice, nil, "sem escolha com um equipamento só")
    T.eq(alvo.equips.mao, nil, "saiu da criatura")
    local card = find(g.players[2].inventory, "n_espada")
    T.ok(card ~= nil, "no Inventário do dono do alvo")
    T.eq(#g.players[1].inventory, 0, "não vai para o dono do Sapo")
    T.eq(card.durability, 2, "a durabilidade fica na carta")
    T.eq(g:card_cost(2, card), 1, "custa 1 no Inventário")
    local un = events(g, "unequip")
    T.eq(un[#un].reason, "sapo")
    T.eq(un[#un].equip_slot, "mao")
    T.eq(g:atk(alvo), 1, "sem o bônus da espada")
  end },

  { "a carta roubada custa o normal depois de jogada", function(T)
    local g = new_game()
    put(g, 1, "sapo", 1)
    local alvo = put(g, 2, "n_sobrev", 1)
    g:equip(alvo, { id = "n_espada", uid = g:next_uid() })
    fight(g, { 1 }, { { 1, 1 } })
    local card, idx = find(g.players[2].inventory, "n_espada")
    T.eq(g.active, 2)
    g.players[2].mana = 1
    T.ok(g:act(2, { type = "play", hand_index = idx, from = "inventory", target = 1 }))
    T.eq(g.players[2].mana, 0, "pagou 1")
    T.eq(alvo.equips.mao.card, card)
    T.eq(card.cost_override, nil, "o custo fixado some ao jogar")
    T.eq(g:card_cost(2, card), 3)
  end },

  { "Sapo com 2 equipamentos: o dono do Sapo escolhe, sem poder escolher nada", function(T)
    local g = new_game()
    put(g, 1, "sapo", 1)
    local alvo = put(g, 2, "n_sobrev", 1)
    g:equip(alvo, { id = "n_espada", uid = g:next_uid() })
    g:equip(alvo, { id = "n_capa", uid = g:next_uid() })
    fight(g, { 1 }, { { 1, 1 } })
    local ch = g.pending_choice
    T.ok(ch ~= nil, "escolha aberta")
    T.eq(ch.player, 1, "quem escolhe é o dono do Sapo")
    T.eq(ch.reason, "sapo")
    T.eq(#ch.options, 2)
    T.eq(ch.options[1].def.id, "n_espada"); T.eq(ch.options[2].def.id, "n_capa")
    T.eq(g:act(1, { type = "choose" }), false, "é preciso escolher")
    T.eq(g:act(2, { type = "choose", index = 1 }), false, "o outro jogador não escolhe")
    T.ok(g:act(1, { type = "choose", index = 2 }))
    T.eq(alvo.equips.peito, nil)
    T.ok(alvo.equips.mao ~= nil, "a espada fica")
    local card = find(g.players[2].inventory, "n_capa")
    T.ok(card ~= nil)
    T.eq(g:card_cost(2, card), 1)
    T.eq(g.pending_choice, nil)
    T.eq(g.active, 2, "o combate termina e a vez passa")
  end },

  { "a escolha do Sapo segura o resto do combate", function(T)
    local g = new_game()
    put(g, 1, "sapo", 1); local a2 = put(g, 1, "n_comum", 2)
    local alvo = put(g, 2, "n_sobrev", 1)
    g:equip(alvo, { id = "n_espada", uid = g:next_uid() })
    g:equip(alvo, { id = "n_capa", uid = g:next_uid() })
    g:equip(alvo, { id = "n_chapeu", uid = g:next_uid() })
    local life = g.players[2].life
    fight(g, { 1, 2 }, { { 1, 1 } })
    T.ok(g.pending_choice ~= nil)
    T.eq(#g.pending_choice.options, 3)
    T.eq(g.players[2].life, life, "o par 2 ainda não resolveu")
    T.ok(g:act(1, { type = "choose", index = 1 }))
    T.eq(g.players[2].life, life - 1, "o par 2 resolveu depois da escolha")
    T.eq(a2.damage, 0)
    T.ok(alvo.equips.mao == nil and alvo.equips.peito ~= nil and alvo.equips.cabeca ~= nil)
  end },

  { "Sapo rouba antes de a criatura morrer pelo golpe", function(T)
    local g = new_game()
    Cards.define{ id = "n_fraco", kind = "criatura", cost = 0, atk = 0, hp = 1, sobrevivente = true }
    put(g, 1, "sapo", 1)
    local alvo = put(g, 2, "n_fraco", 1)
    g:equip(alvo, { id = "n_espada", uid = g:next_uid() })
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(g:creature_at(2, 1), nil, "morreu")
    T.ok(find(g.players[2].inventory, "n_espada") ~= nil, "a espada foi para o Inventário, não para o descarte")
  end },

  { "Sapo com o Inventário do dono do alvo cheio: a carta é destruída", function(T)
    local g = new_game()
    put(g, 1, "sapo", 1)
    local alvo = put(g, 2, "n_sobrev", 1)
    g:equip(alvo, { id = "n_espada", uid = g:next_uid() })
    while g:hand_count(2) < g:hand_limit(2) do give(g, 2, "n_comum") end
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(alvo.equips.mao, nil)
    T.eq(find(g.players[2].inventory, "n_espada"), nil)
    T.ok(find(g.players[2].destroyed, "n_espada") ~= nil)
  end },

  { "Morcego: 0/1 de manhã, 1/1 à tarde, 2/1 à noite, com velocidade 2", function(T)
    local g = new_game()
    local m = put(g, 1, "morcego", 1)
    T.eq(g:period(), "manha")
    T.eq(g:atk(m), 0); T.eq(g:hp(m), 1); T.eq(g:speed(m, "attack"), 2)
    go_to(g, "tarde")
    T.eq(g:atk(m), 1); T.eq(g:hp(m), 1)
    go_to(g, "noite")
    T.eq(g:atk(m), 2); T.eq(g:hp(m), 1)
  end },

  { "Morcego atacando de manhã não causa dano", function(T)
    local g = new_game()
    put(g, 1, "morcego", 1)
    local life = g.players[2].life
    fight(g, { 1 })
    T.eq(g.players[2].life, life)
  end },

  { "Morcego atacando à tarde causa 1", function(T)
    local g = new_game()
    put(g, 1, "morcego", 1)
    go_to(g, "tarde")
    T.eq(g.active, 1)
    local life = g.players[2].life
    fight(g, { 1 })
    T.eq(g.players[2].life, life - 1)
  end },

  { "Morcego atacando à noite causa 2 e golpeia antes do bloqueador", function(T)
    local g = new_game()
    put(g, 1, "morcego", 1)
    go_to(g, "noite")
    T.eq(g.active, 1)
    local life = g.players[2].life
    fight(g, { 1 })
    T.eq(g.players[2].life, life - 2)
    -- Bloqueado por uma criatura de 2 de vida: o Morcego golpeia na fase rápida
    -- e a mata antes de ela golpear.
    local g2 = new_game()
    Cards.define{ id = "n_dois", kind = "criatura", cost = 0, atk = 1, hp = 2 }
    local m = put(g2, 1, "morcego", 1)
    put(g2, 2, "n_dois", 1)
    go_to(g2, "noite")
    fight(g2, { 1 }, { { 1, 1 } })
    T.eq(g2:creature_at(2, 1), nil)
    T.eq(m.damage, 0)
  end },

  { "Pássaro morre e o dono compra quando uma Agressiva do adversário entra", function(T)
    local g = new_game()
    local passaro = put(g, 1, "passaro", 1)
    local hand = #g.players[1].hand
    local deck = #g.players[1].deck
    g.players[2].mana = 2
    g:act(1, { type = "pass" })
    local hand2 = #g.players[2].hand
    T.ok(g:act(2, { type = "play", hand_index = give(g, 2, "cao_de_caca"), slot = 1 }))
    T.eq(g:creature_at(1, 1), nil, "o Pássaro morreu")
    local d = g.players[1].discard
    T.eq(d[#d].uid, passaro.card_uid, "foi para o descarte")
    T.eq(#g.players[1].hand, hand + 1, "o dono comprou 1")
    T.eq(#g.players[1].deck, deck - 1)
    T.eq(#g.players[2].hand, hand2, "o adversário não comprou")
    local deaths = events(g, "death")
    T.eq(deaths[#deaths].uid, passaro.uid)
    T.eq(deaths[#deaths].reason, "passaro")
  end },

  { "Pássaro morre e compra quando uma Agressiva do próprio dono entra", function(T)
    local g = new_game()
    put(g, 1, "passaro", 1)
    local hand = #g.players[1].hand
    g.players[1].mana = 1
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "sapo"), slot = 2 }))
    T.eq(g:creature_at(1, 1), nil)
    T.eq(g:creature_at(1, 2).def.id, "sapo")
    T.eq(#g.players[1].hand, hand + 1)
  end },

  { "Pássaro reage a uma Agressiva criada por efeito", function(T)
    local g = new_game()
    put(g, 1, "passaro", 1)
    local hand = #g.players[1].hand
    g.players[2].extra[1] = { id = "morcego", uid = g:next_uid() }
    T.ok(g:create_token(2, "morcego") ~= nil)
    T.eq(g:creature_at(1, 1), nil)
    T.eq(#g.players[1].hand, hand + 1)
  end },

  { "Pássaro não morre com uma criatura não Agressiva", function(T)
    local g = new_game()
    put(g, 1, "passaro", 1)
    local hand = #g.players[1].hand
    g.players[2].mana = 4
    g:act(1, { type = "pass" })
    T.ok(g:act(2, { type = "play", hand_index = give(g, 2, "porco"), slot = 1 }))
    T.eq(g:creature_at(1, 1).def.id, "passaro")
    T.eq(#g.players[1].hand, hand)
  end },

  { "o ao morrer do Pássaro dispara antes da compra", function(T)
    local g = new_game()
    local log = {}
    local def = Cards.get("passaro")
    local on_death_original = def.on_death
    def.on_death = function() log[#log + 1] = "morreu:" .. #g.players[1].hand end
    put(g, 1, "passaro", 1)
    local hand = #g.players[1].hand
    put(g, 2, "cao_de_caca", 1)
    T.eq(log[1], "morreu:" .. hand, "o ao morrer rodou com a mão ainda sem a compra")
    T.eq(#g.players[1].hand, hand + 1)
    def.on_death = on_death_original
  end },

  { "dois Pássaros morrem e cada dono compra", function(T)
    local g = new_game()
    put(g, 1, "passaro", 1); put(g, 2, "passaro", 1)
    local h1, h2 = #g.players[1].hand, #g.players[2].hand
    put(g, 2, "cao_de_caca", 2)
    T.eq(g:creature_at(1, 1), nil); T.eq(g:creature_at(2, 1), nil)
    T.eq(#g.players[1].hand, h1 + 1); T.eq(#g.players[2].hand, h2 + 1)
  end },

  { "Borboleta: ao morrer com a vida cheia, nada muda", function(T)
    local g = new_game()
    local b = put(g, 1, "borboleta", 1)
    T.eq(g.players[1].life, Game.MAX_LIFE)
    g:kill(b, "teste")
    T.eq(g.players[1].life, Game.MAX_LIFE)
    T.eq(#events(g, "player_heal"), 0)
  end },

  { "Borboleta: ao morrer com dano, o dono recupera 2", function(T)
    local g = new_game()
    local b = put(g, 1, "borboleta", 1)
    g.players[1].life = 15
    g:kill(b, "teste")
    T.eq(g.players[1].life, 17)
    local heals = events(g, "player_heal")
    T.eq(#heals, 1)
    T.eq(heals[1].p, 1); T.eq(heals[1].amount, 2); T.eq(heals[1].source, "borboleta")
  end },

  { "Borboleta: a cura nunca passa do máximo", function(T)
    local g = new_game()
    local b = put(g, 1, "borboleta", 1)
    g.players[1].life = 19
    g:kill(b, "teste")
    T.eq(g.players[1].life, 20)
  end },

  { "Borboleta morrendo em combate cura o dono, não o adversário", function(T)
    local g = new_game()
    put(g, 1, "cao_de_caca", 1)
    put(g, 2, "borboleta", 1)
    g.players[1].life = 10; g.players[2].life = 10
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(g:creature_at(2, 1), nil)
    T.eq(g.players[2].life, 12)
    T.eq(g.players[1].life, 10)
  end },

  { "Cão de caça: 2/2 Agressivo, bloqueado por uma Frágil livre à força", function(T)
    local g = new_game()
    g.players[1].mana = 2
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "cao_de_caca"), slot = 1 }))
    local cao = g:creature_at(1, 1)
    T.eq(g:atk(cao), 2); T.eq(g:hp(cao), 2)
    T.eq(g.players[1].mana, 0)
    g:act(2, { type = "pass" })
    put(g, 2, "borboleta", 1)
    local life = g.players[2].life
    -- O defensor passa sem declarar: a Frágil livre bloqueia o Agressivo.
    assert(g:act(1, { type = "attack", attackers = { 1 } }))
    assert(g:act(1, { type = "pass" }))
    assert(g:act(2, { type = "pass" }))
    T.eq(g:creature_at(2, 1), nil, "a Borboleta bloqueou e morreu")
    T.eq(g.players[2].life, life, "nada chegou ao jogador")
  end },
}
