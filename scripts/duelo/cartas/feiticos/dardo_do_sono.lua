-- dardo_do_sono: feitiço do MVP (#23). Lua 5.1 puro.
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
  id = "dardo_do_sono", name = "Dardo do sono", kind = "feitico", cost = 2, numero = 32,
  speed = "rapido",
  targets = alvo_criatura,
  on_cast = function(game, p, action, card, objects)
    -- Velocidade fixada em 0: a criatura não golpeia, atacando nem bloqueando.
    -- until_round é inclusivo (Game:speed aplica o modificador enquanto
    -- game.round <= until_round), então round + 1 cobre o resto desta rodada e
    -- a próxima inteira; na seguinte a criatura volta à velocidade normal.
    game:add_speed_mod(objects[1], { set = 0, until_round = game.round + 1 })
  end,
  text = "Rápido. Uma criatura fica com Velocidade 0 até o fim da próxima rodada.",
}
