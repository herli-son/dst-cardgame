-- Testes da mesa no jogo: tiles, números e câmera (US #30) com o layout do
-- bug #147 (mesa 15 x 14, par de combate, decks e espaço de eventos).
--
-- O jogo não roda aqui. A calibração é Lua puro (scripts/duelo/mod/mesa.lua)
-- e é testada com um modelo do mundo. No jogo (issue #30) o gerador espelhou
-- o eixo x do layout (flip_x = -1 em map/object_layout.lua) e não o z; com a
-- grade 20 x 20 da US #30 deu x_tile = 38 - col. A grade agora é 21 x 21 e a
-- posição exata no mapa muda a cada mundo, então o modelo é:
--   espelhado (o medido):   x_tile = 40 - col, y_tile = lin + 19;
--   sem espelhamento:       x_tile = 20 + col, y_tile = lin + 19.
-- O portal fica no centro do tile (2, 10) do layout. Como o gerador pode
-- deslocar os objetos em meio tile em relação à grade do chão
-- (map/object_layout.lua centra objetos e tiles de jeitos diferentes), cada
-- caso roda também com o portal deslocado meio tile (2 unidades) em x e z.
--
-- O espelhamento sai da coluna de eventos (a mesa não é simétrica no eixo
-- x); o portal é só conferência e reserva.
--
-- Mapa falso: o tile (tx, ty) cobre [4 tx, 4 tx + 4) x [4 ty, 4 ty + 4) no
-- mundo; centro em (4 tx + 2, 4 ty + 2). É só um modelo para os testes; no
-- jogo a conversão vem de TheWorld.Map:GetTileCenterPoint.

local RAIZ = "./"

-- Cópia nova da mesa por caso: a calibração fica em Mesa.calibracao.
local function nova_mesa()
  local fn, err = loadfile(RAIZ .. "scripts/duelo/mod/mesa.lua")
  assert(fn, err)
  return fn()
end

-- Casos do modelo: espelhado ou não, portal no centro do tile ou deslocado.
local CASOS = {
  { nome = "espelhado", espelhado = true, meio = 0 },
  { nome = "espelhado, portal meio tile fora", espelhado = true, meio = 2 },
  { nome = "sem espelho", espelhado = false, meio = 0 },
  { nome = "sem espelho, portal meio tile fora", espelhado = false, meio = 2 },
}
local MEDIDO = CASOS[1]

-- Tile do mapa de cada (col, lin) do layout.
local function tile_do_mapa(col, lin, caso)
  caso = caso or MEDIDO
  if caso.espelhado then return 40 - col, lin + 19 end
  return 20 + col, lin + 19
end

local function centro_mundo(tx, ty)
  return tx * 4 + 2, ty * 4 + 2
end

local function tile_no_ponto(x, z)
  return math.floor(x / 4), math.floor(z / 4)
end

-- Grade do mapa falso: [tx][ty] = uso do layout ("carta", "chao"...).
local function mapa_falso(Mesa, caso)
  local grade = {}
  for col = 0, Mesa.LARGURA - 1 do
    for lin = 0, Mesa.ALTURA - 1 do
      local tx, ty = tile_do_mapa(col, lin, caso)
      grade[tx] = grade[tx] or {}
      grade[tx][ty] = Mesa.uso_em(col, lin)
    end
  end
  return grade
end

local function uso_no_mapa(grade, tx, ty)
  return grade[tx] and grade[tx][ty] or "fora"
end

-- Posição do portal no mundo: centro do tile (2, 10), mais o deslocamento.
local function portal_no_mundo(caso)
  caso = caso or MEDIDO
  local tx, ty = tile_do_mapa(2, 10, caso)
  local x, z = centro_mundo(tx, ty)
  return x + caso.meio, z + caso.meio
end

-- Coleta os tiles de um uso ("estrutura", por padrão) em volta do portal,
-- como calibracao.lua faz.
local function estruturas_em_volta(Mesa, caso, uso)
  local grade = mapa_falso(Mesa, caso)
  local px, pz = portal_no_mundo(caso)
  local ptx, pty = tile_no_ponto(px, pz)
  local lista = {}
  for tx = ptx - 20, ptx + 20 do
    for ty = pty - 20, pty + 20 do
      if uso_no_mapa(grade, tx, ty) == (uso or "estrutura") then
        lista[#lista + 1] = { x = tx, y = ty }
      end
    end
  end
  return lista, px, pz, ptx, pty
end

local function eventos_em_volta(Mesa, caso)
  return (estruturas_em_volta(Mesa, caso, "evento"))
end

local function calibrar_caso(Mesa, caso)
  local lista, px, pz = estruturas_em_volta(Mesa, caso)
  local ret = assert(Mesa.achar_estruturas(lista))
  return Mesa.calibrar({ estruturas = ret, centro_mundo = centro_mundo, eventos = eventos_em_volta(Mesa, caso),
    portal = { x = px, z = pz } }), ret
end

-- ---------------------------------------------------------------------------
-- Ambiente falso dos módulos de jogo (calibracao, marcadores, camera e o
-- prefab duelo_marcador). Só o que eles chamam.
-- ---------------------------------------------------------------------------

local function carregar(caminho)
  local fn, err = loadfile(RAIZ .. caminho)
  assert(fn, err)
  return fn()
end

-- Ids falsos do jogo (no jogo vêm de tiledefs.lua); o que importa é serem
-- diferentes entre si.
local WORLD_TILES = { IMPASSABLE = 1, ROAD = 2, ROCKY = 3, WOODFLOOR = 10, CARPET = 11, CHECKER = 12,
  MOSAIC_GREY = 47, MOSAIC_BLUE = 49, CARPET2 = 50 }

-- Id do jogo do tile de cada uso do layout, pelo próprio Mesa.
local function tile_por_uso(Mesa, uso)
  local nome = Mesa.WORLD_TILE[Mesa.USO[uso]]
  return nome and WORLD_TILES[nome] or WORLD_TILES.IMPASSABLE
end

local function label_falso()
  local l = { texto = nil, ativo = nil, cor = nil, tamanho = nil, fonte = nil }
  function l:SetText(t) self.texto = t end
  function l:SetColour(r, g, b) self.cor = { r, g, b } end
  function l:SetFontSize(n) self.tamanho = n end
  function l:SetFont(f) self.fonte = f end
  function l:SetWorldOffset() end
  function l:SetUIOffset() end
  function l:Enable(v) self.ativo = v end
  return l
end

-- Entidade falsa: Transform, Label, eventos, tarefas e tags.
local function entidade(reg, nome)
  reg.guid = (reg.guid or 0) + 1
  local e = { GUID = reg.guid, nome = nome, tags = {}, eventos = {}, tarefas = {}, valido = true }
  local pos = { 0, 0, 0 }
  local transform = {
    SetPosition = function(_, x, y, z) pos = { x, y, z } end,
    GetWorldPosition = function() return pos[1], pos[2], pos[3] end,
  }
  e.entity = {
    AddTransform = function() e.Transform = transform end,
    AddNetwork = function() e.rede = true end,
    AddLabel = function() e.Label = label_falso() end,
    SetPristine = function() e.pristine = true end,
  }
  function e:AddTag(t) self.tags[t] = true end
  function e:HasTag(t) return self.tags[t] == true end
  function e:ListenForEvent(ev, fn) self.eventos[ev] = self.eventos[ev] or {}; table.insert(self.eventos[ev], fn) end
  function e:PushEvent(ev, dados)
    for _, fn in ipairs(self.eventos[ev] or {}) do fn(self, dados) end
  end
  function e:DoTaskInTime(_, fn) self.tarefas[#self.tarefas + 1] = fn end
  function e:IsValid() return self.valido end
  function e:Remove() self.valido = false; reg.removidos = (reg.removidos or 0) + 1 end
  reg.entidades = reg.entidades or {}
  reg.entidades[e.GUID] = e
  return e
end

-- tile_outline falso, com o que prefabs/gridplacer.lua (tile_outline_fn) põe
-- nele (sem componente placer, que quebrava outros mods): tags
-- CLASSIFIED, NOCLICK e placer, Transform e AnimState, sem rede nem física,
-- persists = false. O AnimState guarda as cores.
local function gridplacer_falso(reg)
  local e = entidade(reg, "tile_outline")
  e:AddTag("CLASSIFIED")
  e:AddTag("NOCLICK")
  e:AddTag("placer")
  e.persists = false
  e.entity.AddTransform()
  e.AnimState = { mult = { 1, 1, 1, 1 }, add = { 0, 0, 0, 0 } }
  function e.AnimState:SetMultColour(r, g, b, a) self.mult = { r, g, b, a } end
  function e.AnimState:SetAddColour(r, g, b, a) self.add = { r, g, b, a } end
  reg.gridplacers = reg.gridplacers or {}
  reg.gridplacers[#reg.gridplacers + 1] = e
  return e
end

-- Netvar falsa: `set` muda o valor e, se mudou, dispara o dirty na entidade
-- dona (netvars.lua: o dirty sai nos dois lados, só quando o valor muda).
local function fabrica_net(reg, tipo)
  return function(guid, nome, dirty)
    local nv = { tipo = tipo, guid = guid, nome = nome, dirty = dirty, sets = 0 }
    nv.valor = (tipo == "bool") and false or 0
    function nv:set(v)
      self.sets = self.sets + 1
      if v ~= self.valor then
        self.valor = v
        local dono = reg.entidades and reg.entidades[guid]
        if dono then dono:PushEvent(dirty) end
      end
    end
    function nv:value() return self.valor end
    reg.netvars[#reg.netvars + 1] = nv
    return nv
  end
end

-- Câmera falsa com o comportamento de cameras/followcamera.lua que importa:
-- SetDefault refaz distâncias e inclinação, Snap copia o alvo, os setters
-- guardam, o zoom respeita mindist e maxdist, e o extra soma no máximo (e
-- chama MaximizeDistance quando muda, como o jogo).
local function camera_falsa()
  local c = { snaps = 0, extramaxdist = 0, maximizou = 0 }
  function c:SetDefault()
    self.distancetarget, self.mindist, self.maxdist, self.controllable = 30, 15, 50 + self.extramaxdist, true
    self.mindistpitch, self.maxdistpitch = 30, 60
    self.headingtarget = self.headingtarget or 45
  end
  function c:SetTarget(inst) self.target = inst end
  function c:SetMinDistance(d) self.mindist = d end
  function c:SetMaxDistance(d) self.maxdist = d + self.extramaxdist end
  function c:SetExtraMaxDistance(d)
    local antes = self.extramaxdist
    self.maxdist = self.maxdist - antes + d
    self.extramaxdist = d
    if d ~= antes then
      self.maximizou = self.maximizou + 1
      self.distancetarget = (self.maxdist - self.mindist) * 0.7 + self.mindist
    end
  end
  function c:SetPitchRange(min, max) self.mindistpitch, self.maxdistpitch = min, max end
  function c:SetDistance(d) self.distancetarget = d end
  function c:GetDistance() return self.distancetarget end
  function c:ZoomIn(passo) self.distancetarget = math.max(self.mindist, self.distancetarget - (passo or 4)) end
  function c:ZoomOut(passo) self.distancetarget = math.min(self.maxdist, self.distancetarget + (passo or 4)) end
  function c:ContinuousZoomDelta(delta)
    self.distancetarget = math.max(self.mindist, math.min(self.maxdist, self.distancetarget + delta))
  end
  function c:SetHeadingTarget(r) self.headingtarget = r % 360 end
  function c:SetContinuousHeadingTarget(r) self.headingtarget = r % 360 end
  function c:GetHeadingTarget() return self.headingtarget end
  function c:CanControl() return self.controllable end
  function c:Snap() self.snaps = self.snaps + 1; self.heading = self.headingtarget end
  c:SetDefault()
  return c
end

-- Ambiente de um lado: servidor (host ou dedicado) ou cliente.
--   opcoes.servidor, opcoes.dedicado, opcoes.caso (modelo do mundo, CASOS),
--   opcoes.sem_estruturas, opcoes.sem_eventos (o chão da mesa no lugar),
--   opcoes.sem_portal, opcoes.tamanho (Map:GetSize).
local function ambiente_jogo(opcoes)
  local reg = { netvars = {}, log = {}, spawns = {}, sim_postinits = {}, prefab_postinits = {},
    player_postinits = {}, component_postinits = {} }
  local Mesa = nova_mesa()
  local caso = opcoes.caso or MEDIDO
  local grade = mapa_falso(Mesa, caso)
  local G = {
    WORLD_TILES = WORLD_TILES,
    TALKINGFONT = "talkingfont",
    DEFAULTFONT = "opensans",
    AllPlayers = {},
    print = function(msg) reg.log[#reg.log + 1] = msg end,
  }
  G.TheNet = { IsDedicated = function() return opcoes.dedicado == true end,
    GetIsServer = function() return opcoes.servidor == true end }
  G.TheWorld = entidade(reg, "world")
  G.TheWorld.ismastersim = opcoes.servidor == true
  G.TheWorld.Map = {
    GetTileCoordsAtPoint = function(_, x, _, z) return tile_no_ponto(x, z) end,
    GetTileCenterPoint = function(_, tx, ty) local x, z = centro_mundo(tx, ty); return x, 0, z end,
    GetTile = function(_, tx, ty)
      if opcoes.tamanho then
        reg.fora_do_mapa = (reg.fora_do_mapa or 0)
          + ((tx < 0 or ty < 0 or tx >= opcoes.tamanho or ty >= opcoes.tamanho) and 1 or 0)
      end
      local uso = grade[tx] and grade[tx][ty] or "fora"
      if opcoes.sem_estruturas and uso == "estrutura" then uso = "chao" end
      if opcoes.sem_eventos and uso == "evento" then uso = "chao" end
      return tile_por_uso(Mesa, uso)
    end,
  }
  if opcoes.tamanho then
    G.TheWorld.Map.GetSize = function() return opcoes.tamanho, opcoes.tamanho end
  end
  G.TheWorld.Map.GetTileAtPoint = function(m, x, _, z) return m:GetTile(tile_no_ponto(x, z)) end
  local portal = entidade(reg, "multiplayer_portal")
  portal.entity.AddTransform()
  local ppx, ppz = portal_no_mundo(caso)
  portal.Transform:SetPosition(ppx, 0, ppz)
  G.TheSim = { FindFirstEntityWithTag = function(_, tag)
    if tag == "multiplayer_portal" and not opcoes.sem_portal then return portal end
  end }
  G.net_tinybyte = fabrica_net(reg, "tinybyte")
  G.net_float = fabrica_net(reg, "float")
  G.net_bool = fabrica_net(reg, "bool")
  G.CreateEntity = function(nome) return entidade(reg, nome or "entidade") end

  -- Prefab do marcador carregado no ambiente deste lado (no jogo ele roda no
  -- ambiente global: CreateEntity, TheWorld, Prefab, _G).
  local env = setmetatable({}, { __index = function(_, k)
    if k == "Prefab" then return function(nome, fn) return { nome = nome, fn = fn } end end
    if k == "require" then return require end
    return G[k]
  end })
  rawset(env, "_G", G)
  local fn = assert(loadfile(RAIZ .. "scripts/prefabs/duelo_marcador.lua"))
  setfenv(fn, env)
  local prefab = fn()
  G.SpawnPrefab = function(nome)
    reg.spawns[#reg.spawns + 1] = nome
    if nome == prefab.nome then return prefab.fn() end
    if nome == "tile_outline" and not opcoes.sem_gridplacer then return gridplacer_falso(reg) end
  end

  local ctx = {
    GLOBAL = G,
    Mesa = Mesa,
    AddSimPostInit = function(f) reg.sim_postinits[#reg.sim_postinits + 1] = f end,
    AddPrefabPostInit = function(nome, f) reg.prefab_postinits[nome] = reg.prefab_postinits[nome] or {}; table.insert(reg.prefab_postinits[nome], f) end,
    AddPlayerPostInit = function(f) reg.player_postinits[#reg.player_postinits + 1] = f end,
    AddComponentPostInit = function(nome, f) reg.component_postinits[nome] = f end,
  }
  return { G = G, reg = reg, ctx = ctx, Mesa = Mesa, prefab = prefab, portal = portal, grade = grade }
end

-- Instala calibracao, marcadores e camera (cópias novas) como o modmain faz.
local function instalar_tudo(amb)
  local G = amb.ctx.GLOBAL
  local Calibracao = carregar("scripts/duelo/mod/calibracao.lua")
  local ctx = amb.ctx
  Calibracao.instalar({ GLOBAL = ctx.GLOBAL, Mesa = ctx.Mesa, AddSimPostInit = ctx.AddSimPostInit,
    AddPrefabPostInit = ctx.AddPrefabPostInit })
  local Marcadores = carregar("scripts/duelo/mod/marcadores.lua")
  Marcadores.instalar({ GLOBAL = ctx.GLOBAL, Mesa = ctx.Mesa, Calibracao = Calibracao })
  local Camera = carregar("scripts/duelo/mod/camera.lua")
  Camera.instalar({ GLOBAL = ctx.GLOBAL, Mesa = ctx.Mesa, Calibracao = Calibracao,
    AddPlayerPostInit = ctx.AddPlayerPostInit, AddComponentPostInit = ctx.AddComponentPostInit,
    AddSimPostInit = ctx.AddSimPostInit })
  local Contornos = carregar("scripts/duelo/mod/contornos.lua")
  Contornos.instalar({ GLOBAL = G, Mesa = ctx.Mesa, Calibracao = Calibracao })
  amb.Calibracao, amb.Marcadores, amb.Camera, amb.Contornos = Calibracao, Marcadores, Camera, Contornos
  return amb
end

-- Simula a carga do mundo: cria o forest_network (post inits) e roda os
-- AddSimPostInit.
local function carregar_mundo(amb)
  local rede = entidade(amb.reg, "forest_network")
  for _, f in ipairs(amb.reg.prefab_postinits.forest_network or {}) do f(rede) end
  for _, f in ipairs(amb.reg.sim_postinits) do f() end
  amb.rede = rede
  return rede
end

local function no_log(reg, trecho)
  for _, msg in ipairs(reg.log) do
    if msg:find(trecho, 1, true) then return true end
  end
  return false
end

local function netvar(reg, nome)
  for _, nv in ipairs(reg.netvars) do
    if nv.nome == nome then return nv end
  end
end

-- Jogador falso: roda os AddPlayerPostInit.
local function novo_jogador(amb, userid)
  local j = entidade(amb.reg, "jogador")
  j.userid = userid
  for _, f in ipairs(amb.reg.player_postinits) do f(j) end
  return j
end

-- Replica à mão as netvars de um marcador do servidor num do cliente.
local function replicar(origem, destino)
  for _, campo in ipairs({ "duelo_tipo", "duelo_jogador", "duelo_numero" }) do
    destino[campo].valor = origem[campo]:value()
  end
  destino:PushEvent("duelo_marcador.dirty")
end

local NETVARS_MESA = { "duelo.mesa_origem_x", "duelo.mesa_origem_z", "duelo.mesa_espelhado", "duelo.mesa_fonte" }

return {
  { "o modelo do mundo: estruturas nos tiles certos e o portal fora da mesa", function(T)
    local Mesa = nova_mesa()
    for _, caso in ipairs(CASOS) do
      local lista, px, _, ptx, pty = estruturas_em_volta(Mesa, caso)
      T.eq(#lista, 4, caso.nome .. ": 4 tiles de estrutura em volta do portal")
      local etx, ety = tile_do_mapa(2, 10, caso)
      -- Deslocado meio tile, o portal cai na junção com o tile vizinho.
      T.ok(math.abs(ptx - etx) <= (caso.meio > 0 and 1 or 0), caso.nome .. ": portal x no tile da coluna 2")
      T.ok(math.abs(pty - ety) <= (caso.meio > 0 and 1 or 0), caso.nome .. ": portal y no tile da linha 10")
      local _, r = calibrar_caso(Mesa, caso)
      local eventos = eventos_em_volta(Mesa, caso)
      T.eq(#eventos, 2, caso.nome .. ": 2 tiles de eventos")
      if caso.espelhado then
        T.ok(r.x_max < ptx, caso.nome .. ": estruturas com x menor que o portal")
        T.ok(eventos[1].x < r.x_min, caso.nome .. ": eventos com x menor que as estruturas")
      else
        T.ok(r.x_min > ptx, caso.nome .. ": estruturas com x maior que o portal")
        T.ok(eventos[1].x > r.x_max, caso.nome .. ": eventos com x maior que as estruturas")
      end
      T.ok(px ~= nil, "portal")
    end
  end },

  { "calibração com e sem espelho: origem no centro do layout, pelas estruturas e pelos eventos", function(T)
    local Mesa = nova_mesa()
    for _, caso in ipairs(CASOS) do
      local calib = calibrar_caso(Mesa, caso)
      T.eq(calib.espelhado, caso.espelhado, caso.nome .. ": espelhado")
      T.eq(calib.fonte, "estruturas", caso.nome .. ": fonte")
      T.eq(calib.espelhamento, "eventos", caso.nome .. ": espelhamento pela coluna de eventos")
      T.eq(calib.aviso, nil, caso.nome .. ": sem aviso: o portal está onde o layout diz")
      local px, pz = portal_no_mundo(caso)
      local col, lin = Mesa.tile_do_layout(px, pz, calib)
      local folga = caso.meio > 0 and 1 or 0
      T.ok(math.abs(col - 2) <= folga, caso.nome .. ": portal na coluna 2")
      T.ok(math.abs(lin - 10) <= folga, caso.nome .. ": portal na linha 10")
      -- A origem é o centro do tile (10, 10) do layout.
      local cx, cz = centro_mundo(tile_do_mapa(10, 10, caso))
      T.eq(calib.origem_x, cx, caso.nome .. ": origem x")
      T.eq(calib.origem_z, cz, caso.nome .. ": origem z")
      -- O centro (entre os quadrados de combate) é o meio das estruturas.
      local ox, oz = Mesa.centro_abs(calib)
      local c1x, c1z = Mesa.espaco_combate_abs(1, calib)
      local c2x, c2z = Mesa.espaco_combate_abs(2, calib)
      T.eq(ox, (c1x + c2x) / 2, caso.nome .. ": centro x entre os quadrados de combate")
      T.eq(oz, (c1z + c2z) / 2, caso.nome .. ": centro z entre os quadrados de combate")
      -- O centro de cada tile do layout volta para o mesmo tile do mapa.
      for col2 = 0, Mesa.LARGURA - 1 do
        for lin2 = 0, Mesa.ALTURA - 1 do
          local x, z = Mesa.posicao_abs(col2, lin2, calib)
          local tx, ty = tile_no_ponto(x, z)
          local ex, ey = tile_do_mapa(col2, lin2, caso)
          T.eq(tx, ex, "tile x de " .. col2 .. "," .. lin2)
          T.eq(ty, ey, "tile y de " .. col2 .. "," .. lin2)
          local c3, l3 = Mesa.tile_do_layout(x, z, calib)
          T.eq(c3, col2, "ida e volta col")
          T.eq(l3, lin2, "ida e volta lin")
        end
      end
    end
  end },

  { "achar_estruturas recusa tiles faltando, sobrando, girados ou fora do padrão", function(T)
    local Mesa = nova_mesa()
    local function cantos(dx, dy)
      return { { x = 0, y = 0 }, { x = dx, y = 0 }, { x = 0, y = dy }, { x = dx, y = dy } }
    end
    local r, motivo = Mesa.achar_estruturas({})
    T.eq(r, nil, "vazio")
    T.eq(type(motivo), "string", "motivo")
    r = Mesa.achar_estruturas(cantos(2, 11))
    T.ok(r, "o padrão 2 x 11")
    T.eq(r.x_max - r.x_min, 2, "2 colunas entre as estruturas")
    T.eq(r.y_max - r.y_min, 11, "11 linhas entre as estruturas")
    T.eq(Mesa.ESTRUTURAS_DX, 2, "ESTRUTURAS_DX")
    T.eq(Mesa.ESTRUTURAS_DZ, 11, "ESTRUTURAS_DZ")
    local repetidos = cantos(2, 11)
    repetidos[#repetidos + 1] = { x = 2, y = 11 }
    T.ok(Mesa.achar_estruturas(repetidos), "tile repetido conta uma vez")
    r, motivo = Mesa.achar_estruturas(cantos(11, 2))
    T.eq(r, nil, "girado")
    T.ok(motivo:find("giradas"), "motivo diz girado")
    local tres = cantos(2, 11)
    table.remove(tres)
    T.eq(Mesa.achar_estruturas(tres), nil, "3 tiles")
    local cinco = cantos(2, 11)
    cinco[#cinco + 1] = { x = 1, y = 3 }
    T.eq(Mesa.achar_estruturas(cinco), nil, "5 tiles")
    T.eq(Mesa.achar_estruturas(cantos(3, 11)), nil, "3 x 11")
    T.eq(Mesa.achar_estruturas({ { x = 0, y = 0 }, { x = 2, y = 0 }, { x = 1, y = 11 }, { x = 2, y = 11 } }), nil,
      "não é retângulo")
  end },

  { "calibrar avisa quando o portal não está onde o layout diz", function(T)
    local Mesa = nova_mesa()
    local r = assert(Mesa.achar_estruturas((estruturas_em_volta(Mesa, MEDIDO))))
    local eventos = eventos_em_volta(Mesa, MEDIDO)
    local calib = Mesa.calibrar({ estruturas = r, centro_mundo = centro_mundo, eventos = eventos, portal = { x = 0, z = 0 } })
    T.ok(calib.aviso:find("longe do esperado"), "aviso: " .. tostring(calib.aviso))
    T.eq(calib.espelhado, true, "o espelhamento continua saindo dos eventos")
    -- Sem portal, os eventos bastam: nenhum aviso.
    calib = Mesa.calibrar({ estruturas = r, centro_mundo = centro_mundo, eventos = eventos })
    T.eq(calib.aviso, nil, "sem portal e com eventos: sem aviso")
    T.eq(calib.espelhado, true, "espelhado pelos eventos")
    T.eq(calib.espelhamento, "eventos", "de onde saiu")
    -- Sem eventos nem portal não dá para saber: vale o medido no jogo.
    calib = Mesa.calibrar({ estruturas = r, centro_mundo = centro_mundo })
    T.eq(type(calib.aviso), "string", "aviso sem eventos nem portal")
    T.eq(calib.espelhado, true, "o medido no jogo")
    T.eq(calib.espelhamento, "padrao", "de onde saiu")
  end },

  { "reserva pelo portal dá a mesma origem que as estruturas no caso medido", function(T)
    local Mesa = nova_mesa()
    local calib = calibrar_caso(Mesa, MEDIDO)
    local px, pz = portal_no_mundo(MEDIDO)
    local reserva = Mesa.calibrar_pelo_portal(px, pz)
    T.eq(reserva.fonte, "portal", "fonte")
    T.eq(reserva.espelhado, true, "espelhado por padrão (medido)")
    T.eq(type(reserva.aviso), "string", "avisa")
    T.eq(reserva.origem_x, calib.origem_x, "origem x")
    T.eq(reserva.origem_z, calib.origem_z, "origem z")
  end },

  { "36 tiles de espaço absolutos sem sobreposição e sobre os tiles certos da mesa", function(T)
    local Mesa = nova_mesa()
    for _, caso in ipairs(CASOS) do
      local calib = calibrar_caso(Mesa, caso)
      local grade = mapa_falso(Mesa, caso)
      local vistos, total = {}, 0
      local function conferir(x, z, uso, nome)
        T.ok(x ~= nil, nome .. " existe")
        local tx, ty = tile_no_ponto(x, z)
        local cx, cz = centro_mundo(tx, ty)
        T.eq(x, cx, nome .. " no centro do tile (x)")
        T.eq(z, cz, nome .. " no centro do tile (z)")
        T.eq(uso_no_mapa(grade, tx, ty), uso, nome .. " sobre tile de " .. uso)
        local chave = tx .. "," .. ty
        T.ok(not vistos[chave], nome .. " sobrepõe " .. tostring(vistos[chave]))
        vistos[chave] = nome
        total = total + 1
      end
      for p = 1, 2 do
        for n = 1, 6 do
          local e = Mesa.espaco_criatura_abs(p, n, calib)
          conferir(e.carta.x, e.carta.z, "carta", "carta " .. p .. "/" .. n)
          conferir(e.criatura.x, e.criatura.z, "criatura", "criatura " .. p .. "/" .. n)
          T.eq(e.combate, nil, "sem tile de combate por coluna")
        end
        for n = 1, 2 do
          local x, z = Mesa.espaco_estrutura_abs(p, n, calib)
          conferir(x, z, "estrutura", "estrutura " .. p .. "/" .. n)
        end
        for _, qual in ipairs({ "principal", "extra" }) do
          local x, z = Mesa.espaco_deck_abs(p, qual, calib)
          conferir(x, z, "deck", "deck " .. p .. "/" .. qual)
        end
        local x, z = Mesa.espaco_combate_abs(p, calib)
        conferir(x, z, "combate", "combate " .. p)
        T.eq(Mesa.espaco_criatura_abs(p, 7, calib), nil, "não há espaço 7")
        T.eq(Mesa.espaco_estrutura_abs(p, 3, calib), nil, "não há estrutura 3")
        T.eq(Mesa.espaco_deck_abs(p, "outro", calib), nil, "não há outro deck")
      end
      T.eq(Mesa.espaco_combate_abs(3, calib), nil, "espectador não tem quadrado de combate")
      local ev = Mesa.espaco_evento_abs(calib)
      conferir(ev.pilha.x, ev.pilha.z, "evento", "pilha de eventos")
      conferir(ev.em_vigor.x, ev.em_vigor.z, "evento", "evento em vigor")
      T.eq(total, 36, "12 cartas, 12 criaturas, 4 estruturas, 4 decks, 2 de combate e 2 de eventos")
      -- Cada jogador só tem espaços do seu lado da mesa.
      for n = 1, 6 do
        local e1, e2 = Mesa.espaco_criatura_abs(1, n, calib), Mesa.espaco_criatura_abs(2, n, calib)
        T.eq(e1.carta.lin, 13, "cartas do jogador 1 na linha 13")
        T.eq(e1.criatura.lin, 12, "criaturas do jogador 1 na linha 12")
        T.eq(e2.carta.lin, 6, "cartas do jogador 2 na linha 6")
        T.eq(e2.criatura.lin, 7, "criaturas do jogador 2 na linha 7")
      end
      local tiles = Mesa.tiles_dos_espacos(calib)
      T.eq(#tiles, 36, "tiles_dos_espacos: 36 tiles")
      local por_tipo, neutros = {}, 0
      for _, t in ipairs(tiles) do
        por_tipo[t.tipo] = (por_tipo[t.tipo] or 0) + 1
        T.eq(uso_no_mapa(grade, tile_no_ponto(t.x, t.z)), t.tipo, "tiles_dos_espacos: " .. t.tipo .. " sobre o seu tile")
        if t.jogador == 0 then
          neutros = neutros + 1
          T.eq(t.tipo, "evento", "só o espaço de eventos é neutro")
        end
      end
      T.eq(por_tipo.carta, 12, "12 cartas")
      T.eq(por_tipo.criatura, 12, "12 criaturas")
      T.eq(por_tipo.estrutura, 4, "4 estruturas")
      T.eq(por_tipo.deck, 4, "4 decks")
      T.eq(por_tipo.combate, 2, "2 de combate")
      T.eq(por_tipo.evento, 2, "2 de eventos")
      T.eq(neutros, 2, "2 tiles neutros")
    end
  end },

  { "heading: o lado de cada jogador fica embaixo da tela dele", function(T)
    local Mesa = nova_mesa()
    for _, caso in ipairs(CASOS) do
      local calib = calibrar_caso(Mesa, caso)
      T.eq(Mesa.heading(1, calib), 90, "jogador 1 (sul, z maior)")
      T.eq(Mesa.heading(2, calib), 270, "jogador 2 = jogador 1 + 180")
      T.eq(Mesa.heading(3, calib), 90, "espectador olha como o 1")
      T.eq(Mesa.heading(0, calib), 90, "lado desconhecido olha como o 1")
      -- GetDownVec = (cos h, sin h) aponta do centro para os espaços do jogador.
      local ox, oz = Mesa.centro_abs(calib)
      for p = 1, 2 do
        local h = math.rad(Mesa.heading(p, calib))
        local dx, dz = math.cos(h), math.sin(h)
        for n = 1, 6 do
          local e = Mesa.espaco_criatura_abs(p, n, calib)
          T.ok((e.criatura.x - ox) * dx + (e.criatura.z - oz) * dz > 0, "espaço " .. p .. "/" .. n .. " na metade de baixo")
          local o = Mesa.espaco_criatura_abs(3 - p, n, calib)
          T.ok((o.criatura.x - ox) * dx + (o.criatura.z - oz) * dz < 0, "espaço do outro na metade de cima")
        end
      end
    end
  end },

  { "cada jogador conta os espaços da esquerda para a direita da câmera dele", function(T)
    local Mesa = nova_mesa()
    for _, caso in ipairs(CASOS) do
      local calib = calibrar_caso(Mesa, caso)
      local rotulo = caso.nome
      for p = 1, 2 do
        local rx, rz = Mesa.direita(Mesa.heading(p, calib))
        local antes = -math.huge
        for n = 1, 6 do
          local e = Mesa.espaco_criatura_abs(p, n, calib)
          local d = e.carta.x * rx + e.carta.z * rz
          T.ok(d > antes, rotulo .. ": criatura " .. p .. "/" .. n .. " à direita da anterior")
          antes = d
        end
        local x1, z1 = Mesa.espaco_estrutura_abs(p, 1, calib)
        local x2, z2 = Mesa.espaco_estrutura_abs(p, 2, calib)
        T.ok(x1 * rx + z1 * rz < x2 * rx + z2 * rz, rotulo .. ": estrutura 1 à esquerda da 2")
      end
      -- O espaço n de um fica de frente para o 7 - n do outro.
      for n = 1, 6 do
        local a, b = Mesa.espaco_criatura_abs(1, n, calib), Mesa.espaco_criatura_abs(2, 7 - n, calib)
        T.eq(a.carta.x, b.carta.x, rotulo .. ": " .. n .. " de frente para " .. (7 - n))
      end
      -- No caso espelhado a ordem da câmera é a das listas do layout; sem
      -- espelhamento a câmera inverte as colunas.
      for p = 1, 2 do
        for n = 1, 6 do
          local e = Mesa.espaco_criatura_abs(p, n, calib)
          local esperado = caso.espelhado and Mesa.espaco_criatura(p, n).col or Mesa.espaco_criatura(p, 7 - n).col
          T.eq(e.carta.col, esperado, rotulo .. ": coluna do layout " .. p .. "/" .. n)
        end
      end
    end
  end },

  { "a calibração padrão fica em Mesa.calibracao", function(T)
    local Mesa = nova_mesa()
    T.eq(Mesa.calibracao, nil, "nasce sem calibração")
    T.eq(Mesa.espaco_criatura_abs(1, 1), nil, "sem calibração não há posição")
    T.eq(Mesa.tiles_dos_espacos(), nil, "nem tiles")
    local calib = calibrar_caso(Mesa, MEDIDO)
    Mesa.definir_calibracao(calib)
    T.eq(Mesa.calibracao, calib, "guardada")
    local e = Mesa.espaco_criatura_abs(1, 1)
    local e2 = Mesa.espaco_criatura_abs(1, 1, calib)
    T.eq(e.carta.x, e2.carta.x, "x igual à explícita")
    T.eq(e.carta.z, e2.carta.z, "z igual à explícita")
  end },

  { "calibracao.lua, marcadores.lua, camera.lua e o prefab compilam", function(T)
    for _, arq in ipairs({ "scripts/duelo/mod/calibracao.lua", "scripts/duelo/mod/marcadores.lua",
      "scripts/duelo/mod/camera.lua", "scripts/prefabs/duelo_marcador.lua" }) do
      local fn, err = loadfile(RAIZ .. arq)
      T.ok(fn, tostring(err))
    end
    T.eq(type(carregar("scripts/duelo/mod/calibracao.lua").instalar), "function", "Calibracao.instalar")
    T.eq(type(carregar("scripts/duelo/mod/marcadores.lua").instalar), "function", "Marcadores.instalar")
    T.eq(type(carregar("scripts/duelo/mod/camera.lua").instalar), "function", "Camera.instalar")
    local amb = ambiente_jogo({ servidor = true })
    T.eq(amb.prefab.nome, "duelo_marcador", "Prefab(\"duelo_marcador\", fn)")
  end },

  { "servidor acha a mesa no mapa, grava as netvars e avisa os inscritos", function(T)
    for _, caso in ipairs(CASOS) do
      local amb = instalar_tudo(ambiente_jogo({ servidor = true, caso = caso }))
      local recebidas = {}
      amb.Calibracao.quando_calibrar(function(c) recebidas[#recebidas + 1] = c end)
      carregar_mundo(amb)
      local calib = amb.Mesa.calibracao
      T.ok(calib, "Mesa.calibracao definida")
      T.eq(calib.fonte, "estruturas", caso.nome .. ": pelas estruturas")
      T.eq(calib.espelhado, caso.espelhado, caso.nome .. ": espelhado")
      local px, pz = portal_no_mundo(caso)
      T.ok(math.abs(amb.Mesa.tile_do_layout(px, pz) - 2) <= (caso.meio > 0 and 1 or 0), "portal na coluna 2")
      T.eq(#recebidas, 1, "inscrito avisado uma vez")
      T.eq(recebidas[1], calib, "com a calibração")
      T.eq(netvar(amb.reg, "duelo.mesa_origem_x"):value(), calib.origem_x, "netvar origem x")
      T.eq(netvar(amb.reg, "duelo.mesa_origem_z"):value(), calib.origem_z, "netvar origem z")
      T.eq(netvar(amb.reg, "duelo.mesa_espelhado"):value(), caso.espelhado, "netvar espelhado")
      T.eq(netvar(amb.reg, "duelo.mesa_fonte"):value(), 1, "netvar fonte = estruturas")
      T.ok(no_log(amb.reg, "mesa calibrada pelas estruturas"), "log da calibração")
      T.ok(not no_log(amb.reg, "não estão sobre"), caso.nome .. ": os 36 tiles de espaço conferem com o mapa")
      T.ok(no_log(amb.reg, "(eventos)"), caso.nome .. ": o log diz que o espelhamento saiu dos eventos")
      T.ok(not no_log(amb.reg, "coluna de eventos não achada"), caso.nome .. ": sem aviso dos eventos")
      T.ok(not no_log(amb.reg, "longe do esperado"), caso.nome .. ": portal onde o layout diz")
      -- Quem se inscreve depois recebe na hora.
      local tarde
      amb.Calibracao.quando_calibrar(function(c) tarde = c end)
      T.eq(tarde, calib, "inscrito tardio")
    end
  end },

  { "a busca das estruturas não sai do mapa", function(T)
    -- Mapa de 41 x 41 tiles: a mesa (tiles 20..40) encosta na borda leste e
    -- a busca em volta do portal (38 +- 20) passaria dela.
    local amb = instalar_tudo(ambiente_jogo({ servidor = true, tamanho = 41 }))
    carregar_mundo(amb)
    T.eq(amb.reg.fora_do_mapa, 0, "nenhum GetTile fora do mapa")
    T.eq(amb.Mesa.calibracao.fonte, "estruturas", "e as estruturas foram achadas")
  end },

  { "sem estruturas a origem sai do portal, com aviso; sem portal não calibra", function(T)
    local amb = instalar_tudo(ambiente_jogo({ servidor = true, sem_estruturas = true }))
    carregar_mundo(amb)
    local calib = amb.Mesa.calibracao
    T.eq(calib.fonte, "portal", "reserva pelo portal")
    T.eq(calib.espelhado, true, "espelhado medido")
    T.ok(no_log(amb.reg, "estruturas da mesa não achadas"), "avisa no log")
    T.ok(no_log(amb.reg, "4 dos 36 tiles de espaço não estão sobre os tiles esperados"), "a conferência acha as 4 estruturas faltando")
    T.eq(netvar(amb.reg, "duelo.mesa_fonte"):value(), 2, "netvar fonte = portal")
    T.eq(#amb.Marcadores.lista(), 22, "marcadores criados mesmo assim")

    amb = instalar_tudo(ambiente_jogo({ servidor = true, sem_portal = true }))
    carregar_mundo(amb)
    T.eq(amb.Mesa.calibracao, nil, "sem calibração")
    T.ok(no_log(amb.reg, "multiplayer_portal não achado"), "avisa no log")
    T.eq(#amb.Marcadores.lista(), 0, "nenhum marcador")
  end },

  { "cliente monta a calibração pelas netvars do forest_network", function(T)
    local srv = instalar_tudo(ambiente_jogo({ servidor = true }))
    carregar_mundo(srv)
    local cli = instalar_tudo(ambiente_jogo({ servidor = false }))
    local avisos = 0
    cli.Calibracao.quando_calibrar(function() avisos = avisos + 1 end)
    local rede = carregar_mundo(cli)
    T.eq(cli.Mesa.calibracao, nil, "cliente não calcula nada sozinho")
    T.eq(#cli.reg.log, 0, "nem tenta achar o portal")
    T.eq(#rede.tarefas, 1, "agenda uma leitura de 0 s")
    rede.tarefas[1]()
    T.eq(cli.Mesa.calibracao, nil, "fonte 0: ainda não chegou")
    -- Replica os valores do servidor e dispara o dirty.
    for _, nome in ipairs(NETVARS_MESA) do
      netvar(cli.reg, nome).valor = netvar(srv.reg, nome):value()
    end
    rede:PushEvent("duelo.mesadirty")
    local c = cli.Mesa.calibracao
    T.ok(c, "calibração no cliente")
    T.eq(c.origem_x, srv.Mesa.calibracao.origem_x, "origem x")
    T.eq(c.origem_z, srv.Mesa.calibracao.origem_z, "origem z")
    T.eq(c.espelhado, true, "espelhado")
    T.eq(c.fonte, "estruturas", "fonte")
    T.eq(avisos, 1, "inscritos avisados")
    rede:PushEvent("duelo.mesadirty")
    T.eq(avisos, 1, "o mesmo valor não avisa de novo")
    T.eq(#cli.Marcadores.lista(), 0, "cliente não cria marcadores")
    for _, nv in ipairs(cli.reg.netvars) do T.eq(nv.sets, 0, "cliente não escreve " .. nv.nome) end
  end },

  { "servidor cria 22 marcadores com os números certos nas posições da mesa", function(T)
    local amb = instalar_tudo(ambiente_jogo({ servidor = true }))
    carregar_mundo(amb)
    local lista = amb.Marcadores.lista()
    T.eq(#lista, 22, "22 marcadores")
    local marcadores = 0
    for _, nome in ipairs(amb.reg.spawns) do
      if nome == "duelo_marcador" then marcadores = marcadores + 1 end
    end
    T.eq(marcadores, 22, "22 SpawnPrefab do marcador")
    local calib, Mesa = amb.Mesa.calibracao, amb.Mesa
    local TIPO = amb.Marcadores.TIPO
    local vistos, por_tipo = {}, { 0, 0, 0, 0, 0 }
    for _, m in ipairs(lista) do
      T.eq(m.persists, false, "não persiste")
      local tipo, jog, num = m.duelo_tipo:value(), m.duelo_jogador:value(), m.duelo_numero:value()
      T.ok(tipo >= 1 and tipo <= 7 and jog <= 7 and num <= 7, "valores cabem num net_tinybyte (0..7)")
      por_tipo[tipo] = por_tipo[tipo] + 1
      local chave = tipo .. "/" .. jog .. "/" .. num
      T.ok(not vistos[chave], "marcador repetido " .. chave)
      vistos[chave] = true
      local x, _, z = m.Transform:GetWorldPosition()
      local ex, ez
      if tipo == TIPO.criatura then
        local carta = Mesa.espaco_criatura_abs(jog, num, calib).carta
        ex, ez = carta.x, carta.z
      elseif tipo == TIPO.estrutura then ex, ez = Mesa.espaco_estrutura_abs(jog, num, calib)
      elseif tipo == TIPO.deck then ex, ez = Mesa.espaco_deck_abs(jog, num == 1 and "principal" or "extra", calib)
      elseif tipo == TIPO.evento then
        local c = Mesa.espaco_evento_abs(calib).centro
        ex, ez = c.x, c.z
      else ex, ez = Mesa.centro_abs(calib) end
      T.eq(x, ex, chave .. " x")
      T.eq(z, ez, chave .. " z")
      -- Host (servidor com tela): o dirty do set já montou o rótulo.
      T.eq(m.Label.texto, amb.Marcadores.texto(tipo, jog, num), chave .. " texto no host")
      T.eq(m.Label.ativo, true, chave .. " visível")
    end
    T.eq(por_tipo[TIPO.criatura], 12, "12 criaturas")
    T.eq(por_tipo[TIPO.estrutura], 4, "4 estruturas")
    T.eq(por_tipo[TIPO.combate], 1, "1 Combate")
    T.eq(por_tipo[TIPO.deck], 4, "4 decks")
    T.eq(por_tipo[TIPO.evento], 1, "1 Eventos")
    for p = 1, 2 do
      for n = 1, 6 do T.ok(vistos["1/" .. p .. "/" .. n], "criatura " .. p .. "/" .. n) end
      for n = 1, 2 do T.ok(vistos["2/" .. p .. "/" .. n], "estrutura " .. p .. "/" .. n) end
      for n = 1, 2 do T.ok(vistos["4/" .. p .. "/" .. n], "deck " .. p .. "/" .. n) end
    end
    T.ok(vistos["3/0/0"], "Combate, sem jogador")
    T.ok(vistos["5/0/0"], "Eventos, sem jogador")
    -- Recalibrar (console) troca os marcadores, sem duplicar.
    amb.Calibracao.calibrar()
    T.eq(amb.reg.removidos, 22 + 36, "os 22 marcadores antigos (e os 36 contornos do host) removidos")
    T.eq(#amb.Marcadores.lista(), 22, "22 de novo")
  end },
  { "textos e cores dos marcadores", function(T)
    local M = carregar("scripts/duelo/mod/marcadores.lua")
    T.eq(M.TIPO.criatura, 1, "tipo criatura")
    T.eq(M.TIPO.estrutura, 2, "tipo estrutura")
    T.eq(M.TIPO.combate, 3, "tipo combate")
    T.eq(M.TIPO.deck, 4, "tipo deck")
    T.eq(M.TIPO.evento, 5, "tipo evento")
    T.eq(M.texto(1, 1, 3), "J1 3", "criatura")
    T.eq(M.texto(1, 2, 6), "J2 6", "criatura do 2")
    T.eq(M.texto(2, 1, 1), "J1 E1", "estrutura")
    T.eq(M.texto(2, 2, 2), "J2 E2", "estrutura do 2")
    T.eq(M.texto(3, 0, 0), "Combate", "combate")
    T.eq(M.texto(4, 1, 1), "J1 Deck", "deck principal")
    T.eq(M.texto(4, 2, 2), "J2 Extra", "deck extra")
    T.eq(M.texto(4, 1, 3), nil, "não há terceiro deck")
    T.eq(M.texto(5, 0, 0), "Eventos", "eventos")
    T.eq(M.texto(0, 0, 0), nil, "ainda não definido")
    T.eq(M.texto(1, 0, 3), nil, "sem jogador")
    T.eq(M.texto(4, 0, 1), nil, "deck sem jogador")
    T.eq(M.texto(1, 1, 0), nil, "sem número")
    local r1, g1, b1 = M.cor(1, 1)
    local r2, g2, b2 = M.cor(1, 2)
    T.ok(r1 ~= r2 or g1 ~= g2 or b1 ~= b2, "cores diferentes por jogador")
    T.ok(b1 > r1, "jogador 1 azulado")
    T.ok(r2 > b2, "jogador 2 avermelhado")
    -- Sem dono (jogador 0) e nas zonas compartilhadas: cor neutra, nem azul
    -- nem vermelha.
    for _, caso in ipairs({ { 5, 0 }, { 3, 0 }, { 1, 0 }, { 5, 1 } }) do
      local r, g, b = M.cor(caso[1], caso[2])
      T.eq(r, M.CORES.neutro[1], "neutro r")
      T.eq(g, M.CORES.neutro[2], "neutro g")
      T.eq(b, M.CORES.neutro[3], "neutro b")
      T.ok(r > b and g > b and math.abs(r - g) < 0.2, "amarelado: nem azul nem vermelho")
    end
    local rd, gd, bd = M.cor(4, 2)
    T.eq(rd, r2, "deck na cor do dono (r)")
    T.eq(gd, g2, "deck na cor do dono (g)")
    T.eq(bd, b2, "deck na cor do dono (b)")
  end },

  { "cliente monta o texto do marcador pelas netvars", function(T)
    local srv = instalar_tudo(ambiente_jogo({ servidor = true }))
    carregar_mundo(srv)
    local cli = ambiente_jogo({ servidor = false })
    for _, m in ipairs(srv.Marcadores.lista()) do
      local c = cli.prefab.fn()
      T.eq(c.Label.ativo, false, "nasce apagado")
      T.eq(#c.tarefas, 1, "agenda uma leitura de 0 s")
      c.tarefas[1](c)
      T.eq(c.Label.ativo, false, "sem valores ainda")
      replicar(m, c)
      local esperado = srv.Marcadores.texto(m.duelo_tipo:value(), m.duelo_jogador:value(), m.duelo_numero:value())
      T.eq(c.Label.texto, esperado, "texto no cliente")
      T.eq(c.Label.ativo, true, "aceso")
      local r, g, b = srv.Marcadores.cor(m.duelo_tipo:value(), m.duelo_jogador:value())
      T.eq(c.Label.cor[1], r, "cor r")
      T.eq(c.Label.cor[2], g, "cor g")
      T.eq(c.Label.cor[3], b, "cor b")
      T.eq(c.Label.fonte, "talkingfont", "fonte com contorno")
    end
  end },

  { "prefab: marcador sem clique e só a parte de servidor no servidor", function(T)
    local srv = ambiente_jogo({ servidor = true })
    local m = srv.prefab.fn()
    T.ok(m.Transform and m.rede and m.Label, "Transform, Network e Label")
    T.ok(m.pristine, "SetPristine")
    for _, tag in ipairs({ "NOCLICK", "FX", "NOBLOCK" }) do T.ok(m:HasTag(tag), "tag " .. tag) end
    T.eq(m.persists, false, "servidor: persists = false")
    T.eq(type(m.Definir), "function", "servidor: Definir")
    T.eq(m.Physics, nil, "sem física")
    T.eq(#m.tarefas, 0, "servidor não agenda leitura")
    T.ok(m.eventos["duelo_marcador.dirty"], "host escuta o dirty (desenha o rótulo)")
    m:Definir(1, 2, 4)
    T.eq(m.Label.texto, "J2 4", "Definir monta o texto no host")

    local cli = ambiente_jogo({ servidor = false })
    local c = cli.prefab.fn()
    T.ok(c.pristine, "cliente: SetPristine")
    T.eq(c.persists, nil, "cliente: não mexe em persists")
    T.eq(c.Definir, nil, "cliente: sem Definir")
    T.ok(c.duelo_tipo and c.duelo_jogador and c.duelo_numero, "netvars declaradas nos dois lados")
    T.eq(#cli.reg.netvars, #srv.reg.netvars, "mesmas netvars nos dois lados")

    local ded = ambiente_jogo({ servidor = true, dedicado = true })
    local d = ded.prefab.fn()
    T.eq(d.eventos["duelo_marcador.dirty"], nil, "dedicado não escuta o dirty")
    T.eq(d.persists, false, "dedicado: persists = false")
  end },

  { "lado: primeiro é o 1, segundo o 2, demais espectadores; quem volta recupera o lado", function(T)
    local C = carregar("scripts/duelo/mod/camera.lua")
    T.eq(C.escolher_lado({}, nil), 1, "ninguém: 1")
    T.eq(C.escolher_lado({ [1] = true }, nil), 2, "1 ocupado: 2")
    T.eq(C.escolher_lado({ [1] = true, [2] = true }, nil), 3, "cheio: espectador")
    T.eq(C.escolher_lado({ [1] = true }, 2), 2, "volta para o seu")
    T.eq(C.escolher_lado({ [2] = true }, 2), 1, "o seu foi tomado: o livre")
    T.eq(C.escolher_lado({}, 3), 1, "espectador pega um lado livre")

    local amb = instalar_tudo(ambiente_jogo({ servidor = true }))
    carregar_mundo(amb)
    local G = amb.G
    local function entrar(uid)
      local j = novo_jogador(amb, uid)
      table.insert(G.AllPlayers, j)
      G.TheWorld:PushEvent("ms_playerjoined", j)
      return j
    end
    local a, b, c = entrar("A"), entrar("B"), entrar("C")
    T.eq(a.duelo_lado:value(), 1, "A é o 1")
    T.eq(b.duelo_lado:value(), 2, "B é o 2")
    T.eq(c.duelo_lado:value(), 3, "C é espectador")
    -- A sai e volta: recupera o 1.
    table.remove(G.AllPlayers, 1)
    local a2 = entrar("A")
    T.eq(a2.duelo_lado:value(), 1, "A volta como 1")
    -- B sai; quem entra depois fica com o 2.
    for i, j in ipairs(G.AllPlayers) do if j == b then table.remove(G.AllPlayers, i) break end end
    local d = entrar("D")
    T.eq(d.duelo_lado:value(), 2, "D fica com o 2 livre")

    local cli = instalar_tudo(ambiente_jogo({ servidor = false }))
    carregar_mundo(cli)
    local j = novo_jogador(cli, "X")
    T.eq(cli.Camera.atribuir_lado(j), nil, "cliente não atribui lado")
    T.eq(j.duelo_lado.sets, 0, "nem escreve na netvar")
  end },

  { "câmera fixa no centro com o heading do lado e sem rotação", function(T)
    local srv = instalar_tudo(ambiente_jogo({ servidor = true }))
    carregar_mundo(srv)
    local amb = instalar_tudo(ambiente_jogo({ servidor = false }))
    amb.Mesa.definir_calibracao(srv.Mesa.calibracao)
    local G = amb.G
    local cam = camera_falsa()
    G.TheCamera = cam
    G.TheFocalPoint = entidade(amb.reg, "focalpoint")
    local j = novo_jogador(amb, "A")
    G.ThePlayer = j

    -- Q/E: o RotLeft original gira 45 graus pela câmera.
    local pc = { originais = 0 }
    function pc:RotLeft() self.originais = self.originais + 1; cam:SetHeadingTarget(cam:GetHeadingTarget() - 45) end
    function pc:RotRight() self.originais = self.originais + 1; cam:SetHeadingTarget(cam:GetHeadingTarget() + 45) end
    amb.reg.component_postinits.playercontroller(pc, j)

    j:PushEvent("playeractivated")
    T.eq(amb.Camera.travada(), true, "travada na ativação (lado ainda 0: olha como o 1)")
    T.eq(cam.headingtarget, 90, "heading do jogador 1")
    j.duelo_lado.valor = 1
    j:PushEvent("duelo.ladodirty")
    T.eq(cam.headingtarget, 90, "jogador 1 = 90")
    local alvo = cam.target
    T.ok(alvo ~= nil and alvo ~= j and alvo ~= G.TheFocalPoint, "alvo próprio, não o jogador")
    T.eq(alvo.persists, false, "alvo local não persiste")
    T.eq(alvo.rede, nil, "alvo sem rede")
    local ax, _, az = alvo.Transform:GetWorldPosition()
    local cx, cz = amb.Mesa.centro_da_mesa_abs()
    T.ok(math.abs(ax - cx) < 1e-9, "alvo no x do centro da mesa (heading 90 só desloca em z)")
    -- A mesa não é simétrica: o alvo fica 1 coluna para o lado dos eventos
    -- em relação ao par de combate.
    local bx = amb.Mesa.centro_abs()
    local ev = amb.Mesa.espaco_evento_abs().pilha
    T.eq(math.abs(cx - bx), amb.Mesa.TILE_SCALE, "1 tile ao lado do combate")
    T.ok((cx - bx) * (ev.x - bx) > 0, "para o lado da coluna de eventos")
    T.ok(math.abs(az - (cz + amb.Camera.DESLOCAMENTO)) < 1e-9, "alvo deslocado para o lado do jogador 1 (z maior)")
    T.eq(cam.distancetarget, amb.Camera.DISTANCIA, "distância da mesa")
    -- A vista do Aerial View pedida pelo dono (bug #147).
    T.eq(cam.distancetarget, 80, "distância 80")
    T.eq(cam.mindist, 5, "mindist 5")
    T.eq(cam.maxdist, 180, "maxdist 180")
    T.eq(cam.mindistpitch, 40, "mindistpitch 40")
    T.eq(cam.maxdistpitch, 60, "maxdistpitch 60")
    T.eq(cam.mindist, amb.Camera.DISTANCIA_MIN, "mínimo do mod")
    T.eq(cam.maxdist, amb.Camera.DISTANCIA_MAX, "máximo do mod")
    T.ok(cam.snaps >= 1, "Snap")
    T.eq(cam:CanControl(), true, "zoom continua liberado")

    -- Zoom livre entre 30 e 180: o mindist 5 só serve à inclinação.
    T.eq(amb.Camera.ZOOM_MIN, 30, "ZOOM_MIN")
    for _ = 1, 40 do cam:ZoomIn() end
    T.eq(cam.distancetarget, 30, "a roda do mouse não aproxima além de 30")
    cam:ContinuousZoomDelta(-100)
    T.eq(cam.distancetarget, 30, "nem o zoom contínuo")
    cam:ContinuousZoomDelta(7)
    T.eq(cam.distancetarget, 37, "acima de 30 o zoom contínuo é livre")
    for _ = 1, 60 do cam:ZoomOut() end
    T.eq(cam.distancetarget, 180, "afasta até 180")
    cam:SetDistance(amb.Camera.DISTANCIA)
    -- O player_classified limita o extra a PLAYER_CAMERA_MAX_DIST - maxdist
    -- (80 - 180): sem a proteção o máximo voltaria para 80.
    cam:SetExtraMaxDistance(-100)
    T.eq(cam.maxdist, 180, "o extra de distância não baixa o máximo")
    T.eq(cam.extramaxdist, 0, "o extra fica em 0")
    T.eq(cam.distancetarget, amb.Camera.DISTANCIA, "nem mexe na distância")

    pc:RotLeft()
    T.eq(cam.headingtarget, 90, "Q não gira")
    pc:RotRight()
    T.eq(cam.headingtarget, 90, "E não gira")
    T.eq(pc.originais, 0, "RotLeft/RotRight originais nem são chamados")
    cam:SetHeadingTarget(45) -- SnapCamera(resetrot)
    T.eq(cam.headingtarget, 90, "SetHeadingTarget de fora não tira da mesa")
    cam:SetContinuousHeadingTarget(10, 2) -- analógico
    T.eq(cam.headingtarget, 90, "nem a rotação contínua")
    cam:SetDefault() -- FocalPoint:Reset
    T.eq(cam.distancetarget, amb.Camera.DISTANCIA, "SetDefault reaplica a distância")
    T.eq(cam.mindist, amb.Camera.DISTANCIA_MIN, "o mínimo")
    T.eq(cam.maxdist, amb.Camera.DISTANCIA_MAX, "o máximo")
    T.eq(cam.mindistpitch, amb.Camera.PITCH_MIN, "a inclinação mínima")
    T.eq(cam.maxdistpitch, amb.Camera.PITCH_MAX, "a inclinação máxima")
    T.eq(cam.target, alvo, "e o alvo")

    -- O servidor diz que este é o jogador 2: a mesa vira.
    j.duelo_lado.valor = 2
    j:PushEvent("duelo.ladodirty")
    T.eq(cam.headingtarget, 270, "jogador 2 = 90 + 180")
    T.eq(cam.target, alvo, "o mesmo alvo")
    pc:RotLeft()
    T.eq(cam.headingtarget, 270, "Q não gira o jogador 2")
    -- Espectador olha como o 1.
    j.duelo_lado.valor = 3
    j:PushEvent("duelo.ladodirty")
    T.eq(cam.headingtarget, 90, "espectador = 90")

    -- O dirty de outro jogador não mexe na câmera local.
    local outro = novo_jogador(amb, "B")
    outro.duelo_lado.valor = 2
    outro:PushEvent("duelo.ladodirty")
    T.eq(cam.headingtarget, 90, "dirty de outro jogador não muda nada")

    -- Liberar devolve a câmera normal e o Q volta a girar.
    amb.Camera.liberar()
    T.eq(amb.Camera.travada(), false, "liberada")
    T.eq(cam.target, G.TheFocalPoint, "alvo de volta ao TheFocalPoint")
    T.eq(cam.maxdist, 50, "distâncias do jogo de volta")
    T.eq(cam.maxdistpitch, 60, "e a inclinação do jogo")
    T.eq(cam.mindistpitch, 30, "mínima inclusive")
    cam:ZoomIn()
    T.eq(cam.distancetarget, 26, "liberada, o zoom do jogo aproxima abaixo de 30")
    cam:SetExtraMaxDistance(10)
    T.eq(cam.maxdist, 60, "e o extra de distância volta a valer")
    cam:SetExtraMaxDistance(0)
    pc:RotLeft()
    T.eq(cam.headingtarget, 45, "Q gira de novo")
    T.eq(pc.originais, 1, "o original volta a ser chamado")
    T.eq(amb.Camera.aplicar(), true, "aplicar trava de novo")
    T.eq(cam.headingtarget, 90, "de volta à mesa")
  end },

  { "câmera espera a calibração e não roda no servidor dedicado", function(T)
    local amb = instalar_tudo(ambiente_jogo({ servidor = false }))
    local G = amb.G
    local cam = camera_falsa()
    G.TheCamera = cam
    local j = novo_jogador(amb, "A")
    G.ThePlayer = j
    j:PushEvent("playeractivated")
    T.eq(amb.Camera.travada(), false, "sem calibração ainda")
    T.eq(cam.headingtarget, 45, "câmera intocada")
    -- A calibração chega pelo forest_network: a câmera trava.
    local srv = instalar_tudo(ambiente_jogo({ servidor = true }))
    carregar_mundo(srv)
    local rede = carregar_mundo(amb)
    for _, nome in ipairs({ "duelo.mesa_origem_x", "duelo.mesa_origem_z", "duelo.mesa_espelhado", "duelo.mesa_fonte" }) do
      netvar(amb.reg, nome).valor = netvar(srv.reg, nome):value()
    end
    rede:PushEvent("duelo.mesadirty")
    T.eq(amb.Camera.travada(), true, "travou quando a calibração chegou")
    T.eq(cam.headingtarget, 90, "heading do 1")

    local ded = instalar_tudo(ambiente_jogo({ servidor = true, dedicado = true }))
    ded.G.TheCamera = camera_falsa()
    carregar_mundo(ded)
    local jd = novo_jogador(ded, "A")
    T.ok(jd.duelo_lado, "netvar do lado declarada no dedicado")
    T.eq(jd.eventos.playeractivated, nil, "dedicado não escuta playeractivated")
    T.eq(ded.Camera.aplicar(), false, "dedicado não aplica câmera")
  end },

  -- -------------------------------------------------------------------------
  -- Layout aprovado na #30 (bug #147): rótulos, contornos e enquadramento
  -- -------------------------------------------------------------------------

  { "rótulos: número no tile da carta, E1/E2, Deck, Extra, Combate e Eventos", function(T)
    for _, caso in ipairs(CASOS) do
      local amb = instalar_tudo(ambiente_jogo({ servidor = true, caso = caso }))
      carregar_mundo(amb)
      local TIPO = amb.Marcadores.TIPO
      local uso_do_tipo = { [TIPO.criatura] = "carta", [TIPO.estrutura] = "estrutura", [TIPO.deck] = "deck" }
      local por_texto = {}
      for _, m in ipairs(amb.Marcadores.lista()) do
        local x, _, z = m.Transform:GetWorldPosition()
        local tipo, jog = m.duelo_tipo:value(), m.duelo_jogador:value()
        T.eq(por_texto[m.Label.texto], nil, caso.nome .. ": " .. m.Label.texto .. " aparece uma vez só")
        por_texto[m.Label.texto] = { x = x, z = z, tipo = tipo }
        local r, g, b = amb.Marcadores.cor(tipo, jog)
        T.eq(m.Label.cor[1], r, m.Label.texto .. ": cor r")
        T.eq(m.Label.cor[2], g, m.Label.texto .. ": cor g")
        T.eq(m.Label.cor[3], b, m.Label.texto .. ": cor b")
        if uso_do_tipo[tipo] then
          T.eq(uso_no_mapa(amb.grade, tile_no_ponto(x, z)), uso_do_tipo[tipo],
            caso.nome .. ": " .. m.Label.texto .. " no tile de " .. uso_do_tipo[tipo])
          T.eq(m.Label.tamanho, amb.Marcadores.TAMANHO.espaco, m.Label.texto .. ": tamanho de espaço")
        else
          T.eq(jog, 0, m.Label.texto .. ": sem dono")
          T.eq(m.Label.tamanho, amb.Marcadores.TAMANHO.zona, m.Label.texto .. ": tamanho de zona")
        end
      end
      for p = 1, 2 do
        for n = 1, 6 do T.ok(por_texto["J" .. p .. " " .. n], caso.nome .. ": J" .. p .. " " .. n) end
        for _, t in ipairs({ "E1", "E2", "Deck", "Extra" }) do
          T.ok(por_texto["J" .. p .. " " .. t], caso.nome .. ": J" .. p .. " " .. t)
        end
        -- Fileira de trás, da esquerda para a direita de quem olha: Deck,
        -- E1, E2, Extra, atrás dos espaços 1, 3, 4 e 6.
        local rx, rz = amb.Mesa.direita(amb.Mesa.heading(p))
        local antes = -math.huge
        for i, t in ipairs({ "Deck", "E1", "E2", "Extra" }) do
          local m = por_texto["J" .. p .. " " .. t]
          local d = m.x * rx + m.z * rz
          T.ok(d > antes, caso.nome .. ": J" .. p .. " " .. t .. " à direita do anterior")
          antes = d
          local carta = amb.Mesa.espaco_criatura_abs(p, ({ 1, 3, 4, 6 })[i]).carta
          T.eq(d, carta.x * rx + carta.z * rz, caso.nome .. ": J" .. p .. " " .. t .. " atrás do espaço " .. ({ 1, 3, 4, 6 })[i])
        end
      end
      -- "Combate" na junção dos dois quadrados de combate.
      local c = por_texto["Combate"]
      local c1x, c1z = amb.Mesa.espaco_combate_abs(1)
      local c2x, c2z = amb.Mesa.espaco_combate_abs(2)
      T.eq(c.x, (c1x + c2x) / 2, caso.nome .. ": Combate entre os dois quadrados (x)")
      T.eq(c.z, (c1z + c2z) / 2, caso.nome .. ": Combate entre os dois quadrados (z)")
      -- "Eventos" na junção da pilha com o evento em vigor: um rótulo só.
      local e, ev = por_texto["Eventos"], amb.Mesa.espaco_evento_abs()
      T.eq(e.x, ev.pilha.x, caso.nome .. ": Eventos na coluna de eventos")
      T.eq(e.z, (ev.pilha.z + ev.em_vigor.z) / 2, caso.nome .. ": Eventos entre os 2 tiles")
      T.eq(e.z, c.z, caso.nome .. ": Eventos alinhado ao Combate")
      T.eq(por_texto["Evento"], nil, "não há um rótulo de evento por jogador")
    end
  end },

  { "contornos: um tile_outline em cada um dos 36 tiles de espaço, na cor do dono", function(T)
    for _, caso in ipairs(CASOS) do
      local amb = instalar_tudo(ambiente_jogo({ servidor = true, caso = caso }))
      carregar_mundo(amb)
      local lista = amb.Contornos.lista()
      T.eq(#lista, 36, caso.nome .. ": 36 contornos no host")
      T.eq(#amb.reg.gridplacers, 36, "36 SpawnPrefab(\"tile_outline\")")
      T.eq(amb.Contornos.PREFAB, "tile_outline", "não o gridplacer: o componente placer dele quebra outros mods")
      for _, e in ipairs(amb.reg.gridplacers) do T.eq(e.components, nil, "contorno sem componentes") end
      local vistos, por_tipo = {}, { carta = 0, criatura = 0, estrutura = 0, deck = 0, combate = 0, evento = 0 }
      for _, c in ipairs(lista) do
        local g = c.inst
        local x, _, z = g.Transform:GetWorldPosition()
        local tx, ty = tile_no_ponto(x, z)
        local cx, cz = centro_mundo(tx, ty)
        T.eq(x, cx, "no centro do tile (x)")
        T.eq(z, cz, "no centro do tile (z)")
        T.eq(uso_no_mapa(amb.grade, tx, ty), c.tipo, caso.nome .. ": contorno de " .. c.tipo .. " sobre o tile certo")
        local chave = tx .. "," .. ty
        T.ok(not vistos[chave], "um contorno por tile")
        vistos[chave] = true
        por_tipo[c.tipo] = por_tipo[c.tipo] + 1
        -- O tile pertence ao espaço que o contorno diz.
        local e
        if c.tipo == "estrutura" then
          local ex, ez = amb.Mesa.espaco_estrutura_abs(c.jogador, c.n)
          e = { x = ex, z = ez }
        elseif c.tipo == "deck" then
          local ex, ez = amb.Mesa.espaco_deck_abs(c.jogador, c.n)
          e = { x = ex, z = ez }
        elseif c.tipo == "combate" then
          local ex, ez = amb.Mesa.espaco_combate_abs(c.jogador)
          e = { x = ex, z = ez }
        elseif c.tipo == "evento" then
          e = amb.Mesa.espaco_evento_abs()[c.n]
        else
          e = amb.Mesa.espaco_criatura_abs(c.jogador, c.n)[c.tipo]
        end
        T.eq(x, e.x, "espaço " .. c.jogador .. "/" .. c.tipo .. "/" .. tostring(c.n) .. " (x)")
        T.eq(z, e.z, "espaço " .. c.jogador .. "/" .. c.tipo .. "/" .. tostring(c.n) .. " (z)")
        -- Cor do dono: saturada (a do rótulo, clara, saiu quase branca no
        -- jogo), só por multiplicação.
        local r, gg, b = amb.Contornos.cor(c.jogador)
        T.eq(g.AnimState.mult[1], r, "cor r")
        T.eq(g.AnimState.mult[2], gg, "cor g")
        T.eq(g.AnimState.mult[3], b, "cor b")
        T.eq(g.AnimState.mult[4], 1, "opaco")
        if c.jogador == 1 then
          T.ok(b == 1 and r <= 0.2 and gg <= 0.4, "jogador 1 azul nítido")
        elseif c.jogador == 2 then
          T.ok(r == 1 and gg <= 0.2 and b <= 0.2, "jogador 2 vermelho nítido")
        else
          T.eq(c.jogador, 0, "sem dono")
          T.eq(c.tipo, "evento", "só os eventos não têm dono")
          T.ok(r == 1 and gg >= 0.7 and b <= 0.2, "eventos em amarelo: nem azul nem vermelho")
        end
        for i = 1, 4 do T.eq(g.AnimState.add[i], 0, "sem cor somada (só o destaque soma)") end
        -- Sem colisão, sem clique e sem rede (o gridplacer do jogo).
        T.ok(g:HasTag("NOCLICK"), "NOCLICK")
        T.eq(g.Physics, nil, "sem física")
        T.eq(g.rede, nil, "sem rede")
        T.eq(g.persists, false, "não persiste")
      end
      T.eq(por_tipo.carta, 12, "12 cartas")
      T.eq(por_tipo.criatura, 12, "12 criaturas")
      T.eq(por_tipo.estrutura, 4, "4 estruturas")
      T.eq(por_tipo.deck, 4, "4 decks")
      T.eq(por_tipo.combate, 2, "2 de combate")
      T.eq(por_tipo.evento, 2, "2 de eventos")
    end
  end },

  { "contornos: recriados sem duplicar, só com tela, e cada cliente cria os seus", function(T)
    local amb = instalar_tudo(ambiente_jogo({ servidor = true }))
    carregar_mundo(amb)
    local antigos = amb.Contornos.lista()
    amb.Calibracao.calibrar()
    T.eq(#amb.Contornos.lista(), 36, "36 de novo")
    for _, c in ipairs(antigos) do T.eq(c.inst:IsValid(), false, "o antigo foi removido") end

    local ded = instalar_tudo(ambiente_jogo({ servidor = true, dedicado = true }))
    carregar_mundo(ded)
    T.ok(ded.Mesa.calibracao, "o dedicado calibra")
    T.eq(#ded.Contornos.lista(), 0, "mas não cria contornos")
    T.eq(ded.reg.gridplacers, nil, "nenhum gridplacer no dedicado")

    -- Cliente: cria os contornos quando a calibração chega pela rede.
    local cli = instalar_tudo(ambiente_jogo({ servidor = false }))
    local rede = carregar_mundo(cli)
    T.eq(#cli.Contornos.lista(), 0, "sem calibração, sem contornos")
    for _, nome in ipairs(NETVARS_MESA) do
      netvar(cli.reg, nome).valor = netvar(amb.reg, nome):value()
    end
    rede:PushEvent("duelo.mesadirty")
    T.eq(#cli.Contornos.lista(), 36, "36 contornos no cliente")
    for i, c in ipairs(cli.Contornos.lista()) do
      local x, _, z = c.inst.Transform:GetWorldPosition()
      local x2, _, z2 = amb.Contornos.lista()[i].inst.Transform:GetWorldPosition()
      T.eq(x, x2, "mesma posição do host (x)")
      T.eq(z, z2, "mesma posição do host (z)")
    end

    -- Sem o prefab (não carregado): avisa uma vez e não quebra.
    local sem = instalar_tudo(ambiente_jogo({ servidor = true, sem_gridplacer = true }))
    carregar_mundo(sem)
    T.eq(#sem.Contornos.lista(), 0, "nenhum contorno")
    T.ok(no_log(sem.reg, "tile_outline não achado"), "avisa no log")
    T.eq(#sem.Marcadores.lista(), 22, "os rótulos continuam")
  end },

  { "contornos: destacar um espaço muda só os tiles dele", function(T)
    local amb = instalar_tudo(ambiente_jogo({ servidor = true }))
    carregar_mundo(amb)
    local C = amb.Contornos
    local function so(texto, alvo)
      for _, c in ipairs(C.lista()) do
        T.eq(c.inst.AnimState.add[1], alvo(c) and C.DESTAQUE[1] or 0, texto)
      end
    end
    T.eq(C.destacar(1, "criatura", 3, true), 2, "espaço de criatura: carta e criatura")
    so("destaque só no espaço 1/3", function(c)
      return c.jogador == 1 and c.n == 3 and (c.tipo == "carta" or c.tipo == "criatura")
    end)
    T.eq(C.destacar(2, "estrutura", 1, true), 1, "estrutura: 1 tile")
    T.eq(C.destacar(1, "criatura", 3, false), 2, "apaga o destaque")
    so("só a estrutura 2/1 destacada", function(c) return c.jogador == 2 and c.n == 1 and c.tipo == "estrutura" end)
    T.eq(C.destacar(2, "estrutura", 1, false), 1, "apaga")
    T.eq(C.destacar(1, "criatura", 7, true), 0, "espaço que não existe")
    -- Os espaços novos.
    T.eq(C.destacar(1, "deck", "extra", true), 1, "deck extra: 1 tile")
    so("só o deck extra do 1", function(c) return c.jogador == 1 and c.tipo == "deck" and c.n == "extra" end)
    T.eq(C.destacar(1, "deck", "extra", false), 1, "apaga")
    T.eq(C.destacar(2, "combate", nil, true), 1, "quadrado de combate: 1 tile")
    so("só o combate do 2", function(c) return c.jogador == 2 and c.tipo == "combate" end)
    T.eq(C.destacar(2, "combate", nil, false), 1, "apaga")
    T.eq(C.destacar(0, "evento", nil, true), 2, "espaço de eventos: os 2 tiles")
    so("só os eventos", function(c) return c.tipo == "evento" end)
    T.eq(C.destacar(0, "evento", "pilha", false), 1, "apaga só a pilha")
    so("só o evento em vigor", function(c) return c.tipo == "evento" and c.n == "em_vigor" end)
    T.eq(C.destacar(1, "evento", nil, true), 0, "o espaço de eventos não é de um jogador")
  end },

  -- -------------------------------------------------------------------------
  -- Mesa pedida no teste em jogo (bug #147): o que cada jogador vê
  -- -------------------------------------------------------------------------

  { "a mesa vista pela câmera de cada jogador é o mapa pedido, nos dois espelhamentos", function(T)
    -- Mapa do comentário da issue #147, visto pelo jogador 1 (embaixo).
    local PEDIDO = {
      "RRRRRRRRRRRRRRR",
      "RXRRRERERRRPRRR",
      "RRRRRRRRRRRRRRR",
      "RKRKRKRKRKRKRRR",
      "RVRVRVRVRVRVRRR",
      "RRRRRRRRRRRRRRR",
      "RRRRRRDRRRRRReR",
      "RRRRRRARRRRRReR",
      "RRRRRRRRRRRRRRR",
      "RVRVRVRVRVRVRRR",
      "RKRKRKRKRKRKRRR",
      "RRRRRRRRRRRRRRR",
      "RPRRRERERRRXRRR",
      "RRRRRRRRRRRRRRR",
    }
    local LETRA = { carta = "K", criatura = "V", estrutura = "E", evento = "e" }
    -- Desenha a mesa como a câmera do jogador `p` a mostra: colunas pela
    -- direita da tela, linhas por GetDownVec, e cada espaço com a letra do
    -- que as funções absolutas dizem que ele é.
    local function vista(Mesa, calib, p)
      local h = Mesa.heading(p, calib)
      local rx, rz = Mesa.direita(h)
      local bx, bz = math.cos(math.rad(h)), math.sin(math.rad(h))
      local m = Mesa.MESA
      local dmin, bmin = math.huge, math.huge
      for _, canto in ipairs({ { m.col_min, m.lin_min }, { m.col_max, m.lin_max } }) do
        local x, z = Mesa.posicao_abs(canto[1], canto[2], calib)
        dmin = math.min(dmin, x * rx + z * rz)
        bmin = math.min(bmin, x * bx + z * bz)
      end
      local linhas = {}
      for l = 1, m.lin_max - m.lin_min + 1 do
        linhas[l] = {}
        for c = 1, m.col_max - m.col_min + 1 do linhas[l][c] = "R" end
      end
      for _, t in ipairs(Mesa.tiles_dos_espacos(calib)) do
        local c = math.floor((t.x * rx + t.z * rz - dmin) / Mesa.TILE_SCALE + 0.5) + 1
        local l = math.floor((t.x * bx + t.z * bz - bmin) / Mesa.TILE_SCALE + 0.5) + 1
        local letra = LETRA[t.tipo]
        if t.tipo == "deck" then letra = t.n == "principal" and "P" or "X" end
        -- "A" é o quadrado de combate de quem olha, "D" o do outro.
        if t.tipo == "combate" then letra = t.jogador == p and "A" or "D" end
        T.eq(linhas[l][c], "R", "um espaço por tile")
        linhas[l][c] = letra
      end
      for l, linha in ipairs(linhas) do linhas[l] = table.concat(linha) end
      return linhas
    end
    -- O mesmo mapa com a esquerda e a direita trocadas, mas com a numeração
    -- (e portanto os decks) contada de novo da esquerda de quem olha.
    local function trocar_lados(mapa)
      local r = {}
      for l, linha in ipairs(mapa) do
        r[l] = linha:reverse():gsub("[PX]", { P = "X", X = "P" })
      end
      return r
    end
    local Mesa = nova_mesa()
    for _, caso in ipairs(CASOS) do
      local calib = calibrar_caso(Mesa, caso)
      for p = 1, 2 do
        -- Espelhado (o medido): o jogador 1 vê o mapa pedido, com os eventos
        -- à direita; o jogador 2, do outro lado, vê os eventos à esquerda.
        -- Sem espelhamento, o contrário.
        local eventos_a_direita = (p == 1) == caso.espelhado
        local esperado = eventos_a_direita and PEDIDO or trocar_lados(PEDIDO)
        local v = vista(Mesa, calib, p)
        for l, linha in ipairs(esperado) do
          T.eq(v[l], linha, caso.nome .. ": jogador " .. p .. ", linha " .. (l - 1))
        end
      end
    end
  end },

  { "decks e estruturas atrás dos espaços certos de cada jogador, nos dois espelhamentos", function(T)
    local Mesa = nova_mesa()
    for _, caso in ipairs(CASOS) do
      local calib = calibrar_caso(Mesa, caso)
      for p = 1, 2 do
        local nome = caso.nome .. ": jogador " .. p
        local function carta(n) return Mesa.espaco_criatura_abs(p, n, calib).carta end
        local fundo
        local function conferir(x, z, lin, n, o_que)
          T.eq(x, carta(n).x, nome .. ": " .. o_que .. " na coluna do espaço " .. n)
          fundo = fundo or z
          T.eq(z, fundo, nome .. ": " .. o_que .. " na fileira de trás")
          T.eq(lin, p == 1 and 15 or 4, nome .. ": " .. o_que .. " na linha de trás do layout")
          -- Atrás: mais longe do centro que a carta, do mesmo lado.
          local _, cz = Mesa.centro_abs(calib)
          T.ok((z - cz) * (carta(n).z - cz) > 0 and math.abs(z - cz) > math.abs(carta(n).z - cz), nome .. ": " .. o_que .. " atrás da carta")
        end
        local x, z, _, lin = Mesa.espaco_deck_abs(p, "principal", calib)
        conferir(x, z, lin, 1, "deck principal")
        x, z, _, lin = Mesa.espaco_estrutura_abs(p, 1, calib)
        conferir(x, z, lin, 3, "estrutura 1")
        x, z, _, lin = Mesa.espaco_estrutura_abs(p, 2, calib)
        conferir(x, z, lin, 4, "estrutura 2")
        x, z, _, lin = Mesa.espaco_deck_abs(p, "extra", calib)
        conferir(x, z, lin, 6, "deck extra")
      end
      -- O principal de um e o extra do outro dividem a coluna.
      T.eq((Mesa.espaco_deck_abs(1, "principal", calib)), (Mesa.espaco_deck_abs(2, "extra", calib)), caso.nome .. ": principal do 1 e extra do 2")
      T.eq((Mesa.espaco_deck_abs(1, "extra", calib)), (Mesa.espaco_deck_abs(2, "principal", calib)), caso.nome .. ": extra do 1 e principal do 2")
    end
  end },

  { "combate e eventos no mundo: cada quadrado do lado do seu jogador, eventos alinhados", function(T)
    local Mesa = nova_mesa()
    for _, caso in ipairs(CASOS) do
      local calib = calibrar_caso(Mesa, caso)
      local x1, z1 = Mesa.espaco_combate_abs(1, calib)
      local x2, z2 = Mesa.espaco_combate_abs(2, calib)
      T.eq(x1, x2, caso.nome .. ": um em cima do outro")
      T.eq(math.abs(z1 - z2), Mesa.TILE_SCALE, caso.nome .. ": encostados")
      for p = 1, 2 do
        local e = Mesa.espaco_criatura_abs(p, 1, calib).criatura
        local meu = p == 1 and z1 or z2
        local outro = p == 1 and z2 or z1
        T.ok(math.abs(e.z - meu) < math.abs(e.z - outro), caso.nome .. ": o quadrado do jogador " .. p .. " fica do lado dele")
        -- No meio das 6 colunas de criatura.
        local a, b = Mesa.espaco_criatura_abs(p, 3, calib).carta, Mesa.espaco_criatura_abs(p, 4, calib).carta
        T.eq(x1, (a.x + b.x) / 2, caso.nome .. ": entre os espaços 3 e 4 do jogador " .. p)
      end
      local ev = Mesa.espaco_evento_abs(calib)
      T.eq(ev.pilha.x, ev.em_vigor.x, caso.nome .. ": eventos numa coluna só")
      T.eq(ev.pilha.z, z2, caso.nome .. ": pilha na linha do combate do jogador 2")
      T.eq(ev.em_vigor.z, z1, caso.nome .. ": evento em vigor na linha do combate do jogador 1")
      T.eq(ev.centro.x, ev.pilha.x, caso.nome .. ": centro do espaço de eventos (x)")
      T.eq(ev.centro.z, (z1 + z2) / 2, caso.nome .. ": centro do espaço de eventos (z)")
      -- Do lado oposto ao portal.
      local px = portal_no_mundo(caso)
      T.ok((ev.pilha.x - x1) * (px - x1) < 0, caso.nome .. ": eventos de um lado do combate, portal do outro")
      -- 1 coluna de paralelepípedos entre a última coluna de cartas e os eventos.
      local perto = math.huge
      for p = 1, 2 do
        for n = 1, 6 do
          perto = math.min(perto, math.abs(Mesa.espaco_criatura_abs(p, n, calib).carta.x - ev.pilha.x))
        end
      end
      T.eq(perto, 2 * Mesa.TILE_SCALE, caso.nome .. ": 2 tiles da última coluna de cartas")
    end
    T.eq(Mesa.espaco_evento_abs(), nil, "sem calibração não há posição")
    T.eq(Mesa.espaco_combate_abs(1), nil, "nem do combate")
    T.eq(Mesa.espaco_deck_abs(1, "principal"), nil, "nem dos decks")
  end },

  { "achar_eventos: o lado da coluna de eventos, ou o motivo de não servir", function(T)
    local Mesa = nova_mesa()
    -- Estruturas em x 10 e 12, y 4 e 15 (o próprio layout, sem espelho).
    local r = assert(Mesa.achar_estruturas({ { x = 10, y = 4 }, { x = 12, y = 4 }, { x = 10, y = 15 }, { x = 12, y = 15 } }))
    T.eq(Mesa.EVENTOS_DX, 7, "eventos a 7 colunas do centro das estruturas")
    T.eq(Mesa.achar_eventos({ { x = 18, y = 9 }, { x = 18, y = 10 } }, r), 1, "x maior: sem espelho")
    T.eq(Mesa.achar_eventos({ { x = 4, y = 10 }, { x = 4, y = 9 } }, r), -1, "x menor: espelhado")
    T.eq(Mesa.achar_eventos({ { x = 18, y = 9 }, { x = 18, y = 10 }, { x = 18, y = 9 } }, r), 1, "tile repetido conta uma vez")
    local function recusa(tiles, nome)
      local lado, motivo = Mesa.achar_eventos(tiles, r)
      T.eq(lado, nil, nome)
      T.eq(type(motivo), "string", nome .. ": motivo")
    end
    recusa({}, "nenhum tile")
    recusa(nil, "lista ausente")
    recusa({ { x = 18, y = 9 } }, "1 tile")
    recusa({ { x = 18, y = 9 }, { x = 18, y = 10 }, { x = 18, y = 11 } }, "3 tiles")
    recusa({ { x = 18, y = 9 }, { x = 17, y = 10 } }, "colunas diferentes")
    recusa({ { x = 18, y = 8 }, { x = 18, y = 9 } }, "fora das linhas do combate")
    recusa({ { x = 18, y = 9 }, { x = 18, y = 9.5 } }, "linha que não é do combate")
    recusa({ { x = 17, y = 9 }, { x = 17, y = 10 } }, "na distância errada das estruturas")
    recusa({ { x = 11, y = 9 }, { x = 11, y = 10 } }, "no meio das estruturas")
  end },

  { "sem a coluna de eventos o espelhamento sai do portal, com aviso; se discordam, avisa", function(T)
    local Mesa = nova_mesa()
    for _, caso in ipairs(CASOS) do
      local lista, px, pz = estruturas_em_volta(Mesa, caso)
      local r = assert(Mesa.achar_estruturas(lista))
      local com = calibrar_caso(Mesa, caso)
      local sem = Mesa.calibrar({ estruturas = r, centro_mundo = centro_mundo, eventos = {}, portal = { x = px, z = pz } })
      T.eq(sem.espelhado, caso.espelhado, caso.nome .. ": espelhado pelo portal")
      T.eq(sem.espelhamento, "portal", caso.nome .. ": de onde saiu")
      T.ok(sem.aviso:find("coluna de eventos não achada"), caso.nome .. ": avisa")
      T.ok(not sem.aviso:find("longe do esperado"), caso.nome .. ": o portal está onde o layout diz")
      T.eq(sem.origem_x, com.origem_x, caso.nome .. ": mesma origem x")
      T.eq(sem.origem_z, com.origem_z, caso.nome .. ": mesma origem z")
      -- Portal do mesmo lado dos eventos: a mesa (os eventos) manda, e o log avisa.
      local ox = Mesa.centro_abs(com)
      local torto = Mesa.calibrar({ estruturas = r, centro_mundo = centro_mundo, eventos = eventos_em_volta(Mesa, caso),
        portal = { x = 2 * ox - px, z = pz } })
      T.eq(torto.espelhado, caso.espelhado, caso.nome .. ": os eventos mandam")
      T.eq(torto.espelhamento, "eventos", caso.nome .. ": de onde saiu")
      T.ok(torto.aviso:find("não bate com o da coluna de eventos"), caso.nome .. ": avisa da discordância")
    end

    -- No servidor: mundo sem os tiles de eventos (por exemplo, um mundo
    -- gerado com a mesa anterior não teria o padrão inteiro).
    local amb = instalar_tudo(ambiente_jogo({ servidor = true, sem_eventos = true }))
    carregar_mundo(amb)
    local calib = amb.Mesa.calibracao
    T.eq(calib.fonte, "estruturas", "a origem continua saindo das estruturas")
    T.eq(calib.espelhado, true, "espelhado pelo portal")
    T.ok(no_log(amb.reg, "coluna de eventos não achada"), "avisa no log")
    T.ok(no_log(amb.reg, "(portal)"), "o log diz que o espelhamento saiu do portal")
    T.ok(no_log(amb.reg, "2 dos 36 tiles de espaço não estão sobre os tiles esperados"), "a conferência acha os 2 tiles de eventos faltando")
    T.eq(#amb.Contornos.lista(), 36, "os contornos são criados mesmo assim")
  end },

  { "a calibração pelos eventos não depende do portal estar no lugar", function(T)
    -- Portal em qualquer ponto perto da mesa: a origem e o espelhamento são
    -- os mesmos; só o aviso do portal muda.
    for _, caso in ipairs(CASOS) do
      local Mesa = nova_mesa()
      local certo = calibrar_caso(Mesa, caso)
      local r = assert(Mesa.achar_estruturas((estruturas_em_volta(Mesa, caso))))
      local eventos = eventos_em_volta(Mesa, caso)
      for _, p in ipairs({ { x = 0, z = 0 }, { x = 500, z = -30 }, { x = certo.origem_x, z = certo.origem_z } }) do
        local c = Mesa.calibrar({ estruturas = r, centro_mundo = centro_mundo, eventos = eventos, portal = p })
        T.eq(c.origem_x, certo.origem_x, caso.nome .. ": origem x")
        T.eq(c.origem_z, certo.origem_z, caso.nome .. ": origem z")
        T.eq(c.espelhado, caso.espelhado, caso.nome .. ": espelhado")
        T.eq(type(c.aviso), "string", caso.nome .. ": o portal fora do lugar só gera aviso")
      end
    end
  end },

  { "câmera: a mesa inteira cabe, com a fileira de trás acima do inventário", function(T)
    local C = carregar("scripts/duelo/mod/camera.lua")
    local Mesa = nova_mesa()
    -- A vista do Aerial View: distância 80 entre 5 e 180, pitch de 40 a 60.
    T.eq(C.DISTANCIA, 80, "distância 80")
    T.eq(C.DISTANCIA_MIN, 5, "mindist")
    T.eq(C.DISTANCIA_MAX, 180, "maxdist")
    T.eq(C.PITCH_MIN, 40, "mindistpitch")
    T.eq(C.PITCH_MAX, 60, "maxdistpitch")
    T.ok(math.abs(C.pitch(80) - (40 + 20 * 75 / 175)) < 1e-9, "pitch de followcamera.lua em 80: 48,6")
    T.ok(math.abs(C.pitch(80) - 48.571) < 0.001, "48,6 graus")
    T.eq(C.pitch(5), 40, "pitch no mínimo")
    T.eq(C.pitch(180), 60, "pitch no máximo")
    T.eq(C.pitch(92.5), 50, "pitch no meio do caminho")
    T.eq(C.pitch(1), 40, "não passa do mínimo")
    T.eq(C.pitch(500), 60, "nem do máximo")
    -- A conta, à mão, para o ponto embaixo do alvo: a câmera fica a
    -- 1,5 + d sen(p) de altura e d cos(p) atrás; o alvo (1,5 acima do chão)
    -- fica no meio da tela e o chão embaixo dele um pouco abaixo.
    local p = math.rad(C.pitch(80))
    local altura, tras = 1.5 + 80 * math.sin(p), 80 * math.cos(p)
    local a = math.atan(altura / tras)
    local esperado = (1 + math.tan(p - a) / math.tan(math.rad(17.5))) / 2
    T.ok(math.abs(C.altura_na_tela(0, 0, 80, 0) - esperado) < 1e-9, "altura_na_tela bate com a fórmula do cabeçalho")
    T.ok(esperado < 0.5 and esperado > 0.45, "o chão sob o alvo fica logo abaixo do meio da tela: " .. esperado)
    -- Com a câmera mais longe a inclinação muda: a conta usa o pitch da
    -- distância pedida.
    local longe_p = math.rad(60)
    local a2 = math.atan((1.5 + 180 * math.sin(longe_p)) / (180 * math.cos(longe_p) + 10))
    T.ok(math.abs(C.altura_na_tela(10, 0, 180, 0) - (1 + math.tan(longe_p - a2) / math.tan(math.rad(17.5))) / 2) < 1e-9,
      "pitch variável: 60 graus em 180")
    -- Referência do jogo (US #30, mesa 16 x 16): estruturas a 22 unidades do
    -- centro, com a câmera de então (distância 70, pitch 54, deslocamento
    -- 8), ficaram acima da barra de inventário.
    local confirmado = C.altura_na_tela(-22, 0, 70, 8, 54)
    T.ok(math.abs(confirmado - 0.193) < 0.001, "referência confirmada no jogo: " .. confirmado)
    T.eq(C.REFERENCIA_INVENTARIO, 0.193, "guardada no módulo")

    -- Distâncias a partir do centro geométrico da mesa (o alvo, sem o
    -- deslocamento), para o lado de quem olha (negativo = embaixo da tela),
    -- tiradas do próprio layout. Vale para o jogador 1; a mesa é simétrica
    -- nas linhas, então para o 2 dá o mesmo.
    local m, centro = Mesa.MESA, Mesa.CENTRO_DA_MESA
    local meio_tile = Mesa.TILE_SCALE / 2
    T.eq(centro.col, 12, "centro da mesa na coluna 12: 1 coluna para o lado dos eventos")
    T.eq(centro.lin, Mesa.CENTRO.lin, "e na linha do centro do combate")
    local borda = (m.lin_max - centro.lin) * Mesa.TILE_SCALE + meio_tile
    local fundo = (Mesa.espaco_estrutura(1, 1).lin - centro.lin) * Mesa.TILE_SCALE
    local largura = (m.col_max - centro.col) * Mesa.TILE_SCALE + meio_tile
    T.eq(borda, 28, "meia profundidade da mesa")
    T.eq(fundo, 22, "fileira de trás")
    T.eq(largura, 30, "meia largura da mesa")
    T.eq((centro.col - m.col_min) * Mesa.TILE_SCALE + meio_tile, largura, "a mesa fica centrada no alvo")
    local perto = C.altura_na_tela(-borda)
    local longe = C.altura_na_tela(borda)
    T.ok(perto > 0, "borda de perto na tela: " .. perto)
    T.ok(longe < 0.97, "borda de longe na tela: " .. longe)
    -- A fileira de trás do próprio lado inteira (até a beira de perto do
    -- tile) acima do ponto confirmado no jogo.
    T.ok(C.altura_na_tela(-fundo - meio_tile) >= C.REFERENCIA_INVENTARIO,
      "fileira de trás do próprio lado acima do inventário: " .. C.altura_na_tela(-fundo - meio_tile))
    -- O lado de lá inteiro na tela, com folga: a fileira de trás do outro
    -- jogador até a beira de longe do tile.
    T.ok(C.altura_na_tela(fundo + meio_tile) < 0.95, "fileira de trás do outro lado: " .. C.altura_na_tela(fundo + meio_tile))
    -- Nenhuma fileira sai da tela, e a ordem é a das linhas.
    local antes = -1
    for lin = m.lin_max, m.lin_min, -1 do
      local y, lado = C.altura_na_tela((centro.lin - lin) * Mesa.TILE_SCALE, largura)
      T.ok(y > antes, "linha " .. lin .. " acima da anterior")
      T.ok(y > 0 and y < 1, "linha " .. lin .. " na tela")
      T.ok(lado < 0.8, "linha " .. lin .. ": os cantos da mesa cabem na largura (16:9), com folga")
      antes = y
    end
    -- Todos os tiles de espaço cabem na tela, em 16:9 e em 4:3 (a coluna de
    -- eventos é a mais aberta), para os dois jogadores.
    for _, t in ipairs({ Mesa.espaco_evento().pilha, Mesa.espaco_evento().em_vigor,
      Mesa.espaco_deck(1, "principal"), Mesa.espaco_deck(1, "extra"),
      Mesa.espaco_deck(2, "principal"), Mesa.espaco_deck(2, "extra") }) do
      for _, sinal in ipairs({ 1, -1 }) do
        local s = sinal * (centro.lin - t.lin) * Mesa.TILE_SCALE
        local x = math.abs(t.col - centro.col) * Mesa.TILE_SCALE + meio_tile
        local y, lado = C.altura_na_tela(s - meio_tile, x)
        T.ok(y >= C.REFERENCIA_INVENTARIO and y < 0.95, "tile " .. t.col .. "," .. t.lin .. " na altura da tela: " .. y)
        T.ok(lado * (16 / 9) / (4 / 3) < 1, "tile " .. t.col .. "," .. t.lin .. " na largura, até em 4:3")
      end
    end
    -- O portal e o pátio inteiro, do lado oposto aos eventos, continuam na
    -- tela em 16:9.
    local px = math.abs(Mesa.PORTAL.x + (Mesa.LARGURA - 1) / 2 - centro.col) * Mesa.TILE_SCALE
    local _, lado_portal = C.altura_na_tela(0, px)
    T.ok(lado_portal < 1, "portal dentro da largura: " .. lado_portal)
    local beira = (centro.col - Mesa.PATIO.col_min) * Mesa.TILE_SCALE + meio_tile
    for lin = Mesa.PATIO.lin_min, Mesa.PATIO.lin_max do
      local _, lado = C.altura_na_tela((centro.lin - lin) * Mesa.TILE_SCALE - meio_tile, beira)
      T.ok(lado < 1, "pátio do portal dentro da largura (linha " .. lin .. "): " .. lado)
    end
    -- Sem o deslocamento, a fileira de trás desceria para baixo da referência.
    T.ok(C.altura_na_tela(-fundo - meio_tile, 0, C.DISTANCIA, 0) < C.REFERENCIA_INVENTARIO, "o deslocamento é necessário")
    -- O zoom vai de 30 a 180: no mais longe a mesa inteira continua na tela.
    T.ok(C.altura_na_tela(-borda, 0, C.DISTANCIA_MAX) > C.REFERENCIA_INVENTARIO, "em 180 a borda de perto fica acima do inventário")
    T.ok(C.altura_na_tela(borda, 0, C.DISTANCIA_MAX) < 0.9, "e a de longe dentro da tela")
  end },
}
