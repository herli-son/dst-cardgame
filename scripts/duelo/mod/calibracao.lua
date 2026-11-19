-- Calibração da mesa no jogo (US #30).
--
-- Os tiles da mesa já vêm da geração (static layout da US #29), mas a mesa
-- não fica num lugar fixo do mapa: o gerador escolhe onde a põe e espelha o
-- eixo x (scripts/duelo/mod/mesa.lua, cabeçalho). Este módulo descobre, sem
-- números fixos, onde a mesa ficou, e entrega a posição a todos:
--
--   * No servidor, `AddSimPostInit` (modutil.lua; mods.lua, ModWrangler:
--     SimPostInit) roda em gamelogic.lua (DoInitGame) depois de
--     PopulateWorld: o mapa (Map:SetFromString) e as entidades salvas, o
--     portal entre elas, já existem, e o forest_network também
--     (gamelogic.lua cria `<mapa>_network` dentro de PopulateWorld).
--   * O portal é achado por `TheSim:FindFirstEntityWithTag("multiplayer_portal")`
--     (a tag vem de prefabs/multiplayer_portal.lua; o mesmo FindFirstEntityWithTag
--     é usado em components/retrofitforestmap_anr.lua). A posição vem de
--     `Transform:GetWorldPosition()` e o tile dele de
--     `TheWorld.Map:GetTileCoordsAtPoint(x, 0, z)` (consolecommands.lua,
--     componentutil.lua).
--   * Em volta do tile do portal (Calibracao.RAIO tiles para cada lado), cada
--     tile é lido com `TheWorld.Map:GetTile(tx, ty)` (debugkeys.lua) e
--     comparado com `WORLD_TILES.CARPET` (o id vem de tiledefs.lua por
--     tilemanager.lua). Os tiles de carpete vão para Mesa.achar_carpete, e o
--     retângulo para Mesa.calibrar, com `TheWorld.Map:GetTileCenterPoint(tx, ty)`
--     (components/map.lua, IsTerraformingBlockedByAnObject; debugcommands.lua)
--     convertendo tile em posição do mundo. Sem carpete, a origem sai só do
--     portal (Mesa.calibrar_pelo_portal) e o log avisa.
--   * Os 16 espaços são conferidos com `TheWorld.Map:GetTileAtPoint(x, 0, z)`
--     (components/map.lua) contra `WORLD_TILES.MOSAIC_GREY`/`MOSAIC_BLUE`;
--     uma diferença só gera aviso no log.
--   * A calibração vai aos clientes por variáveis de rede no forest_network
--     (netvars.lua: `net_float` para a origem, `net_bool` para o
--     espelhamento, `net_tinybyte` para a fonte, 0 = ainda não calibrada),
--     declaradas nos dois lados por `AddPrefabPostInit("forest_network", ...)`,
--     como o relógio da US #31. Os clientes montam a mesma tabela em
--     Mesa.calibracao quando o evento "dirty" chega (e uma vez numa tarefa de
--     0 s, para o caso de os valores chegarem junto com a entidade).
--
-- Quem precisa da calibração (marcadores, câmera) se inscreve em
-- `Calibracao.quando_calibrar(fn)`: `fn(calib)` roda no servidor depois do
-- cálculo e nos clientes quando os valores chegam; se já houver calibração,
-- roda na hora. `DUELO.Calibracao.calibrar()` no console do servidor refaz
-- tudo (e os marcadores são recriados).
--
-- Este arquivo é Lua puro: tudo do jogo chega por `ctx` em `instalar`, para
-- os testes (tests/test_mod_mesa.lua) rodarem com um ambiente falso.

local Calibracao = {}

-- Raio da busca em volta do portal, em tiles: a mesa inteira cabe nele.
Calibracao.RAIO = 20

local FONTES = { carpete = 1, portal = 2 }
local NOMES_FONTE = { [1] = "carpete", [2] = "portal" }

local DIRTY = "duelo.mesadirty"

local estado = {
  GLOBAL = nil,
  Mesa = nil,
  rede = nil, -- netvars no forest_network
  ouvintes = {},
}

local function servidor()
  local w = estado.GLOBAL and estado.GLOBAL.TheWorld or nil
  return w ~= nil and w.ismastersim == true
end

local function avisar(msg)
  local p = estado.GLOBAL and estado.GLOBAL.print or print
  p("[duelo] " .. msg)
end

local function notificar(calib)
  for _, fn in ipairs(estado.ouvintes) do fn(calib) end
end

-- Inscreve `fn(calib)`; chama na hora se já houver calibração.
function Calibracao.quando_calibrar(fn)
  estado.ouvintes[#estado.ouvintes + 1] = fn
  local calib = estado.Mesa and estado.Mesa.calibracao or nil
  if calib ~= nil then fn(calib) end
end

-- Servidor: escreve a calibração nas netvars (se já existirem).
local function escrever(calib)
  local r = estado.rede
  if r == nil or calib == nil then return end
  r.origem_x:set(calib.origem_x)
  r.origem_z:set(calib.origem_z)
  r.espelhado:set(calib.espelhado == true)
  r.fonte:set(FONTES[calib.fonte] or FONTES.portal)
end

-- Cliente: lê as netvars e, se mudou, guarda em Mesa.calibracao.
local function ler()
  local r = estado.rede
  if r == nil then return nil end
  local fonte = r.fonte:value()
  if fonte == 0 then return nil end
  local calib = {
    origem_x = r.origem_x:value(),
    origem_z = r.origem_z:value(),
    espelhado = r.espelhado:value() == true,
    fonte = NOMES_FONTE[fonte] or "portal",
  }
  local atual = estado.Mesa.calibracao
  if atual ~= nil and atual.origem_x == calib.origem_x and atual.origem_z == calib.origem_z
    and atual.espelhado == calib.espelhado and atual.fonte == calib.fonte then
    return atual
  end
  estado.Mesa.definir_calibracao(calib)
  notificar(calib)
  return calib
end

local function post_init_rede(inst)
  local G = estado.GLOBAL
  estado.rede = {
    origem_x = G.net_float(inst.GUID, "duelo.mesa_origem_x", DIRTY),
    origem_z = G.net_float(inst.GUID, "duelo.mesa_origem_z", DIRTY),
    espelhado = G.net_bool(inst.GUID, "duelo.mesa_espelhado", DIRTY),
    fonte = G.net_tinybyte(inst.GUID, "duelo.mesa_fonte", DIRTY),
  }
  if servidor() then
    escrever(estado.Mesa.calibracao)
  else
    inst:ListenForEvent(DIRTY, ler)
    inst:DoTaskInTime(0, ler)
  end
end

-- Servidor: tiles de carpete em volta do tile (ptx, pty).
local function tiles_de_carpete(map, ptx, pty)
  local carpete = estado.GLOBAL.WORLD_TILES.CARPET
  local lista = {}
  local r = Calibracao.RAIO
  for tx = ptx - r, ptx + r do
    for ty = pty - r, pty + r do
      if map:GetTile(tx, ty) == carpete then
        lista[#lista + 1] = { x = tx, y = ty }
      end
    end
  end
  return lista
end

-- Servidor: quantos dos 16 espaços não caem no tile esperado.
local function conferir_espacos(map, calib)
  local Mesa, T = estado.Mesa, estado.GLOBAL.WORLD_TILES
  local erros = 0
  for p = 1, 2 do
    for n = 1, 6 do
      local x, z = Mesa.espaco_criatura_abs(p, n, calib)
      if map:GetTileAtPoint(x, 0, z) ~= T.MOSAIC_GREY then erros = erros + 1 end
    end
    for n = 1, 2 do
      local x, z = Mesa.espaco_estrutura_abs(p, n, calib)
      if map:GetTileAtPoint(x, 0, z) ~= T.MOSAIC_BLUE then erros = erros + 1 end
    end
  end
  return erros
end

-- Servidor: acha a mesa, guarda em Mesa.calibracao, manda aos clientes e
-- avisa os inscritos. Devolve a calibração (ou nil sem portal).
function Calibracao.calibrar()
  if not servidor() then
    avisar("Calibracao.calibrar só funciona no servidor")
    return nil
  end
  local G, Mesa = estado.GLOBAL, estado.Mesa
  local map = G.TheWorld.Map
  local portal = G.TheSim:FindFirstEntityWithTag("multiplayer_portal")
  if portal == nil then
    avisar("multiplayer_portal não achado: mesa sem calibração")
    return nil
  end
  local px, _, pz = portal.Transform:GetWorldPosition()
  local ptx, pty = map:GetTileCoordsAtPoint(px, 0, pz)
  local retangulo, motivo = Mesa.achar_carpete(tiles_de_carpete(map, ptx, pty))

  local calib
  if retangulo ~= nil then
    calib = Mesa.calibrar({
      carpete = retangulo,
      centro_mundo = function(tx, ty)
        local x, _, z = map:GetTileCenterPoint(tx, ty)
        return x, z
      end,
      portal = { x = px, z = pz },
    })
  else
    avisar("carpete da mesa não achado (" .. tostring(motivo) .. ")")
    calib = Mesa.calibrar_pelo_portal(px, pz)
  end
  if calib.aviso ~= nil then avisar(calib.aviso) end
  avisar(string.format("mesa calibrada pelo %s: origem (%.1f, %.1f), espelhado = %s, portal no tile (%d, %d)",
    calib.fonte, calib.origem_x, calib.origem_z, tostring(calib.espelhado), ptx, pty))

  local erros = conferir_espacos(map, calib)
  if erros > 0 then
    avisar(erros .. " dos 16 espaços não estão sobre o tile esperado")
  end

  Mesa.definir_calibracao(calib)
  escrever(calib)
  notificar(calib)
  return calib
end

-- Liga o módulo no ambiente do mod.
--   ctx.GLOBAL: ambiente global do jogo;
--   ctx.Mesa: duelo/mod/mesa;
--   ctx.AddSimPostInit, ctx.AddPrefabPostInit: de modutil.lua.
function Calibracao.instalar(ctx)
  estado.GLOBAL = ctx.GLOBAL
  estado.Mesa = ctx.Mesa
  estado.rede = nil
  estado.ouvintes = {}
  ctx.AddPrefabPostInit("forest_network", post_init_rede)
  ctx.AddSimPostInit(function()
    if servidor() then Calibracao.calibrar() end
  end)
  return Calibracao
end

return Calibracao
