-- Static layout da mesa do duelo (US #29), no formato que o Tiled exporta
-- para Lua e que map/static_layout.lua (StaticLayout.Get) lê:
--
--   * `tilewidth = 64`: um valor de `data` por tile (o leitor divide 64 pela
--     largura do tile para saber quantos valores pular; com 64 não pula nada).
--   * camada `BG_TILES`: índices na ordem GROUND_TYPES (0 = não mexe no chão).
--   * camada `FG_OBJECTS`: objetos com `type` = prefab e posição em pixels
--     (64 px por tile, origem no canto noroeste); o leitor converte para
--     tiles relativos ao centro do layout.
--
-- O conteúdo vem de duelo/mod/mesa.lua, que é a única fonte da geometria;
-- este arquivo só o traduz para o formato do Tiled. Vive em scripts/duelo/mod/
-- porque a pasta scripts/ do mod entra no package.path durante o carregamento
-- do modworldgenmain (mods.lua), então `require("duelo/mod/layouts/mesa")`
-- funciona do jeito que StaticLayout.Get espera; não precisa estar em
-- scripts/map/static_layouts/.

local Mesa = require("duelo/mod/mesa")

local PX_POR_TILE = 64

local function objeto(prefab, x_tiles, z_tiles)
  -- x_tiles/z_tiles são relativos ao centro do layout; o Tiled conta do canto.
  return {
    name = "",
    type = prefab,
    shape = "rectangle",
    x = (x_tiles + Mesa.LARGURA / 2) * PX_POR_TILE,
    y = (z_tiles + Mesa.ALTURA / 2) * PX_POR_TILE,
    width = 0,
    height = 0,
    visible = true,
    properties = {},
  }
end

return {
  version = "1.1",
  luaversion = "5.1",
  orientation = "orthogonal",
  width = Mesa.LARGURA,
  height = Mesa.ALTURA,
  tilewidth = PX_POR_TILE,
  tileheight = PX_POR_TILE,
  properties = {},
  tilesets = {
    {
      name = "tiles",
      firstgid = 1,
      tilewidth = PX_POR_TILE,
      tileheight = PX_POR_TILE,
      spacing = 0,
      margin = 0,
      image = "tiles.png",
      imagewidth = 512,
      imageheight = 448,
      properties = {},
      tiles = {},
    },
  },
  layers = {
    {
      type = "tilelayer",
      name = "BG_TILES",
      x = 0,
      y = 0,
      width = Mesa.LARGURA,
      height = Mesa.ALTURA,
      visible = true,
      opacity = 1,
      properties = {},
      encoding = "lua",
      data = Mesa.dados_bg_tiles(),
    },
    {
      type = "objectgroup",
      name = "FG_OBJECTS",
      visible = true,
      opacity = 1,
      properties = {},
      objects = {
        -- O portal é exigido pela location forest (required_prefabs) e é por
        -- onde os jogadores entram. O multiplayer_portal não registra ponto de
        -- nascimento (components/playerspawner.lua escuta
        -- ms_registerspawnpoint, que só os prefabs spawnpoint_* disparam),
        -- então o spawnpoint_master vai junto, no mesmo ponto.
        objeto("multiplayer_portal", Mesa.PORTAL.x, Mesa.PORTAL.z),
        objeto("spawnpoint_master", Mesa.PORTAL.x, Mesa.PORTAL.z),
      },
    },
  },
}
