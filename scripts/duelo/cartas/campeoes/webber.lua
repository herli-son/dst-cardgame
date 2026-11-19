-- webber: Campeão do deck do Webber (#21), nível 1. Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

-- Fora desta versão: "Ativar, 1 vez por rodada, gastando a vez: evolua uma Casa
-- de aranha" (US #49; a Casa de aranha está fora do MVP), o nível 2 e "sobe de
-- nível". O text diz só o que vale agora.
return Cards.define{
  id = "webber", name = "Webber", kind = "criatura", cost = 3, numero = 20,
  campeao = true, sobrevivente = true,
  atk = 1, hp = 3,
  types = { aranha = true },
  -- Ao jogar: cria 1 Aranha. No motor, on_play roda ao entrar em campo (também
  -- por efeito, como reviver), igual às outras cartas com "Ao jogar". A cópia sai
  -- do baralho extra do dono; sem cópia ou sem espaço em campo, nada acontece
  -- (ver fichas.lua).
  on_play = function(game, c)
    game:create_token(c.owner, "aranha")
  end,
  -- Aranhas do adversário não podem bloquear o Webber (restrição de bloqueio do
  -- motor: vale no bloqueio declarado, nos obrigatórios e no salto da Guarda).
  cannot_be_blocked_by = function(game, a, d)
    return d.owner ~= a.owner and d.def.types.aranha == true
  end,
  text = "Campeão. Sobrevivente. Aranha. Ao jogar: crie 1 Aranha. "
    .. "Aranhas do adversário não podem bloquear o Webber.",
}
