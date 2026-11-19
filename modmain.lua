-- Ponto de entrada do mod em jogo (servidor e clientes; mods.lua carrega
-- modmain.lua depois do modworldgenmain.lua).
--
-- Nesta US (#29, "Mundo mínimo com a arena") o mod em jogo é só o mínimo: o
-- mundo vazio vem inteiro da geração (modworldgenmain.lua) e das
-- configurações do nível, que o jogo aplica sozinho (worldsettings_overrides.lua).
-- Não há nada que dependa do servidor ainda, então este arquivo apenas:
--
--   * importa o que o resto do mod vai usar do ambiente global;
--   * carrega a geometria da mesa (scripts/duelo/mod/mesa.lua), para as US
--     seguintes acharem as coordenadas no mesmo lugar nos dois lados.
--
-- O que vem nas próximas US:
--   * US #30: tiles em jogo (TheWorld.Map:SetTile), câmera fixa na mesa e
--     direção por jogador (TheCamera:SetHeadingTarget), bloqueio da rotação.
--   * US #31: relógio travado por jogada (AddComponentPostInit("clock")),
--     divisão 5/5/6 por ms_setseasonclocksegs, visão noturna de todos.
--   * US #33: criaturas de verdade nos espaços da mesa.
--   * US #37: RPCs, variáveis de rede e a mão no inventário.

local require = GLOBAL.require
local TheNet = GLOBAL.TheNet

-- Geometria da mesa: Lua puro, igual nos testes e no jogo.
local Mesa = require("duelo/mod/mesa")

-- Exposto no ambiente do mod para os arquivos das próximas US (modimport)
-- lerem a mesma tabela.
DUELO = {
  Mesa = Mesa,
}

-- Lado do servidor. Por enquanto não há configuração fora do nível; o bloco
-- fica explícito para as US seguintes pendurarem aqui o que for só do servidor.
if TheNet:GetIsServer() then
  -- Nada ainda: o nível DUELO_MESA já desliga chefes, invasões, clima,
  -- eventos e estações pelas suas próprias configurações.
end
