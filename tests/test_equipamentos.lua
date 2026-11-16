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
}
