-- pomada: feitiço do MVP (#23). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

-- Dois modos, decididos pelo alvo único em action.target:
--   { p, slot }                  cura 3 de dano de uma criatura (de qualquer jogador)
--   { p, zone = "jogador" }      o jogador p (qualquer um dos dois) recupera 3 de vida
-- O motor já confere o formato, recusa espaço vazio e trata o alvo perdido;
-- objects[1] chega como a criatura ou como { player = p }.
local function alvo_criatura_ou_jogador(game, p, action, objects)
  local t = action.target
  if t == nil or #objects ~= 1 then return false, "escolha uma criatura ou um jogador" end
  local zone = t.zone or "criatura"
  if zone ~= "criatura" and zone ~= "jogador" then
    return false, "escolha uma criatura ou um jogador"
  end
  return true
end

return Cards.define{
  id = "pomada", name = "Pomada", kind = "feitico", cost = 1, numero = 31,
  speed = "instantaneo",
  targets = alvo_criatura_ou_jogador,
  on_cast = function(game, p, action, card, objects)
    local alvo = objects[1]
    if alvo.player then
      game:heal_player(alvo.player, 3, "pomada")
    else
      game:heal_creature(alvo, 3, card, "pomada")
    end
  end,
  text = "Instantâneo. Cure 3 de dano de uma criatura ou um jogador recupera 3 de vida.",
}
