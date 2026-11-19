-- armadura_de_madeira: equipamento básico do deck do Wilson (#20). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos nos cabeçalhos de cards.lua e equipamentos.lua.

local Cards = require("duelo/core/cards")

return Cards.define{
  id = "armadura_de_madeira", name = "Armadura de madeira", kind = "equipamento", cost = 2, numero = 16,
  slot = "peito", hp_bonus = 1, durability = 3,
  -- O portador recebe 1 de dano a menos de cada fonte (damage_creature). Um golpe
  -- reduzido a zero ainda gasta 1 de durabilidade.
  damage_reduction = 1,
  text = "Peito. O portador ganha +1 de vida e recebe 1 de dano a menos de cada fonte. "
    .. "Durabilidade 3.",
}
