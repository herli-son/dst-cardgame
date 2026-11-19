-- passaro: criatura neutra do MVP (#22). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

return Cards.define{
  id = "passaro", name = "Pássaro", kind = "criatura", cost = 1, numero = 5,
  atk = 0, hp = 1,
  kw = { fragil = true },
  -- Reage à entrada de qualquer criatura Agressiva, de qualquer jogador, jogada
  -- ou criada. O abate dispara o "ao morrer" normalmente; a compra vem depois.
  on_any_enter = function(game, passaro, nova)
    if not nova.def.kw.agressivo then return end
    game:kill(passaro, "passaro")
    game:draw(passaro.owner, 1)
  end,
  text = "Frágil. Quando uma criatura Agressiva entra em jogo, abata o Pássaro "
    .. "e o dono dele compra 1 carta.",
}
