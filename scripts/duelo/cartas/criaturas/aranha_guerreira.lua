-- aranha_guerreira: criatura do deck do Webber (#21). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

return Cards.define{
  id = "aranha_guerreira", name = "Aranha guerreira", kind = "criatura", cost = 3, numero = 22,
  atk = 2, hp = 4, speed = 2,
  types = { aranha = true },
  kw = { agressivo = true },
  text = "Aranha. Agressiva. Velocidade 2.",
}
