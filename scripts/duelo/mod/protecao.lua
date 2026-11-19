-- Proteção dos jogadores: nada do mundo interfere no duelo (US #31).
--
-- Registrado por `AddPlayerPostInit` (modutil.lua: é um AddPrefabPostInitAny
-- filtrado pela tag "player"; roda depois de o prefab do jogador ser
-- construído, no servidor e nos clientes, para todo jogador que entra,
-- inclusive depois do início). O que cada chamada faz e onde se confirma:
--
-- Nos dois lados (o componente existe no servidor e no cliente,
-- prefabs/player_common.lua adiciona `playervision` antes do bloco
-- `ismastersim`):
--   * `playervision:ForceNightVision(true)` (components/playervision.lua):
--     liga a visão noturna permanente e dispara o evento "nightvision". No
--     servidor, components/grue.lua escuta esse evento (e consulta
--     `HasNightVision()` ao iniciar) e dá ao jogador a imunidade
--     "nightvision": o Charlie só ataca quem não tem nenhuma imunidade. No
--     cliente, components/ambientlighting.lua lê o mesmo estado ao ativar o
--     jogador (`CanEntitySeeInDark`) e clareia a luz ambiente; como
--     `forcenightvision` não é variável de rede, cada cliente precisa fazer
--     a própria chamada.
--   * `playervision:ForceNoNightVisionCC(true)` (components/playervision.lua,
--     UpdateCCTable): não aplica o filtro verde do chapéu de toupeira, para a
--     noite continuar com cara de noite (docs/investigacao-scripts-dst.md).
--
-- Só no servidor (componentes que só existem lá):
--   * `health:SetInvincible(true)` (components/health.lua): `DoDelta` ignora
--     todo dano com `invincible`; dispara "invincibletoggle", que o grue
--     também usa como imunidade. Cobre golpes, fome (o dano de fome passa por
--     `health:DoDelta`, cause = "hunger"), frio e calor
--     (components/temperature.lua, OnUpdate: retorna antes de qualquer
--     cálculo quando `health:IsInvincible()`) e afogamento
--     (components/drownable.lua, ShouldX_InternalCheck: "Godmode check").
--   * `hunger:Pause()` (components/hunger.lua): cancela a tarefa periódica
--     que desconta a fome; a barra fica parada em vez de só não matar.
--   * `sanity.ignore = true` (components/sanity.lua, OnUpdate: com `ignore`
--     e sem `redirect` não recalcula; é o mesmo campo que
--     prefabs/player_common.lua liga pelo modo de jogo `no_sanity`).
--   * `temperature:SetTemp(TUNING.STARTING_TEMP)` (components/temperature.lua,
--     SetTemp: com `settemp` definido, OnUpdate não altera a temperatura;
--     tuning.lua: STARTING_TEMP = 35). Garante a temperatura fixa mesmo se a
--     invencibilidade for mexida.
--
-- O jogo desfaz parte disso por conta própria: ao recarregar um jogador
-- salvo, prefabs/player_common.lua (EnableLoadingProtection /
-- DisableLoadingProtection) liga a invencibilidade e a desliga 1,5 s depois
-- da ativação; ao reviver (prefabs/player_common_extensions.lua,
-- CommonActualRez) chama `hunger:Resume()` e `temperature:SetTemp()`. Por
-- isso a proteção é reaplicada quando o evento "invincibletoggle" chega com
-- `invincible = false` (numa tarefa de 0 s, para não reentrar no próprio
-- evento) e em "ms_respawnedfromghost".
--
-- Não é preciso mexer em `playerdamage`/PVP: o dano entre jogadores também
-- passa por `health:DoDelta`. Também não desligamos `drownable` nem o
-- `grue` diretamente: os dois já se desligam pela invencibilidade e pela
-- visão noturna, como anotado acima.
--
-- Este arquivo é Lua puro: tudo do jogo chega por `ctx` em `instalar`, para
-- os testes (tests/test_mod_protecao.lua) rodarem com um ambiente falso.

local Protecao = {}

local estado = {
  GLOBAL = nil,
}

local function servidor()
  local w = estado.GLOBAL and estado.GLOBAL.TheWorld or nil
  return w ~= nil and w.ismastersim == true
end

-- Visão noturna: servidor e clientes.
function Protecao.aplicar_visao(inst)
  local visao = inst.components and inst.components.playervision or nil
  if visao == nil then return false end
  visao:ForceNightVision(true)
  visao:ForceNoNightVisionCC(true)
  return true
end

-- Invulnerabilidade, fome, sanidade e temperatura: só no servidor.
-- Idempotente: pode ser chamada quantas vezes for preciso.
function Protecao.aplicar_servidor(inst)
  local c = inst.components or {}
  if c.health ~= nil and not c.health:IsInvincible() then
    c.health:SetInvincible(true)
  end
  if c.hunger ~= nil then
    c.hunger:Pause()
  end
  if c.sanity ~= nil then
    c.sanity.ignore = true
  end
  if c.temperature ~= nil then
    local tuning = estado.GLOBAL and estado.GLOBAL.TUNING or nil
    c.temperature:SetTemp(tuning and tuning.STARTING_TEMP or 35)
  end
  return true
end

local function reaplicar_quando_desligarem(inst)
  inst:ListenForEvent("invincibletoggle", function(_, data)
    if data ~= nil and data.invincible == false then
      inst:DoTaskInTime(0, function()
        if inst:IsValid() then Protecao.aplicar_servidor(inst) end
      end)
    end
  end)
  inst:ListenForEvent("ms_respawnedfromghost", function()
    Protecao.aplicar_servidor(inst)
  end)
end

-- Post init de cada jogador.
function Protecao.aplicar(inst)
  Protecao.aplicar_visao(inst)
  if servidor() then
    Protecao.aplicar_servidor(inst)
    reaplicar_quando_desligarem(inst)
  end
end

-- Liga o módulo no ambiente do mod.
--   ctx.GLOBAL: ambiente global do jogo;
--   ctx.AddPlayerPostInit: de modutil.lua.
function Protecao.instalar(ctx)
  estado.GLOBAL = ctx.GLOBAL
  ctx.AddPlayerPostInit(Protecao.aplicar)
  return Protecao
end

return Protecao
