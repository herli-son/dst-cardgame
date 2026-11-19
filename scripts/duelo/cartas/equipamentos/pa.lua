-- pa: equipamento básico do deck do Wilson (#20). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos nos cabeçalhos de cards.lua e equipamentos.lua.

local Cards = require("duelo/core/cards")

return Cards.define{
  id = "pa", name = "Pá", kind = "equipamento", cost = 1, numero = 14,
  slot = "mao", atk_bonus = 1, durability = 1,
  -- Golpear marca a Pá como pronta nesta rodada (marca booleana na instância
  -- equipada: golpes a mais na mesma rodada não mudam nada). A marca some no fim
  -- da rodada (ela guarda a rodada) e quando a Pá sai da criatura (a instância
  -- deixa de existir; reequipar cria outra, sem marca).
  on_strike = function(game, portador, alvo, equip)
    equip.pronta = game.round
  end,
  -- Ativar (opcional, nunca abre escolha): fora do combate, com a pilha vazia,
  -- na vez do dono; consome a marca e compra 1 carta. Instantâneo: não gasta a
  -- vez. No máximo 1 compra por rodada por Pá. Não gasta durabilidade (no_wear).
  activation = { speed = "instantaneo", no_wear = true },
  can_activate = function(game, p, equip)
    if equip.pronta ~= game.round then return false, "a Pá precisa ter golpeado nesta rodada" end
    if game:stack_open() then return false, "a Pá só é ativada fora do combate, com a pilha vazia" end
    return true
  end,
  activate = function(game, p, equip)
    equip.pronta = nil
    game:draw(p, 1)
  end,
  text = "Mão. O portador ganha +1 de ataque. Durabilidade 1. Golpear: a Pá fica pronta "
    .. "até o fim da rodada. Ativar (fora do combate): se a Pá estiver pronta, deixa de "
    .. "estar e você compra 1 carta.",
}
