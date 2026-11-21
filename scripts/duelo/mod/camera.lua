-- Câmera fixa na mesa e lado de cada jogador (US #30; enquadramento e vista
-- de longe pedidos no bug #147).
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
--   * distância e inclinação (bug #147, terceira rodada: a vista do mod
--     Aerial View, que o dono testou e aprovou; só os números vêm de lá):
--     `SetMinDistance(5)`, `SetMaxDistance(180)`, `SetPitchRange(40, 60)`,
--     `SetDistance(80)` e `Snap` (followcamera.lua; os campos são `mindist`,
--     `maxdist`, `mindistpitch`, `maxdistpitch` e `distancetarget`, e todos
--     têm setter). O pitch sai da distância (Update e Snap: lerp de
--     mindistpitch a maxdistpitch por (d - mindist) / (maxdist - mindist)):
--     em 80 dá 40 + 20 * 75 / 175 = 48,6 graus, e afastar com o zoom
--     inclina a câmera até 60 graus em 180.
--   * limite prático do zoom: fora de caverna o HUD liga as nuvens quando a
--     distância passa de 75% da faixa (TUNING.HUD_CLOUD_CUTOFF em
--     screens/playerhud.lua, UpdateClouds): com 5..180 isso é acima de ~136,
--     e um segundo depois a câmera é puxada de volta para 110
--     (followcamera.lua, should_push_down). O zoom útil é de 30 a ~136; em
--     80 (a vista padrão) nada disso acontece. Limitações conhecidas: quem
--     entra já com bônus de distância (monóculo, módulo do WX-78) começa em
--     127,5 (MaximizeDistance do player_classified), e Camera.liberar não
--     devolve esse bônus até ele mudar de novo.
--   * zoom: livre entre ZOOM_MIN = 30 e 180. O `mindist` fica em 5 porque é
--     ele que dá a inclinação acima; para a roda do mouse não chegar a 5
--     (perto demais para uma câmera parada no centro da mesa), `ZoomIn` e
--     `ContinuousZoomDelta` da TheCamera, com a câmera travada, não deixam
--     a distância passar para baixo de ZOOM_MIN. Acima de 80
--     (PLAYER_CAMERA_MAX_DIST, constants.lua) o jogo avisa que entidades
--     podem sumir e aparecer nas bordas: a conferir no jogo.
--   * enquadramento. Em followcamera.lua o fov vertical é 35 (SetDefault).
--     A câmera olha para o alvo + 1,5 de altura (targetoffset), de d
--     unidades, com pitch p: fica a 1,5 + d sen(p) de altura e d cos(p)
--     atrás do alvo (em 80: 61,5 e 52,9). Um ponto do chão a s unidades do
--     centro da mesa (s > 0 para o alto da tela), com o alvo deslocado
--     DESLOCAMENTO para o lado de quem olha, fica a
--     f = d cos(p) + DESLOCAMENTO + s da câmera na horizontal e aparece na
--     altura da tela (1 + tan(p - a) / tan(17,5)) / 2, onde
--     a = atan((1,5 + d sen(p)) / f) é o ângulo dele abaixo do horizonte
--     (Camera.altura_na_tela, que faz a mesma conta com o pitch de qualquer
--     distância).
--     A mesa 15 x 16 vai de 32 unidades abaixo a 32 acima do centro (8
--     tiles). A fileira de trás do próprio lado tem 2 tiles: o de trás (a
--     carta da estrutura, os decks, as destruídas) com o centro a 26 abaixo
--     e a beira de perto a 28; o da frente a 22. DISTANCIA = 80 é a pedida
--     pelo dono; sem deslocar o alvo, o tile de trás ficaria em -1% da
--     altura, fora da tela. Com DESLOCAMENTO = 12 unidades para o lado de
--     quem olha (ao longo de GetDownVec), a beira de perto desse tile fica
--     em 20,8%, acima do ponto confirmado no jogo como visível sobre a
--     barra de inventário (19,3%, Camera.REFERENCIA_INVENTARIO), e o outro
--     lado ainda cabe inteiro. De baixo para cima da tela, em 16:9:
--       borda de perto da mesa                          13%
--       fileira de trás do próprio lado (tile de trás)  25% (beira: 21%)
--       fileira de trás do próprio lado (tile da frente) 32%
--       cartas e criaturas do próprio lado              45% e 51%
--       as duas fileiras de combate                     62% e 67%
--       criaturas e cartas do outro lado                76% e 80%
--       fileira de trás do outro lado                   88% e 91% (beira: 93%)
--       borda de longe da mesa                          96%
--     A moldura de pedra de longe fica em 99%, no limite da tela. Com menos
--     deslocamento a fileira de trás desce (10: beira em 17%); com mais, a
--     borda de longe sai (16: 99%).
--     Na largura, a mesa não é simétrica em volta do combate (a coluna dos
--     eventos fica de um lado), então o alvo é o centro geométrico da mesa
--     (Mesa.centro_da_mesa_abs), 1 coluna para o lado dos eventos: os
--     cantos de perto da mesa (30 unidades para cada lado) ficam a 79% da
--     meia largura da tela; a coluna dos eventos, com o descarte e as
--     destruídas, a no máximo 66%; do outro lado, o portal a 81% e a beira
--     do pátio a 96%. Em 4:3 todos os espaços cabem (o mais aberto, as
--     destruídas de perto, a 88%), mas a borda de paralelepípedos de perto
--     e o pátio do portal saem pela lateral.
--     Com o zoom: em 180 (pitch 60) a mesa inteira ocupa de 33% a 79% da
--     altura; abaixo de uns 70 ela já não cabe inteira (a borda de longe
--     sai por cima e a fileira de trás de perto desce para a barra).
--     Antes: mesa 15 x 14 com a câmera do jogo no máximo (80, pitch 60) e
--     DESLOCAMENTO = 8; mesa 13 x 11, DISTANCIA = 65, DESLOCAMENTO = 5.
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
--     refaz distâncias, inclinação e `controllable`. Por isso, com a câmera
--     travada, `SetHeadingTarget` e `SetContinuousHeadingTarget` da
--     TheCamera passam a usar sempre o heading do lado, e `SetDefault`
--     reaplica a configuração da mesa logo depois do original.
--     `SetExtraMaxDistance` também é trocado: o player_classified
--     (OnPlayerCameraExtraDistDirty, na ativação do jogador e quando um
--     bônus de distância muda) limita o extra a
--     PLAYER_CAMERA_MAX_DIST - maxdist, que com maxdist = 180 é negativo e
--     baixaria o máximo de volta para 80 (e ainda chamaria
--     MaximizeDistance). Com a câmera travada o extra fica sempre 0.
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
Camera.DESLOCAMENTO = 12
-- Valores do mod Aerial View pedidos pelo dono (bug #147): mindist e maxdist
-- de followcamera.lua. O mínimo entra na conta do pitch; o zoom não desce
-- abaixo de ZOOM_MIN.
Camera.DISTANCIA_MIN = 5
Camera.DISTANCIA_MAX = 180
Camera.ZOOM_MIN = 30
Camera.PITCH_MIN = 40 -- mindistpitch
Camera.PITCH_MAX = 60 -- maxdistpitch

-- Valores de cameras/followcamera.lua (SetDefault) usados na conta do
-- enquadramento.
Camera.FOV = 35
Camera.ALTURA_ALVO = 1.5 -- targetoffset.y

-- Altura da tela (0 = embaixo) de um ponto que, no jogo, ficou visível acima
-- da barra de inventário (US #30: estruturas a 22 unidades do centro, com a
-- câmera de então, distância 70, pitch 54 e deslocamento 8).
Camera.REFERENCIA_INVENTARIO = 0.193

-- Pitch (graus) que followcamera.lua usa na distância d, com o mínimo e o
-- máximo do mod.
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
-- de tela 16:9 (1 = borda da tela). O pitch é o da distância `d`
-- (Camera.pitch), a não ser que `pitch` (graus) venha dado.
function Camera.altura_na_tela(s, x, d, desloc, pitch)
  d = d or Camera.DISTANCIA
  desloc = desloc or Camera.DESLOCAMENTO
  local p = math.rad(pitch or Camera.pitch(d))
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

-- Servidor: no começo de uma partida (US #42), o lado da mesa de cada um
-- passa a ser o lado pelo qual ele joga; os demais ficam de espectadores. Um
-- espectador que entra na partida deixa de ver a mesa pelo lado errado.
function Camera.definir_lados(um, dois)
  if not servidor() then return false end
  for _, jogador in ipairs(estado.GLOBAL.AllPlayers or {}) do
    local uid = jogador.userid
    if jogador.duelo_lado ~= nil and uid ~= nil and uid ~= "" then
      local lado = Camera.LADO.espectador
      if uid == um then lado = 1 elseif uid == dois then lado = 2 end
      estado.lados_por_usuario[uid] = lado
      if jogador.duelo_lado:value() ~= lado then jogador.duelo_lado:set(lado) end
    end
  end
  return true
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

-- Aplica alvo, distâncias, inclinação e heading da mesa na câmera.
local function configurar(cam)
  cam:SetTarget(estado.alvo)
  -- Passa pela proteção: zera o extra, para o máximo ser o do mod. Vem antes
  -- de SetDistance porque o original pode chamar MaximizeDistance.
  cam:SetExtraMaxDistance(0)
  cam:SetMinDistance(Camera.DISTANCIA_MIN)
  cam:SetMaxDistance(Camera.DISTANCIA_MAX)
  cam:SetPitchRange(Camera.PITCH_MIN, Camera.PITCH_MAX)
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
  local set_extra = cam.SetExtraMaxDistance
  local zoom_in = cam.ZoomIn
  local zoom_continuo = cam.ContinuousZoomDelta
  -- Com a câmera travada, o zoom não aproxima além de ZOOM_MIN.
  local function segurar_zoom(self)
    if estado.travada and self:GetDistance() < Camera.ZOOM_MIN then self:SetDistance(Camera.ZOOM_MIN) end
  end
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
  cam.SetExtraMaxDistance = function(self, extra)
    if estado.travada then return set_extra(self, 0) end
    return set_extra(self, extra)
  end
  cam.ZoomIn = function(self, ...)
    local ret = zoom_in(self, ...)
    segurar_zoom(self)
    return ret
  end
  cam.ContinuousZoomDelta = function(self, ...)
    local ret = zoom_continuo(self, ...)
    segurar_zoom(self)
    return ret
  end
end

-- Posição do alvo da câmera: o centro geométrico da mesa (que, com a coluna
-- de eventos, fica 1 coluna para o lado dela em relação ao combate)
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
