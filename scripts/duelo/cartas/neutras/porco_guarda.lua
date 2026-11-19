-- porco_guarda: criatura neutra do MVP (#22). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

-- A Guarda (o salto para o próximo atacante sem bloqueador) é regra do motor:
-- ver combate.lua. A carta só carrega a palavra-chave.
return Cards.define{
  id = "porco_guarda", name = "Porco guarda", kind = "criatura", cost = 5,
  atk = 2, hp = 7,
  types = { porco = true },
  kw = { guarda = true },
  text = "Porco. Guarda: ao bloquear e sobreviver, passa a bloquear também o "
    .. "próximo atacante à direita que ficou sem bloqueador, uma vez por combate.",
}
