-- Contornos dos espaços da mesa (bug #147, decisão da #30).
--
-- Cada tile de espaço (carta e criatura dos 12 espaços de criatura e as 4
-- estruturas, 28 tiles) ganha um contorno no chão do tamanho de um tile, na
-- cor do dono (azul J1, vermelho J2, as mesmas cores dos rótulos de
-- duelo/mod/marcadores.lua). O contorno é o `gridplacer` do próprio jogo
-- (prefabs/gridplacer.lua), o quadrado que aparece ao colocar turf.
--
-- Por que local, em cada cliente: o prefab `gridplacer` não tem rede (não
-- chama `entity:AddNetwork()`; o próprio arquivo marca "Non-networked
-- entity"), então um gridplacer criado no servidor só apareceria na tela do
-- host. Ele é carregado com o mundo em todos os lados (prefabs/world.lua
-- depende de "hud", e prefabs/hud.lua depende de "gridplacer"), e o jogo o
-- cria do lado do cliente (components/playercontroller.lua,
-- gridplacer_group_outline em prefabs/gridplacer.lua). Por isso cada
-- cliente com tela (o host inclusive; nada no servidor dedicado) cria os
-- seus a partir da calibração, como a câmera faz com o alvo
-- (duelo/mod/camera.lua): `Calibracao.quando_calibrar` roda no host depois
-- do cálculo e nos clientes quando as netvars chegam.
--
-- O que o gridplacer já traz e serve aqui (prefabs/gridplacer.lua, fn):
-- tags CLASSIFIED e NOCLICK (o mouse não o seleciona), nenhuma física,
-- `persists = false`, `SetCanSleep(false)`, `SetLightOverride(1)` (aparece
-- de noite), camada LAYER_BACKGROUND deitada no chão
-- (ANIM_ORIENTATION.OnGround). O componente `placer` dele só age quando o
-- jogo o atualiza (Placer:OnUpdate, ligado pelo playercontroller para o
-- placer de construção); parado numa posição, ele fica como o jogo usa em
-- gridplacer_group_outline: `SpawnPrefab("gridplacer")` +
-- `Transform:SetPosition` no centro do tile.
--
-- Cor: `AnimState:SetMultColour(r, g, b, 1)` (o próprio gridplacer usa
-- SetMultColour para ficar vermelho em OnCannotBuild). Destaque:
-- `AnimState:SetAddColour(...)` clareia o contorno (prefabs/seeds.lua usa
-- SetAddColour num tile_outline); `Contornos.destacar` fica pronto para a
-- US #38 marcar os alvos válidos, mas ainda não é chamado.
--
-- Este arquivo é Lua puro: tudo do jogo chega por `ctx` em `instalar`, para
-- os testes (tests/test_mod_mesa.lua) rodarem com um ambiente falso.

local Contornos = {}

Contornos.PREFAB = "gridplacer"
-- Cor somada ao contorno destacado (r, g, b, a).
Contornos.DESTAQUE = { 0.35, 0.35, 0.35, 0 }
Contornos.SEM_DESTAQUE = { 0, 0, 0, 0 }

local estado = {
  GLOBAL = nil,
  Mesa = nil,
  Marcadores = nil,
  contornos = {}, -- lista de { inst, jogador, tipo, n }
  avisou = false,
}

local function dedicado()
  local net = estado.GLOBAL and estado.GLOBAL.TheNet or nil
  return net ~= nil and net:IsDedicated() == true
end

local function avisar(msg)
  local p = estado.GLOBAL and estado.GLOBAL.print or print
  p("[duelo] " .. msg)
end

-- Cor do dono (r, g, b): a mesma dos rótulos.
function Contornos.cor(jogador)
  local M = estado.Marcadores
  return M.cor(M.TIPO.criatura, jogador)
end

-- Remove os contornos criados neste lado.
function Contornos.remover()
  for _, c in ipairs(estado.contornos) do
    if c.inst:IsValid() then c.inst:Remove() end
  end
  estado.contornos = {}
end

-- Cliente com tela (inclusive o host): remove os contornos antigos e cria um
-- gridplacer em cada um dos 28 tiles de espaço. Devolve a lista.
function Contornos.criar(calib)
  if dedicado() then return nil end
  Contornos.remover()
  local G = estado.GLOBAL
  for _, t in ipairs(estado.Mesa.tiles_dos_espacos(calib) or {}) do
    local inst = G.SpawnPrefab(Contornos.PREFAB)
    if inst == nil then
      if not estado.avisou then avisar("prefab gridplacer não achado: espaços sem contorno") end
      estado.avisou = true
      break
    end
    inst.Transform:SetPosition(t.x, 0, t.z)
    local r, g, b = Contornos.cor(t.jogador)
    inst.AnimState:SetMultColour(r, g, b, 1)
    inst.persists = false
    estado.contornos[#estado.contornos + 1] = { inst = inst, jogador = t.jogador, tipo = t.tipo, n = t.n }
  end
  return estado.contornos
end

function Contornos.lista()
  return estado.contornos
end

-- Destaca (ou apaga o destaque de) um espaço: `tipo` "criatura" (os 2
-- tiles, carta e criatura) ou "estrutura"; `n` na numeração da câmera.
-- Devolve quantos contornos mudaram. Para a US #38 (alvos válidos).
function Contornos.destacar(jogador, tipo, n, ligado)
  local cor = ligado == false and Contornos.SEM_DESTAQUE or Contornos.DESTAQUE
  local mudou = 0
  for _, c in ipairs(estado.contornos) do
    local mesmo_tipo = (tipo == "estrutura" and c.tipo == "estrutura")
      or (tipo == "criatura" and (c.tipo == "carta" or c.tipo == "criatura"))
    if mesmo_tipo and c.jogador == jogador and c.n == n and c.inst:IsValid() then
      c.inst.AnimState:SetAddColour(cor[1], cor[2], cor[3], cor[4])
      mudou = mudou + 1
    end
  end
  return mudou
end

-- Liga o módulo no ambiente do mod.
--   ctx.GLOBAL: ambiente global do jogo;
--   ctx.Mesa: duelo/mod/mesa;
--   ctx.Calibracao: duelo/mod/calibracao (já instalado);
--   ctx.Marcadores: duelo/mod/marcadores (cores dos donos).
-- Fora do servidor dedicado, cria os contornos a cada calibração.
function Contornos.instalar(ctx)
  estado.GLOBAL = ctx.GLOBAL
  estado.Mesa = ctx.Mesa
  estado.Marcadores = ctx.Marcadores
  estado.contornos = {}
  estado.avisou = false
  ctx.Calibracao.quando_calibrar(function(calib)
    if not dedicado() then Contornos.criar(calib) end
  end)
  return Contornos
end

return Contornos
