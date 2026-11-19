-- Números e zonas da mesa (US #30).
--
-- Em cada um dos 16 espaços fica um marcador com o número e o dono
-- ("J1 3", "J2 E1"), na cor do jogador, e no centro um rótulo "Combate".
-- O marcador é o prefab do mod `duelo_marcador`
-- (scripts/prefabs/duelo_marcador.lua, registrado por PrefabFiles no
-- modmain): uma entidade de rede sem física, sem arte e sem clique, só com
-- um Label.
--
-- Por que um prefab de rede com netvars: o texto do Label é local (o motor
-- não o replica), então o servidor manda o que cada marcador é por três
-- `net_tinybyte` (netvars.lua: 0..7) — tipo (1 criatura, 2 estrutura,
-- 3 centro), jogador (0, 1, 2) e número (0..6) — e cada lado monta o
-- texto quando o evento "dirty" chega (netvars.lua: o "dirty" dispara no
-- servidor e nos clientes; no host o próprio servidor desenha). Num cliente
-- o rótulo também é montado uma vez numa tarefa de 0 s, para o caso de os
-- valores chegarem junto com a entidade. A posição vem do Transform, que já
-- é replicado. Assim, quando a partida (US #33, #37) precisar mudar um
-- marcador (destacar, esconder), basta o servidor mudar as netvars.
-- A alternativa de cada cliente criar entidades locais a partir da
-- calibração evitaria o prefab, mas deixaria o servidor sem como mexer neles.
--
-- Chamadas do jogo e onde se confirmam:
--   * `inst.entity:AddLabel()` e `Label:SetFont`, `SetFontSize`,
--     `SetWorldOffset`, `SetUIOffset`, `SetColour`, `SetText`, `Enable`:
--     prefabs/dummytarget.lua, prefabs/sounddebugicon.lua,
--     components/healthbar.lua. O Label é desenhado na tela (tamanho em
--     pixels, sempre de pé), então fica legível com qualquer heading.
--   * Fonte `TALKINGFONT` (fonts.lua; tem contorno, lê-se sobre qualquer
--     chão), com `DEFAULTFONT` de reserva.
--   * `SpawnPrefab`, `Transform:SetPosition`, `inst:Remove()`,
--     `inst:IsValid()`: entityscript.lua / mainfunctions.lua.
--   * `inst.persists = false` (mainfunctions.lua, SaveGame: só entra no save
--     quem tem `persists`; entityscript.lua o liga por padrão): o
--     marcador não é salvo; o servidor o recria a cada carga na calibração,
--     então não há duplicata ao recarregar.
--
-- Este arquivo é Lua puro: tudo do jogo chega por `ctx` em `instalar` (e
-- pelo `G` que o prefab passa a `preparar`), para os testes
-- (tests/test_mod_mesa.lua) rodarem com um ambiente falso.

local Marcadores = {}

Marcadores.PREFAB = "duelo_marcador"
Marcadores.TIPO = { criatura = 1, estrutura = 2, centro = 3 }
Marcadores.TEXTO_CENTRO = "Combate"

-- Cores (r, g, b em 0..1): azul para o jogador 1, vermelho para o 2.
Marcadores.CORES = {
  [1] = { 0.45, 0.75, 1 },
  [2] = { 1, 0.5, 0.45 },
  centro = { 1, 0.9, 0.6 },
}

Marcadores.TAMANHO = { espaco = 28, centro = 36 }

local DIRTY = "duelo_marcador.dirty"

local estado = {
  GLOBAL = nil,
  Mesa = nil,
  marcadores = {}, -- servidor: os marcadores criados
}

local function servidor()
  local w = estado.GLOBAL and estado.GLOBAL.TheWorld or nil
  return w ~= nil and w.ismastersim == true
end

-- Texto do marcador, ou nil se o marcador ainda não foi definido.
function Marcadores.texto(tipo, jogador, numero)
  if tipo == Marcadores.TIPO.centro then return Marcadores.TEXTO_CENTRO end
  if jogador ~= 1 and jogador ~= 2 then return nil end
  if numero == nil or numero < 1 then return nil end
  if tipo == Marcadores.TIPO.criatura then
    return "J" .. jogador .. " " .. numero
  elseif tipo == Marcadores.TIPO.estrutura then
    return "J" .. jogador .. " E" .. numero
  end
  return nil
end

function Marcadores.cor(tipo, jogador)
  local c = tipo == Marcadores.TIPO.centro and Marcadores.CORES.centro or Marcadores.CORES[jogador]
  c = c or Marcadores.CORES.centro
  return c[1], c[2], c[3]
end

-- Lê as netvars e atualiza o Label (servidor com tela e clientes).
function Marcadores.atualizar_rotulo(inst)
  local tipo = inst.duelo_tipo:value()
  local jogador = inst.duelo_jogador:value()
  local numero = inst.duelo_numero:value()
  local texto = Marcadores.texto(tipo, jogador, numero)
  local label = inst.Label
  if texto == nil then
    label:Enable(false)
    return nil
  end
  label:SetText(texto)
  label:SetColour(Marcadores.cor(tipo, jogador))
  label:SetFontSize(tipo == Marcadores.TIPO.centro and Marcadores.TAMANHO.centro or Marcadores.TAMANHO.espaco)
  label:Enable(true)
  return texto
end

-- Chamado pelo prefab nos dois lados, antes de SetPristine: declara as
-- netvars (iguais no servidor e nos clientes, netvars.lua), arruma o Label e,
-- fora do servidor dedicado, escuta o "dirty".
--   G: ambiente global do jogo (o prefab passa _G).
function Marcadores.preparar(inst, G)
  inst.duelo_tipo = G.net_tinybyte(inst.GUID, "duelo_marcador.tipo", DIRTY)
  inst.duelo_jogador = G.net_tinybyte(inst.GUID, "duelo_marcador.jogador", DIRTY)
  inst.duelo_numero = G.net_tinybyte(inst.GUID, "duelo_marcador.numero", DIRTY)

  local label = inst.Label
  label:SetFont(G.TALKINGFONT or G.DEFAULTFONT)
  label:SetFontSize(Marcadores.TAMANHO.espaco)
  label:SetWorldOffset(0, 0.5, 0)
  label:SetUIOffset(0, 0, 0)
  label:SetColour(1, 1, 1)
  label:SetText("")
  label:Enable(false)

  if not G.TheNet:IsDedicated() then
    inst:ListenForEvent(DIRTY, Marcadores.atualizar_rotulo)
    if not G.TheWorld.ismastersim then
      inst:DoTaskInTime(0, Marcadores.atualizar_rotulo)
    end
  end
end

-- Servidor: diz o que o marcador é (as netvars levam aos clientes).
function Marcadores.definir(inst, tipo, jogador, numero)
  inst.duelo_tipo:set(tipo)
  inst.duelo_jogador:set(jogador or 0)
  inst.duelo_numero:set(numero or 0)
end

local function criar_um(x, z, tipo, jogador, numero)
  local inst = estado.GLOBAL.SpawnPrefab(Marcadores.PREFAB)
  if inst == nil then return nil end
  inst.Transform:SetPosition(x, 0, z)
  Marcadores.definir(inst, tipo, jogador, numero)
  estado.marcadores[#estado.marcadores + 1] = inst
  return inst
end

-- Servidor: remove os marcadores antigos e cria os 17 (12 criaturas,
-- 4 estruturas e o centro) nas posições da calibração. Devolve a lista.
function Marcadores.criar(calib)
  if not servidor() then return nil end
  local Mesa = estado.Mesa
  Marcadores.remover()
  local T = Marcadores.TIPO
  for p = 1, 2 do
    for n = 1, 6 do
      local x, z = Mesa.espaco_criatura_abs(p, n, calib)
      criar_um(x, z, T.criatura, p, n)
    end
    for n = 1, 2 do
      local x, z = Mesa.espaco_estrutura_abs(p, n, calib)
      criar_um(x, z, T.estrutura, p, n)
    end
  end
  local cx, cz = Mesa.centro_abs(calib)
  criar_um(cx, cz, T.centro, 0, 0)
  return estado.marcadores
end

-- Servidor: remove os marcadores criados.
function Marcadores.remover()
  for _, inst in ipairs(estado.marcadores) do
    if inst:IsValid() then inst:Remove() end
  end
  estado.marcadores = {}
end

function Marcadores.lista()
  return estado.marcadores
end

-- Liga o módulo no ambiente do mod.
--   ctx.GLOBAL: ambiente global do jogo;
--   ctx.Mesa: duelo/mod/mesa;
--   ctx.Calibracao: duelo/mod/calibracao (já instalado).
-- No servidor, cria os marcadores a cada calibração.
function Marcadores.instalar(ctx)
  estado.GLOBAL = ctx.GLOBAL
  estado.Mesa = ctx.Mesa
  estado.marcadores = {}
  ctx.Calibracao.quando_calibrar(function(calib)
    if servidor() then Marcadores.criar(calib) end
  end)
  return Marcadores
end

return Marcadores
