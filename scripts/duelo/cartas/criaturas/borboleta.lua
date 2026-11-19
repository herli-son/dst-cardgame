-- borboleta: criatura neutra do MVP (#22). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

return Cards.define{
  id = "borboleta", name = "Borboleta", kind = "criatura", cost = 1,
  atk = 0, hp = 1,
  kw = { fragil = true },
  on_death = function(game, c)
    game:heal_player(c.owner, 2, "borboleta")
  end,
  text = "Frágil. Ao morrer, o dono recupera 2 de vida.",
}
