local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local log
local IDS = { "t_sobrevivente", "t_comum", "t_machado", "t_lanca", "t_armadura", "t_oculos" }

local function define_test_cards()
  log = {}
  Cards.define{ id = "t_sobrevivente", kind = "criatura", cost = 0, atk = 1, hp = 3, sobrevivente = true }
  Cards.define{ id = "t_comum", kind = "criatura", cost = 0, atk = 1, hp = 1 }
  Cards.define{ id = "t_machado", kind = "equipamento", slot = "mao", cost = 2, atk_bonus = 2, durability = 4 }
  Cards.define{ id = "t_lanca", kind = "equipamento", slot = "mao", cost = 3, atk_bonus = 3, durability = 6 }
  Cards.define{ id = "t_armadura", kind = "equipamento", slot = "peito", cost = 1, hp_bonus = 2, durability = 2 }
  Cards.define{ id = "t_oculos", kind = "equipamento", slot = "cabeca", cost = 1,
    on_equip = function(g, c, e) log[#log + 1] = "equipou:" .. c.def.id end }
end

local function clear_test_cards()
  for _, id in ipairs(IDS) do Cards.remove(id) end
end

local function new_game(hand1)
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "t_comum" }; d2[i] = { id = "t_comum" } end
  for _, id in ipairs(hand1 or {}) do d1[#d1 + 1] = { id = id } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  g.players[1].mana = 10
  return g
end

-- Ataque do jogador 1 com bloqueios do jogador 2 ({ { atacante, bloqueador }, ... }).
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

local function put(g, p, id, slot)
  return g:place_creature(p, { id = id, uid = g:next_uid() }, slot)
end

local function idx(zone, id)
  for i, card in ipairs(zone) do if card.id == id then return i end end
end

local function play(g, id, fields)
  local a = { type = "play", hand_index = idx(g.players[1].hand, id) }
  for k, v in pairs(fields or {}) do a[k] = v end
  local ok, err = g:act(1, a)
  if ok and g.active == 2 then g:act(2, { type = "pass" }) end
  return ok, err
end

return {
  { "equipar um Sobrevivente soma o bônus e paga a mana", function(T)
    local g = new_game({ "t_sobrevivente", "t_machado" })
    play(g, "t_sobrevivente", { slot = 1 })
    T.ok(play(g, "t_machado", { target = 1 }))
    local c = g:creature_at(1, 1)
    T.eq(c.equips.mao.def.id, "t_machado")
    T.eq(g:atk(c), 3)
    T.eq(g.players[1].mana, 8)
    clear_test_cards()
  end },

  { "só Sobreviventes usam equipamentos", function(T)
    local g = new_game({ "t_comum", "t_machado" })
    play(g, "t_comum", { slot = 1 })
    local ok = play(g, "t_machado", { target = 1 })
    T.eq(ok, false)
    ok = play(g, "t_machado", { target = 4 })
    T.eq(ok, false, "espaço vazio")
    clear_test_cards()
  end },

  { "equipar num espaço ocupado manda o antigo para o Inventário com a durabilidade", function(T)
    local g = new_game({ "t_sobrevivente", "t_machado", "t_lanca" })
    play(g, "t_sobrevivente", { slot = 1 })
    play(g, "t_machado", { target = 1 })
    local c = g:creature_at(1, 1)
    g:wear(c, "mao", 1)
    play(g, "t_lanca", { target = 1 })
    T.eq(c.equips.mao.def.id, "t_lanca")
    local inv = g.players[1].inventory
    T.eq(#inv, 1)
    T.eq(inv[1].id, "t_machado")
    T.eq(inv[1].durability, 3, "mantém os marcadores")
    T.eq(g:atk(c), 4)
    clear_test_cards()
  end },

  { "equipamento pode ser jogado do Inventário e volta com a durabilidade guardada", function(T)
    local g = new_game({ "t_sobrevivente", "t_machado", "t_lanca" })
    play(g, "t_sobrevivente", { slot = 1 })
    play(g, "t_machado", { target = 1 })
    local c = g:creature_at(1, 1)
    g:wear(c, "mao", 2)
    play(g, "t_lanca", { target = 1 })
    T.ok(play(g, "t_machado", { target = 1, from = "inventory",
      hand_index = idx(g.players[1].inventory, "t_machado") }))
    T.eq(c.equips.mao.durability, 2)
    T.eq(g.players[1].inventory[1].id, "t_lanca")
    clear_test_cards()
  end },

  { "durabilidade em zero manda o equipamento para o descarte", function(T)
    local g = new_game({ "t_sobrevivente", "t_armadura" })
    play(g, "t_sobrevivente", { slot = 1 })
    play(g, "t_armadura", { target = 1 })
    local c = g:creature_at(1, 1)
    T.eq(g:hp(c), 5)
    g:wear(c, "peito", 1)
    T.ok(c.equips.peito ~= nil)
    g:wear(c, "peito", 1)
    T.eq(c.equips.peito, nil)
    local d = g.players[1].discard
    T.eq(d[#d].id, "t_armadura")
    T.eq(g:hp(c), 3)
    clear_test_cards()
  end },

  { "efeito ao equipar dispara e os três espaços são independentes", function(T)
    local g = new_game({ "t_sobrevivente", "t_machado", "t_armadura", "t_oculos" })
    play(g, "t_sobrevivente", { slot = 2 })
    play(g, "t_machado", { target = 2 })
    play(g, "t_armadura", { target = 2 })
    play(g, "t_oculos", { target = 2 })
    local c = g:creature_at(1, 2)
    T.ok(c.equips.mao and c.equips.peito and c.equips.cabeca)
    T.eq(log[1], "equipou:t_sobrevivente")
    g:discard_all_equips(c, "morte")
    T.eq(next(c.equips), nil)
    T.eq(#g.players[1].discard, 3)
    clear_test_cards()
  end },

  { "Inventário cheio: o equipamento substituído é destruído", function(T)
    local g = new_game({ "t_sobrevivente", "t_machado" })
    play(g, "t_sobrevivente", { slot = 1 })
    play(g, "t_machado", { target = 1 })
    local pl = g.players[1]
    while g:hand_count(1) < Game.HAND_LIMIT do pl.hand[#pl.hand + 1] = { id = "t_comum", uid = g:next_uid() } end
    g:equip(g:creature_at(1, 1), { id = "t_lanca", uid = g:next_uid() })
    T.eq(#pl.inventory, 0)
    T.eq(pl.destroyed[#pl.destroyed].id, "t_machado")
    clear_test_cards()
  end },

  { "a ferramenta na mão gasta 1 por golpe dado, contra criatura ou jogador", function(T)
    local g = new_game()
    local c = put(g, 1, "t_sobrevivente", 1)
    g:equip(c, { id = "t_machado", uid = g:next_uid() })
    fight(g, { 1 })
    T.eq(c.equips.mao.durability, 3, "golpe no jogador gasta")
    local g2 = new_game()
    local c2 = put(g2, 1, "t_sobrevivente", 1)
    g2:equip(c2, { id = "t_machado", uid = g2:next_uid() })
    put(g2, 2, "t_sobrevivente", 1)
    fight(g2, { 1 }, { { 1, 1 } })
    T.eq(c2.equips.mao.durability, 3, "golpe na criatura gasta")
    clear_test_cards()
  end },

  { "a armadura no peito gasta 1 por golpe recebido, mesmo com dano zero", function(T)
    Cards.define{ id = "t_zero", kind = "criatura", cost = 0, atk = 0, hp = 3 }
    local g = new_game()
    put(g, 1, "t_zero", 1)
    local d = put(g, 2, "t_sobrevivente", 1)
    g:equip(d, { id = "t_armadura", uid = g:next_uid() })
    fight(g, { 1 }, { { 1, 1 } })
    T.eq(d.damage, 0)
    T.eq(d.equips.peito.durability, 1, "golpe de dano zero ainda gasta a armadura")
    T.eq(g:creature_at(1, 1).damage, 1, "o bloqueador golpeou de volta")
    -- Armadura com 1 de durabilidade quebra no golpe recebido.
    local g2 = new_game()
    put(g2, 1, "t_zero", 1)
    local d2 = put(g2, 2, "t_sobrevivente", 1)
    g2:equip(d2, { id = "t_armadura", uid = g2:next_uid(), durability = 1 })
    fight(g2, { 1 }, { { 1, 1 } })
    T.eq(d2.equips.peito, nil, "quebrou")
    T.eq(g2.players[2].discard[#g2.players[2].discard].id, "t_armadura")
    Cards.remove("t_zero")
    clear_test_cards()
  end },

  { "o equipamento que quebra no golpe ainda dispara o seu Golpear", function(T)
    local hits = 0
    Cards.define{ id = "t_pa", kind = "equipamento", slot = "mao", cost = 1, atk_bonus = 1, durability = 1,
      on_strike = function() hits = hits + 1 end }
    local g = new_game()
    local c = put(g, 1, "t_sobrevivente", 1)
    g:equip(c, { id = "t_pa", uid = g:next_uid() })
    fight(g, { 1 })
    T.eq(hits, 1)
    T.eq(c.equips.mao, nil, "quebrou depois do Golpear")
    Cards.remove("t_pa")
    clear_test_cards()
  end },

  { "ao atacar dispara na declaração, para a criatura e os equipamentos dela", function(T)
    local log = {}
    Cards.define{ id = "t_bravo", kind = "criatura", cost = 0, atk = 1, hp = 3, sobrevivente = true,
      on_attack = function(g, c) log[#log + 1] = "criatura" end }
    Cards.define{ id = "t_picareta", kind = "equipamento", slot = "mao", cost = 1,
      on_attack = function(g, c, e) log[#log + 1] = "equip:" .. e.def.id .. ":" .. c.def.id end }
    local g = new_game()
    local c = put(g, 1, "t_bravo", 1)
    g:equip(c, { id = "t_picareta", uid = g:next_uid() })
    put(g, 1, "t_sobrevivente", 2)
    T.ok(g:act(1, { type = "attack", attackers = { 2, 1 } }))
    T.eq(#log, 2, "só quem ataca dispara; o Sobrevivente sem efeito não entra")
    T.eq(log[1], "criatura"); T.eq(log[2], "equip:t_picareta:t_bravo")
    T.eq(g.combat ~= nil, true, "dispara antes dos bloqueios")
    Cards.remove("t_bravo"); Cards.remove("t_picareta")
    clear_test_cards()
  end },

  { "redução de dano tira 1 de cada fonte, no mínimo 0, e o golpe ainda gasta a armadura", function(T)
    Cards.define{ id = "t_madeira", kind = "equipamento", slot = "peito", cost = 2, hp_bonus = 1, durability = 3,
      damage_reduction = 1 }
    Cards.define{ id = "t_forte", kind = "criatura", cost = 0, atk = 3, hp = 9 }
    local g = new_game()
    local c = put(g, 1, "t_sobrevivente", 1)
    g:equip(c, { id = "t_madeira", uid = g:next_uid() })
    T.eq(g:damage_creature(c, 3, nil, "teste"), 2)
    T.eq(c.damage, 2)
    local ev = g.events[#g.events]
    T.eq(ev.t, "creature_damage"); T.eq(ev.amount, 2); T.eq(ev.reduced, 1)
    T.eq(g:damage_creature(c, 1, nil, "teste"), 0, "1 de dano vira 0")
    T.eq(c.damage, 2)
    T.eq(g.events[#g.events], ev, "nada emitido quando o dano vira 0")
    -- Em combate: o golpe de 1 do bloqueador não fere, mas gasta a armadura.
    local g2 = new_game()
    local a = put(g2, 1, "t_sobrevivente", 1)
    g2:equip(a, { id = "t_madeira", uid = g2:next_uid() })
    put(g2, 2, "t_comum", 1)
    fight(g2, { 1 }, { { 1, 1 } })
    T.eq(a.damage, 0)
    T.eq(a.equips.peito.durability, 2)
    Cards.remove("t_madeira"); Cards.remove("t_forte")
    clear_test_cards()
  end },
}
