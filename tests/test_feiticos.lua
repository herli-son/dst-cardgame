-- Feitiços do MVP (#23): Dardo, Pomada e Dardo do sono.
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

-- O executor restaura o registro de cartas entre os casos, então o módulo é
-- carregado de novo a cada caso.
local function load_feiticos()
  package.loaded["duelo/cartas/feiticos/init"] = nil
  return require("duelo/cartas/feiticos/init")
end

local function load_criaturas()
  package.loaded["duelo/cartas/criaturas/init"] = nil
  return require("duelo/cartas/criaturas/init")
end

local function define_test_cards()
  Cards.define{ id = "f_tres", kind = "criatura", cost = 0, atk = 1, hp = 3 }
  Cards.define{ id = "f_quatro", kind = "criatura", cost = 0, atk = 1, hp = 4 }
  Cards.define{ id = "f_grande", kind = "criatura", cost = 0, atk = 2, hp = 9 }
end

local function new_game()
  load_feiticos()
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "f_grande" }; d2[i] = { id = "f_grande" } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function put(g, p, id, slot)
  return g:place_creature(p, { id = id, uid = g:next_uid() }, slot)
end

-- Põe a carta na mão de p, com mana para jogá-la, e devolve o índice.
local function give(g, p, id)
  local pl = g.players[p]
  pl.hand[#pl.hand + 1] = { id = id, uid = g:next_uid() }
  pl.mana = math.max(pl.mana, Cards.get(id).cost)
  return #pl.hand
end

local function cast(g, p, id, target)
  return g:act(p, { type = "play", hand_index = give(g, p, id), target = target })
end

-- Joga um Rápido e resolve a pilha na hora (os dois passam sem responder).
local function cast_and_resolve(g, p, id, target)
  local ok, err = cast(g, p, id, target)
  if not ok then return ok, err end
  assert(g:act(p, { type = "pass" }))
  assert(g:act(Game.other(p), { type = "pass" }))
  return true
end

-- Ataque do jogador atk com bloqueios do defensor ({ { atacante, bloqueador }, ... }),
-- resolvido até o fim.
local function fight(g, atk, attackers, blocks)
  local def = Game.other(atk)
  assert(g:act(atk, { type = "attack", attackers = attackers }))
  assert(g:act(atk, { type = "pass" }))
  if blocks then
    local list = {}
    for i, pr in ipairs(blocks) do list[i] = { attacker = pr[1], blocker = pr[2] } end
    assert(g:act(def, { type = "block", blocks = list }))
  end
  assert(g:act(def, { type = "pass" }))
  if blocks and #blocks > 0 then assert(g:act(atk, { type = "pass" })) end
end

-- Encerra a rodada: os dois passam com a pilha vazia.
local function next_round(g)
  local round = g.round
  assert(g:act(g.active, { type = "pass" }))
  assert(g:act(g.active, { type = "pass" }))
  assert(g.round == round + 1, "a rodada devia ter avançado")
end

local function events(g, t)
  local list = {}
  for _, ev in ipairs(g.events) do if ev.t == t then list[#list + 1] = ev end end
  return list
end

local function last_discard(g, p)
  local d = g.players[p].discard
  return d[#d]
end

return {
  { "o módulo registra os 3 feitiços com custo, tipo e número do documento", function(T)
    local ids = load_feiticos()
    package.loaded["duelo/cartas/numeros"] = nil
    local numeros = require("duelo/cartas/numeros")
    T.eq(#ids, 3)
    local esperado = {
      dardo = { "Dardo", 2, "rapido", 30 },
      pomada = { "Pomada", 1, "instantaneo", 31 },
      dardo_do_sono = { "Dardo do sono", 2, "rapido", 32 },
    }
    for _, id in ipairs(ids) do
      local e = esperado[id]
      T.ok(e ~= nil, "carta inesperada: " .. id)
      local def = Cards.get(id)
      T.ok(def ~= nil, id .. " registrada")
      T.eq(def.kind, "feitico", id)
      T.eq(def.name, e[1], id .. " nome")
      T.eq(def.cost, e[2], id .. " custo")
      T.eq(def.speed, e[3], id .. " tipo")
      T.eq(def.numero, e[4], id .. " número")
      T.eq(numeros[id], e[4], id .. " número na lista oficial")
      T.eq(type(def.text), "string", id .. " texto")
      esperado[id] = nil
    end
    T.eq(next(esperado), nil, "todas as cartas foram registradas")
  end },

  ----------------------------------------------------------------------------
  -- Dardo
  ----------------------------------------------------------------------------

  { "Dardo: 3 de dano mata uma criatura de 3 de vida", function(T)
    local g = new_game()
    local c = put(g, 2, "f_tres", 1)
    T.ok(cast_and_resolve(g, 1, "dardo", { p = 2, slot = 1 }))
    T.eq(g:creature_at(2, 1), nil, "morreu")
    local deaths = events(g, "death")
    T.eq(deaths[#deaths].uid, c.uid)
    T.eq(last_discard(g, 1).id, "dardo", "o Dardo vai para o descarte")
    T.eq(g.players[1].mana, 0, "pagou 2")
  end },

  { "Dardo: 3 de dano numa criatura de 4 de vida fica marcado", function(T)
    local g = new_game()
    local c = put(g, 2, "f_quatro", 1)
    T.ok(cast_and_resolve(g, 1, "dardo", { p = 2, slot = 1 }))
    T.eq(g:creature_at(2, 1), c, "continua em campo")
    T.eq(c.damage, 3)
    local dmg = events(g, "creature_damage")
    T.eq(#dmg, 1)
    T.eq(dmg[1].uid, c.uid); T.eq(dmg[1].amount, 3); T.eq(dmg[1].reason, "dardo")
  end },

  { "Dardo pode mirar uma criatura do próprio jogador", function(T)
    local g = new_game()
    local c = put(g, 1, "f_quatro", 2)
    T.ok(cast_and_resolve(g, 1, "dardo", { p = 1, slot = 2 }))
    T.eq(c.damage, 3)
  end },

  { "Dardo recusa jogada sem alvo, com espaço vazio ou mirando um jogador", function(T)
    local g = new_game()
    put(g, 2, "f_tres", 1)
    T.eq(cast(g, 1, "dardo", nil), false, "sem alvo")
    T.eq(cast(g, 1, "dardo", { p = 2, slot = 3 }), false, "espaço vazio")
    T.eq(cast(g, 1, "dardo", { p = 2, zone = "jogador" }), false, "jogador")
    T.eq(g:stack_open(), false)
    T.eq(g:creature_at(2, 1).damage, 0)
  end },

  { "Dardo em resposta a um ataque: o atacante morre antes de golpear", function(T)
    local g = new_game()
    put(g, 1, "f_tres", 1)
    local life = g.players[2].life
    assert(g:act(1, { type = "attack", attackers = { 1 } }))
    assert(g:act(1, { type = "pass" }))
    T.ok(cast(g, 2, "dardo", { p = 1, slot = 1 }), "o defensor responde com o Dardo")
    T.eq(#g.stack, 2, "o Dardo fica em cima do ataque")
    assert(g:act(2, { type = "pass" }))
    assert(g:act(1, { type = "pass" }))
    T.eq(g:stack_open(), false)
    T.eq(g:creature_at(1, 1), nil, "o atacante morreu")
    T.eq(g.players[2].life, life, "nenhum golpe chegou ao defensor")
  end },

  { "Dardo com alvo perdido não faz nada e vai para o descarte", function(T)
    local g = new_game()
    put(g, 2, "f_quatro", 1)
    T.ok(cast(g, 1, "dardo", { p = 2, slot = 1 }))
    -- O alvo sai e outra criatura entra no mesmo espaço: não é mais o alvo.
    g.players[2].field[1] = nil
    local outra = put(g, 2, "f_quatro", 1)
    assert(g:act(1, { type = "pass" }))
    assert(g:act(2, { type = "pass" }))
    T.eq(outra.damage, 0)
    T.eq(#events(g, "creature_damage"), 0)
    local fz = events(g, "fizzle")
    T.eq(#fz, 1); T.eq(fz[1].id, "dardo")
    T.eq(last_discard(g, 1).id, "dardo")
  end },

  ----------------------------------------------------------------------------
  -- Pomada
  ----------------------------------------------------------------------------

  { "Pomada numa criatura cura 3 de dano", function(T)
    local g = new_game()
    local c = put(g, 2, "f_grande", 1)
    c.damage = 4
    T.ok(cast(g, 1, "pomada", { p = 2, slot = 1 }))
    T.eq(c.damage, 1)
    local heals = events(g, "creature_heal")
    T.eq(#heals, 1)
    T.eq(heals[1].uid, c.uid); T.eq(heals[1].amount, 3); T.eq(heals[1].reason, "pomada")
    T.eq(last_discard(g, 1).id, "pomada")
    T.eq(g.players[1].mana, 0, "pagou 1")
  end },

  { "Pomada numa criatura nunca cura mais do que o dano que ela tem", function(T)
    local g = new_game()
    local c = put(g, 1, "f_grande", 1)
    c.damage = 2
    T.ok(cast(g, 1, "pomada", { p = 1, slot = 1 }))
    T.eq(c.damage, 0)
    T.eq(events(g, "creature_heal")[1].amount, 2)
    local g2 = new_game()
    local sem = put(g2, 1, "f_grande", 1)
    T.ok(cast(g2, 1, "pomada", { p = 1, slot = 1 }))
    T.eq(sem.damage, 0)
    T.eq(#events(g2, "creature_heal"), 0, "sem dano, nada a curar")
  end },

  { "Pomada no jogador recupera 3 de vida", function(T)
    local g = new_game()
    g.players[1].life = 15
    T.ok(cast(g, 1, "pomada", { p = 1, zone = "jogador" }))
    T.eq(g.players[1].life, 18)
    local heals = events(g, "player_heal")
    T.eq(#heals, 1)
    T.eq(heals[1].p, 1); T.eq(heals[1].amount, 3); T.eq(heals[1].source, "pomada")
  end },

  { "Pomada no jogador respeita o teto de 20 e não faz nada com a vida cheia", function(T)
    local g = new_game()
    g.players[1].life = 19
    T.ok(cast(g, 1, "pomada", { p = 1, zone = "jogador" }))
    T.eq(g.players[1].life, Game.MAX_LIFE)
    T.eq(events(g, "player_heal")[1].amount, 1)
    T.ok(cast(g, 1, "pomada", { p = 1, zone = "jogador" }))
    T.eq(g.players[1].life, Game.MAX_LIFE)
    T.eq(#events(g, "player_heal"), 1, "com a vida cheia não há cura")
    T.eq(last_discard(g, 1).id, "pomada", "mesmo assim vai para o descarte")
  end },

  { "Pomada pode mirar o adversário", function(T)
    local g = new_game()
    g.players[2].life = 10
    T.ok(cast(g, 1, "pomada", { p = 2, zone = "jogador" }))
    T.eq(g.players[2].life, 13)
    T.eq(g.players[1].life, Game.MAX_LIFE)
  end },

  { "Pomada é Instantânea: resolve na hora e não gasta a vez", function(T)
    local g = new_game()
    local vez, active = g.vez, g.active
    g.players[1].life = 15
    T.ok(cast(g, 1, "pomada", { p = 1, zone = "jogador" }))
    T.eq(g.players[1].life, 18, "resolveu sem passar pela pilha")
    T.eq(g:stack_open(), false)
    T.eq(g.active, active, "a vez continua com quem jogou")
    T.eq(g.vez, vez, "não conta para o período")
  end },

  { "Pomada com a pilha aberta resolve por cima da pilha, sem fechá-la", function(T)
    local g = new_game()
    local c = put(g, 1, "f_tres", 1)
    put(g, 2, "f_grande", 1)
    assert(g:act(1, { type = "attack", attackers = { 1 } }))
    assert(g:act(1, { type = "pass" }))
    -- O defensor responde com um Dardo no atacante e, antes de resolver,
    -- o atacante usa a Pomada para salvá-lo depois do dano.
    T.ok(cast(g, 2, "dardo", { p = 1, slot = 1 }))
    assert(g:act(2, { type = "pass" }))
    T.eq(g.active, 1)
    c.damage = 1
    T.ok(cast(g, 1, "pomada", { p = 1, slot = 1 }), "Instantâneo com a pilha aberta")
    T.eq(c.damage, 0, "curou na hora")
    T.eq(#g.stack, 2, "a pilha continua com o ataque e o Dardo")
    T.eq(g.active, 1, "a vez não passou")
    assert(g:act(1, { type = "pass" }))
    T.eq(g:stack_open(), false, "sem nada novo na pilha, o passe resolve")
    T.eq(g:creature_at(1, 1), nil, "o Dardo ainda mata a criatura de 3 de vida")
  end },

  { "Pomada recusa jogada sem alvo ou com espaço vazio", function(T)
    local g = new_game()
    T.eq(cast(g, 1, "pomada", nil), false, "sem alvo")
    T.eq(cast(g, 1, "pomada", { p = 2, slot = 1 }), false, "espaço vazio")
    T.eq(cast(g, 1, "pomada", { p = 3, zone = "jogador" }), false, "jogador inexistente")
    T.eq(#events(g, "instant"), 0)
  end },

  ----------------------------------------------------------------------------
  -- Dardo do sono
  ----------------------------------------------------------------------------

  { "Dardo do sono: a criatura fica com velocidade 0 nesta e na próxima rodada", function(T)
    local g = new_game()
    local c = put(g, 2, "f_grande", 1)
    local round = g.round
    T.ok(cast_and_resolve(g, 1, "dardo_do_sono", { p = 2, slot = 1 }))
    T.eq(g:speed(c, "attack"), 0); T.eq(g:speed(c, "block"), 0)
    next_round(g)
    T.eq(g.round, round + 1)
    T.eq(g:speed(c, "attack"), 0, "ainda dorme na próxima rodada")
    next_round(g)
    T.eq(g.round, round + 2)
    T.eq(g:speed(c, "attack"), 1, "acorda na rodada seguinte")
    T.eq(g:speed(c, "block"), 1)
  end },

  { "Dardo do sono: a criatura não golpeia bloqueando nesta rodada nem atacando na próxima", function(T)
    local g = new_game()
    local a = put(g, 1, "f_grande", 1)
    local c = put(g, 2, "f_grande", 1)
    T.ok(cast_and_resolve(g, 1, "dardo_do_sono", { p = 2, slot = 1 }))
    -- Rodada 1: a vez volta ao jogador 1, que ataca; a criatura adormecida
    -- bloqueia sem revidar.
    assert(g:act(2, { type = "pass" }))
    fight(g, 1, { 1 }, { { 1, 1 } })
    T.eq(c.damage, 2, "leva o golpe do atacante")
    T.eq(a.damage, 0, "não revida")
    -- Rodada 2: o jogador 2 ataca com ela e nada chega ao jogador 1.
    next_round(g)
    T.eq(g.attacker, 2)
    local life = g.players[1].life
    fight(g, 2, { 1 })
    T.eq(g.players[1].life, life, "atacando, também não golpeia")
    -- Rodada 3: acordou e volta a golpear ao bloquear.
    next_round(g)
    T.eq(g.attacker, 1)
    fight(g, 1, { 1 }, { { 1, 1 } })
    T.eq(a.damage, 2, "revidou")
    T.eq(c.damage, 4)
  end },

  { "Dardo do sono deixa o Morcego (velocidade 2) em 0", function(T)
    local g = new_game()
    load_criaturas()
    local m = put(g, 2, "morcego", 1)
    T.eq(g:speed(m, "attack"), 2)
    T.ok(cast_and_resolve(g, 1, "dardo_do_sono", { p = 2, slot = 1 }))
    T.eq(g:speed(m, "attack"), 0)
    T.eq(g:speed(m, "block"), 0)
    next_round(g); next_round(g)
    T.eq(g:speed(m, "attack"), 2, "volta à velocidade 2 depois")
  end },

  { "Dardo do sono recusa jogada sem alvo ou mirando um jogador", function(T)
    local g = new_game()
    T.eq(cast(g, 1, "dardo_do_sono", nil), false)
    T.eq(cast(g, 1, "dardo_do_sono", { p = 2, zone = "jogador" }), false)
    T.eq(g:stack_open(), false)
  end },

  { "Dardo do sono com alvo perdido não faz nada", function(T)
    local g = new_game()
    put(g, 2, "f_grande", 1)
    T.ok(cast(g, 1, "dardo_do_sono", { p = 2, slot = 1 }))
    g.players[2].field[1] = nil
    local outra = put(g, 2, "f_grande", 1)
    assert(g:act(1, { type = "pass" }))
    assert(g:act(2, { type = "pass" }))
    T.eq(g:speed(outra, "attack"), 1)
    T.eq(#events(g, "fizzle"), 1)
    T.eq(last_discard(g, 1).id, "dardo_do_sono")
  end },
}
