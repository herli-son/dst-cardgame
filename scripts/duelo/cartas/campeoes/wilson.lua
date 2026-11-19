-- wilson: campeão do deck do Wilson, nível 1 (#20). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.
-- Nível 2 e "sobe de nível" ficam para a US #49.

local Cards = require("duelo/core/cards")

local MAQUINA = "maquina_de_ciencia"

-- Tira do baralho a primeira Máquina de Ciência a partir do topo (fim da lista).
local function buscar_maquina(game, p)
  local deck = game.players[p].deck
  for i = #deck, 1, -1 do
    if deck[i].id == MAQUINA then return table.remove(deck, i) end
  end
end

return Cards.define{
  id = "wilson", name = "Wilson", kind = "criatura", cost = 4, numero = 10,
  atk = 1, hp = 3,
  campeao = true, nivel = 1, sobrevivente = true,
  -- Ao entrar em jogo: se você não tiver uma Máquina de Ciência em jogo, procure
  -- uma no seu baralho (só no baralho), mostre-a (evento "reveal") e coloque-a
  -- em jogo; embaralhe o baralho. Com a zona de estruturas cheia, ela entra pela
  -- regra de substituição do motor (escolha "substituir_estrutura": o dono
  -- escolhe qual destruir ou nenhuma, e sem substituição a Máquina vai para o
  -- descarte). Sem Máquina no baralho, nada acontece e o baralho não é
  -- embaralhado (o jogador não viu a ordem dele).
  on_play = function(game, wilson)
    local p = wilson.owner
    if game:has_structure(p, MAQUINA) then return end
    local card = buscar_maquina(game, p)
    if card == nil then return end
    game:emit{ t = "reveal", p = p, card_uid = card.uid, id = card.id, source = "baralho", by = wilson.def.id }
    game:enter_structure(p, card)
    game:shuffle_deck(p)
  end,
  text = "Campeão. Sobrevivente. Ao entrar em jogo: se você não tiver uma Máquina de "
    .. "Ciência em jogo, procure uma no seu baralho, mostre-a e coloque-a em jogo. "
    .. "Embaralhe o baralho.",
}
