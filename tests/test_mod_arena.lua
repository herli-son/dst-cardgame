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
      AddSimPostInit = function() end,
    }
    rodar("modmain.lua", env)
    T.eq(env.DUELO.Mesa, Mesa, "DUELO.Mesa é o módulo duelo/mod/mesa")
    T.ok(servidor, "consulta se é servidor")
    -- US #30: prefab do marcador e os módulos da mesa.
    T.eq(type(env.PrefabFiles), "table", "PrefabFiles")
    local tem = false
    for _, nome in ipairs(env.PrefabFiles) do
      if nome == "duelo_marcador" then tem = true end
      local fn = loadfile(RAIZ .. "scripts/prefabs/" .. nome .. ".lua")
      T.ok(fn, "scripts/prefabs/" .. nome .. ".lua existe e compila")
    end
    T.ok(tem, "PrefabFiles registra duelo_marcador")
    T.eq(type(env.DUELO.Calibracao.calibrar), "function", "DUELO.Calibracao")
    T.eq(type(env.DUELO.Marcadores.criar), "function", "DUELO.Marcadores")
    T.eq(type(env.DUELO.Camera.aplicar), "function", "DUELO.Camera")
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
    T.eq(layout.width, layout.height, "layout quadrado (object_layout.lua usa #ground nos dois eixos)")
    T.eq(layout.width, Mesa.LARGURA, "largura da grade")
    T.eq(layout.width, 21, "grade 21 x 21")
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
    T.eq(usados[Mesa.TILE.XADREZ], 24, "12 espaços de criatura com 2 tiles cada")
    T.eq(usados[Mesa.TILE.MOSAICO_CINZA], 8, "4 espaços de estrutura com 2 tiles cada")
    T.eq(usados[Mesa.TILE.MADEIRA], 8, "4 decks com 2 tiles cada")
    T.eq(usados[Mesa.TILE.TAPETE], 12, "6 pares de quadrados de combate")
    T.eq(usados[Mesa.TILE.TAPETE2], 2, "2 tiles do espaço de eventos")
    T.eq(usados[Mesa.TILE.LADRILHO], 4, "2 descartes com 2 tiles cada")
    T.eq(usados[Mesa.TILE.TIJOLO], 4, "2 blocos de destruídas com 2 tiles cada")
    T.eq(usados[Mesa.TILE.PARALELEPIPEDO], 15 * 16 - 62, "paralelepípedos: o resto da mesa 15 x 16")
    T.eq(usados[Mesa.TILE.PEDRA], 17 * 18 - 15 * 16 + 3 * 3, "pedra: a moldura de 1 tile e o pátio 3 x 3")
    T.eq(usados[Mesa.TILE.FORA], 21 * 21 - 17 * 18 - 3 * 3, "fora da moldura e do pátio")
    T.eq(usados[Mesa.TILE.IMPASSAVEL], nil, "nenhum tile intransitável explícito")

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
    -- O portal fica no pátio de pedra, fora da mesa.
    local col = math.floor(x + layout.width / 2)
    local lin = math.floor(y + layout.height / 2)
    T.eq(Mesa.uso_em(col, lin), "patio", "portal sobre o pátio")
    T.eq(Mesa.indice_em(col, lin), Mesa.TILE.PEDRA, "pátio de pedra")
    local m = Mesa.MESA
    T.ok(col < m.col_min or col > m.col_max or lin < m.lin_min or lin > m.lin_max, "portal fora da mesa")
    -- O portal e o spawn caem no centro de um tile: em pixels, (k + 0,5) * 64.
    -- A conta de map/object_layout.lua (canto + N / 2 - 0,5 +- posição) dá
    -- então um número inteiro de tiles, espelhado ou não.
    T.eq(portal.x / 64 - math.floor(portal.x / 64), 0.5, "portal no centro do tile (x)")
    T.eq(portal.y / 64 - math.floor(portal.y / 64), 0.5, "portal no centro do tile (y)")
    for _, sinal in ipairs({ 1, -1 }) do
      local tiles = layout.width / 2 - 0.5 + sinal * x
      T.eq(tiles, math.floor(tiles), "posição do portal em tiles inteiros (sinal " .. sinal .. ")")
    end
  end },

  { "tiles do layout conferidos em GROUND_TYPES", function(T)
    -- map/static_layout.lua, GROUND_TYPES, contando um a um: 2 = ROAD,
    -- 3 = ROCKY, 9 = WOODFLOOR, 10 = CARPET, 11 = CHECKER, 25 = BRICK,
    -- 27 = TILES, 47 = MOSAIC_GREY, 50 = CARPET2.
    local esperado = {
      PARALELEPIPEDO = { 2, "ROAD" }, PEDRA = { 3, "ROCKY" }, MADEIRA = { 9, "WOODFLOOR" },
      TAPETE = { 10, "CARPET" }, XADREZ = { 11, "CHECKER" }, TIJOLO = { 25, "BRICK" }, LADRILHO = { 27, "TILES" },
      MOSAICO_CINZA = { 47, "MOSAIC_GREY" }, TAPETE2 = { 50, "CARPET2" },
    }
    for nome, e in pairs(esperado) do
      T.eq(Mesa.TILE[nome], e[1], nome .. ": índice de " .. e[2])
      T.eq(Mesa.WORLD_TILE[nome], e[2], nome .. ": nome no jogo")
    end
    for uso, nome in pairs(Mesa.USO) do
      T.ok(Mesa.TILE[nome] ~= nil, "uso " .. uso .. " tem tile")
    end
    -- Pedido do dono: paralelepípedos na mesa, pedra em volta.
    T.eq(Mesa.USO.chao, "PARALELEPIPEDO", "chão da mesa = ROAD")
    T.eq(Mesa.USO.moldura, "PEDRA", "moldura = ROCKY")
    T.eq(Mesa.USO.patio, "PEDRA", "pátio = ROCKY")
    -- A calibração conta com um piso só das estruturas e outro só dos eventos.
    for _, unico in ipairs({ "estrutura", "evento" }) do
      for uso, nome in pairs(Mesa.USO) do
        if uso ~= unico then T.ok(nome ~= Mesa.USO[unico], "só " .. unico .. " usa " .. Mesa.USO[unico]) end
      end
    end
    -- Cada tipo de espaço tem o seu piso (carta e criatura dividem o xadrez).
    local pisos = {}
    for _, uso in ipairs({ "criatura", "estrutura", "deck", "combate", "evento", "descarte", "destruidas" }) do
      T.ok(not pisos[Mesa.USO[uso]], uso .. " com piso próprio")
      pisos[Mesa.USO[uso]] = uso
    end
    T.eq(Mesa.USO.carta, Mesa.USO.criatura, "carta e criatura no mesmo piso")
  end },

  { "espaços de mesa.lua caem nos tiles certos, sem sobreposição", function(T)
    local bg = require("duelo/mod/layouts/mesa").layers[1].data
    local function tile(col, lin) return bg[lin * Mesa.LARGURA + col + 1] end
    local ocupados, total = {}, 0
    local function marcar(e, nome)
      local chave = e.col .. "," .. e.lin
      T.ok(not ocupados[chave], nome .. " sobrepõe " .. tostring(ocupados[chave]))
      ocupados[chave] = nome
      total = total + 1
    end
    -- Bloco de 2 tiles: as duas partes na mesma coluna, encostadas, sobre o
    -- piso `piso`.
    local function marcar_bloco(e, partes, piso, nome)
      for _, parte in ipairs(partes) do
        T.eq(e[parte].col, e.col, nome .. ": " .. parte .. " na coluna do bloco")
        T.eq(tile(e[parte].col, e[parte].lin), piso, nome .. " (" .. parte .. ")")
        marcar(e[parte], nome .. " (" .. parte .. ")")
      end
      T.eq(math.abs(e[partes[1]].lin - e[partes[2]].lin), 1, nome .. ": os 2 tiles encostados")
    end
    for jogador = 1, 2 do
      local j = Mesa.JOGADORES[jogador]
      T.eq(#j.criaturas, 6, "6 criaturas do jogador " .. jogador)
      T.eq(#j.estruturas, 2, "2 estruturas do jogador " .. jogador)
      T.eq(#j.combate, 6, "6 quadrados de combate do jogador " .. jogador)
      for n, e in ipairs(j.criaturas) do
        T.eq(Mesa.espaco_criatura(jogador, n), e, "espaco_criatura")
        T.eq(e.combate, nil, "o quadrado de combate não faz parte do espaço de criatura")
        marcar_bloco(e, { "carta", "criatura" }, Mesa.TILE.XADREZ, "criatura " .. jogador .. "/" .. n)
      end
      for n, e in ipairs(j.estruturas) do
        T.eq(Mesa.espaco_estrutura(jogador, n), e, "espaco_estrutura")
        marcar_bloco(e, { "carta", "frente" }, Mesa.TILE.MOSAICO_CINZA, "estrutura " .. jogador .. "/" .. n)
      end
      for _, qual in ipairs({ "principal", "extra" }) do
        marcar_bloco(Mesa.espaco_deck(jogador, qual), { "tras", "frente" }, Mesa.TILE.MADEIRA, "deck " .. jogador .. "/" .. qual)
      end
      for k = 1, 6 do
        local c = Mesa.espaco_combate(jogador, k)
        T.eq(c, j.combate[k], "espaco_combate")
        T.eq(tile(c.col, c.lin), Mesa.TILE.TAPETE, "combate " .. jogador .. "/" .. k)
        marcar(c, "combate " .. jogador .. "/" .. k)
      end
      T.eq(Mesa.espaco_combate(jogador, 7), nil, "não há quadrado de combate 7")
      marcar_bloco(Mesa.espaco_descarte(jogador), { "tras", "frente" }, Mesa.TILE.LADRILHO, "descarte " .. jogador)
      marcar_bloco(Mesa.espaco_destruidas(jogador), { "tras", "frente" }, Mesa.TILE.TIJOLO, "destruídas " .. jogador)
    end
    local ev = Mesa.espaco_evento()
    for _, parte in ipairs({ "pilha", "em_vigor" }) do
      T.eq(tile(ev[parte].col, ev[parte].lin), Mesa.TILE.TAPETE2, "evento " .. parte)
      marcar(ev[parte], "evento " .. parte)
    end
    T.eq(total, 62, "62 tiles de espaço")
    -- Colunas da mesa (0..14, a partir da borda oeste): espaços e combate em
    -- 1, 3, ..., 11; eventos, descarte e destruídas em 13.
    local m = Mesa.MESA
    for n = 1, 6 do
      T.eq(Mesa.espaco_criatura(1, n).col - m.col_min, 2 * n - 1, "coluna do espaço " .. n)
      T.eq(Mesa.espaco_combate(1, n).col - m.col_min, 2 * n - 1, "coluna do quadrado de combate " .. n)
    end
    T.eq(ev.pilha.col - m.col_min, 13, "eventos na coluna 13 da mesa")
    -- Linhas da mesa (0..15): 1 e 2 fileira de trás do J2, 4 cartas do J2,
    -- 5 criaturas do J2, 7 combate do J2, 8 combate do J1, 10 criaturas do
    -- J1, 11 cartas do J1, 13 e 14 fileira de trás do J1.
    local function lin(t) return t.lin - m.lin_min end
    T.eq(lin(Mesa.espaco_estrutura(2, 1).carta), 1, "carta das estruturas do J2")
    T.eq(lin(Mesa.espaco_estrutura(2, 1).frente), 2, "estruturas do J2 em pé")
    T.eq(lin(Mesa.espaco_deck(2, "principal").tras), 1, "decks do J2 (trás)")
    T.eq(lin(Mesa.espaco_deck(2, "principal").frente), 2, "decks do J2 (frente)")
    T.eq(lin(Mesa.espaco_criatura(2, 1).carta), 4, "cartas do J2")
    T.eq(lin(Mesa.espaco_criatura(2, 1).criatura), 5, "criaturas do J2")
    T.eq(lin(Mesa.espaco_combate(2, 1)), 7, "combate do J2")
    T.eq(lin(Mesa.espaco_combate(1, 1)), 8, "combate do J1")
    T.eq(lin(Mesa.espaco_criatura(1, 1).criatura), 10, "criaturas do J1")
    T.eq(lin(Mesa.espaco_criatura(1, 1).carta), 11, "cartas do J1")
    T.eq(lin(Mesa.espaco_estrutura(1, 1).frente), 13, "estruturas do J1 em pé")
    T.eq(lin(Mesa.espaco_estrutura(1, 1).carta), 14, "carta das estruturas do J1")
    T.eq(lin(Mesa.espaco_deck(1, "extra").frente), 13, "decks do J1 (frente)")
    T.eq(lin(Mesa.espaco_deck(1, "extra").tras), 14, "decks do J1 (trás)")
    T.eq(m.col_max - m.col_min + 1, 15, "15 colunas")
    T.eq(m.lin_max - m.lin_min + 1, 16, "16 linhas")
    -- Cada jogador conta da sua esquerda: o espaço n de um fica de frente
    -- para o 7 - n do outro (mesma coluna).
    for n = 1, 6 do
      T.eq(Mesa.espaco_criatura(1, n).col, Mesa.espaco_criatura(2, 7 - n).col, "espaço " .. n .. " frente ao " .. (7 - n))
    end
    T.ok(Mesa.espaco_criatura(1, 1).col < Mesa.espaco_criatura(1, 6).col, "jogador 1 cresce para o leste")
    T.ok(Mesa.espaco_criatura(2, 1).col > Mesa.espaco_criatura(2, 6).col, "jogador 2 cresce para o oeste")
    T.ok(Mesa.espaco_criatura(1, 1).carta.lin > Mesa.espaco_criatura(2, 1).carta.lin, "jogador 1 ao sul do jogador 2")
  end },

  { "centro_do_tile e posicao usam TILE_SCALE = 4 relativo ao centro do layout", function(T)
    T.eq(Mesa.TILE_SCALE, 4, "TILE_SCALE")
    local x, z = Mesa.centro_do_tile(0, 0)
    T.eq(x, -40, "canto noroeste x")
    T.eq(z, -40, "canto noroeste z")
    x, z = Mesa.centro_do_tile(20, 20)
    T.eq(x, 40, "canto sudeste x")
    T.eq(z, 40, "canto sudeste z")
    x, z = Mesa.centro_do_tile(10, 10)
    T.eq(x, 0, "o tile (10, 10) é o centro do layout")
    T.eq(z, 0, "o tile (10, 10) é o centro do layout")
    -- O centro (entre as duas fileiras de combate, no meio das 6 colunas)
    -- fica na coluna 11, na junção das linhas 9 e 10.
    T.eq(Mesa.CENTRO.col, 11, "centro na coluna 11")
    T.eq(Mesa.CENTRO.lin, 9.5, "entre as linhas 9 e 10")
    x, z = Mesa.centro_do_tile(Mesa.CENTRO.col, Mesa.CENTRO.lin)
    T.eq(x, 4, "centro x: 1 tile a leste do centro do layout")
    T.eq(z, -2, "centro z: meio tile ao norte")
    -- tiles vizinhos distam exatamente um tile
    local x1 = Mesa.centro_do_tile(5, 0)
    local x2 = Mesa.centro_do_tile(6, 0)
    T.eq(x2 - x1, 4, "um tile = 4 unidades")

    local px, pz = Mesa.posicao_do_portal()
    T.eq(px, -32, "portal x")
    T.eq(pz, 0, "portal z")
    -- Com o portal achado em (100, 50) no mundo, a origem é (132, 50).
    local ox, oz = Mesa.origem_pelo_portal(100, 50)
    T.eq(ox, 132, "origem x")
    T.eq(oz, 50, "origem z")
    local e = Mesa.espaco_criatura(1, 1).carta -- (6, 13)
    local ex, ez = Mesa.posicao(e.col, e.lin, ox, oz)
    T.eq(ex, 132 + (6 - 10) * 4, "carta 1/1 x absoluto")
    T.eq(ez, 50 + (13 - 10) * 4, "carta 1/1 z absoluto")
    -- Espelhado em x: portal achado em (164, 50) dá a mesma origem.
    ox, oz = Mesa.origem_pelo_portal(164, 50, true)
    T.eq(ox, 132, "origem x espelhada")
    local mx = Mesa.posicao(e.col, e.lin, ox, oz, true)
    T.eq(mx, 132 - (6 - 10) * 4, "carta 1/1 x espelhado")
  end },

  -- -------------------------------------------------------------------------
  -- Layout do bug #147 (pedido do dono no teste em jogo)
  -- -------------------------------------------------------------------------

  { "paralelepípedos em volta de cada bloco: só se encostam os tiles de um bloco e os 2 quadrados de um par de combate", function(T)
    local bg = require("duelo/mod/layouts/mesa").layers[1].data
    local function tile(col, lin) return bg[lin * Mesa.LARGURA + col + 1] end
    -- Bloco de cada tile de espaço: os 2 tiles de um espaço de criatura, de
    -- uma estrutura, de um deck, do descarte, das destruídas ou dos eventos
    -- são o mesmo bloco; cada quadrado de combate é o seu.
    local function espaco(col, lin)
      local uso, jogador, n = Mesa.uso_em(col, lin)
      if uso == "carta" or uso == "criatura" then return jogador .. "/criatura/" .. n end
      if uso == "estrutura" or uso == "deck" then return jogador .. "/" .. uso .. "/" .. n end
      if uso == "combate" then return jogador .. "/combate/" .. n end
      if uso == "descarte" or uso == "destruidas" then return jogador .. "/" .. uso end
      if uso == "evento" then return "evento" end
      return nil
    end
    local tiles_de_espaco, encostados, tamanho = 0, 0, {}
    for lin = 0, Mesa.ALTURA - 1 do
      for col = 0, Mesa.LARGURA - 1 do
        local dono = espaco(col, lin)
        if dono then
          tiles_de_espaco = tiles_de_espaco + 1
          tamanho[dono] = (tamanho[dono] or 0) + 1
          -- Os 8 vizinhos: ou são do mesmo bloco, ou são paralelepípedos; a
          -- única exceção é o quadrado de combate do outro jogador que forma
          -- o par, logo acima ou abaixo.
          for dl = -1, 1 do
            for dc = -1, 1 do
              if dl ~= 0 or dc ~= 0 then
                local outro = espaco(col + dc, lin + dl)
                local nome = dono .. " em " .. col .. "," .. lin .. " vizinho " .. (col + dc) .. "," .. (lin + dl)
                if outro and outro ~= dono then
                  T.ok(dono:find("/combate/") and outro:find("/combate/"), nome .. " encosta em outro espaço")
                  T.eq(dc, 0, nome .. ": um em cima do outro")
                  -- O par: o quadrado k de um com o 7 - k do outro.
                  local p1, k1 = dono:match("^(%d)/combate/(%d)$")
                  local p2, k2 = outro:match("^(%d)/combate/(%d)$")
                  T.ok(p1 ~= p2, nome .. ": de jogadores diferentes")
                  T.eq(tonumber(k1) + tonumber(k2), 7, nome .. ": o quadrado k de um com o 7 - k do outro")
                  encostados = encostados + 1
                elseif outro == dono then
                  T.eq(dc, 0, nome .. ": os 2 tiles do bloco na mesma coluna")
                else
                  T.eq(tile(col + dc, lin + dl), Mesa.TILE.PARALELEPIPEDO, nome .. " é paralelepípedo")
                end
              end
            end
          end
        end
      end
    end
    T.eq(tiles_de_espaco, 62, "62 tiles de espaço")
    T.eq(encostados, 12, "só os 6 pares de combate se encostam (vistos dos dois lados)")
    local blocos = 0
    for dono, n in pairs(tamanho) do
      blocos = blocos + 1
      T.eq(n, dono:find("/combate/") and 1 or 2, dono .. ": 1 tile por quadrado de combate, 2 por bloco")
    end
    T.eq(blocos, 12 + 4 + 4 + 12 + 2 + 2 + 1, "12 criaturas, 4 estruturas, 4 decks, 12 quadrados, 2 descartes, 2 destruídas e os eventos")
  end },

  { "paralelepípedos na borda da mesa, moldura de pedra em volta e o pátio do portal", function(T)
    local m, f, p = Mesa.MESA, Mesa.MOLDURA, Mesa.PATIO
    for col = m.col_min, m.col_max do
      T.eq(Mesa.indice_em(col, m.lin_min), Mesa.TILE.PARALELEPIPEDO, "borda norte " .. col)
      T.eq(Mesa.indice_em(col, m.lin_max), Mesa.TILE.PARALELEPIPEDO, "borda sul " .. col)
    end
    for lin = m.lin_min, m.lin_max do
      T.eq(Mesa.indice_em(m.col_min, lin), Mesa.TILE.PARALELEPIPEDO, "borda oeste " .. lin)
      T.eq(Mesa.indice_em(m.col_max, lin), Mesa.TILE.PARALELEPIPEDO, "borda leste " .. lin)
    end
    T.ok(f == 1 or f == 2, "moldura de 1 ou 2 tiles")
    T.ok(m.col_min - f >= 0 and m.col_max + f <= Mesa.LARGURA - 1, "a moldura cabe na largura da grade")
    T.ok(m.lin_min - f >= 0 and m.lin_max + f <= Mesa.ALTURA - 1, "a moldura cabe na altura da grade")
    for lin = 0, Mesa.ALTURA - 1 do
      for col = 0, Mesa.LARGURA - 1 do
        local na_mesa = col >= m.col_min and col <= m.col_max and lin >= m.lin_min and lin <= m.lin_max
        local na_moldura = not na_mesa and col >= m.col_min - f and col <= m.col_max + f
          and lin >= m.lin_min - f and lin <= m.lin_max + f
        local no_patio = col >= p.col_min and col <= p.col_max and lin >= p.lin_min and lin <= p.lin_max
        local nome = col .. "," .. lin
        if na_moldura then
          T.eq(Mesa.uso_em(col, lin), "moldura", "moldura " .. nome)
          T.eq(Mesa.indice_em(col, lin), Mesa.TILE.PEDRA, "moldura de pedra " .. nome)
        elseif not na_mesa then
          T.eq(Mesa.indice_em(col, lin), no_patio and Mesa.TILE.PEDRA or Mesa.TILE.FORA, "fora da mesa " .. nome)
        else
          T.ok(Mesa.indice_em(col, lin) ~= Mesa.TILE.PEDRA, "sem pedra dentro da mesa " .. nome)
        end
      end
    end
    -- Pátio 3 x 3 ligado à moldura, do lado oposto aos eventos, na altura do
    -- combate, com o portal no tile do meio.
    T.eq(p.col_max - p.col_min, 2, "pátio com 3 colunas")
    T.eq(p.lin_max - p.lin_min, 2, "pátio com 3 linhas")
    T.eq(p.col_max + 1, m.col_min - f, "pátio encostado na moldura oeste")
    local ev = Mesa.espaco_evento()
    T.ok(ev.pilha.col > Mesa.CENTRO.col and p.col_max < Mesa.CENTRO.col, "eventos de um lado, portal do outro")
    T.ok(p.lin_min <= Mesa.CENTRO.lin and Mesa.CENTRO.lin <= p.lin_max, "na altura do combate")
    T.eq(Mesa.PORTAL.x + (Mesa.LARGURA - 1) / 2, (p.col_min + p.col_max) / 2, "portal na coluna do meio do pátio")
    T.eq(Mesa.PORTAL.z + (Mesa.ALTURA - 1) / 2, (p.lin_min + p.lin_max) / 2, "portal na linha do meio do pátio")
  end },

  { "espaço de criatura: 2 tiles, carta atrás e criatura virada para o centro", function(T)
    local centro = Mesa.CENTRO.lin
    for jogador = 1, 2 do
      for n, e in ipairs(Mesa.JOGADORES[jogador].criaturas) do
        local nome = jogador .. "/" .. n
        T.eq(e.carta.col, e.criatura.col, nome .. ": carta e criatura na mesma coluna")
        T.eq(math.abs(e.carta.lin - e.criatura.lin), 1, nome .. ": carta e criatura encostadas")
        T.eq(math.abs(e.criatura.lin - centro), 2.5, nome .. ": criatura do lado do centro")
        T.eq(math.abs(e.carta.lin - centro), 3.5, nome .. ": carta atrás da criatura")
      end
    end
  end },

  { "combate: 6 pares de quadrados, um par na frente de cada coluna de espaços", function(T)
    local m = Mesa.MESA
    for k = 1, 6 do
      local c1, c2 = Mesa.espaco_combate(1, k), Mesa.espaco_combate(2, 7 - k)
      T.eq(c1.col, Mesa.espaco_criatura(1, k).col, "quadrado " .. k .. " do J1 na coluna do espaço " .. k .. " dele")
      T.eq(c2.col, Mesa.espaco_criatura(2, 7 - k).col, "quadrado " .. (7 - k) .. " do J2 na coluna do espaço " .. (7 - k) .. " dele")
      T.eq(c1.col, c2.col, "o " .. k .. " de um de frente para o " .. (7 - k) .. " do outro")
      T.eq(c1.lin - c2.lin, 1, "encostados, o do jogador 1 ao sul")
      T.eq((c1.lin + c2.lin) / 2, (m.lin_min + m.lin_max) / 2, "no meio das linhas da mesa")
      T.eq((c1.lin + c2.lin) / 2, Mesa.CENTRO.lin, "Mesa.CENTRO entre as duas fileiras")
      -- Paralelepípedos entre as colunas de combate.
      T.eq(Mesa.uso_em(c1.col - 1, c1.lin), "chao", "paralelepípedos à esquerda do par " .. k)
      T.eq(Mesa.uso_em(c1.col + 1, c2.lin), "chao", "paralelepípedos à direita do par " .. k)
      local uso, jogador, n = Mesa.uso_em(c1.col, c1.lin)
      T.eq(uso, "combate", "uso")
      T.eq(jogador, 1, "do jogador 1")
      T.eq(n, k, "número do quadrado")
    end
    T.eq(Mesa.CENTRO.col, (Mesa.espaco_criatura(1, 1).col + Mesa.espaco_criatura(1, 6).col) / 2, "Mesa.CENTRO no meio das colunas de criatura")
    T.eq(Mesa.uso_em(Mesa.CENTRO.col, 9), "chao", "o centro fica numa coluna de paralelepípedos, entre os pares 3 e 4")
    local combates = { 0, 0 }
    for lin = 0, Mesa.ALTURA - 1 do
      for col = 0, Mesa.LARGURA - 1 do
        local uso, jogador = Mesa.uso_em(col, lin)
        if jogador == 1 then T.ok(lin > Mesa.CENTRO.lin, "jogador 1 ao sul do centro") end
        if jogador == 2 then T.ok(lin < Mesa.CENTRO.lin, "jogador 2 ao norte do centro") end
        if uso == "combate" then combates[jogador] = combates[jogador] + 1 end
      end
    end
    T.eq(combates[1], 6, "6 quadrados do jogador 1")
    T.eq(combates[2], 6, "6 quadrados do jogador 2")
    T.eq(Mesa.COMBATE, nil, "a zona de combate de fileira inteira não existe mais")
    T.eq(Mesa.CENTRO_COMBATE, nil, "nem o centro antigo")
    -- O rótulo "Combate": na coluna de paralelepípedos da borda, do lado do
    -- portal, entre as duas fileiras.
    local r = Mesa.ROTULO_COMBATE
    T.eq(r.col, m.col_min, "rótulo na coluna da borda")
    T.eq(r.col, Mesa.espaco_combate(1, 1).col - 1, "ao lado da primeira coluna de espaços")
    T.eq(r.lin, Mesa.CENTRO.lin, "entre as duas fileiras")
    T.eq(Mesa.uso_em(r.col, 9), "chao", "sobre paralelepípedos")
    T.eq(Mesa.uso_em(r.col, 10), "chao", "nas duas linhas")
  end },

  { "fileira de trás de 2 tiles: principal atrás do 1, estruturas atrás do 3 e do 4, extra atrás do 6", function(T)
    for jogador = 1, 2 do
      local nome = "jogador " .. jogador
      local e1 = Mesa.espaco_estrutura(jogador, 1)
      local carta = Mesa.espaco_criatura(jogador, 1).carta.lin
      local function longe(t) return math.abs(t.lin - Mesa.CENTRO.lin) end
      -- Estrutura: a carta atrás e a estrutura em pé na frente, como no
      -- espaço de criatura.
      T.eq(longe(e1.frente), math.abs(carta - Mesa.CENTRO.lin) + 2, nome .. ": 1 linha de paralelepípedos atrás das cartas")
      T.eq(longe(e1.carta), longe(e1.frente) + 1, nome .. ": a carta da estrutura atrás dela")
      T.eq(Mesa.espaco_deck(jogador, "principal").col, Mesa.espaco_criatura(jogador, 1).col, nome .. ": principal atrás do 1")
      T.eq(e1.col, Mesa.espaco_criatura(jogador, 3).col, nome .. ": estrutura 1 atrás do 3")
      T.eq(Mesa.espaco_estrutura(jogador, 2).col, Mesa.espaco_criatura(jogador, 4).col, nome .. ": estrutura 2 atrás do 4")
      T.eq(Mesa.espaco_deck(jogador, "extra").col, Mesa.espaco_criatura(jogador, 6).col, nome .. ": extra atrás do 6")
      T.eq(Mesa.espaco_estrutura(jogador, 2).carta.lin, e1.carta.lin, nome .. ": estruturas na mesma fileira (carta)")
      T.eq(Mesa.espaco_estrutura(jogador, 2).frente.lin, e1.frente.lin, nome .. ": estruturas na mesma fileira (frente)")
      for _, e in ipairs({ Mesa.espaco_deck(jogador, "principal"), Mesa.espaco_deck(jogador, "extra"),
        Mesa.espaco_destruidas(jogador) }) do
        T.eq(e.tras.lin, e1.carta.lin, nome .. ": tile de trás na linha de fora")
        T.eq(e.frente.lin, e1.frente.lin, nome .. ": tile da frente na linha de dentro")
        T.eq(e.tras.col, e.frente.col, nome .. ": os 2 tiles na mesma coluna")
      end
      -- uso_em diz a parte de cada tile.
      local uso, dono, n, parte = Mesa.uso_em(e1.carta.col, e1.carta.lin)
      T.eq(uso, "estrutura", nome .. ": uso do tile da carta")
      T.eq(dono, jogador, nome .. ": dono")
      T.eq(n, 1, nome .. ": número da estrutura")
      T.eq(parte, "carta", nome .. ": parte")
      T.eq(select(4, Mesa.uso_em(e1.frente.col, e1.frente.lin)), "frente", nome .. ": parte do tile da frente")
      local d = Mesa.espaco_deck(jogador, "extra")
      uso, dono, n, parte = Mesa.uso_em(d.tras.col, d.tras.lin)
      T.eq(uso, "deck", nome .. ": uso do deck")
      T.eq(n, "extra", nome .. ": qual deck")
      T.eq(parte, "tras", nome .. ": parte do deck")
      T.eq(Mesa.espaco_deck(jogador, "outro"), nil, "não há outro deck")
    end
    -- O espaço n de um fica de frente para o 7 - n do outro: o principal de
    -- um e o extra do outro dividem a coluna.
    T.eq(Mesa.espaco_deck(1, "principal").col, Mesa.espaco_deck(2, "extra").col, "principal do J1 e extra do J2")
    T.eq(Mesa.espaco_deck(1, "extra").col, Mesa.espaco_deck(2, "principal").col, "extra do J1 e principal do J2")
    T.eq(Mesa.espaco_estrutura(1, 1).col, Mesa.espaco_estrutura(2, 2).col, "estrutura 1 frente à 2")
  end },

  { "eventos: um espaço neutro de 2 tiles, alinhado ao combate, na borda oposta ao portal", function(T)
    local m, ev = Mesa.MESA, Mesa.espaco_evento()
    T.eq(ev.pilha.col, ev.em_vigor.col, "os 2 tiles na mesma coluna")
    T.eq(ev.pilha.lin, Mesa.espaco_combate(2, 1).lin, "pilha na linha do combate do jogador 2")
    T.eq(ev.em_vigor.lin, Mesa.espaco_combate(1, 1).lin, "evento em vigor na linha do combate do jogador 1")
    T.eq(ev.pilha.col, m.col_max - 1, "na penúltima coluna: paralelepípedos na borda")
    T.eq(ev.pilha.col - Mesa.espaco_criatura(1, 6).col, 2, "1 coluna de paralelepípedos depois da última carta")
    T.eq(Mesa.uso_em(ev.pilha.col - 1, ev.pilha.lin), "chao", "coluna de separação")
    local uso, jogador, parte = Mesa.uso_em(ev.pilha.col, ev.pilha.lin)
    T.eq(uso, "evento", "uso")
    T.eq(jogador, 0, "sem dono")
    T.eq(parte, "pilha", "parte")
    local eventos = 0
    for lin = 0, Mesa.ALTURA - 1 do
      for col = 0, Mesa.LARGURA - 1 do
        if Mesa.uso_em(col, lin) == "evento" then eventos = eventos + 1 end
      end
    end
    T.eq(eventos, 2, "só 2 tiles de eventos")
  end },

  { "o mapa da grade é o mapa pedido pelo dono, com a moldura e o pátio em volta", function(T)
    -- Mapa do comentário da issue #147, visto pelo jogador 1 (embaixo).
    local pedido = {
      "RRRRRRRRRRRRRRR",
      "RXRRRERERRRPRZR",
      "RXRRRERERRRPRZR",
      "RRRRRRRRRRRRRRR",
      "RKRKRKRKRKRKRLR",
      "RVRVRVRVRVRVRLR",
      "RRRRRRRRRRRRRRR",
      "RDRDRDRDRDRDReR",
      "RARARARARARAReR",
      "RRRRRRRRRRRRRRR",
      "RVRVRVRVRVRVRLR",
      "RKRKRKRKRKRKRLR",
      "RRRRRRRRRRRRRRR",
      "RPRRRERERRRXRZR",
      "RPRRRERERRRXRZR",
      "RRRRRRRRRRRRRRR",
    }
    local m = Mesa.MESA
    local gerado = Mesa.mapa_ascii()
    T.eq(#pedido, m.lin_max - m.lin_min + 1, "16 linhas")
    for i, linha in ipairs(pedido) do
      T.eq(gerado[m.lin_min + i]:sub(m.col_min + 1, m.col_max + 1), linha, "linha " .. (i - 1) .. " da mesa")
    end
  end },

  { "o mapa ASCII do cabeçalho de mesa.lua é o que o módulo gera", function(T)
    local f = assert(io.open(RAIZ .. "scripts/duelo/mod/mesa.lua", "r"))
    local texto = f:read("*a")
    f:close()
    local linhas = {}
    for linha in texto:gmatch("[^\n]+") do
      local lin, grade = linha:match("^%-%-[%slin]+(%d+)%s+([%.oRKVEPXADeLZ@]+)")
      if lin and #grade == Mesa.LARGURA then linhas[tonumber(lin) + 1] = grade end
    end
    local gerado = Mesa.mapa_ascii()
    T.eq(#gerado, Mesa.ALTURA, "21 linhas geradas")
    for i, l in ipairs(gerado) do
      T.eq(linhas[i], l, "linha " .. (i - 1) .. " do cabeçalho")
    end
  end },
}
