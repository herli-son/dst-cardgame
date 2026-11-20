-- Marcador de um espaço da mesa (US #30): só um texto no chão, sem arte,
-- sem física e sem clique. O que ele mostra vem de scripts/duelo/mod/marcadores.lua.
--
-- Arquivo de prefab do mod: registrado por `PrefabFiles` no modmain.lua
-- (mods.lua, RegisterPrefabs: carrega "prefabs/<nome>" da pasta scripts do
-- mod com LoadPrefabFile, mainfunctions.lua). Roda no ambiente global do
-- jogo, como os prefabs da Klei, por isso usa CreateEntity, TheWorld e
-- Prefab direto.
--
-- Estrutura de prefab de rede (o mesmo esqueleto de prefabs/dummytarget.lua):
--   * `entity:AddTransform()`, `entity:AddNetwork()` (a posição é
--     replicada) e `entity:AddLabel()` (o texto, local a cada lado);
--   * tags `NOCLICK` (o mouse não o seleciona), `FX` e `NOBLOCK` (não
--     atrapalha construir nem andar; nenhuma física é adicionada);
--   * as netvars são declaradas antes de `entity:SetPristine()`, nos dois
--     lados (netvars.lua);
--   * `if not TheWorld.ismastersim then return inst end`: o resto é só do
--     servidor — `persists = false` (o marcador não vai para o save; a
--     calibração o recria a cada carga) e `inst.Definir`.

local Marcadores = require("duelo/mod/marcadores")

local function fn()
  local inst = CreateEntity()

  inst.entity:AddTransform()
  inst.entity:AddNetwork()
  inst.entity:AddLabel()

  inst:AddTag("NOCLICK")
  inst:AddTag("FX")
  inst:AddTag("NOBLOCK")

  Marcadores.preparar(inst, _G)

  inst.entity:SetPristine()

  if not TheWorld.ismastersim then
    return inst
  end

  inst.persists = false
  inst.Definir = Marcadores.definir

  return inst
end

return Prefab("duelo_marcador", fn)
