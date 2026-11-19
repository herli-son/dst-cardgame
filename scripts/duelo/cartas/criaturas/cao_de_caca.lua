-- cao_de_caca: criatura neutra do MVP (#22). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

-- As variantes por estação ficam para a US #45.
return Cards.define{
  id = "cao_de_caca", name = "Cão de caça", kind = "criatura", cost = 2,
  atk = 2, hp = 2,
  kw = { agressivo = true },
  text = "Agressivo.",
}
