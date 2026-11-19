-- Deck do Webber (#21): Webber (nível 1), Aranha e Aranha guerreira.
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
  Cards.define{ id = "w_comum", kind = "criatura", cost = 0, atk = 1, hp = 9 }
  Cards.define{ id = "w_fragil", kind = "criatura", cost = 0, atk = 1, hp = 9, kw = { fragil = true } }
end

-- Baralho extra com n cópias de cada id.
local function extra_deck(ids, n)
  local list = {}
  for _, id in ipairs(ids) do
    for _ = 1, n do list[#list + 1] = { id = id } end
  end
  return list
end

-- opts.extra = { n1, n2 }: cópias de Aranha no baralho extra de cada jogador.
local function new_game(opts)
  opts = opts or {}
  load_cartas()
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "w_comum" }; d2[i] = { id = "w_comum" } end
  local extra = opts.extra or { 3, 3 }
  local g = Game.new{ decks = { d1, d2 },
    extra_decks = { extra_deck({ "aranha" }, extra[1]), extra_deck({ "aranha" }, extra[2]) },
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

-- Ataca com os espaços dados e entrega a vez ao defensor.
local function attack(g, slots)
  assert(g:act(1, { type = "attack", attackers = slots }))
  assert(g:act(1, { type = "pass" }))
end

local function block(g, list)
  local blocks = {}
  for i, pr in ipairs(list) do blocks[i] = { attacker = pr[1], blocker = pr[2] } end
  return g:act(2, { type = "block", blocks = blocks })
end

local function blocker_of(g, a)
  for _, ev in ipairs(g.events) do
    if ev.t == "block" then
      for _, b in ipairs(ev.blocks) do if b.attacker == a.uid then return b.blocker, ev.auto end end
    end
  end
end

local function events(g, t)
  local list = {}
  for _, ev in ipairs(g.events) do if ev.t == t then list[#list + 1] = ev end end
  return list
end

local function count(g, p, id)
  local n = 0
  for _, c in ipairs(g:creatures(p)) do if c.def.id == id then n = n + 1 end end
  return n
end

return {
  { "as três cartas estão registradas com os atributos e os números oficiais", function(T)
    local _, numeros = load_cartas()
    local w = Cards.get("webber")
    T.ok(w ~= nil, "webber registrado")
    T.eq(w.kind, "criatura"); T.eq(w.campeao, true); T.eq(w.sobrevivente, true)
    T.eq(w.cost, 3); T.eq(w.atk, 1); T.eq(w.hp, 3)
    T.eq(w.types.aranha, true)
    T.eq(type(w.text), "string")
    local a = Cards.get("aranha")
    T.eq(a.cost, 1); T.eq(a.atk, 2); T.eq(a.hp, 1)
    T.eq(a.kw.agressivo, true); T.eq(a.types.aranha, true)
    local ag = Cards.get("aranha_guerreira")
    T.eq(ag.cost, 3); T.eq(ag.atk, 2); T.eq(ag.hp, 4); T.eq(ag.speed, 2)
    T.eq(ag.kw.agressivo, true); T.eq(ag.types.aranha, true)
    T.eq(numeros.webber, 20); T.eq(numeros.aranha, 21); T.eq(numeros.aranha_guerreira, 22)
    T.eq(w.numero, 20); T.eq(a.numero, 21); T.eq(ag.numero, 22)
  end },

  { "Webber jogado da mão cria 1 Aranha, tirada do baralho extra do dono", function(T)
    local g = new_game()
    g.players[1].mana = 3
    local extra = #g.players[1].extra
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "webber"), slot = 1 }))
    T.eq(g.players[1].mana, 0)
    T.eq(g:creature_at(1, 1).def.id, "webber")
    T.eq(count(g, 1, "aranha"), 1)
    local aranha = g:creature_at(1, 2)
    T.eq(aranha.def.id, "aranha", "entra no primeiro espaço livre")
    T.eq(aranha.ficha, true)
    T.eq(#g.players[1].extra, extra - 1, "a cópia saiu do baralho extra do dono")
    T.eq(#g.players[2].extra, 3, "o baralho extra do adversário não muda")
  end },

  { "Webber não cria Aranha sem cópia no baralho extra", function(T)
    local g = new_game{ extra = { 0, 3 } }
    put(g, 1, "webber", 1)
    T.eq(count(g, 1, "aranha"), 0)
    T.eq(#events(g, "no_copy"), 1)
    T.eq(#g.players[2].extra, 3, "não pega do adversário")
  end },

  { "Webber não cria Aranha sem espaço em campo", function(T)
    local g = new_game()
    for s = 1, Game.FIELD_SLOTS - 1 do put(g, 1, "w_comum", s) end
    put(g, 1, "webber", Game.FIELD_SLOTS)
    T.eq(count(g, 1, "aranha"), 0)
    T.eq(#events(g, "no_space"), 1)
    T.eq(#g.players[1].extra, 3, "a cópia nem sai do baralho extra")
  end },

  { "Aranha do adversário não pode bloquear o Webber, mas outra criatura pode", function(T)
    local g = new_game()
    put(g, 1, "webber", 1)
    put(g, 2, "aranha", 1); put(g, 2, "aranha_guerreira", 2); put(g, 2, "w_comum", 3)
    attack(g, { 1 })
    T.eq(block(g, { { 1, 1 } }), false, "Aranha")
    T.eq(block(g, { { 1, 2 } }), false, "Aranha guerreira")
    T.ok(block(g, { { 1, 3 } }), "criatura comum")
  end },

  { "a restrição é por dono: só recusa Aranhas do adversário, e o Webber adversário é uma delas", function(T)
    local g = new_game()
    local w1 = put(g, 1, "webber", 1)
    local minha = g:creature_at(1, 2)
    local w2 = put(g, 2, "webber", 1)
    local deles = g:creature_at(2, 2)
    local deny = w1.def.cannot_be_blocked_by
    T.eq(deny(g, w1, minha), false, "a Aranha do próprio dono não é recusada")
    T.eq(deny(g, w1, deles), true, "a Aranha do adversário é recusada")
    T.eq(deny(g, w1, w2), true, "o Webber adversário é Aranha")
    attack(g, { 1 })
    T.eq(block(g, { { 1, 1 } }), false, "Webber não bloqueia o Webber adversário")
    T.eq(block(g, { { 1, 2 } }), false, "nem a Aranha dele")
    T.ok(block(g, {}))
  end },

  { "a Aranha criada pelo Webber pode bloquear um ataque do adversário", function(T)
    local g = new_game()
    put(g, 1, "w_comum", 1)
    put(g, 2, "webber", 1)
    T.eq(g:creature_at(2, 2).def.id, "aranha")
    attack(g, { 1 })
    T.ok(block(g, { { 1, 2 } }))
  end },

  { "o bloqueio obrigatório não força uma Aranha a bloquear o Webber", function(T)
    -- A Aranha é Agressiva: se o Webber fosse Frágil, ela seria exigida; com a
    -- restrição, o defensor que só tem Aranhas não é obrigado a nada, e ao
    -- passar sem declarar nenhum bloqueio automático acontece.
    local g = new_game()
    local w = put(g, 1, "webber", 1)
    w.def = setmetatable({ kw = { fragil = true, agressivo = true } }, { __index = w.def })
    put(g, 2, "aranha", 1)
    attack(g, { 1 })
    T.ok(g:can_act(2, { type = "block", blocks = {} }), "pode ficar sem bloqueio")
    local life = g.players[2].life
    assert(g:act(2, { type = "pass" }))
    T.eq(blocker_of(g, w), nil, "nenhum bloqueio automático")
    T.eq(g.players[2].life, life - 1)
  end },

  { "uma Aranha Frágil do adversário não é atraída pelo Webber Agressivo", function(T)
    local g = new_game()
    local w = put(g, 1, "webber", 1)
    w.def = setmetatable({ kw = { agressivo = true } }, { __index = w.def })
    Cards.define{ id = "w_aranha_fragil", kind = "criatura", cost = 0, atk = 1, hp = 9,
      types = { aranha = true }, kw = { fragil = true } }
    put(g, 2, "w_aranha_fragil", 1)
    attack(g, { 1 })
    T.ok(g:can_act(2, { type = "block", blocks = {} }))
    assert(g:act(2, { type = "pass" }))
    T.eq(blocker_of(g, w), nil)
  end },

  { "Aranha guerreira golpeia na fase rápida", function(T)
    local g = new_game()
    Cards.define{ id = "w_dois", kind = "criatura", cost = 0, atk = 1, hp = 2 }
    local ag = put(g, 1, "aranha_guerreira", 1)
    put(g, 2, "w_dois", 1)
    attack(g, { 1 })
    T.ok(block(g, { { 1, 1 } }))
    assert(g:act(2, { type = "pass" })); assert(g:act(1, { type = "pass" }))
    local phases = events(g, "strike_phase")
    T.eq(#phases, 1)
    T.eq(phases[1].phase, "rapida")
    T.eq(g:creature_at(2, 1), nil, "a bloqueadora morre antes de golpear")
    T.eq(ag.damage, 0)
  end },

  { "Aranha é bloqueada por uma Frágil livre, como toda Agressiva", function(T)
    local g = new_game()
    local a = put(g, 1, "aranha", 1)
    local f = put(g, 2, "w_fragil", 1)
    attack(g, { 1 })
    T.eq(block(g, {}), false)
    assert(g:act(2, { type = "pass" }))
    T.eq(blocker_of(g, a), f.uid)
  end },
}
