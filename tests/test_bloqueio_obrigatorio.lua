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

  { "atacante que saiu de campo não cria obrigação", function(T)
    local g = new_game()
    local f = put(g, 1, "b_fragil", 1); put(g, 1, "b_comum", 2)
    put(g, 2, "b_agressivo", 1); put(g, 2, "b_comum", 2)
    attack(g, { 1, 2 })
    g:remove_creature(f, "hand")
    T.ok(block(g, { { 2, 2 } }))
  end },

  { "a Agressiva do tipo Rival não foge da Frágil se outro Porco atende o Rival", function(T)
    local g = new_game()
    Cards.define{ id = "b_porco_agressivo", kind = "criatura", cost = 0, atk = 1, hp = 9,
      kw = { agressivo = true }, types = { porco = true } }
    put(g, 1, "b_merm", 1); put(g, 1, "b_fragil", 2)
    local ap = put(g, 2, "b_porco_agressivo", 1)
    local porco = put(g, 2, "b_porco", 2)
    attack(g, { 1, 2 })
    T.eq(block(g, { { 1, 1 } }), false, "deixaria a Frágil sem a Agressiva")
    T.ok(block(g, { { 1, 2 }, { 2, 1 } }))
    g = new_game()
    local m = put(g, 1, "b_merm", 1); local f = put(g, 1, "b_fragil", 2)
    ap = put(g, 2, "b_porco_agressivo", 1); porco = put(g, 2, "b_porco", 2)
    attack(g, { 1, 2 })
    resolve_without_blocks(g)
    T.eq(blocker_of(g, m), porco.uid, "no automático, o Porco comum fica com o Rival")
    T.eq(blocker_of(g, f), ap.uid)
  end },

  { "Rivais de tipos diferentes são todos atendidos quando possível", function(T)
    local g = new_game()
    Cards.define{ id = "b_rival_coelho", kind = "criatura", cost = 0, atk = 1, hp = 9, kw = { rival = "coelho" } }
    Cards.define{ id = "b_porco_coelho", kind = "criatura", cost = 0, atk = 1, hp = 9,
      types = { porco = true, coelho = true } }
    Cards.define{ id = "b_rival_porco", kind = "criatura", cost = 0, atk = 1, hp = 9, kw = { rival = "porco" } }
    local rp = put(g, 1, "b_rival_porco", 1); local rc = put(g, 1, "b_rival_coelho", 2)
    local pc = put(g, 2, "b_porco_coelho", 1); local porco = put(g, 2, "b_porco", 2)
    attack(g, { 1, 2 })
    T.eq(block(g, { { 1, 1 } }), false)
    T.ok(block(g, { { 1, 2 }, { 2, 1 } }))
    g = new_game()
    rp = put(g, 1, "b_rival_porco", 1); rc = put(g, 1, "b_rival_coelho", 2)
    pc = put(g, 2, "b_porco_coelho", 1); porco = put(g, 2, "b_porco", 2)
    attack(g, { 1, 2 })
    resolve_without_blocks(g)
    T.eq(blocker_of(g, rp), porco.uid)
    T.eq(blocker_of(g, rc), pc.uid)
  end },

  { "criatura com dano letal esperando não conta nas obrigações", function(T)
    local g = new_game()
    put(g, 1, "b_agressivo", 1)
    local f = put(g, 2, "b_fragil", 1)
    attack(g, { 1 })
    f.damage = 9
    T.ok(block(g, {}), "a Frágil condenada não está livre para bloquear")
  end },
}
