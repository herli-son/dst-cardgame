-- Cartas de simulação (#26): um conjunto só para testes, mais variado que o do
-- test_bot, para o simulador exercitar o motor inteiro. Lua 5.1 puro.
--
-- Interface:
--   local CartasSim = require("cartas_sim")
--   CartasSim.define()            registra as cartas (prefixo "sim_")
--   CartasSim.deck(variante)      baralho de 30 cartas: "agressivo" | "controle"
--   CartasSim.extra()             baralho extra (fichas)
--   CartasSim.decks()             { deck("agressivo"), deck("controle") }
--   CartasSim.extra_decks()       { extra(), extra() }
--
-- Só usa campos que o motor já suporta (ver o cabeçalho de cards.lua).

local Cards = require("duelo/core/cards")

local CartasSim = {}

-- O alvo é uma criatura em campo (não um jogador nem uma estrutura).
local function creature_target(g, p, action, objects)
  local o = objects[1]
  if o == nil or o.uid == nil or o.def == nil or o.def.kind ~= "criatura" then return false, "escolha uma criatura" end
  return true
end

-- O alvo é um jogador.
local function player_target(g, p, action, objects)
  local o = objects[1]
  if o == nil or o.player == nil then return false, "escolha um jogador" end
  return true
end

-- O alvo é uma criatura ou um jogador.
local function any_target(g, p, action, objects)
  local o = objects[1]
  if o == nil then return false, "escolha um alvo" end
  if o.player ~= nil then return true end
  if o.def == nil or o.def.kind ~= "criatura" then return false, "escolha uma criatura ou um jogador" end
  return true
end

function CartasSim.define()
  -- Criaturas simples, com Velocidade 0 a 3.
  Cards.define{ id = "sim_rato", kind = "criatura", cost = 1, atk = 1, hp = 1 }
  Cards.define{ id = "sim_lesma", kind = "criatura", cost = 1, atk = 2, hp = 3, speed = 0 }
  Cards.define{ id = "sim_lobo", kind = "criatura", cost = 2, atk = 3, hp = 2 }
  Cards.define{ id = "sim_corvo", kind = "criatura", cost = 2, atk = 2, hp = 1, speed = 2 }
  Cards.define{ id = "sim_pantera", kind = "criatura", cost = 4, atk = 3, hp = 3, speed = 3 }
  Cards.define{ id = "sim_urso", kind = "criatura", cost = 5, atk = 5, hp = 6 }
  -- Palavras-chave de bloqueio obrigatório.
  Cards.define{ id = "sim_coelho", kind = "criatura", cost = 1, atk = 2, hp = 1, kw = { fragil = true } }
  Cards.define{ id = "sim_cao", kind = "criatura", cost = 2, atk = 2, hp = 2, kw = { agressivo = true } }
  Cards.define{ id = "sim_porco", kind = "criatura", cost = 2, atk = 2, hp = 3, types = { porco = true } }
  Cards.define{ id = "sim_cacador", kind = "criatura", cost = 3, atk = 3, hp = 2, kw = { rival = "porco" } }
  -- Não ataca / não bloqueia.
  Cards.define{ id = "sim_muro", kind = "criatura", cost = 1, atk = 0, hp = 4, no_attack = true }
  Cards.define{ id = "sim_furtivo", kind = "criatura", cost = 2, atk = 3, hp = 1, no_block = true }
  -- Efeito de entrada com alvo escolhido na jogada.
  Cards.define{ id = "sim_lanceiro", kind = "criatura", cost = 3, atk = 2, hp = 2,
    play_targets = creature_target,
    on_play = function(g, c, objects)
      if objects then g:damage_creature(objects[1], 1, c, "lanceiro") end
    end }
  -- Ao morrer, cria uma ficha do baralho extra.
  Cards.define{ id = "sim_aranha", kind = "criatura", cost = 2, atk = 2, hp = 2,
    on_death = function(g, c) g:create_token(c.owner, "sim_aranhinha") end }
  Cards.define{ id = "sim_aranhinha", kind = "criatura", cost = 0, atk = 1, hp = 1 }
  -- Sobrevivente: porta equipamentos.
  Cards.define{ id = "sim_sobrevivente", kind = "criatura", cost = 3, atk = 2, hp = 3, sobrevivente = true }
  -- Golpear: recupera 1 de vida do dono.
  Cards.define{ id = "sim_curandeira", kind = "criatura", cost = 2, atk = 1, hp = 2,
    on_strike = function(g, c) g:heal_player(c.owner, 1, "curandeira") end }
  -- Sacrifício como custo.
  Cards.define{ id = "sim_golem", kind = "criatura", cost = 3, atk = 6, hp = 6, sacrifice = { count = 1 } }
  -- Ao morrer, o dono escolhe uma criatura sua para curar 2, ou nenhuma. As
  -- opções são montadas quando a escolha abre (prepare), com o campo daquele
  -- momento.
  Cards.define{ id = "sim_xama", kind = "criatura", cost = 2, atk = 1, hp = 3,
    on_death = function(g, c)
      local spec = { reason = "xama", allow_none = true }
      spec.prepare = function(gg)
        spec.options = {}
        for _, mine in ipairs(gg:creatures(c.owner)) do spec.options[#spec.options + 1] = mine.slot end
      end
      spec.resolve = function(gg, idx)
        if idx == nil then return end
        local alvo = gg:creature_at(c.owner, spec.options[idx])
        if alvo then gg:heal_creature(alvo, 2, nil, "xama") end
      end
      g:set_choice(c.owner, spec)
    end }
  -- Ao entrar, cria uma estrutura do baralho extra; com a zona cheia, o dono
  -- escolhe qual substituir ou nenhuma (escolha "substituir_estrutura").
  Cards.define{ id = "sim_construtor", kind = "criatura", cost = 2, atk = 1, hp = 2,
    on_play = function(g, c) g:create_token(c.owner, "sim_totem") end }
  Cards.define{ id = "sim_totem", kind = "estrutura", cost = 0,
    activation = { speed = "instantaneo", once_per_round = true },
    activate = function(g, p) g:heal_player(p, 1, "totem") end }

  -- Feitiços: um de cada tipo, com alvo.
  Cards.define{ id = "sim_faisca", kind = "feitico", speed = "instantaneo", cost = 1,
    targets = creature_target,
    on_cast = function(g, p, action, card, objects) g:damage_creature(objects[1], 1, nil, "faisca") end }
  Cards.define{ id = "sim_raio", kind = "feitico", speed = "rapido", cost = 2,
    targets = creature_target,
    on_cast = function(g, p, action, card, objects) g:damage_creature(objects[1], 3, nil, "raio") end }
  Cards.define{ id = "sim_meteoro", kind = "feitico", speed = "lento", cost = 3,
    targets = any_target,
    on_cast = function(g, p, action, card, objects)
      local o = objects[1]
      if o.player then g:damage_player(o.player, 4, "meteoro") else g:damage_creature(o, 4, nil, "meteoro") end
    end }
  -- Rápido que fere um jogador.
  Cards.define{ id = "sim_flecha", kind = "feitico", speed = "rapido", cost = 2,
    targets = player_target,
    on_cast = function(g, p, action, card, objects) g:damage_player(objects[1].player, 3, "flecha") end }
  Cards.define{ id = "sim_cura", kind = "feitico", speed = "instantaneo", cost = 1,
    targets = player_target,
    on_cast = function(g, p, action, card, objects) g:heal_player(objects[1].player, 3, "cura") end }

  -- Estruturas com efeito ativado uma vez por rodada.
  Cards.define{ id = "sim_tocha", kind = "estrutura", cost = 2,
    activation = { speed = "instantaneo", once_per_round = true },
    activate = function(g, p) g:damage_player(g.other(p), 1, "tocha") end }
  Cards.define{ id = "sim_altar", kind = "estrutura", cost = 3,
    activation = { speed = "rapido", once_per_round = true },
    targets = creature_target,
    activate = function(g, p, st, action, objects) g:damage_creature(objects[1], 1, nil, "altar") end }

  -- Equipamentos com durabilidade; o machado gasta 1 a cada Golpear.
  Cards.define{ id = "sim_machado", kind = "equipamento", slot = "mao", cost = 2, atk_bonus = 2, durability = 3,
    on_strike = function(g, holder, target, equip) g:wear(holder, equip.def.slot, 1) end }
  Cards.define{ id = "sim_armadura", kind = "equipamento", slot = "peito", cost = 1, hp_bonus = 2, durability = 2,
    on_strike = function(g, holder, target, equip) g:wear(holder, equip.def.slot, 1) end }
  -- Equipamento com efeito ativado (gasta durabilidade ao usar).
  Cards.define{ id = "sim_lanterna", kind = "equipamento", slot = "cabeca", cost = 2, durability = 2,
    activation = { speed = "instantaneo", once_per_round = true },
    activate = function(g, p, equip) g:damage_player(g.other(p), 1, "lanterna") end }
end

local DECKS = {
  agressivo = {
    sim_rato = 2, sim_lobo = 3, sim_corvo = 2, sim_coelho = 3, sim_cao = 2, sim_furtivo = 2,
    sim_pantera = 2, sim_aranha = 2, sim_golem = 1, sim_faisca = 2, sim_raio = 1, sim_meteoro = 1,
    sim_flecha = 2, sim_tocha = 1, sim_sobrevivente = 1, sim_machado = 1, sim_lanceiro = 1, sim_construtor = 1,
  },
  controle = {
    sim_lesma = 2, sim_muro = 2, sim_porco = 3, sim_cacador = 2, sim_urso = 2, sim_curandeira = 1,
    sim_xama = 2, sim_construtor = 2, sim_sobrevivente = 2, sim_aranha = 1, sim_lanceiro = 1, sim_cura = 2,
    sim_raio = 1, sim_meteoro = 2, sim_altar = 1, sim_tocha = 1, sim_machado = 1, sim_armadura = 1, sim_lanterna = 1,
  },
}

-- Baralho de 30 cartas; a ordem é fixa (o motor embaralha com o rng da partida).
function CartasSim.deck(variant)
  local spec = DECKS[variant or "agressivo"]
  assert(spec, "variante de baralho desconhecida: " .. tostring(variant))
  local ids = {}
  for id in pairs(spec) do ids[#ids + 1] = id end
  table.sort(ids)
  local deck = {}
  for _, id in ipairs(ids) do
    for _ = 1, spec[id] do deck[#deck + 1] = { id = id } end
  end
  assert(#deck == 30, "baralho " .. tostring(variant) .. " com " .. #deck .. " cartas")
  return deck
end

function CartasSim.extra()
  local extra = {}
  for _ = 1, 3 do extra[#extra + 1] = { id = "sim_aranhinha" } end
  for _ = 1, 3 do extra[#extra + 1] = { id = "sim_totem" } end
  return extra
end

function CartasSim.decks()
  return { CartasSim.deck("agressivo"), CartasSim.deck("controle") }
end

function CartasSim.extra_decks()
  return { CartasSim.extra(), CartasSim.extra() }
end

return CartasSim
