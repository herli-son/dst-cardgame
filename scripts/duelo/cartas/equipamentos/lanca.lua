-- lanca: equipamento básico do deck do Wilson (#20). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos nos cabeçalhos de cards.lua e equipamentos.lua.

local Cards = require("duelo/core/cards")

return Cards.define{
  id = "lanca", name = "Lança", kind = "equipamento", cost = 3, numero = 13,
  slot = "mao", atk_bonus = 3, durability = 6,
  -- Sem efeito: a durabilidade gasta 1 por golpe dado (regra do motor).
  text = "Mão. O portador ganha +3 de ataque. Durabilidade 6.",
}
