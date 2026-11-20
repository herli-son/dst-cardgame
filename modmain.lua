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
--       - duelo/mod/calibracao.lua: o servidor acha a mesa no mapa (estruturas
--         e coluna de eventos, em volta do portal) e manda a calibração aos clientes (Mesa.calibracao).
--       - duelo/mod/marcadores.lua + prefabs/duelo_marcador.lua: número e
--         dono de cada espaço (criaturas, estruturas, decks, descarte e
--         destruídas) e os rótulos "Combate" e "Eventos".
--       - duelo/mod/contornos.lua: contorno (tile_outline do jogo, local a
--         cada cliente) em cada tile de espaço, na cor do dono (bug #147).
--       - duelo/mod/camera.lua: lado de cada jogador (1, 2 ou espectador) e
--         câmera fixa no centro, com o lado do jogador embaixo e sem Q/E.
--   * US #31: nada do mundo interfere no duelo.
--       - duelo/mod/protecao.lua: visão noturna de todos (sem Charlie),
--         invencibilidade, fome, sanidade e temperatura paradas.
--       - duelo/mod/relogio.lua: relógio do mundo travado, 5/5/6, estação
--         fixa, andado pela partida (DUELO.Relogio.avancar). A opção
--         "relogio" do modinfo.lua diz como ele nasce enquanto não há partida.
--
--   * US #41: o servidor decide as jogadas. O motor (duelo/core) só é
--     carregado no servidor; os clientes só mandam ações e recebem eventos.
--       - duelo/mod/rede.lua: as RPCs de mod (ação e pedido de estado para o
--         servidor; eventos, estado e recusa para os clientes). Registradas
--         nos dois lados, na mesma ordem.
--       - duelo/mod/partida_servidor.lua (só no servidor): a partida em
--         curso; confere e aplica as ações no motor e distribui o resultado.
--       - duelo/mod/visao.lua: o que cada lado pode ver (a mão e o baralho
--         do outro nunca saem do servidor).
--       - duelo/mod/partida_cliente.lua (só onde há tela): a visão local da
--         partida e o envio das ações.
--
-- O que vem nas próximas US:
--   * US #33: criaturas de verdade nos espaços da mesa.
--   * US #37: a mão no inventário.
--   * US #42: preparar, começar e terminar a partida.

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

-- Contornos dos espaços (tile_outline local, criado em cada cliente com tela a
-- cada calibração).
local Contornos = require("duelo/mod/contornos").instalar({
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

-- Transporte da partida (US #41). As RPCs são registradas aqui, nos dois
-- lados e na mesma ordem (os ids saem da ordem de registro).
local Rede = require("duelo/mod/rede").instalar({
  GLOBAL = GLOBAL,
  AddModRPCHandler = AddModRPCHandler,
  AddClientModRPCHandler = AddClientModRPCHandler,
  SendModRPCToServer = SendModRPCToServer,
  SendModRPCToClient = SendModRPCToClient,
  GetModRPC = GetModRPC,
  GetClientModRPC = GetClientModRPC,
  AddSimPostInit = AddSimPostInit,
  -- Tempo real, que não para com o servidor pausado (ver rede.lua).
  agora = function() return GLOBAL.GetTimeRealSeconds() end,
})

-- A partida no servidor: o único lugar que carrega o motor (duelo/core/game),
-- por isso o require fica dentro do bloco do servidor. Num cliente o arquivo
-- nem é lido.
local Partida = nil
if TheNet:GetIsServer() then
  Partida = require("duelo/mod/partida_servidor").instalar({
    GLOBAL = GLOBAL,
    rede = Rede,
  })
end

-- A visão da partida em quem tem tela (clientes e host; o servidor dedicado
-- não tem jogador local). No host os dois lados convivem.
local Cliente = nil
if not TheNet:IsDedicated() then
  Cliente = require("duelo/mod/partida_cliente").instalar({
    GLOBAL = GLOBAL,
    rede = Rede,
    AddPlayerPostInit = AddPlayerPostInit,
  })
end

-- Exposto no ambiente do mod (para os arquivos das próximas US) e no
-- ambiente global (para o console: DUELO.Relogio.avancar(1),
-- DUELO.Relogio.travar(), DUELO.Relogio.liberar(),
-- DUELO.Calibracao.calibrar(), DUELO.Camera.liberar(),
-- DUELO.Camera.aplicar(); US #41, no console do servidor:
-- DUELO.Partida.iniciar_teste(), DUELO.Partida.estado(),
-- DUELO.Partida.encerrar(); no console do cliente:
-- DUELO.Cliente.enviar({ type = "pass" }), DUELO.Cliente.imprimir()).
DUELO = {
  Mesa = Mesa,
  Protecao = Protecao,
  Relogio = Relogio,
  Calibracao = Calibracao,
  Marcadores = Marcadores,
  Contornos = Contornos,
  Camera = Camera,
  Rede = Rede,
  Partida = Partida, -- nil nos clientes
  Cliente = Cliente, -- nil no servidor dedicado
}
GLOBAL.DUELO = DUELO

-- O nível DUELO_MESA já desliga chefes, invasões, clima, eventos e estações
-- pelas suas próprias configurações; o resto da US #31 corre pelos post
-- inits acima, e o que é só do servidor na US #41 está no bloco da partida.
