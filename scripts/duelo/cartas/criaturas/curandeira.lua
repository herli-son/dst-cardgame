-- curandeira: criatura do deck do Webber (#129). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

-- "Sua aranha": aranha (types.aranha) do dono da Curandeira, ela inclusa.
local function aranha_sua(fonte, c)
  return c.owner == fonte.owner and c.def.types.aranha == true
end

return Cards.define{
  id = "curandeira", name = "Curandeira", kind = "criatura", cost = 4, numero = 23,
  atk = 0, hp = 4,
  types = { aranha = true },
  -- +1 de vida para as aranhas do dono enquanto ela está em campo (a própria
  -- Curandeira fica 0/5). Quando ela sai, a vida volta e uma aranha com dano
  -- igual à vida base morre no estado estável (regra do motor, ver Game:hp).
  aura_hp = function(game, fonte, alvo)
    if aranha_sua(fonte, alvo) then return 1 end
    return 0
  end,
  -- Quando uma aranha do dono sobrevive a uma fonte de dano, cura 2 dela, na
  -- hora (ver fire_survive_effects em combate.lua). Cada Curandeira em campo
  -- cura 2: duas Curandeiras curam 4.
  on_survive_damage = function(game, fonte, c, amount, source)
    if aranha_sua(fonte, c) then game:heal_creature(c, 2, fonte, "curandeira") end
  end,
  text = "Aranha. Suas aranhas, incluindo esta, têm +1 de vida. "
    .. "Quando uma aranha sua sobreviver a dano, cure 2 dela.",
}
