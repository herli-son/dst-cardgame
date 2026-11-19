-- machado: equipamento básico do deck do Wilson (#20). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos nos cabeçalhos de cards.lua e equipamentos.lua.

local Cards = require("duelo/core/cards")

return Cards.define{
  id = "machado", name = "Machado", kind = "equipamento", cost = 2, numero = 12,
  slot = "mao", atk_bonus = 2, durability = 4,
  -- Ao atacar (o portador é declarado atacante): a fogueira do dono ganha +1.
  -- De dia o bônus fica guardado e entra quando a noite desta rodada começar;
  -- à noite soma na hora (Game:fogueira_bonus cuida dos dois casos).
  on_attack = function(game, portador)
    game:fogueira_bonus(portador.owner, 1)
  end,
  text = "Mão. O portador ganha +2 de ataque. Durabilidade 4. Ao atacar: sua fogueira "
    .. "começa a noite desta rodada com +1 (se já for noite, ganha +1 agora).",
}
