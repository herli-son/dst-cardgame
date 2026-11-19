-- Criaturas neutras do MVP (#22): cartas comuns aos dois baralhos. Lua 5.1 puro.
-- Carregar o módulo registra as cartas no motor (Cards.define) e devolve a
-- lista dos ids registrados, na ordem do documento.
--
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

local ids = {}

local function define(def)
  Cards.define(def)
  ids[#ids + 1] = def.id
  return def
end

----------------------------------------------------------------------------
-- Porcos
----------------------------------------------------------------------------

define{
  id = "porco", name = "Porco", kind = "criatura", cost = 4,
  atk = 4, hp = 5,
  types = { porco = true },
  text = "Porco. Sem efeito.",
}

-- A Guarda (o salto para o próximo atacante sem bloqueador) é regra do motor:
-- ver combate.lua. A carta só carrega a palavra-chave.
define{
  id = "porco_guarda", name = "Porco guarda", kind = "criatura", cost = 5,
  atk = 2, hp = 7,
  types = { porco = true },
  kw = { guarda = true },
  text = "Porco. Guarda: ao bloquear e sobreviver, passa a bloquear também o "
    .. "próximo atacante à direita que ficou sem bloqueador, uma vez por combate.",
}

----------------------------------------------------------------------------
-- Cão de caça
----------------------------------------------------------------------------

-- As variantes por estação ficam para a US #45.
define{
  id = "cao_de_caca", name = "Cão de caça", kind = "criatura", cost = 2,
  atk = 2, hp = 2,
  kw = { agressivo = true },
  text = "Agressivo.",
}

return ids
