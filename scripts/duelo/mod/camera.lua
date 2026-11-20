-- Câmera fixa na mesa e lado de cada jogador (US #30; enquadramento da
-- mesa 15 x 14 no bug #147).
--
-- Cada cliente vê a mesa inteira de uma câmera parada no centro, com o seu
-- lado embaixo da tela. A câmera é do cliente (TheCamera, criada em main.lua
-- com cameras/followcamera.lua), então cada um aplica a sua; o servidor só
-- decide o lado de cada jogador.
--
-- Lado (servidor; enquanto não existe partida, US #37):
--   * o primeiro jogador a entrar é o 1 (sul), o segundo é o 2 (norte); os
--     demais são espectadores (3) e olham como o 1. Um lado só é ocupado
--     por quem está conectado (AllPlayers), e quem sai e volta recupera o
--     seu lado se ele ainda estiver livre (guardado por `userid`).
--   * o lado fica numa variável de rede do próprio jogador, `inst.duelo_lado`
--     (`net_tinybyte`, netvars.lua: 0 = ainda não chegou, 1, 2 ou 3),
--     declarada nos dois lados por `AddPlayerPostInit` (modutil.lua).
--   * o servidor atribui no evento "ms_playerjoined" do TheWorld
--     (prefabs/player_common.lua, OnPlayerJoined: o `userid` já foi
--     definido em OnSetOwner), registrado no `AddSimPostInit`.
--
-- Câmera (cliente, inclusive o host; nada no servidor dedicado):
--   * aplicada quando o jogador local ativa (evento "playeractivated" no
--     próprio jogador, prefabs/player_common.lua, ActivatePlayer: ThePlayer e
--     o HUD já existem), quando o lado chega ("duelo.ladodirty") e quando a
--     calibração chega (duelo/mod/calibracao.lua). Não é preciso
--     `AddClassPostConstruct("cameras/followcamera")`: a câmera já existe
--     muito antes (main.lua a cria logo depois de carregar os mods) e o que
--     falta para aplicar (jogador, lado, centro) só existe na ativação.
--   * alvo: `TheCamera:SetTarget(inst)` (followcamera.lua) lê
--     `inst.Transform:GetWorldPosition()` a cada Update, então o alvo é uma
--     entidade local, invisível e sem rede, parada no centro da mesa
--     (CreateEntity + AddTransform, tags CLASSIFIED/NOCLICK, como as barras
--     de components/healthbar.lua). `SetCustomLocation` não serve: o Update
--     sobrescreve `targetpos` com a posição do alvo a cada quadro. O
--     TheFocalPoint (prefabs/focalpoint.lua, preso ao jogador) continua no
--     jogador: o som e a área ativa (update.lua) seguem com ele.
--   * distância: `SetMinDistance`, `SetMaxDistance`, `SetDistance` e `Snap`
--     (followcamera.lua). O zoom continua livre entre o mínimo e o máximo
--     (docs/investigacao-scripts-dst.md, "Câmera"); o máximo é
--     PLAYER_CAMERA_MAX_DIST = 80 (constants.lua: mais longe, entidades
--     começam a sumir e aparecer).
--   * enquadramento (bug #147: a mesa passou a 15 x 14 tiles, com a coluna
--     de eventos de um lado). Em followcamera.lua o fov vertical é 35
--     (SetDefault) e o pitch sai da distância (Update: lerp de
--     mindistpitch = 30 a maxdistpitch = 60 por
--     (d - mindist) / (maxdist - mindist)); com o mínimo e o máximo do mod
--     (30 e 80), d = 80 dá pitch 60. A câmera olha para o alvo + 1,5 de
--     altura (targetoffset), de d unidades: fica a 1,5 + d sen(p) = 70,8 de
--     altura e d cos(p) = 40,0 atrás do alvo. Um ponto do chão a s unidades
--     do alvo (s > 0 para o alto da tela) aparece na altura da tela
--     (1 + tan(a - p) / tan(17,5)) / 2, onde a = atan(70,8 / (40,0 + s)) é o
--     ângulo dele abaixo do horizonte (Camera.altura_na_tela). A mesa vai de
--     28 unidades abaixo a 28 acima do centro (7 tiles), e a fileira de trás
--     do próprio lado (decks e estruturas) fica a 22 abaixo. Para as 14
--     linhas caberem, a distância é a máxima (80: dá para aproximar com o
--     zoom, não para afastar), e o alvo fica DESLOCAMENTO = 8 unidades para
--     o lado do jogador (ao longo de GetDownVec), senão a fileira de trás
--     ficaria em 5% da altura, sob a barra de inventário. Resultado (de
--     baixo para cima da tela, em 16:9):
--       borda de perto da mesa                    10%
--       fileira de trás do próprio lado (centro)  22%   (US #30, confirmado
--         no jogo acima da barra de inventário: 19%)
--       cartas e criaturas do próprio lado        38% e 45%
--       par de combate                            58% e 65%
--       criaturas e cartas do outro lado          76% e 81%
--       fileira de trás do outro lado             92%
--       borda de longe da mesa                    99%
--     A moldura de pedra de longe sai pelo alto da tela; nenhum espaço fica
--     nela. Na largura, a mesa não é mais simétrica em volta do combate (a
--     coluna de eventos fica de um lado), então o alvo é o centro geométrico
--     da mesa (Mesa.centro_da_mesa_abs), 1 coluna para o lado dos eventos:
--     os cantos da mesa (30 unidades para cada lado) ficam a 75% da meia
--     largura da tela na fileira de perto, a mais larga na tela; a coluna de
--     eventos a 55%; do outro lado, o portal a 85% e a beira do pátio a 97%.
--     Em 4:3 a borda de paralelepípedos de perto encosta na lateral e o
--     pátio do portal sai da tela, mas todos os espaços cabem (o mais
--     aberto, a coluna de eventos, a 73%).
--     Antes: mesa 13 x 11, DISTANCIA = 65, DESLOCAMENTO = 5; mesa 16 x 16,
--     DISTANCIA = 70, DESLOCAMENTO = 8.
--   * heading: `SetHeadingTarget(h)`. Em followcamera.lua (Apply), a câmera
--     olha na horizontal para (-cos h, -sin h) e fica do lado oposto, e
--     GetDownVec = (cos h, sin h) é a direção do mundo que aponta para baixo
--     na tela. O lado do jogador fica embaixo quando (cos h, sin h) aponta
--     do centro para a fileira dele: h = atan2(dz, dx) (Mesa.heading). Com
--     o eixo z não espelhado, jogador 1 = 90 e jogador 2 = 270 (= 90 + 180).
--     O espelhamento do eixo x não muda o heading; ele muda a ordem das
--     colunas, que é resolvida pela numeração por câmera (Mesa.espaco_*_abs).
--   * rotação: Q/E (CONTROL_ROTATE_LEFT/RIGHT) e o analógico chamam
--     `PlayerController:RotLeft/RotRight` (components/playercontroller.lua,
--     DoCameraControl), que também são chamados pelos botões do mapa
--     (widgets/mapcontrols.lua, screens/mapscreen.lua). Um
--     `AddComponentPostInit("playercontroller")` troca os dois, na
--     instância, por versões que não fazem nada com a câmera travada. Não
--     usamos `TheCamera:SetControllable(false)` porque ele também desliga o
--     zoom (decisão da investigação).
--   * proteção: outras partes do jogo mexem na câmera por conta própria.
--     `SnapCamera(resetrot)` (prefabs/player_classified.lua, DoSnapCamera)
--     volta o heading para 45; `FocalPoint:Reset` (components/focalpoint.lua)
--     e o "cameradistance" do player_classified chamam `SetDefault`, que
--     refaz distâncias e `controllable`. Por isso, com a câmera travada,
--     `SetHeadingTarget` e `SetContinuousHeadingTarget` da TheCamera passam
--     a usar sempre o heading do lado, e `SetDefault` reaplica a
--     configuração da mesa logo depois do original.
--
-- No console do cliente: `DUELO.Camera.liberar()` devolve a câmera normal
-- (presa ao jogador) e `DUELO.Camera.aplicar()` trava de novo.
--
-- Este arquivo é Lua puro: tudo do jogo chega por `ctx` em `instalar`, para
-- os testes (tests/test_mod_mesa.lua) rodarem com um ambiente falso.

local Camera = {}

Camera.LADO = { desconhecido = 0, jogador1 = 1, jogador2 = 2, espectador = 3 }

Camera.DISTANCIA = 80
-- Unidades do alvo, a partir do centro da mesa, na direção do lado de quem
-- olha (ver o cabeçalho, "enquadramento").
Camera.DESLOCAMENTO = 8
Camera.DISTANCIA_MIN = 30
Camera.DISTANCIA_MAX = 80 -- PLAYER_CAMERA_MAX_DIST (constants.lua)

-- Valores de cameras/followcamera.lua (SetDefault) usados na conta do
-- enquadramento.
Camera.FOV = 35
Camera.PITCH_MIN = 30 -- mindistpitch
Camera.PITCH_MAX = 60 -- maxdistpitch
Camera.ALTURA_ALVO = 1.5 -- targetoffset.y

-- Pitch (graus) que followcamera.lua usa na distância d, com o zoom mínimo
-- e máximo do mod.
function Camera.pitch(d)
  local t = (d - Camera.DISTANCIA_MIN) / (Camera.DISTANCIA_MAX - Camera.DISTANCIA_MIN)
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return Camera.PITCH_MIN + (Camera.PITCH_MAX - Camera.PITCH_MIN) * t
end

-- Conta do enquadramento (cabeçalho): altura na tela (0 = embaixo, 1 = em
-- cima) de um ponto do chão a `s` unidades do centro da mesa na direção do
-- alto da tela, com a câmera a `d` (padrão DISTANCIA) e o alvo deslocado
-- `desloc` (padrão DESLOCAMENTO) para o lado de quem olha. Também devolve a
-- posição horizontal de um ponto `x` unidades para o lado, em meias larguras
-- de tela 16:9 (1 = borda da tela).
function Camera.altura_na_tela(s, x, d, desloc)
  d = d or Camera.DISTANCIA
  desloc = desloc or Camera.DESLOCAMENTO
  local p = math.rad(Camera.pitch(d))
  local altura = Camera.ALTURA_ALVO + d * math.sin(p)
  local frente = d * math.cos(p) + s + desloc -- distância horizontal da câmera
  local profundidade = frente * math.cos(p) + altura * math.sin(p)
  local meio = math.tan(math.rad(Camera.FOV / 2))
  local y = (frente * math.sin(p) - altura * math.cos(p)) / profundidade / meio
  local lado = (x or 0) / profundidade / (meio * 16 / 9)
  return (y + 1) / 2, lado
end

local NETVAR = "duelo.lado"
local NETVAR_DIRTY = "duelo.ladodirty"

local estado = {
  GLOBAL = nil,
  Mesa = nil,
  travada = false,
  heading = nil,
  lado = nil,
  alvo = nil, -- entidade local no centro da mesa
  lados_por_usuario = {}, -- servidor: userid -> último lado
}

local function servidor()
  local w = estado.GLOBAL and estado.GLOBAL.TheWorld or nil
  return w ~= nil and w.ismastersim == true
end

local function dedicado()
  local net = estado.GLOBAL and estado.GLOBAL.TheNet or nil
  return net ~= nil and net:IsDedicated() == true
end

local function avisar(msg)
  local p = estado.GLOBAL and estado.GLOBAL.print or print
  p("[duelo] " .. msg)
end

-- Lógica pura do lado: `ocupados[l]` diz se o lado l (1 ou 2) está com outro
-- jogador conectado; `anterior` é o lado que este usuário já teve.
function Camera.escolher_lado(ocupados, anterior)
  if (anterior == 1 or anterior == 2) and not ocupados[anterior] then return anterior end
  if not ocupados[1] then return 1 end
  if not ocupados[2] then return 2 end
  return Camera.LADO.espectador
end

-- Servidor: escolhe e grava o lado de um jogador.
function Camera.atribuir_lado(jogador)
  if not servidor() or jogador.duelo_lado == nil then return nil end
  local ocupados = {}
  for _, outro in ipairs(estado.GLOBAL.AllPlayers or {}) do
    if outro ~= jogador and outro.duelo_lado ~= nil
      and (jogador.userid == nil or jogador.userid == "" or outro.userid ~= jogador.userid) then
      local v = outro.duelo_lado:value()
      if v == 1 or v == 2 then ocupados[v] = true end
    end
  end
  local uid = jogador.userid
  local lado = Camera.escolher_lado(ocupados, uid and estado.lados_por_usuario[uid] or nil)
  if uid ~= nil and uid ~= "" then estado.lados_por_usuario[uid] = lado end
  jogador.duelo_lado:set(lado)
  return lado
end

-- Heading da câmera para um lado (espectador e desconhecido olham como o 1).
function Camera.heading(lado, calib)
  return estado.Mesa.heading(lado, calib)
end

function Camera.travada()
  return estado.travada
end

local function criar_alvo()
  local G = estado.GLOBAL
  local inst = G.CreateEntity("duelo_camera_alvo")
  --[[Entidade local, sem rede]]
  inst.entity:AddTransform()
  inst:AddTag("CLASSIFIED")
  inst:AddTag("NOCLICK")
  inst.persists = false
  return inst
end

-- Aplica distância, alvo e heading da mesa na câmera.
local function configurar(cam)
  cam:SetTarget(estado.alvo)
  cam:SetMinDistance(Camera.DISTANCIA_MIN)
  cam:SetMaxDistance(Camera.DISTANCIA_MAX)
  cam:SetDistance(Camera.DISTANCIA)
  cam:SetHeadingTarget(estado.heading) -- passa pela proteção: usa estado.heading
end

-- Troca, uma vez por câmera, os métodos que outras partes do jogo usam para
-- girar ou reiniciar a câmera.
local function proteger(cam)
  if cam._duelo_protegida then return end
  cam._duelo_protegida = true
  local set_heading = cam.SetHeadingTarget
  local set_continuo = cam.SetContinuousHeadingTarget
  local set_default = cam.SetDefault
  cam.SetHeadingTarget = function(self, r)
    if estado.travada then return set_heading(self, estado.heading) end
    return set_heading(self, r)
  end
  cam.SetContinuousHeadingTarget = function(self, r, delta)
    if estado.travada then return set_heading(self, estado.heading) end
    return set_continuo(self, r, delta)
  end
  cam.SetDefault = function(self, ...)
    local ret = set_default(self, ...)
    if estado.travada and estado.alvo ~= nil and estado.alvo:IsValid() then configurar(self) end
    return ret
  end
end

-- Posição do alvo da câmera: o centro geométrico da mesa (que, com a coluna
-- de eventos, fica 1 coluna para o lado dela em relação ao par de combate)
-- deslocado DESLOCAMENTO unidades na direção que fica embaixo da tela,
-- (cos h, sin h).
function Camera.alvo(calib, heading)
  local cx, cz = estado.Mesa.centro_da_mesa_abs(calib)
  local h = math.rad(heading or 90)
  return cx + Camera.DESLOCAMENTO * math.cos(h), cz + Camera.DESLOCAMENTO * math.sin(h)
end

-- Cliente: trava a câmera no centro da mesa com o heading do lado do
-- jogador local. Devolve true se aplicou (falta jogador, câmera ou
-- calibração: devolve false e espera o próximo evento).
function Camera.aplicar()
  local G = estado.GLOBAL
  if dedicado() then return false end
  local jogador, cam = G.ThePlayer, G.TheCamera
  local calib = estado.Mesa.calibracao
  if jogador == nil or cam == nil or calib == nil then return false end

  local lado = jogador.duelo_lado ~= nil and jogador.duelo_lado:value() or Camera.LADO.desconhecido
  estado.lado = lado
  estado.heading = Camera.heading(lado, calib)

  if estado.alvo == nil or not estado.alvo:IsValid() then estado.alvo = criar_alvo() end
  local cx, cz = Camera.alvo(calib, estado.heading)
  estado.alvo.Transform:SetPosition(cx, 0, cz)

  proteger(cam)
  estado.travada = true
  configurar(cam)
  cam:Snap()
  return true
end

-- Cliente: devolve a câmera normal, presa ao jogador (para testes no jogo).
function Camera.liberar()
  local G = estado.GLOBAL
  estado.travada = false
  local cam = G.TheCamera
  if cam ~= nil then
    cam:SetTarget(G.TheFocalPoint)
    cam:SetDefault()
    cam:Snap()
  end
  avisar("câmera liberada; DUELO.Camera.aplicar() trava de novo")
  return true
end

-- Post init do jogador: netvar nos dois lados; no cliente, aplica a câmera
-- quando este é o jogador local.
local function post_init_jogador(inst)
  inst.duelo_lado = estado.GLOBAL.net_tinybyte(inst.GUID, NETVAR, NETVAR_DIRTY)
  if dedicado() then return end
  inst:ListenForEvent("playeractivated", function() Camera.aplicar() end)
  inst:ListenForEvent(NETVAR_DIRTY, function()
    if inst == estado.GLOBAL.ThePlayer then Camera.aplicar() end
  end)
end

-- Post init do playercontroller: Q/E não giram com a câmera travada.
local function post_init_controle(self)
  local rot_esq, rot_dir = self.RotLeft, self.RotRight
  self.RotLeft = function(pc, ...)
    if estado.travada then return end
    return rot_esq(pc, ...)
  end
  self.RotRight = function(pc, ...)
    if estado.travada then return end
    return rot_dir(pc, ...)
  end
end

-- Liga o módulo no ambiente do mod.
--   ctx.GLOBAL: ambiente global do jogo;
--   ctx.Mesa: duelo/mod/mesa;
--   ctx.Calibracao: duelo/mod/calibracao (já instalado);
--   ctx.AddPlayerPostInit, ctx.AddComponentPostInit, ctx.AddSimPostInit:
--     de modutil.lua.
function Camera.instalar(ctx)
  estado.GLOBAL = ctx.GLOBAL
  estado.Mesa = ctx.Mesa
  estado.travada, estado.heading, estado.lado, estado.alvo = false, nil, nil, nil
  estado.lados_por_usuario = {}

  ctx.AddPlayerPostInit(post_init_jogador)
  ctx.AddComponentPostInit("playercontroller", post_init_controle)
  ctx.AddSimPostInit(function()
    if not servidor() then return end
    local G = estado.GLOBAL
    G.TheWorld:ListenForEvent("ms_playerjoined", function(_, jogador) Camera.atribuir_lado(jogador) end)
    for _, jogador in ipairs(G.AllPlayers or {}) do
      if jogador.duelo_lado ~= nil and jogador.duelo_lado:value() == 0 then Camera.atribuir_lado(jogador) end
    end
  end)
  ctx.Calibracao.quando_calibrar(function()
    if estado.GLOBAL.ThePlayer ~= nil then Camera.aplicar() end
  end)
  return Camera
end

return Camera
