local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local function define()
  Cards.define{ id = "x_coelho", kind = "criatura", cost = 0, atk = 1, hp = 1 }
  Cards.define{ id = "x_casa", kind = "estrutura", cost = 0 }
  Cards.define{ id = "x_base", kind = "criatura", cost = 0, atk = 1, hp = 9 }
end

local function copies(id, n)
  local list = {}
  for i = 1, n do list[i] = { id = id } end
  return list
end

local function new_game(extra1)
  define()
  local d1, d2 = copies("x_base", 20), copies("x_base", 20)
  local g = Game.new{ decks = { d1, d2 }, extra_decks = { extra1 or {}, {} },
    first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function count(list, id)
  local n = 0
  for _, c in ipairs(list) do if c.id == id then n = n + 1 end end
  return n
end

return {
  { "criar uma ficha tira a cópia do baralho extra", function(T)
    local g = new_game(copies("x_coelho", 2))
    local c = g:create_token(1, "x_coelho")
    T.ok(c ~= nil)
    T.eq(c.ficha, true)
    T.eq(count(g.players[1].extra, "x_coelho"), 1)
  end },

  { "sem cópia no baralho extra, a criação não acontece", function(T)
    local g = new_game(copies("x_coelho", 1))
    T.ok(g:create_token(1, "x_coelho") ~= nil)
    local c, why = g:create_token(1, "x_coelho")
    T.eq(c, nil)
    T.eq(why, "sem_copia")
    T.eq(g.events[#g.events].t, "no_copy")
    T.eq(#g:creatures(1), 1)
  end },

  { "o baralho extra de um jogador não serve ao outro", function(T)
    local g = new_game(copies("x_coelho", 1))
    local c, why = g:create_token(2, "x_coelho")
    T.eq(c, nil)
    T.eq(why, "sem_copia")
  end },

  { "sem espaço em campo, a cópia fica no baralho extra", function(T)
    local g = new_game(copies("x_coelho", 1))
    for s = 1, 6 do g:place_creature(1, { id = "x_base", uid = g:next_uid() }, s) end
    local c, why = g:create_token(1, "x_coelho")
    T.eq(c, nil)
    T.eq(why, "sem_espaco")
    T.eq(count(g.players[1].extra, "x_coelho"), 1)
  end },

  { "estrutura criada que não entra volta para o baralho extra", function(T)
    local g = new_game(copies("x_casa", 3))
    g:create_token(1, "x_casa"); g:create_token(1, "x_casa")
    local _, why = g:create_token(1, "x_casa")
    T.eq(why, "pendente")
    T.eq(count(g.players[1].extra, "x_casa"), 0)
    T.ok(g:act(1, { type = "choose", index = nil }))
    T.eq(count(g.players[1].extra, "x_casa"), 1)
  end },

  { "ficha morta vai para o descarte e pode voltar a campo", function(T)
    local g = new_game(copies("x_coelho", 1))
    local c = g:create_token(1, "x_coelho")
    g:kill(c, "teste")
    local d = g.players[1].discard
    T.eq(d[#d].id, "x_coelho")
    local card = table.remove(d)
    local back = g:place_creature(1, card, 3)
    T.eq(back.ficha, true, "revivida, continua ficha")
    T.eq(count(g.players[1].extra, "x_coelho"), 0)
  end },

  { "ficha marcada para voltar ao baralho extra não fica no descarte", function(T)
    define()
    Cards.define{ id = "x_fantasma", kind = "criatura", cost = 0, atk = 1, hp = 1, returns_to_extra = true }
    local g = new_game(copies("x_fantasma", 1))
    local c = g:create_token(1, "x_fantasma")
    g:kill(c, "teste")
    T.eq(count(g.players[1].discard, "x_fantasma"), 0)
    T.eq(count(g.players[1].extra, "x_fantasma"), 1)
    Cards.remove("x_fantasma")
  end },

  { "ficha destruída vai para as Destruídas", function(T)
    local g = new_game(copies("x_coelho", 1))
    local c = g:create_token(1, "x_coelho")
    g:remove_creature(c, "destroyed", "teste")
    T.eq(count(g.players[1].destroyed, "x_coelho"), 1)
    T.eq(count(g.players[1].extra, "x_coelho"), 0)
  end },

  { "ficha devolvida à mão volta para o baralho extra", function(T)
    local g = new_game(copies("x_coelho", 1))
    local c = g:create_token(1, "x_coelho")
    local hand = #g.players[1].hand
    g:remove_creature(c, "hand", "teste")
    T.eq(#g.players[1].hand, hand)
    T.eq(count(g.players[1].extra, "x_coelho"), 1)
  end },

  { "com a mão cheia, a ficha não é criada e a cópia fica no baralho extra", function(T)
    local g = new_game(copies("x_coelho", 1))
    local pl = g.players[1]
    while g:hand_count(1) < g:hand_limit(1) do pl.hand[#pl.hand + 1] = { id = "x_base", uid = g:next_uid() } end
    local c, why = g:create_token(1, "x_coelho", { zone = "hand" })
    T.eq(c, nil); T.eq(why, "sem_espaco")
    T.eq(count(pl.extra, "x_coelho"), 1)
    T.eq(#pl.destroyed, 0)
  end },

  { "criatura criada por estrutura fica ligada a ela, até 3", function(T)
    local g = new_game(copies("x_coelho", 5))
    local st = g:put_structure(1, { id = "x_casa", uid = g:next_uid() }, 1)
    for _ = 1, 3 do T.ok(g:create_token(1, "x_coelho", { link = st }) ~= nil) end
    T.eq(#g:linked_to(st), 3)
    local c, why = g:create_token(1, "x_coelho", { link = st })
    T.eq(c, nil); T.eq(why, "limite_vinculo")
    T.eq(count(g.players[1].extra, "x_coelho"), 2, "a cópia fica no baralho extra")
    T.ok(g:create_token(1, "x_coelho") ~= nil, "sem vínculo, não há limite")
  end },

  { "quando a estrutura sai de campo, as ligadas ficam sem vínculo", function(T)
    local g = new_game(copies("x_coelho", 5))
    local st = g:put_structure(1, { id = "x_casa", uid = g:next_uid() }, 1)
    local a = g:create_token(1, "x_coelho", { link = st })
    g:break_structure(1, 1, "teste")
    T.eq(g:creature_at(1, a.slot), a, "continua em campo")
    T.eq(a.link, nil)
    local st2 = g:put_structure(1, { id = "x_casa", uid = g:next_uid() }, 1)
    local b = g:create_token(1, "x_coelho", { link = st2 })
    g:put_structure(1, { id = "x_casa", uid = g:next_uid() }, 2)
    g:put_structure(1, { id = "x_casa", uid = g:next_uid() }, 1)
    T.eq(b.link, nil, "substituída (destruída) também desfaz o vínculo")
  end },

  { "criatura criada por estrutura que já saiu de campo não fica ligada", function(T)
    local g = new_game(copies("x_coelho", 2))
    local st = g:put_structure(1, { id = "x_casa", uid = g:next_uid() }, 1)
    g:break_structure(1, 1, "teste")
    local c = g:create_token(1, "x_coelho", { link = st })
    T.ok(c ~= nil)
    T.eq(c.link, nil)
  end },

  { "ficha com destino desconhecido vai para o descarte, como uma carta comum", function(T)
    local g = new_game(copies("x_coelho", 1))
    local c = g:create_token(1, "x_coelho")
    g:remove_creature(c, nil, "teste")
    T.eq(count(g.players[1].discard, "x_coelho"), 1)
    T.eq(count(g.players[1].extra, "x_coelho"), 0)
  end },

  { "ficha do descarte movida para a mão volta ao baralho extra", function(T)
    local g = new_game(copies("x_coelho", 1))
    local c = g:create_token(1, "x_coelho")
    g:kill(c, "teste")
    local card = table.remove(g.players[1].discard)
    local hand = #g.players[1].hand
    g:add_to_hand(1, card, "descarte")
    T.eq(#g.players[1].hand, hand)
    T.eq(count(g.players[1].extra, "x_coelho"), 1)
  end },

  { "equipamento ficha trocado por outro volta ao baralho extra", function(T)
    define()
    Cards.define{ id = "x_sobrev", kind = "criatura", cost = 0, atk = 1, hp = 3, sobrevivente = true }
    Cards.define{ id = "x_isca", kind = "equipamento", slot = "mao", cost = 0 }
    local g = new_game(copies("x_isca", 1))
    local s = g:place_creature(1, { id = "x_sobrev", uid = g:next_uid() }, 1)
    local isca = g:take_from_extra(1, "x_isca")
    g:equip(s, isca)
    g:equip(s, { id = "x_isca", uid = g:next_uid() })
    T.eq(#g.players[1].inventory, 0)
    T.eq(count(g.players[1].extra, "x_isca"), 1)
  end },
}
