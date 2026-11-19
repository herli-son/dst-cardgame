-- porco: criatura neutra do MVP (#22). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

return Cards.define{
  id = "porco", name = "Porco", kind = "criatura", cost = 4,
  atk = 4, hp = 5,
  types = { porco = true },
  text = "Porco. Sem efeito.",
}
