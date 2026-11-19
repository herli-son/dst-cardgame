-- Testes do mundo mínimo com a arena (US #29).
--
-- O código do mod não roda aqui de verdade: não há motor do jogo. O que dá
-- para conferir fora do jogo é (a) que os três arquivos do mod compilam e rodam
-- num ambiente falso, (b) o que eles registram, (c) os dados do layout e
-- (d) a conversão de tiles para unidades do mundo. O teste de verdade é no
-- jogo (docs/mod.md).
--
-- Os arquivos são lidos relativos à raiz do repositório, de onde o runner
-- roda (package.path começa com "scripts/?.lua").

local Mesa = require("duelo/mod/mesa")

local RAIZ = "./"

-- Ambiente falso de modworldgenmain: captura o que o mod registra.
local function ambiente_worldgen()
  local reg = { levels = {}, tasks = {}, tasksets = {}, starts = {}, rooms = {}, layouts = {} }
  local modulos = {
    ["map/layouts"] = { Layouts = reg.layouts },
    ["map/static_layout"] = {
      Get = function(caminho, extras)
        local layout = extras or {}
        layout.layout_file = caminho
        layout.fonte = require(caminho)
        return layout
      end,
    },
  }
  local GLOBAL = {
    require = function(nome)
      return modulos[nome] or require(nome)
    end,
    PLACE_MASK = { IGNORE_IMPASSABLE_BARREN_RESERVED = 7 },
    LAYOUT_POSITION = { RANDOM = 0, CENTER = 1 },
  }
  local env = {
    GLOBAL = GLOBAL,
    LEVELTYPE = { SURVIVAL = "survival" },
    WORLD_TILES = { IMPASSABLE = 1 },
    AddLevel = function(tipo, dados) reg.levels[#reg.levels + 1] = { tipo = tipo, dados = dados } end,
    AddTask = function(nome, dados) reg.tasks[nome] = dados end,
    AddTaskSet = function(nome, dados) reg.tasksets[nome] = dados end,
    AddStartLocation = function(nome, dados) reg.starts[nome] = dados end,
    AddRoom = function(nome, dados) reg.rooms[nome] = dados end,
    pairs = pairs, ipairs = ipairs, type = type, tostring = tostring,
    string = string, table = table, math = math, print = function() end,
  }
  return env, reg
end

local function rodar(arquivo, env)
  local fn, err = loadfile(RAIZ .. arquivo)
  assert(fn, err)
  setfenv(fn, env)
  return fn()
end

-- Roda modworldgenmain uma vez por caso (ele é barato) e devolve os registros.
local function registrar()
  local env, reg = ambiente_worldgen()
  rodar("modworldgenmain.lua", env)
  return reg
end

local function nivel(reg)
  return reg.levels[1].dados
end

local function contem(lista, valor)
  for _, v in ipairs(lista) do
    if v == valor then return true end
  end
  return false
end

return {
  { "modinfo.lua compila e declara os campos obrigatórios", function(T)
    local env = {}
    rodar("modinfo.lua", env)
    T.eq(type(env.name), "string", "name")
    T.eq(type(env.description), "string", "description")
    T.eq(env.author, "herli-son", "author")
    T.eq(env.version, "0.1.0", "version")
    T.eq(env.api_version, 10, "api_version")
    T.eq(env.dst_compatible, true, "dst_compatible")
    T.eq(env.dont_starve_compatible, false, "dont_starve_compatible")
    T.eq(env.all_clients_require_mod, true, "all_clients_require_mod")
    T.eq(env.client_only_mod, false, "client_only_mod")
    T.eq(type(env.server_filter_tags), "table", "server_filter_tags")
    T.eq(type(env.configuration_options), "table", "configuration_options")
    T.eq(env.icon, nil, "sem ícone enquanto não houver arquivo")
    T.eq(env.icon_atlas, nil, "sem atlas de ícone")
  end },

  { "modmain.lua compila e expõe a mesa", function(T)
    local servidor = false
    -- Ambiente mínimo do modmain: as funções de modutil.lua que ele usa são
    -- stubs vazios (a US #31 as testa em tests/test_mod_protecao.lua).
    local env = {
      GLOBAL = {
        require = require,
        TheNet = { GetIsServer = function() servidor = true; return true end },
      },
      GetModConfigData = function() return nil end,
      AddPlayerPostInit = function() end,
      AddComponentPostInit = function() end,
      AddPrefabPostInit = function() end,
    }
    rodar("modmain.lua", env)
    T.eq(env.DUELO.Mesa, Mesa, "DUELO.Mesa é o módulo duelo/mod/mesa")
    T.ok(servidor, "consulta se é servidor")
  end },

  { "modworldgenmain.lua registra layout, task, task set, start e nível", function(T)
    local reg = registrar()
    T.eq(#reg.levels, 1, "um nível")
    T.eq(reg.levels[1].tipo, "survival", "tipo SURVIVAL")
    local n = nivel(reg)
    T.ok(n.id and n.id:sub(1, 7) ~= "CUSTOM_", "id sem prefixo CUSTOM_")
    T.eq(n.location, "forest", "location")
    T.ok(n.version >= 2, "versão 2 do formato de overrides")
    T.eq(type(n.name), "string", "name")
    T.eq(type(n.desc), "string", "desc")
    T.ok(contem(n.required_prefabs, "multiplayer_portal"), "exige o portal")

    local ts = reg.tasksets[n.overrides.task_set]
    T.ok(ts, "task_set aponta para um task set registrado")
    T.eq(ts.location, "forest", "task set na floresta")
    T.eq(#ts.tasks, 1, "uma task")
    local task = reg.tasks[ts.tasks[1]]
    T.ok(task, "a task do task set foi registrada")
    T.ok(contem(ts.valid_start_tasks, ts.tasks[1]), "a task é início válido")
    T.eq(task.room_choices.Blank, 1, "só a sala Blank")
    T.eq(task.background_room, "Blank", "fundo Blank")
    T.eq(task.room_bg, 1, "fundo IMPASSABLE")
    T.eq(#task.locks, 0, "sem locks")
    T.eq(#task.keys_given, 0, "sem keys")

    local st = reg.starts[n.overrides.start_location]
    T.ok(st, "start_location aponta para um start registrado")
    T.eq(st.location, "forest", "start na floresta")
    T.eq(st.start_node, "Blank", "nó de início Blank")
    local layout = reg.layouts[st.start_setpeice]
    T.ok(layout, "start_setpeice aponta para o layout registrado")
    T.eq(layout.layout_file, "duelo/mod/layouts/mesa", "arquivo do layout")
    T.eq(layout.disable_transform, true, "sem rotação aleatória")
    T.eq(layout.layout_position, 1, "layout no centro")
  end },

  { "nível zera geração, chefes, invasões, clima, eventos e estações", function(T)
    local o = nivel(registrar()).overrides
    T.eq(o.world_size, "small", "world_size")
    T.eq(o.roads, "never", "roads")
    T.eq(o.has_ocean, false, "has_ocean")
    T.eq(o.season_start, "default", "season_start (default = outono)")
    for _, chave in ipairs({
      "touchstone", "boons", "traps", "poi", "protected", "branching", "loop",
      "spiders", "houndmound", "merm", "tentacles", "walrus", "pigs", "beefalo", "rabbits",
      "trees", "grass", "berrybush", "flint", "rock", "ponds",
      "deerclops", "bearger", "goosemoose", "dragonfly", "antliontribute", "crabking",
      "beequeen", "malbatross", "klaus", "spiderqueen", "eyeofterror", "daywalker2",
      "hounds", "winterhounds", "summerhounds", "pirateraids", "lureplants", "hound_mounds",
      "hunt", "alternatehunt", "krampus", "shadowcreatures", "brightmarecreatures",
      "weather", "lightning", "frograin", "wildfires", "meteorshowers",
      "rifts_enabled", "rifts_frequency", "lunarhail_frequency", "regrowth",
      "birds", "butterfly", "penguins", "perd",
    }) do
      T.eq(o[chave], "never", chave)
    end
    T.eq(o.ocean_seastack, "ocean_never", "ocean_seastack usa a escala ocean_*")
    T.eq(o.ocean_waterplant, "ocean_never", "ocean_waterplant usa a escala ocean_*")
    T.eq(o.petrification, "none", "petrification")
    T.eq(o.specialevent, "none", "specialevent")
    T.eq(o.wanderingtrader_enabled, "none", "wanderingtrader_enabled")
    -- A tela do jogo exige pelo menos uma estação com duração.
    T.eq(o.autumn, "verylongseason")
    for _, estacao in ipairs({ "winter", "spring", "summer" }) do
      T.eq(o[estacao], "noseason", estacao)
    end
    T.eq(o.ghostenabled, "none", "sem fantasmas")
    T.eq(o.spawnmode, "fixed", "nascimento no portal")
    for _, chave in ipairs({ "crow_carnival", "hallowed_nights", "winters_feast" }) do
      T.eq(o[chave], nil, chave .. " não é forçado")
    end
  end },

  { "layout tem width*height tiles válidos e o portal em FG_OBJECTS", function(T)
    local layout = require("duelo/mod/layouts/mesa")
    T.eq(layout.width, layout.height, "layout quadrado")
    T.eq(layout.width, Mesa.LARGURA, "largura da mesa")
    T.eq(layout.tilewidth, 64, "um valor por tile")
    local bg, fg
    for _, camada in ipairs(layout.layers) do
      if camada.type == "tilelayer" and camada.name == "BG_TILES" then bg = camada end
      if camada.type == "objectgroup" and camada.name:find("FG_OBJECTS") then fg = camada end
    end
    T.ok(bg, "camada BG_TILES")
    T.ok(fg, "camada FG_OBJECTS")
    T.eq(#bg.data, layout.width * layout.height, "width*height valores")
    local validos = {}
    for _, i in pairs(Mesa.TILE) do validos[i] = true end
    local usados = {}
    for _, v in ipairs(bg.data) do
      T.ok(validos[v], "índice de tile válido: " .. tostring(v))
      usados[v] = (usados[v] or 0) + 1
    end
    T.eq(usados[Mesa.TILE.MOSAICO_CINZA], 12, "12 espaços de criatura")
    T.eq(usados[Mesa.TILE.MOSAICO_AZUL], 4, "4 espaços de estrutura")
    T.eq(usados[Mesa.TILE.CARPETE], 8 * 4, "centro 8x4")
    T.eq(usados[Mesa.TILE.FORA], 20 * 20 - 16 * 16, "fora da mesa só a borda")
    -- bordas de fora: primeira e última linha e coluna
    for col = 0, Mesa.LARGURA - 1 do
      T.eq(bg.data[col + 1], 0, "linha 0 fora")
      T.eq(bg.data[(Mesa.ALTURA - 1) * Mesa.LARGURA + col + 1], 0, "última linha fora")
    end

    local portal, spawn
    for _, obj in ipairs(fg.objects) do
      if obj.type == "multiplayer_portal" then portal = obj end
      if obj.type == "spawnpoint_master" then spawn = obj end
    end
    T.ok(portal, "multiplayer_portal no layout")
    T.ok(spawn, "spawnpoint_master no layout")
    T.eq(portal.x, spawn.x, "spawn no portal (x)")
    T.eq(portal.y, spawn.y, "spawn no portal (y)")
    -- Conversão de map/static_layout.lua: x/64 - width/2 (tilefactor 1).
    local x = (portal.x + portal.width / 2) / 64 - layout.width / 2
    local y = (portal.y + portal.height / 2) / 64 - layout.height / 2
    T.eq(x, Mesa.PORTAL.x, "portal em x (tiles)")
    T.eq(y, Mesa.PORTAL.z, "portal em z (tiles)")
    -- O portal fica sobre chão da mesa, não sobre um espaço nem fora.
    local col = math.floor(x + layout.width / 2)
    local lin = math.floor(y + layout.height / 2)
    T.eq(Mesa.uso_em(col, lin), "chao", "portal sobre o chão")
  end },

  { "espaços de mesa.lua caem nos tiles certos, sem sobreposição", function(T)
    local bg = require("duelo/mod/layouts/mesa").layers[1].data
    local function tile(col, lin) return bg[lin * Mesa.LARGURA + col + 1] end
    local ocupados = {}
    local function marcar(e, nome)
      local chave = e.col .. "," .. e.lin
      T.ok(not ocupados[chave], nome .. " sobrepõe " .. tostring(ocupados[chave]))
      ocupados[chave] = nome
    end
    for jogador = 1, 2 do
      local j = Mesa.JOGADORES[jogador]
      T.eq(#j.criaturas, 6, "6 criaturas do jogador " .. jogador)
      T.eq(#j.estruturas, 2, "2 estruturas do jogador " .. jogador)
      for n, e in ipairs(j.criaturas) do
        T.eq(tile(e.col, e.lin), Mesa.TILE.MOSAICO_CINZA, "criatura " .. jogador .. "/" .. n)
        T.eq(Mesa.espaco_criatura(jogador, n), e, "espaco_criatura")
        marcar(e, "criatura " .. jogador .. "/" .. n)
      end
      for n, e in ipairs(j.estruturas) do
        T.eq(tile(e.col, e.lin), Mesa.TILE.MOSAICO_AZUL, "estrutura " .. jogador .. "/" .. n)
        T.eq(Mesa.espaco_estrutura(jogador, n), e, "espaco_estrutura")
        marcar(e, "estrutura " .. jogador .. "/" .. n)
      end
    end
    local c = Mesa.CENTRO
    for lin = c.lin_min, c.lin_max do
      for col = c.col_min, c.col_max do
        T.eq(tile(col, lin), Mesa.TILE.CARPETE, "centro " .. col .. "," .. lin)
        marcar({ col = col, lin = lin }, "centro")
      end
    end
    -- Cada jogador conta da sua esquerda: o espaço n de um fica de frente
    -- para o 7 - n do outro (mesma coluna).
    for n = 1, 6 do
      T.eq(Mesa.espaco_criatura(1, n).col, Mesa.espaco_criatura(2, 7 - n).col, "espaço " .. n .. " frente ao " .. (7 - n))
    end
    T.eq(Mesa.espaco_estrutura(1, 1).col, Mesa.espaco_estrutura(2, 2).col, "estrutura 1 frente à 2")
    -- Jogador 1 (sul) conta do oeste para o leste; jogador 2 (norte), ao contrário.
    T.ok(Mesa.espaco_criatura(1, 1).col < Mesa.espaco_criatura(1, 6).col, "jogador 1 cresce para o leste")
    T.ok(Mesa.espaco_criatura(2, 1).col > Mesa.espaco_criatura(2, 6).col, "jogador 2 cresce para o oeste")
    T.ok(Mesa.espaco_criatura(1, 1).lin > Mesa.espaco_criatura(2, 1).lin, "jogador 1 ao sul do jogador 2")
  end },

  { "centro_do_tile e posicao usam TILE_SCALE = 4 relativo ao centro do layout", function(T)
    T.eq(Mesa.TILE_SCALE, 4, "TILE_SCALE")
    local x, z = Mesa.centro_do_tile(0, 0)
    T.eq(x, -38, "canto noroeste x")
    T.eq(z, -38, "canto noroeste z")
    x, z = Mesa.centro_do_tile(19, 19)
    T.eq(x, 38, "canto sudeste x")
    T.eq(z, 38, "canto sudeste z")
    x, z = Mesa.centro_do_tile(9, 9)
    T.eq(x, -2, "tile 9 fica meio tile a oeste do centro")
    T.eq(z, -2, "tile 9 fica meio tile ao norte do centro")
    x, z = Mesa.centro_do_tile(10, 10)
    T.eq(x, 2, "tile 10 fica meio tile a leste do centro")
    -- tiles vizinhos distam exatamente um tile
    local x1 = Mesa.centro_do_tile(5, 0)
    local x2 = Mesa.centro_do_tile(6, 0)
    T.eq(x2 - x1, 4, "um tile = 4 unidades")

    local px, pz = Mesa.posicao_do_portal()
    T.eq(px, -26, "portal x")
    T.eq(pz, 0, "portal z")
    -- Com o portal achado em (100, 50) no mundo, a origem é (126, 50).
    local ox, oz = Mesa.origem_pelo_portal(100, 50)
    T.eq(ox, 126, "origem x")
    T.eq(oz, 50, "origem z")
    local e = Mesa.espaco_criatura(1, 1) -- (7, 13)
    local ex, ez = Mesa.posicao(e.col, e.lin, ox, oz)
    T.eq(ex, 126 + (7 + 0.5 - 10) * 4, "espaço 1/1 x absoluto")
    T.eq(ez, 50 + (13 + 0.5 - 10) * 4, "espaço 1/1 z absoluto")
    -- Espelhado em x: portal achado em (152, 50) dá a mesma origem.
    ox, oz = Mesa.origem_pelo_portal(152, 50, true)
    T.eq(ox, 126, "origem x espelhada")
    local mx = Mesa.posicao(e.col, e.lin, ox, oz, true)
    T.eq(mx, 126 - (7 + 0.5 - 10) * 4, "espaço 1/1 x espelhado")
  end },
}
