-- Geração do mundo do mod (US #29): o nível "Mesa do duelo".
--
-- Este arquivo roda no carregamento da geração de mundo (mods.lua carrega
-- modworldgenmain.lua na tela de criação e no processo que gera o mapa). Ele
-- registra, nesta ordem:
--
--   1. o static layout da mesa, na tabela Layouts de map/layouts.lua (é onde
--      map/object_layout.lua procura um layout pelo nome; modutil.lua não tem
--      AddLayout, então a inserção é direta na tabela);
--   2. uma task com só a sala Blank (vazia e intransitável), um task set com
--      essa task e uma start location que põe o layout no nó de início;
--   3. o nível, que aparece como predefinição na criação de mundo e pode ser
--      escolhido num servidor dedicado pelo worldgenoverride.lua.
--
-- Chaves de `overrides`: todas conferidas em map/customize.lua (nomes dos
-- itens de WORLDGEN_GROUP, WORLDGEN_MISC e WORLDSETTINGS_GROUP, com valores
-- das listas de descrições de lá). Em resumo:
--
--   * WORLDGEN_GROUP.misc: task_set, start_location, world_size, branching,
--     loop, roads, touchstone, boons, prefabswaps_start, moon_fissure,
--     terrariumchest, stageplays, junkyard, balatro.
--   * WORLDGEN_GROUP.global: season_start (valores: default, winter, spring,
--     summer e combinações; "default" é o outono, map/forest_map.lua).
--   * WORLDGEN_GROUP.monsters/animals/resources: a lista de prefabs do mapa,
--     com never..insane (os itens ocean_* usam ocean_never..ocean_insane).
--   * WORLDGEN_MISC: has_ocean, layout_mode, keep_disconnected_tiles,
--     no_joining_islands (não são itens da tela; são repassados ao gerador,
--     map/forest_map.lua, e a location forest os define em map/locations.lua).
--   * WORLDSETTINGS_GROUP: chefes (giants), mutações lunares, monstros,
--     animais, regrowth, portal_resources, misc (clima, invasões, fendas) e
--     global (specialevent, estações, dia, sobreviventes).
--   * traps, poi e protected NÃO são itens de customize.lua: são chaves que o
--     nível da Forja (map/levels/lavaarena.lua) usa e que o gerador repassa
--     como override de tempo de execução; ficam aqui pelo mesmo motivo.
--
-- As quatro estações em "noseason" mandam ms_setseasonlength com 0 para
-- todas; components/seasons.lua trata isso sem travar (GetNextSeason devolve
-- a própria estação quando nenhuma tem duração), então o mundo fica no outono.
--
-- O que NÃO é feito aqui: relógio e visão noturna (US #31), tiles e câmera
-- (US #30). Cavernas não são chave de nível: basta o servidor não subir o
-- shard das cavernas (docs/mod.md).

local Layouts = GLOBAL.require("map/layouts").Layouts
local StaticLayout = GLOBAL.require("map/static_layout")

local LAYOUT = "DueloMesa"
local SALA = "Blank" -- sala vazia e intransitável de map/rooms.lua
local TASK = "duelo_mesa_task"
local TASK_SET = "duelo_mesa_taskset"
local START = "duelo_mesa_start"
local NIVEL = "DUELO_MESA"

-- 1. Layout da mesa (geometria em scripts/duelo/mod/mesa.lua).
Layouts[LAYOUT] = StaticLayout.Get("duelo/mod/layouts/mesa", {
  start_mask = GLOBAL.PLACE_MASK.IGNORE_IMPASSABLE_BARREN_RESERVED,
  fill_mask = GLOBAL.PLACE_MASK.IGNORE_IMPASSABLE_BARREN_RESERVED,
  layout_position = GLOBAL.LAYOUT_POSITION.CENTER,
  disable_transform = true, -- sem rotação aleatória: a mesa tem lado norte e sul
})

-- 2. Task, task set e start location.
AddTask(TASK, {
  locks = {},
  keys_given = {},
  room_choices = { [SALA] = 1 },
  background_room = SALA,
  room_bg = WORLD_TILES.IMPASSABLE,
  colour = { r = 0.2, g = 0.6, b = 0.9, a = 1 },
})

AddTaskSet(TASK_SET, {
  name = "Mesa do duelo",
  location = "forest",
  tasks = { TASK },
  valid_start_tasks = { TASK },
})

AddStartLocation(START, {
  name = "Mesa do duelo",
  location = "forest",
  start_setpeice = LAYOUT,
  start_node = SALA,
})

-- 3. Nível.
local overrides = {
  -- Geração: só a nossa task, mapa pequeno, sem estradas nem extras.
  task_set = TASK_SET,
  start_location = START,
  world_size = "small",
  branching = "never",
  loop = "never",
  roads = "never",
  touchstone = "never",
  boons = "never",
  prefabswaps_start = "classic",
  moon_fissure = "never",
  terrariumchest = "never",
  stageplays = "never",
  junkyard = "never",
  balatro = "never",
  season_start = "default", -- outono

  -- Geração (WORLDGEN_MISC): sem oceano; o resto segue a Forja.
  has_ocean = false,
  layout_mode = "RestrictNodesByKey",
  keep_disconnected_tiles = true,
  no_joining_islands = true,

  -- Chaves da Forja repassadas ao gerador (não são itens de customize.lua).
  traps = "never",
  poi = "never",
  protected = "never",

  -- Geração: monstros do mapa.
  spiders = "never",
  houndmound = "never",
  merm = "never",
  tentacles = "never",
  chess = "never",
  walrus = "never",
  moon_spiders = "never",
  ocean_waterplant = "ocean_never",
  angrybees = "never",
  tallbirds = "never",

  -- Geração: animais do mapa.
  rabbits = "never",
  moles = "never",
  buzzard = "never",
  catcoon = "never",
  pigs = "never",
  lightninggoat = "never",
  beefalo = "never",
  bees = "never",
  moon_carrot = "never",
  moon_fruitdragon = "never",
  ocean_shoal = "never",
  ocean_wobsterden = "never",
  ocean_otterdens = "never",

  -- Geração: recursos do mapa.
  flowers = "never",
  grass = "never",
  sapling = "never",
  marshbush = "never",
  tumbleweed = "never",
  reeds = "never",
  trees = "never",
  flint = "never",
  rock = "never",
  rock_ice = "never",
  meteorspawner = "never",
  berrybush = "never",
  carrot = "never",
  mushroom = "never",
  cactus = "never",
  moon_tree = "never",
  moon_sapling = "never",
  moon_berrybush = "never",
  moon_rock = "never",
  moon_hotspring = "never",
  moon_starfish = "never",
  moon_bullkelp = "never",
  ponds = "never",
  ocean_bullkelp = "never",
  ocean_seastack = "ocean_never",
  palmconetree = "never",

  -- Configurações: chefes.
  liefs = "never",
  deciduousmonster = "never",
  bearger = "never",
  deerclops = "never",
  goosemoose = "never",
  dragonfly = "never",
  antliontribute = "never",
  crabking = "never",
  beequeen = "never",
  malbatross = "never",
  fruitfly = "never",
  klaus = "never",
  spiderqueen = "never",
  eyeofterror = "never",
  daywalker2 = "never",
  sharkboi = "never",

  -- Configurações: mutações lunares.
  mutated_hounds = "never",
  penguins_moon = "never",
  moon_spider = "never",
  mutated_birds = "never",
  mutated_merm = "never",
  mutated_spiderqueen = "never",
  mutated_bird_gestalt = "never",
  mutated_buzzard_gestalt = "never",
  mutated_deerclops = "never",
  mutated_bearger = "never",
  mutated_warg = "never",

  -- Configurações: monstros e invasões.
  lureplants = "never",
  hound_mounds = "never",
  mosquitos = "never",
  sharks = "never",
  squid = "never",
  wasps = "never",
  frogs = "never",
  walrus_setting = "never",
  cookiecutters = "never",
  pirateraids = "never",
  merms = "never",
  spiders_setting = "never",
  spider_warriors = "never",
  bats_setting = "never",
  hounds = "never",
  winterhounds = "never",
  summerhounds = "never",
  hunt = "never",
  alternatehunt = "never",
  krampus = "never",
  shadowcreatures = "never",
  brightmarecreatures = "never",

  -- Configurações: animais.
  butterfly = "never",
  birds = "never",
  perd = "never",
  penguins = "never",
  bees_setting = "never",
  catcoons = "never",
  rabbits_setting = "never",
  wobsters = "never",
  gnarwail = "never",
  fishschools = "never",
  otters_setting = "never",
  moles_setting = "never",
  grassgekkos = "never",
  beefaloheat = "never",

  -- Configurações: rebrota e recursos do portal.
  regrowth = "never",
  evergreen_regrowth = "never",
  deciduoustree_regrowth = "never",
  twiggytrees_regrowth = "never",
  moon_tree_regrowth = "never",
  flowers_regrowth = "never",
  carrots_regrowth = "never",
  reeds_regrowth = "never",
  cactus_regrowth = "never",
  saltstack_regrowth = "never",
  palmconetree_regrowth = "never",
  basicresource_regrowth = "none",
  portal_spawnrate = "never",
  bananabush_portalrate = "never",
  lightcrab_portalrate = "never",
  monkeytail_portalrate = "never",
  palmcone_seed_portalrate = "never",
  powder_monkey_portalrate = "never",

  -- Configurações: clima, fendas e eventos de mundo.
  weather = "never",
  lightning = "never",
  frograin = "never",
  wildfires = "never",
  petrification = "none",
  meteorshowers = "never",
  rifts_enabled = "never",
  rifts_frequency = "never",
  lunarhail_frequency = "never",
  wanderingtrader_enabled = "none",
  disease_delay = "none",

  -- Configurações: eventos sazonais e estações. Com specialevent = "none" os
  -- eventos individuais ficam em "default" (= não forçados).
  specialevent = "none",
  autumn = "noseason",
  winter = "noseason",
  spring = "noseason",
  summer = "noseason",
  day = "default", -- a divisão 5/5/6 é feita pelo relógio (US #31)

  -- Configurações: sobreviventes. O duelo não usa fome, frio nem morte.
  spawnmode = "fixed",
  ghostenabled = "none",
  ghostsanitydrain = "none",
  portalresurection = "none",
  resettime = "none",
  healthpenalty = "none",
  temperaturedamage = "nonlethal",
  hunger = "nonlethal",
  -- darkness fica no padrão: a visão noturna da US #31 já impede o Charlie.
  extrastartingitems = "none",
  seasonalstartingitems = "never",
  spawnprotection = "never",
}

AddLevel(LEVELTYPE.SURVIVAL, {
  id = NIVEL,
  name = "Mesa do duelo",
  desc = "Mundo mínimo do DST Card Game: só a mesa, o portal e nada mais.",
  location = "forest",
  version = 2, -- formato novo de overrides (tabela chave = valor), modcompatability.lua
  overrides = overrides,
  required_prefabs = { "multiplayer_portal" },
  background_node_range = { 0, 1 },
})
