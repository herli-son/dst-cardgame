-- armadura_de_grama: equipamento básico do deck do Wilson (#20). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos nos cabeçalhos de cards.lua e equipamentos.lua.

local Cards = require("duelo/core/cards")

return Cards.define{
  id = "armadura_de_grama", name = "Armadura de grama", kind = "equipamento", cost = 1, numero = 15,
  slot = "peito", hp_bonus = 2, durability = 2,
  -- Sem efeito: a durabilidade gasta 1 por golpe recebido (regra do motor).
  text = "Peito. O portador ganha +2 de vida. Durabilidade 2.",
}
