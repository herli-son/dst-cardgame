-- dardo: feitiço do MVP (#23). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

-- Alvo único em action.target, apontando uma criatura em campo (de qualquer
-- jogador). O motor já recusa espaço vazio e trata o alvo perdido.
local function alvo_criatura(game, p, action, objects)
  local t = action.target
  if t == nil or (t.zone or "criatura") ~= "criatura" or #objects ~= 1 then
    return false, "escolha uma criatura"
  end
  return true
end

return Cards.define{
  id = "dardo", name = "Dardo", kind = "feitico", cost = 2, numero = 30,
  speed = "rapido",
  targets = alvo_criatura,
  on_cast = function(game, p, action, card, objects)
    game:damage_creature(objects[1], 3, card, "dardo")
  end,
  text = "Rápido. Cause 3 de dano a uma criatura.",
}
