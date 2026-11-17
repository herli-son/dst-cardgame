local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local function new_game()
  Cards.define{ id = "b_comum", kind = "criatura", cost = 0, atk = 1, hp = 9 }
  Cards.define{ id = "b_fragil", kind = "criatura", cost = 0, atk = 1, hp = 9, kw = { fragil = true } }
  Cards.define{ id = "b_agressivo", kind = "criatura", cost = 0, atk = 1, hp = 9, kw = { agressivo = true } }
  Cards.define{ id = "b_agressivo_nb", kind = "criatura", cost = 0, atk = 1, hp = 9,
    kw = { agressivo = true }, no_block = true }
  Cards.define{ id = "b_merm", kind = "criatura", cost = 0, atk = 1, hp = 9,
    kw = { agressivo = true, rival = "porco" } }
  Cards.define{ id = "b_porco", kind = "criatura", cost = 0, atk = 1, hp = 9, types = { porco = true } }
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "b_comum" }; d2[i] = { id = "b_comum" } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function put(g, p, id, slot)
  return g:place_creature(p, { id = id, uid = g:next_uid() }, slot)
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

-- O defensor passa sem declarar e o combate resolve.
local function resolve_without_blocks(g)
  assert(g:act(2, { type = "pass" }))
end

local function blocker_of(g, a)
  for _, ev in ipairs(g.events) do
    if ev.t == "block" then
      for _, b in ipairs(ev.blocks) do if b.attacker == a.uid then return b.blocker, ev.auto end end
    end
  end
end

return {
  { "Frágil atacando deve ser bloqueada por uma Agressiva do defensor", function(T)
    local g = new_game()
    put(g, 1, "b_fragil", 1)
    put(g, 2, "b_comum", 1); put(g, 2, "b_agressivo", 2)
    attack(g, { 1 })
    T.eq(block(g, {}), false, "sem bloqueio")
    T.eq(block(g, { { 1, 1 } }), false, "bloqueada por quem não é Agressiva")
    T.ok(block(g, { { 1, 2 } }))
  end },

  { "Frágil atacando sem Agressiva no defensor pode ficar sem bloqueio", function(T)
    local g = new_game()
    put(g, 1, "b_fragil", 1)
    put(g, 2, "b_comum", 1); put(g, 2, "b_agressivo_nb", 2)
    attack(g, { 1 })
    T.ok(block(g, {}), "Agressiva que não bloqueia não conta")
  end },

  { "a Agressiva do defensor não escapa da Frágil bloqueando outro atacante", function(T)
    local g = new_game()
    put(g, 1, "b_fragil", 1); put(g, 1, "b_comum", 2)
    put(g, 2, "b_agressivo", 1)
    attack(g, { 1, 2 })
    T.eq(block(g, { { 2, 1 } }), false)
    T.ok(block(g, { { 1, 1 } }))
  end },

  { "com mais Frágeis do que Agressivas, basta usar todas as Agressivas", function(T)
    local g = new_game()
    put(g, 1, "b_fragil", 1); put(g, 1, "b_fragil", 2)
    put(g, 2, "b_agressivo", 1)
    attack(g, { 1, 2 })
    T.ok(block(g, { { 2, 1 } }), "o defensor escolhe qual Frágil")
  end },

  { "Agressiva atacando é bloqueada por uma Frágil livre", function(T)
    local g = new_game()
    put(g, 1, "b_agressivo", 1)
    put(g, 2, "b_fragil", 1)
    attack(g, { 1 })
    T.eq(block(g, {}), false)
    T.ok(block(g, { { 1, 1 } }))
  end },

  { "Frágil que bloqueia outro atacante não está livre", function(T)
    local g = new_game()
    put(g, 1, "b_agressivo", 1); put(g, 1, "b_comum", 2)
    put(g, 2, "b_fragil", 1)
    attack(g, { 1, 2 })
    T.ok(block(g, { { 2, 1 } }))
  end },

  { "Rival tem prioridade sobre a atração do Agressivo", function(T)
    local g = new_game()
    put(g, 1, "b_merm", 1)
    put(g, 2, "b_fragil", 1); put(g, 2, "b_porco", 2)
    attack(g, { 1 })
    T.eq(block(g, {}), false)
    T.eq(block(g, { { 1, 1 } }), false, "a Frágil não basta com um Porco disponível")
    T.ok(block(g, { { 1, 2 } }), "bloqueado pelo Porco, a Frágil fica livre")
  end },

  { "sem criatura do tipo Rival, vale a atração do Agressivo", function(T)
    local g = new_game()
    put(g, 1, "b_merm", 1)
    put(g, 2, "b_fragil", 1)
    attack(g, { 1 })
    T.eq(block(g, {}), false)
    T.ok(block(g, { { 1, 1 } }))
  end },

  { "defensor que passa sem declarar tem os bloqueios obrigatórios completados", function(T)
    local g = new_game()
    local f1 = put(g, 1, "b_fragil", 1)
    local f2 = put(g, 1, "b_fragil", 2)
    local m = put(g, 1, "b_merm", 3)
    local ag = put(g, 2, "b_agressivo", 4)
    local porco = put(g, 2, "b_porco", 5)
    put(g, 2, "b_comum", 6)
    local life = g.players[2].life
    attack(g, { 1, 2, 3 })
    resolve_without_blocks(g)
    local b, auto = blocker_of(g, f1)
    T.eq(b, ag.uid, "a primeira Frágil na ordem declarada fica com a Agressiva")
    T.eq(auto, true)
    T.eq(blocker_of(g, f2), nil)
    T.eq(blocker_of(g, m), porco.uid, "Rival primeiro")
    T.eq(g.players[2].life, life - 1, "só a segunda Frágil passa")
  end },

  { "Frágil livre bloqueia sozinha a Agressiva quando o defensor passa", function(T)
    local g = new_game()
    local a = put(g, 1, "b_agressivo", 1)
    local f = put(g, 2, "b_fragil", 3)
    local life = g.players[2].life
    attack(g, { 1 })
    resolve_without_blocks(g)
    T.eq(blocker_of(g, a), f.uid)
    T.eq(g.players[2].life, life)
    T.eq(f.damage, 1)
  end },
}
