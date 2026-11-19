-- morcego: criatura neutra do MVP (#22). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

-- Ataque e vida por período (Game:period(): "manha" | "tarde" | "noite").
local MORCEGO = { manha = { 0, 1 }, tarde = { 1, 1 }, noite = { 2, 1 } }

return Cards.define{
  id = "morcego", name = "Morcego", kind = "criatura", cost = 1, numero = 4,
  atk = 0, hp = 1, speed = 2,
  kw = { agressivo = true },
  stats = function(game, c)
    local s = MORCEGO[game:period()] or MORCEGO.manha
    return s[1], s[2]
  end,
  text = "Agressivo. Velocidade 2. De manhã é 0/1, à tarde 1/1 e à noite 2/1.",
}
