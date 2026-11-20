-- Contornos dos espaços da mesa (bug #147, decisão da #30).
--
-- Cada tile de espaço (62: carta e criatura dos 12 espaços de criatura, 8 de
-- estrutura, 8 de deck, os 12 quadrados de combate, 4 de descarte, 4 de
-- destruídas e os 2 tiles do espaço de eventos) ganha um contorno no chão
-- do tamanho de um tile, na cor do dono: azul para o jogador 1, vermelho
-- para o 2 e amarelo para o espaço de
-- eventos, que não tem dono. O contorno é o `tile_outline` do próprio jogo
-- (prefabs/gridplacer.lua), o mesmo quadrado do `gridplacer` que aparece ao
-- colocar turf (mesmo bank, build e animação), mas sem o componente `placer`.
--
-- Por que não o `gridplacer`: ele adiciona o componente `placer`, e outros
-- mods penduram código nesse componente (AddComponentPostInit("placer")),
-- contando com um jogador construindo. Criado fora desse contexto, um mod de
-- posicionamento da Workshop quebrou o jogo (visto no teste do bug #147). O
-- `tile_outline` não tem componente nenhum.
--
-- Por que local, em cada cliente: o prefab não tem rede (não chama
-- `entity:AddNetwork()`; o próprio arquivo marca "Non-networked entity"),
-- então um criado no servidor só apareceria na tela do host. Ele é carregado
-- com o mundo em todos os lados (prefabs/world.lua depende de "hud", e
-- prefabs/hud.lua depende de "gridplacer", que registra o tile_outline no
-- mesmo arquivo). Por isso cada cliente com tela (o host inclusive; nada no
-- servidor dedicado) cria os seus a partir da calibração, como a câmera faz
-- com o alvo (duelo/mod/camera.lua): `Calibracao.quando_calibrar` roda no
-- host depois do cálculo e nos clientes quando as netvars chegam.
--
-- O que o tile_outline já traz (prefabs/gridplacer.lua, tile_outline_fn):
-- tags CLASSIFIED e NOCLICK (o mouse não o seleciona), nenhuma física,
-- `persists = false`, `SetCanSleep(false)`, `SetLightOverride(1)` (aparece
-- de noite), camada LAYER_BACKGROUND deitada no chão
-- (ANIM_ORIENTATION.OnGround), animação parada. Uso: `SpawnPrefab` +
-- `Transform:SetPosition` no centro do tile.
--
-- Cor: `AnimState:SetMultColour(r, g, b, 1)` (o gridplacer do jogo usa
-- SetMultColour para ficar vermelho em OnCannotBuild). A multiplicação só
-- tira cor da arte, que é clara: no primeiro teste em jogo, com as cores dos
-- rótulos (azul claro 0,45/0,75/1 e salmão 1/0,5/0,45), o contorno do
-- jogador 1 saiu quase branco e o do 2 laranja, porque as outras componentes
-- continuavam altas. Por isso os contornos têm cores próprias
-- (Contornos.CORES), saturadas: a componente do dono em 1 e as outras bem
-- baixas, o que dá azul e vermelho nítidos sobre arte branca. A cor não usa
-- SetAddColour: somar cor a uma arte clara a leva para o branco, o contrário
-- do que se quer; a soma fica só para o destaque. Os rótulos continuam com
-- as cores claras, que se leem melhor em texto.
-- Destaque: `AnimState:SetAddColour(...)` clareia o contorno
-- (prefabs/seeds.lua usa SetAddColour num tile_outline);
-- `Contornos.destacar` fica pronto para a US #38 marcar os alvos válidos,
-- mas ainda não é chamado.
--
-- Este arquivo é Lua puro: tudo do jogo chega por `ctx` em `instalar`, para
-- os testes (tests/test_mod_mesa.lua) rodarem com um ambiente falso.

local Contornos = {}

Contornos.PREFAB = "tile_outline"
-- Cores dos contornos (r, g, b de SetMultColour): azul para o jogador 1,
-- vermelho para o 2 e amarelo para o que não tem dono (jogador 0).
Contornos.CORES = {
  [1] = { 0.1, 0.3, 1 },
  [2] = { 1, 0.1, 0.1 },
  neutro = { 1, 0.8, 0.1 },
}
-- Cor somada ao contorno destacado (r, g, b, a).
Contornos.DESTAQUE = { 0.35, 0.35, 0.35, 0 }
Contornos.SEM_DESTAQUE = { 0, 0, 0, 0 }

local estado = {
  GLOBAL = nil,
  Mesa = nil,
  contornos = {}, -- lista de { inst, jogador, tipo, n, parte }
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

-- Cor do contorno do dono (r, g, b); neutra sem dono.
function Contornos.cor(jogador)
  local c = Contornos.CORES[jogador] or Contornos.CORES.neutro
  return c[1], c[2], c[3]
end

-- Remove os contornos criados neste lado.
function Contornos.remover()
  for _, c in ipairs(estado.contornos) do
    if c.inst:IsValid() then c.inst:Remove() end
  end
  estado.contornos = {}
end

-- Cliente com tela (inclusive o host): remove os contornos antigos e cria um
-- tile_outline em cada um dos 62 tiles de espaço. Devolve a lista.
function Contornos.criar(calib)
  if dedicado() then return nil end
  Contornos.remover()
  local G = estado.GLOBAL
  for _, t in ipairs(estado.Mesa.tiles_dos_espacos(calib) or {}) do
    local inst = G.SpawnPrefab(Contornos.PREFAB)
    if inst == nil then
      if not estado.avisou then avisar("prefab tile_outline não achado: espaços sem contorno") end
      estado.avisou = true
      break
    end
    inst.Transform:SetPosition(t.x, 0, t.z)
    local r, g, b = Contornos.cor(t.jogador)
    inst.AnimState:SetMultColour(r, g, b, 1)
    inst.persists = false
    estado.contornos[#estado.contornos + 1] = { inst = inst, jogador = t.jogador, tipo = t.tipo, n = t.n,
      parte = t.parte }
  end
  return estado.contornos
end

function Contornos.lista()
  return estado.contornos
end

-- Destaca (ou apaga o destaque de) um espaço. `tipo`:
--   "criatura": os 2 tiles (carta e criatura) do espaço `n` do jogador;
--   "estrutura": os 2 tiles (carta e frente) da estrutura `n`;
--   "deck": os 2 tiles do deck `n` ("principal" ou "extra");
--   "combate": o quadrado de combate `n` do jogador (nil: os 6);
--   "descarte" | "destruidas": os 2 tiles do bloco do jogador (sem `n`);
--   "evento": o espaço de eventos, com jogador 0; `n` = "pilha" ou
--     "em_vigor", ou nil para os 2 tiles.
-- `n` na numeração da câmera. Devolve quantos contornos mudaram. Para a
-- US #38 (alvos válidos).
function Contornos.destacar(jogador, tipo, n, ligado)
  local cor = ligado == false and Contornos.SEM_DESTAQUE or Contornos.DESTAQUE
  local mudou = 0
  for _, c in ipairs(estado.contornos) do
    local mesmo_tipo = c.tipo == tipo or (tipo == "criatura" and c.tipo == "carta")
    if mesmo_tipo and c.jogador == jogador and (n == nil or c.n == n) and c.inst:IsValid() then
      c.inst.AnimState:SetAddColour(cor[1], cor[2], cor[3], cor[4])
      mudou = mudou + 1
    end
  end
  return mudou
end

-- Liga o módulo no ambiente do mod.
--   ctx.GLOBAL: ambiente global do jogo;
--   ctx.Mesa: duelo/mod/mesa;
--   ctx.Calibracao: duelo/mod/calibracao (já instalado).
-- Fora do servidor dedicado, cria os contornos a cada calibração.
function Contornos.instalar(ctx)
  estado.GLOBAL = ctx.GLOBAL
  estado.Mesa = ctx.Mesa
  estado.contornos = {}
  estado.avisou = false
  ctx.Calibracao.quando_calibrar(function(calib)
    if not dedicado() then Contornos.criar(calib) end
  end)
  return Contornos
end

return Contornos
