-- Ganchos do motor ligados à vida das criaturas (US #129): aura_hp (bônus de
-- vida contínuo por aura) e on_survive_damage ("sobreviveu a dano"). Testados
-- com cartas de teste próprias.
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local log

local function define_test_cards()
  log = {}
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
  -- Ouvinte: anota quem sobreviveu a quanto dano e cura 1 dela.
  Cards.define{ id = "v_ouvinte", kind = "criatura", cost = 0, atk = 0, hp = 3,
    on_survive_damage = function(g, ouvinte, c, amount, source)
      log[#log + 1] = ouvinte.slot .. ":" .. c.def.id .. "@" .. c.slot .. "-" .. amount
        .. (source and ("<" .. source.def.id) or "")
      g:heal_creature(c, 1, ouvinte, "ouvinte")
    end }
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
    -- As duas mortes saem na verificação da fase, antes do fim do combate.
    local fim, mortes = nil, 0
    for i, ev in ipairs(g.events) do
      if ev.t == "combat_end" and fim == nil then fim = i end
      if ev.t == "death" and ev.uid == tipo.uid then mortes = i end
    end
    T.ok(fim ~= nil and mortes > 0 and mortes < fim, "morte da aliada antes de combat_end")
  end },

  { "um ouvinte com dano letal pendente não roda", function(T)
    local g = new_game()
    local ouvinte = put(g, 1, "v_ouvinte", 1)
    local muro = put(g, 1, "v_muro", 2)
    -- Dano letal no ouvinte sem passar por settle: ele ainda está em campo,
    -- mas fora de jogo (dano >= vida), igual ao critério de in_play.
    ouvinte.damage = 3
    g:damage_creature(muro, 1, nil, "teste")
    T.eq(#log, 0, "não cura nem anota")
    T.eq(muro.damage, 1)
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

  { "on_survive_damage dispara nas criaturas do dono quando uma sobrevive a dano, a própria inclusa", function(T)
    local g = new_game()
    local muro = put(g, 1, "v_muro", 1)
    local ouv = put(g, 1, "v_ouvinte", 2)
    put(g, 2, "v_ouvinte", 1)
    T.eq(g:damage_creature(muro, 2, nil, "teste"), 2)
    T.eq(#log, 1, "só o ouvinte do dono")
    T.eq(log[1], "2:v_muro@1-2")
    T.eq(muro.damage, 1, "curado em 1 pelo ouvinte")
    T.eq(#events(g, "creature_heal"), 1)
    log = {}
    g:damage_creature(ouv, 1, muro, "teste")
    T.eq(log[1], "2:v_ouvinte@2-1<v_muro", "a própria ouvinte, com a fonte")
    T.eq(ouv.damage, 0)
  end },

  { "dano letal não conta como sobreviver", function(T)
    local g = new_game()
    local rato = put(g, 1, "v_rato", 1)
    put(g, 1, "v_ouvinte", 2)
    g:damage_creature(rato, 1, nil, "teste")
    T.eq(#log, 0)
    g:settle()
    T.eq(g:creature_at(1, 1), nil)
    local muro = put(g, 1, "v_muro", 1)
    g:damage_creature(muro, 9, nil, "teste")
    T.eq(#log, 0, "dano acima da vida")
  end },

  { "dano reduzido a zero não é sofrer dano", function(T)
    local g = new_game()
    Cards.define{ id = "v_sobrev", kind = "criatura", cost = 0, atk = 1, hp = 5, sobrevivente = true }
    Cards.define{ id = "v_placa", kind = "equipamento", cost = 0, slot = "peito", damage_reduction = 1 }
    local c = put(g, 1, "v_sobrev", 1)
    g:equip(c, { id = "v_placa", uid = g:next_uid() })
    put(g, 1, "v_ouvinte", 2)
    T.eq(g:damage_creature(c, 1, nil, "teste"), 0)
    T.eq(#events(g, "damage_absorbed"), 1)
    T.eq(#log, 0)
    T.eq(g:damage_creature(c, 2, nil, "teste"), 1)
    T.eq(log[1], "2:v_sobrev@1-1", "o dano informado é o marcado, depois da redução")
  end },

  { "a aura conta para sobreviver: 1 de dano em 1 de vida base com +1 de aura", function(T)
    local g = new_game()
    local tipo = put(g, 1, "v_tipo", 1)
    put(g, 1, "v_aura", 2)
    put(g, 1, "v_ouvinte", 3)
    g:damage_creature(tipo, 1, nil, "teste")
    T.eq(#log, 1)
    T.eq(tipo.damage, 0, "curada")
    g:settle()
    T.eq(g:creature_at(1, 1), tipo)
  end },

  { "em combate, dispara por golpe, na hora, antes das mortes da fase", function(T)
    local g = new_game()
    Cards.define{ id = "v_lobo", kind = "criatura", cost = 0, atk = 2, hp = 1 }
    put(g, 1, "v_lobo", 1)
    local muro = put(g, 2, "v_muro", 1)
    put(g, 2, "v_ouvinte", 2)
    T.ok(g:act(1, { type = "attack", attackers = { 1 } }))
    T.ok(g:act(1, { type = "pass" }))
    T.ok(g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 1 } } }))
    T.ok(g:act(2, { type = "pass" }))
    T.ok(g:act(1, { type = "pass" }))
    T.eq(#log, 1, "o lobo morreu e é do adversário: só o muro conta")
    T.eq(log[1], "2:v_muro@1-2<v_lobo")
    T.eq(muro.damage, 1, "curado em 1 na hora do golpe")
    T.eq(g:creature_at(1, 1), nil, "o lobo (2/1) morreu com o revide")
    local evs = {}
    for _, ev in ipairs(g.events) do
      if ev.t == "creature_heal" or ev.t == "death" then evs[#evs + 1] = ev.t end
    end
    T.eq(evs[1], "creature_heal", "a cura vem antes da morte da fase")
    T.eq(evs[2], "death")
  end },
}
