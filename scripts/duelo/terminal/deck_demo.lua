-- Cartas de exemplo e baralhos de demonstração para jogar pelo terminal.
-- Lua 5.1 puro. As cartas daqui são só para testar o motor; não são as cartas
-- do jogo.
--
-- Interface:
--   local Demo = require("duelo/terminal/deck_demo")
--   Demo.define()            registra as cartas (pode ser chamado mais de uma vez)
--   Demo.decks()             -> { baralho1, baralho2 }, cada um com 30 cartas
--   Demo.IDS                 lista dos ids definidos

local Cards = require("duelo/core/cards")

local Demo = {}

local function e_criatura(o)
  return o ~= nil and o.uid ~= nil and o.def ~= nil and o.def.kind == "criatura"
end

function Demo.define()
  Cards.define{ id = "demo_coelho", name = "Coelho", kind = "criatura", cost = 1, atk = 2, hp = 1,
    kw = { fragil = true } }
  Cards.define{ id = "demo_cao", name = "Cao de caca", kind = "criatura", cost = 2, atk = 2, hp = 2,
    kw = { agressivo = true } }
  Cards.define{ id = "demo_aranha", name = "Aranha", kind = "criatura", cost = 2, atk = 2, hp = 3, speed = 2,
    types = { aranha = true } }
  Cards.define{ id = "demo_lobo", name = "Lobo", kind = "criatura", cost = 3, atk = 3, hp = 3 }
  Cards.define{ id = "demo_beija_flor", name = "Beija-flor", kind = "criatura", cost = 3, atk = 1, hp = 2, speed = 3,
    text = "Golpeia duas vezes." }
  Cards.define{ id = "demo_lenhador", name = "Lenhador", kind = "criatura", cost = 3, atk = 2, hp = 4,
    sobrevivente = true, text = "Pode usar equipamentos." }
  Cards.define{ id = "demo_urso", name = "Urso", kind = "criatura", cost = 5, atk = 5, hp = 6 }
  Cards.define{ id = "demo_raio", name = "Raio", kind = "feitico", speed = "rapido", cost = 2,
    text = "Causa 3 de dano a uma criatura.",
    targets = function(g, p, action, objects)
      if not e_criatura(objects[1]) then return false, "escolha uma criatura como alvo" end
      return true
    end,
    on_cast = function(g, p, action, card, objects)
      g:damage_creature(objects[1], 3, nil, "raio")
    end }
  Cards.define{ id = "demo_curativo", name = "Curativo", kind = "feitico", speed = "instantaneo", cost = 1,
    text = "Um jogador recupera 3 de vida.",
    targets = function(g, p, action, objects)
      local o = objects[1]
      if o == nil or o.player == nil then return false, "escolha um jogador como alvo (eu ou ele)" end
      return true
    end,
    on_cast = function(g, p, action, card, objects)
      g:heal_player(objects[1].player, 3, "curativo")
    end }
  Cards.define{ id = "demo_tocha", name = "Tocha", kind = "estrutura", cost = 2,
    text = "Ativar: 1 de dano ao oponente, uma vez por rodada.",
    activation = { speed = "instantaneo", once_per_round = true },
    activate = function(g, p) g:damage_player(g.other(p), 1, "tocha") end }
  Cards.define{ id = "demo_lanca", name = "Lanca", kind = "equipamento", slot = "mao", cost = 2,
    atk_bonus = 2, text = "O portador ganha +2 de ataque." }
  Cards.define{ id = "demo_armadura", name = "Armadura de grama", kind = "equipamento", slot = "peito", cost = 1,
    hp_bonus = 2, text = "O portador ganha +2 de vida." }
end

Demo.IDS = { "demo_coelho", "demo_cao", "demo_aranha", "demo_lobo", "demo_beija_flor", "demo_lenhador",
  "demo_urso", "demo_raio", "demo_curativo", "demo_tocha", "demo_lanca", "demo_armadura" }

-- Quantidade de cada carta num baralho de 30.
local LISTA = {
  { "demo_coelho", 4 }, { "demo_cao", 3 }, { "demo_aranha", 3 }, { "demo_lobo", 3 },
  { "demo_beija_flor", 2 }, { "demo_lenhador", 3 }, { "demo_urso", 2 }, { "demo_raio", 3 },
  { "demo_curativo", 2 }, { "demo_tocha", 2 }, { "demo_lanca", 2 }, { "demo_armadura", 1 },
}

local function baralho()
  local d = {}
  for _, item in ipairs(LISTA) do
    for _ = 1, item[2] do d[#d + 1] = { id = item[1] } end
  end
  return d
end

function Demo.decks()
  Demo.define()
  return { baralho(), baralho() }
end

return Demo
