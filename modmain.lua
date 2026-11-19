-- Ponto de entrada do mod em jogo (servidor e clientes; mods.lua carrega
-- modmain.lua depois do modworldgenmain.lua).
--
-- Este arquivo só liga os pedaços: cada regra do mod em jogo mora num
-- módulo próprio em scripts/duelo/mod/, em Lua puro, que recebe o que
-- precisa do jogo pela tabela `ctx` da sua função `instalar`. Assim os
-- testes (tests/test_mod_*.lua) rodam os módulos com um ambiente falso.
--
--   * US #29: mundo mínimo. O mundo vazio vem da geração
--     (modworldgenmain.lua) e das configurações do nível; aqui só a
--     geometria da mesa (duelo/mod/mesa.lua) é exposta.
--   * US #30: mesa de tiles, números e câmera. Os tiles já vêm da geração.
--       - duelo/mod/calibracao.lua: o servidor acha a mesa no mapa (portal e
--         carpete) e manda a calibração aos clientes (Mesa.calibracao).
--       - duelo/mod/marcadores.lua + prefabs/duelo_marcador.lua: número e
--         dono de cada um dos 16 espaços e o rótulo "Combate" no centro.
--       - duelo/mod/camera.lua: lado de cada jogador (1, 2 ou espectador) e
--         câmera fixa no centro, com o lado do jogador embaixo e sem Q/E.
--   * US #31: nada do mundo interfere no duelo.
--       - duelo/mod/protecao.lua: visão noturna de todos (sem Charlie),
--         invencibilidade, fome, sanidade e temperatura paradas.
--       - duelo/mod/relogio.lua: relógio do mundo travado, 5/5/6, estação
--         fixa, andado pela partida (DUELO.Relogio.avancar). A opção
--         "relogio" do modinfo.lua diz como ele nasce enquanto não há partida.
--
-- O que vem nas próximas US:
--   * US #33: criaturas de verdade nos espaços da mesa.
--   * US #37: RPCs, variáveis de rede e a mão no inventário.

local require = GLOBAL.require
local TheNet = GLOBAL.TheNet

-- Geometria da mesa: Lua puro, igual nos testes e no jogo.
local Mesa = require("duelo/mod/mesa")

-- Opção "relogio" do modinfo.lua (modutil.lua, GetModConfigData): o relógio
-- nasce travado, a não ser que a opção diga "livre".
local relogio_travado = GetModConfigData("relogio") ~= "livre"

-- Proteção dos jogadores (AddPlayerPostInit: servidor e clientes; o módulo
-- decide o que vale em cada lado por TheWorld.ismastersim).
local Protecao = require("duelo/mod/protecao").instalar({
  GLOBAL = GLOBAL,
  AddPlayerPostInit = AddPlayerPostInit,
})

-- Relógio da partida (AddComponentPostInit("clock") e
-- AddPrefabPostInit("forest_network"): os dois lados; os comandos só agem
-- no servidor).
local Relogio = require("duelo/mod/relogio").instalar({
  GLOBAL = GLOBAL,
  AddComponentPostInit = AddComponentPostInit,
  AddPrefabPostInit = AddPrefabPostInit,
  travado = relogio_travado,
})

-- Prefabs do mod (mods.lua, RegisterPrefabs: scripts/prefabs/<nome>.lua).
PrefabFiles = {
  "duelo_marcador",
}

-- Calibração da mesa (AddPrefabPostInit("forest_network"): os dois lados;
-- AddSimPostInit: o cálculo só no servidor).
local Calibracao = require("duelo/mod/calibracao").instalar({
  GLOBAL = GLOBAL,
  Mesa = Mesa,
  AddSimPostInit = AddSimPostInit,
  AddPrefabPostInit = AddPrefabPostInit,
})

-- Marcadores dos espaços (criados pelo servidor a cada calibração).
local Marcadores = require("duelo/mod/marcadores").instalar({
  GLOBAL = GLOBAL,
  Mesa = Mesa,
  Calibracao = Calibracao,
})

-- Câmera e lado dos jogadores (AddPlayerPostInit e
-- AddComponentPostInit("playercontroller"): os dois lados; AddSimPostInit:
-- a escolha do lado só no servidor).
local Camera = require("duelo/mod/camera").instalar({
  GLOBAL = GLOBAL,
  Mesa = Mesa,
  Calibracao = Calibracao,
  AddPlayerPostInit = AddPlayerPostInit,
  AddComponentPostInit = AddComponentPostInit,
  AddSimPostInit = AddSimPostInit,
})

-- Exposto no ambiente do mod (para os arquivos das próximas US) e no
-- ambiente global (para o console: DUELO.Relogio.avancar(1),
-- DUELO.Relogio.travar(), DUELO.Relogio.liberar(),
-- DUELO.Calibracao.calibrar(), DUELO.Camera.liberar(),
-- DUELO.Camera.aplicar()).
DUELO = {
  Mesa = Mesa,
  Protecao = Protecao,
  Relogio = Relogio,
  Calibracao = Calibracao,
  Marcadores = Marcadores,
  Camera = Camera,
}
GLOBAL.DUELO = DUELO

-- Lado do servidor. O nível DUELO_MESA já desliga chefes, invasões, clima,
-- eventos e estações pelas suas próprias configurações; o resto da US #31
-- corre pelos post inits acima. O bloco fica para as US seguintes
-- pendurarem aqui o que for só do servidor (RPCs da US #37).
if TheNet:GetIsServer() then
  -- Nada ainda.
end
