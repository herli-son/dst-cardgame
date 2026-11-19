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
}
