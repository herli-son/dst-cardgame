-- Ganchos do motor ligados à vida das criaturas (US #129): aura_hp (bônus de
-- vida contínuo por aura). Testados com cartas de teste próprias.
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local function define_test_cards()
  Cards.define{ id = "v_rato", kind = "criatura", cost = 0, atk = 1, hp = 1 }
  Cards.define{ id = "v_tipo", kind = "criatura", cost = 0, atk = 1, hp = 1, types = { bicho = true } }
  Cards.define{ id = "v_muro", kind = "criatura", cost = 0, atk = 1, hp = 5 }
  -- Aura: +1 de vida para as criaturas do tipo "bicho" do dono, ela inclusa.
  Cards.define{ id = "v_aura", kind = "criatura", cost = 0, atk = 0, hp = 2, types = { bicho = true },
    aura_hp = function(g, fonte, alvo)
      if alvo.def.types.bicho then return 1 end
      return 0
    end }
  -- Aura para todas as criaturas do dono, sem filtro.
  Cards.define{ id = "v_aura_geral", kind = "criatura", cost = 0, atk = 0, hp = 1,
    aura_hp = function() return 2 end }
end

local function new_game()
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "v_rato" }; d2[i] = { id = "v_rato" } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function put(g, p, id, slot)
  return g:place_creature(p, { id = id, uid = g:next_uid() }, slot)
end

local function events(g, t)
  local list = {}
  for _, ev in ipairs(g.events) do if ev.t == t then list[#list + 1] = ev end end
  return list
end

return {
  { "aura_hp soma na vida das criaturas do dono que a aura escolhe, a fonte inclusa", function(T)
    local g = new_game()
    local tipo = put(g, 1, "v_tipo", 1)
    local rato = put(g, 1, "v_rato", 2)
    local alheio = put(g, 2, "v_tipo", 1)
    T.eq(g:hp(tipo), 1)
    local aura = put(g, 1, "v_aura", 3)
    T.eq(g:hp(tipo), 2, "criatura do tipo do dono")
    T.eq(g:hp(aura), 3, "a própria fonte")
    T.eq(g:hp(rato), 1, "fora do filtro da aura")
    T.eq(g:hp(alheio), 1, "criatura do adversário")
  end },

  { "auras de fontes diferentes somam", function(T)
    local g = new_game()
    local tipo = put(g, 1, "v_tipo", 1)
    put(g, 1, "v_aura", 2); put(g, 1, "v_aura", 3); put(g, 1, "v_aura_geral", 4)
    T.eq(g:hp(tipo), 5)
    T.eq(g:hp(g:creature_at(1, 2)), 2 + 2 + 2, "uma aura do tipo vale para a outra, e a geral também")
  end },

  { "a aura vale com os bônus de equipamento e com stats", function(T)
    local g = new_game()
    Cards.define{ id = "v_sobrev", kind = "criatura", cost = 0, atk = 1, hp = 1, sobrevivente = true,
      stats = function() return 1, 2 end }
    Cards.define{ id = "v_colete", kind = "equipamento", cost = 0, slot = "peito", hp_bonus = 3 }
    local c = put(g, 1, "v_sobrev", 1)
    g:equip(c, { id = "v_colete", uid = g:next_uid() })
    put(g, 1, "v_aura_geral", 2)
    T.eq(g:hp(c), 2 + 3 + 2)
  end },

  { "quando a fonte sai de campo, o dano marcado que vira letal mata no estado estável", function(T)
    local g = new_game()
    local tipo = put(g, 1, "v_tipo", 1)
    local aura = put(g, 1, "v_aura", 2)
    g:damage_creature(tipo, 1, nil, "teste")
    g:settle()
    T.eq(g:creature_at(1, 1), tipo, "com a aura, 1 de dano em 2 de vida não mata")
    g:kill(aura, "teste")
    T.eq(g:creature_at(1, 2), nil)
    g:settle()
    T.eq(g:creature_at(1, 1), nil, "sem a aura, o dano é igual à vida e a criatura morre")
    local deaths = events(g, "death")
    T.eq(#deaths, 2)
    T.eq(deaths[2].reason, "dano")
    T.eq(deaths[2].killer_uid, nil)
  end },

  { "a morte da fonte em combate leva junto quem só vivia pela aura, na mesma verificação", function(T)
    local g = new_game()
    -- Atacante 5/5 do adversário mata a aura (0/3) no bloqueio; a criatura do
    -- tipo já tinha 1 de dano em 2 de vida.
    local tipo = put(g, 2, "v_tipo", 1)
    put(g, 2, "v_aura", 2)
    g:damage_creature(tipo, 1, nil, "teste")
    Cards.define{ id = "v_urso", kind = "criatura", cost = 0, atk = 5, hp = 5 }
    local urso = put(g, 1, "v_urso", 1)
    T.ok(g:act(1, { type = "attack", attackers = { 1 } }))
    T.ok(g:act(1, { type = "pass" }))
    T.ok(g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 2 } } }))
    T.ok(g:act(2, { type = "pass" }))
    T.ok(g:act(1, { type = "pass" }))
    T.eq(g:creature_at(2, 2), nil, "a aura morreu")
    T.eq(g:creature_at(2, 1), nil, "a criatura do tipo morreu junto, sem outro dano")
    T.eq(g:creature_at(1, 1), urso)
  end },

  { "uma criatura que sai e volta ganha a aura de novo (vida máxima sempre recalculada)", function(T)
    local g = new_game()
    local aura = put(g, 1, "v_aura", 1)
    local tipo = put(g, 1, "v_tipo", 2)
    T.eq(g:hp(tipo), 2)
    g:remove_creature(aura, "hand", "teste")
    T.eq(g:hp(tipo), 1)
    put(g, 1, "v_aura", 1)
    T.eq(g:hp(tipo), 2)
  end },
}
