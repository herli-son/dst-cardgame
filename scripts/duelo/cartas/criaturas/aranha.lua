-- aranha: criatura do deck do Webber (#21). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

-- Está no baralho principal e também é criada pelo Webber: a criação tira a
-- cópia do baralho extra (regra do motor, ver fichas.lua).
return Cards.define{
  id = "aranha", name = "Aranha", kind = "criatura", cost = 1, numero = 21,
  atk = 2, hp = 1,
  types = { aranha = true },
  kw = { agressivo = true },
  text = "Aranha. Agressiva.",
}
