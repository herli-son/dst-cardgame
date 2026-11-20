-- Testes da mesa no jogo: tiles, números e câmera (US #30) com o layout
-- aprovado (bug #147).
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

-- Grade do mapa falso: [tx][ty] = uso do layout ("carta", "cascalho"...).
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

-- Coleta os tiles de estrutura em volta do portal, como calibracao.lua faz.
local function estruturas_em_volta(Mesa, caso)
  local grade = mapa_falso(Mesa, caso)
  local px, pz = portal_no_mundo(caso)
  local ptx, pty = tile_no_ponto(px, pz)
  local lista = {}
  for tx = ptx - 20, ptx + 20 do
    for ty = pty - 20, pty + 20 do
      if uso_no_mapa(grade, tx, ty) == "estrutura" then
        lista[#lista + 1] = { x = tx, y = ty }
      end
    end
  end
  return lista, px, pz, ptx, pty
end

local function calibrar_caso(Mesa, caso)
  local lista, px, pz = estruturas_em_volta(Mesa, caso)
  local ret = assert(Mesa.achar_estruturas(lista))
  return Mesa.calibrar({ estruturas = ret, centro_mundo = centro_mundo, portal = { x = px, z = pz } }), ret
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
local WORLD_TILES = { IMPASSABLE = 1, ROCKY = 3, CARPET = 11, CHECKER = 12, MOSAIC_GREY = 47, MOSAIC_BLUE = 49 }

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
-- SetDefault refaz distâncias, Snap copia o alvo, os setters guardam.
local function camera_falsa()
  local c = { snaps = 0 }
  function c:SetDefault()
    self.distancetarget, self.mindist, self.maxdist, self.controllable = 30, 15, 50, true
    self.headingtarget = self.headingtarget or 45
  end
  function c:SetTarget(inst) self.target = inst end
  function c:SetMinDistance(d) self.mindist = d end
  function c:SetMaxDistance(d) self.maxdist = d end
  function c:SetDistance(d) self.distancetarget = d end
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
--   opcoes.sem_estruturas, opcoes.sem_portal, opcoes.tamanho (Map:GetSize).
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
      if opcoes.sem_estruturas and uso == "estrutura" then uso = "cascalho" end
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
  Contornos.instalar({ GLOBAL = G, Mesa = ctx.Mesa, Calibracao = Calibracao, Marcadores = Marcadores })
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
      if caso.espelhado then
        T.ok(r.x_max < ptx, caso.nome .. ": estruturas com x menor que o portal")
      else
        T.ok(r.x_min > ptx, caso.nome .. ": estruturas com x maior que o portal")
      end
      T.ok(px ~= nil, "portal")
    end
  end },

  { "calibração com e sem espelho: origem no centro da zona de combate", function(T)
    local Mesa = nova_mesa()
    for _, caso in ipairs(CASOS) do
      local calib = calibrar_caso(Mesa, caso)
      T.eq(calib.espelhado, caso.espelhado, caso.nome .. ": espelhado")
      T.eq(calib.fonte, "estruturas", caso.nome .. ": fonte")
      T.eq(calib.aviso, nil, caso.nome .. ": sem aviso: o portal está onde o layout diz")
      local px, pz = portal_no_mundo(caso)
      local col, lin = Mesa.tile_do_layout(px, pz, calib)
      local folga = caso.meio > 0 and 1 or 0
      T.ok(math.abs(col - 2) <= folga, caso.nome .. ": portal na coluna 2")
      T.ok(math.abs(lin - 10) <= folga, caso.nome .. ": portal na linha 10")
      -- A origem é o centro do tile (10, 10) do layout.
      local ox, oz = Mesa.centro_abs(calib)
      local cx, cz = centro_mundo(tile_do_mapa(10, 10, caso))
      T.eq(ox, cx, caso.nome .. ": origem x")
      T.eq(oz, cz, caso.nome .. ": origem z")
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
    r = Mesa.achar_estruturas(cantos(6, 8))
    T.ok(r, "o padrão 6 x 8")
    T.eq(r.x_max - r.x_min, 6, "6 colunas entre as estruturas")
    T.eq(r.y_max - r.y_min, 8, "8 linhas entre as estruturas")
    local repetidos = cantos(6, 8)
    repetidos[#repetidos + 1] = { x = 6, y = 8 }
    T.ok(Mesa.achar_estruturas(repetidos), "tile repetido conta uma vez")
    r, motivo = Mesa.achar_estruturas(cantos(8, 6))
    T.eq(r, nil, "girado")
    T.ok(motivo:find("giradas"), "motivo diz girado")
    local tres = cantos(6, 8)
    table.remove(tres)
    T.eq(Mesa.achar_estruturas(tres), nil, "3 tiles")
    local cinco = cantos(6, 8)
    cinco[#cinco + 1] = { x = 3, y = 3 }
    T.eq(Mesa.achar_estruturas(cinco), nil, "5 tiles")
    T.eq(Mesa.achar_estruturas(cantos(7, 8)), nil, "7 x 8")
    T.eq(Mesa.achar_estruturas({ { x = 0, y = 0 }, { x = 6, y = 0 }, { x = 1, y = 8 }, { x = 6, y = 8 } }), nil,
      "não é retângulo")
  end },

  { "calibrar avisa quando o portal não está onde o layout diz", function(T)
    local Mesa = nova_mesa()
    local r = assert(Mesa.achar_estruturas((estruturas_em_volta(Mesa, MEDIDO))))
    local calib = Mesa.calibrar({ estruturas = r, centro_mundo = centro_mundo, portal = { x = 0, z = 0 } })
    T.eq(type(calib.aviso), "string", "aviso")
    calib = Mesa.calibrar({ estruturas = r, centro_mundo = centro_mundo })
    T.eq(type(calib.aviso), "string", "aviso sem portal")
    T.eq(calib.espelhado, false, "sem portal não dá para saber")
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

  { "16 espaços absolutos sem sobreposição e sobre os tiles certos da mesa", function(T)
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
          local tx, ty = tile_no_ponto(e.combate.x, e.combate.z)
          T.eq(uso_no_mapa(grade, tx, ty), "combate", "combate à frente de " .. p .. "/" .. n)
        end
        for n = 1, 2 do
          local x, z = Mesa.espaco_estrutura_abs(p, n, calib)
          conferir(x, z, "estrutura", "estrutura " .. p .. "/" .. n)
        end
        T.eq(Mesa.espaco_criatura_abs(p, 7, calib), nil, "não há espaço 7")
        T.eq(Mesa.espaco_estrutura_abs(p, 3, calib), nil, "não há estrutura 3")
      end
      T.eq(total, 28, "12 cartas, 12 criaturas e 4 estruturas")
      local ox, oz = Mesa.centro_abs(calib)
      T.eq(uso_no_mapa(grade, tile_no_ponto(ox, oz)), "combate", "centro da mesa na zona de combate")
      -- Cada jogador só tem espaços do seu lado da mesa.
      for n = 1, 6 do
        local e1, e2 = Mesa.espaco_criatura_abs(1, n, calib), Mesa.espaco_criatura_abs(2, n, calib)
        T.eq(e1.carta.lin, 12, "cartas do jogador 1 na linha 12")
        T.eq(e1.criatura.lin, 11, "criaturas do jogador 1 na linha 11")
        T.eq(e2.carta.lin, 8, "cartas do jogador 2 na linha 8")
        T.eq(e2.criatura.lin, 9, "criaturas do jogador 2 na linha 9")
      end
      local tiles = Mesa.tiles_dos_espacos(calib)
      T.eq(#tiles, 28, "tiles_dos_espacos: 28 tiles")
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
      -- O espaço n de um fica de frente para o 7 - n do outro, e os dois
      -- atacam pelo mesmo tile da zona de combate.
      for n = 1, 6 do
        local a, b = Mesa.espaco_criatura_abs(1, n, calib), Mesa.espaco_criatura_abs(2, 7 - n, calib)
        T.eq(a.carta.x, b.carta.x, rotulo .. ": " .. n .. " de frente para " .. (7 - n))
        T.eq(a.combate.x, b.combate.x, rotulo .. ": mesmo tile de combate (x)")
        T.eq(a.combate.z, b.combate.z, rotulo .. ": mesmo tile de combate (z)")
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
      T.ok(not no_log(amb.reg, "não estão sobre"), caso.nome .. ": os 16 espaços conferem com o mapa")
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
    T.ok(no_log(amb.reg, "4 dos 16 espaços não estão sobre os tiles esperados"), "a conferência acha as 4 estruturas faltando")
    T.eq(netvar(amb.reg, "duelo.mesa_fonte"):value(), 2, "netvar fonte = portal")
    T.eq(#amb.Marcadores.lista(), 17, "marcadores criados mesmo assim")

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

  { "servidor cria 17 marcadores com os números certos nas posições da mesa", function(T)
    local amb = instalar_tudo(ambiente_jogo({ servidor = true }))
    carregar_mundo(amb)
    local lista = amb.Marcadores.lista()
    T.eq(#lista, 17, "17 marcadores")
    local marcadores = 0
    for _, nome in ipairs(amb.reg.spawns) do
      if nome == "duelo_marcador" then marcadores = marcadores + 1 end
    end
    T.eq(marcadores, 17, "17 SpawnPrefab do marcador")
    local calib, Mesa = amb.Mesa.calibracao, amb.Mesa
    local vistos, por_tipo = {}, { 0, 0, 0 }
    for _, m in ipairs(lista) do
      T.eq(m.persists, false, "não persiste")
      local tipo, jog, num = m.duelo_tipo:value(), m.duelo_jogador:value(), m.duelo_numero:value()
      por_tipo[tipo] = por_tipo[tipo] + 1
      local chave = tipo .. "/" .. jog .. "/" .. num
      T.ok(not vistos[chave], "marcador repetido " .. chave)
      vistos[chave] = true
      local x, _, z = m.Transform:GetWorldPosition()
      local ex, ez
      if tipo == 1 then
        local carta = Mesa.espaco_criatura_abs(jog, num, calib).carta
        ex, ez = carta.x, carta.z
      elseif tipo == 2 then ex, ez = Mesa.espaco_estrutura_abs(jog, num, calib)
      else ex, ez = Mesa.centro_abs(calib) end
      T.eq(x, ex, chave .. " x")
      T.eq(z, ez, chave .. " z")
      -- Host (servidor com tela): o dirty do set já montou o rótulo.
      T.eq(m.Label.texto, amb.Marcadores.texto(tipo, jog, num), chave .. " texto no host")
      T.eq(m.Label.ativo, true, chave .. " visível")
    end
    T.eq(por_tipo[1], 12, "12 criaturas")
    T.eq(por_tipo[2], 4, "4 estruturas")
    T.eq(por_tipo[3], 1, "1 centro")
    for p = 1, 2 do
      for n = 1, 6 do T.ok(vistos["1/" .. p .. "/" .. n], "criatura " .. p .. "/" .. n) end
      for n = 1, 2 do T.ok(vistos["2/" .. p .. "/" .. n], "estrutura " .. p .. "/" .. n) end
    end
    T.ok(vistos["3/0/0"], "centro")
    -- Recalibrar (console) troca os marcadores, sem duplicar.
    amb.Calibracao.calibrar()
    T.eq(amb.reg.removidos, 17 + 28, "os 17 marcadores antigos (e os 28 contornos do host) removidos")
    T.eq(#amb.Marcadores.lista(), 17, "17 de novo")
  end },
  { "textos e cores dos marcadores", function(T)
    local M = carregar("scripts/duelo/mod/marcadores.lua")
    T.eq(M.texto(1, 1, 3), "J1 3", "criatura")
    T.eq(M.texto(1, 2, 6), "J2 6", "criatura do 2")
    T.eq(M.texto(2, 1, 1), "J1 E1", "estrutura")
    T.eq(M.texto(2, 2, 2), "J2 E2", "estrutura do 2")
    T.eq(M.texto(3, 0, 0), "Combate", "centro")
    T.eq(M.texto(0, 0, 0), nil, "ainda não definido")
    T.eq(M.texto(1, 0, 3), nil, "sem jogador")
    T.eq(M.texto(1, 1, 0), nil, "sem número")
    local r1, g1, b1 = M.cor(1, 1)
    local r2, g2, b2 = M.cor(1, 2)
    T.ok(r1 ~= r2 or g1 ~= g2 or b1 ~= b2, "cores diferentes por jogador")
    T.ok(b1 > r1, "jogador 1 azulado")
    T.ok(r2 > b2, "jogador 2 avermelhado")
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
    local cx, cz = amb.Mesa.centro_abs()
    T.ok(math.abs(ax - cx) < 1e-9, "alvo no x do centro (heading 90 só desloca em z)")
    T.ok(math.abs(az - (cz + amb.Camera.DESLOCAMENTO)) < 1e-9, "alvo deslocado para o lado do jogador 1 (z maior)")
    T.eq(cam.distancetarget, amb.Camera.DISTANCIA, "distância da mesa")
    T.eq(cam.mindist, amb.Camera.DISTANCIA_MIN, "zoom mínimo")
    T.eq(cam.maxdist, amb.Camera.DISTANCIA_MAX, "zoom máximo")
    T.ok(cam.snaps >= 1, "Snap")
    T.eq(cam:CanControl(), true, "zoom continua liberado")

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
    T.eq(cam.maxdist, amb.Camera.DISTANCIA_MAX, "e o zoom máximo")
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

  { "rótulos: número no tile da carta, estruturas E1/E2 e Combate no centro", function(T)
    for _, caso in ipairs(CASOS) do
      local amb = instalar_tudo(ambiente_jogo({ servidor = true, caso = caso }))
      carregar_mundo(amb)
      local por_texto = {}
      for _, m in ipairs(amb.Marcadores.lista()) do
        local x, _, z = m.Transform:GetWorldPosition()
        local uso = uso_no_mapa(amb.grade, tile_no_ponto(x, z))
        por_texto[m.Label.texto] = uso
        local tipo = m.duelo_tipo:value()
        if tipo == 1 then T.eq(uso, "carta", caso.nome .. ": " .. m.Label.texto .. " no tile da carta") end
        if tipo == 2 then T.eq(uso, "estrutura", caso.nome .. ": " .. m.Label.texto .. " no tile da estrutura") end
        if tipo == 3 then T.eq(uso, "combate", caso.nome .. ": Combate na zona de combate") end
      end
      for _, t in ipairs({ "J1 E1", "J1 E2", "J2 E1", "J2 E2" }) do
        T.eq(por_texto[t], "estrutura", caso.nome .. ": " .. t)
      end
      T.eq(por_texto["Combate"], "combate", caso.nome .. ": Combate")
      local x, _, z = amb.Marcadores.lista()[17].Transform:GetWorldPosition()
      T.eq((amb.Mesa.tile_do_layout(x, z)), amb.Mesa.CENTRO_COMBATE.col, "Combate na coluna do centro")
    end
  end },

  { "contornos: um gridplacer por tile de espaço, na cor do dono", function(T)
    for _, caso in ipairs(CASOS) do
      local amb = instalar_tudo(ambiente_jogo({ servidor = true, caso = caso }))
      carregar_mundo(amb)
      local lista = amb.Contornos.lista()
      T.eq(#lista, 28, caso.nome .. ": 28 contornos no host")
      T.eq(#amb.reg.gridplacers, 28, "28 SpawnPrefab(\"tile_outline\")")
      T.eq(amb.Contornos.PREFAB, "tile_outline", "não o gridplacer: o componente placer dele quebra outros mods")
      for _, e in ipairs(amb.reg.gridplacers) do T.eq(e.components, nil, "contorno sem componentes") end
      local vistos, por_tipo = {}, { carta = 0, criatura = 0, estrutura = 0 }
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
        else
          e = amb.Mesa.espaco_criatura_abs(c.jogador, c.n)[c.tipo]
        end
        T.eq(x, e.x, "espaço " .. c.jogador .. "/" .. c.tipo .. "/" .. c.n .. " (x)")
        T.eq(z, e.z, "espaço " .. c.jogador .. "/" .. c.tipo .. "/" .. c.n .. " (z)")
        -- Cor do dono, a mesma dos rótulos.
        local r, gg, b = amb.Marcadores.cor(amb.Marcadores.TIPO.criatura, c.jogador)
        T.eq(g.AnimState.mult[1], r, "cor r")
        T.eq(g.AnimState.mult[2], gg, "cor g")
        T.eq(g.AnimState.mult[3], b, "cor b")
        T.eq(g.AnimState.mult[4], 1, "opaco")
        if c.jogador == 1 then T.ok(b > r, "jogador 1 azul") else T.ok(r > b, "jogador 2 vermelho") end
        T.eq(g.AnimState.add[1], 0, "sem destaque")
        -- Sem colisão, sem clique e sem rede (o gridplacer do jogo).
        T.ok(g:HasTag("NOCLICK"), "NOCLICK")
        T.eq(g.Physics, nil, "sem física")
        T.eq(g.rede, nil, "sem rede")
        T.eq(g.persists, false, "não persiste")
      end
      T.eq(por_tipo.carta, 12, "12 cartas")
      T.eq(por_tipo.criatura, 12, "12 criaturas")
      T.eq(por_tipo.estrutura, 4, "4 estruturas")
    end
  end },

  { "contornos: recriados sem duplicar, só com tela, e cada cliente cria os seus", function(T)
    local amb = instalar_tudo(ambiente_jogo({ servidor = true }))
    carregar_mundo(amb)
    local antigos = amb.Contornos.lista()
    amb.Calibracao.calibrar()
    T.eq(#amb.Contornos.lista(), 28, "28 de novo")
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
    T.eq(#cli.Contornos.lista(), 28, "28 contornos no cliente")
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
    T.eq(#sem.Marcadores.lista(), 17, "os rótulos continuam")
  end },

  { "contornos: destacar um espaço muda só os tiles dele", function(T)
    local amb = instalar_tudo(ambiente_jogo({ servidor = true }))
    carregar_mundo(amb)
    local C = amb.Contornos
    T.eq(C.destacar(1, "criatura", 3, true), 2, "espaço de criatura: carta e criatura")
    for _, c in ipairs(C.lista()) do
      local alvo = c.jogador == 1 and c.n == 3 and (c.tipo == "carta" or c.tipo == "criatura")
      T.eq(c.inst.AnimState.add[1], alvo and C.DESTAQUE[1] or 0, "destaque só no espaço 1/3")
    end
    T.eq(C.destacar(2, "estrutura", 1, true), 1, "estrutura: 1 tile")
    T.eq(C.destacar(1, "criatura", 3, false), 2, "apaga o destaque")
    for _, c in ipairs(C.lista()) do
      local alvo = c.jogador == 2 and c.n == 1 and c.tipo == "estrutura"
      T.eq(c.inst.AnimState.add[1], alvo and C.DESTAQUE[1] or 0, "só a estrutura 2/1 destacada")
    end
    T.eq(C.destacar(1, "criatura", 7, true), 0, "espaço que não existe")
  end },

  { "câmera: as 11 linhas da mesa cabem, com as estruturas acima do inventário", function(T)
    local C = carregar("scripts/duelo/mod/camera.lua")
    local Mesa = nova_mesa()
    T.eq(C.pitch(C.DISTANCIA), 51, "pitch de followcamera.lua em 65 (mínimo 30, máximo 80)")
    T.eq(C.pitch(C.DISTANCIA_MIN), 30, "pitch no zoom mínimo")
    T.eq(C.pitch(C.DISTANCIA_MAX), 60, "pitch no zoom máximo")
    -- Distâncias a partir do centro da zona de combate, para o lado de quem
    -- olha (negativo = embaixo da tela), tiradas do próprio layout.
    local m, centro = Mesa.MESA, Mesa.CENTRO_COMBATE
    local meio_tile = Mesa.TILE_SCALE / 2
    local borda = (m.lin_max - centro.lin) * Mesa.TILE_SCALE + meio_tile -- 22
    local estrutura = (Mesa.espaco_estrutura(1, 1).lin - centro.lin) * Mesa.TILE_SCALE -- 16
    local largura = (m.col_max - centro.col) * Mesa.TILE_SCALE + meio_tile -- 26
    local perto = C.altura_na_tela(-borda)
    local longe = C.altura_na_tela(borda)
    local propria = C.altura_na_tela(-estrutura)
    T.ok(perto > 0, "borda de perto na tela: " .. perto)
    T.ok(longe < 0.95, "borda de longe na tela, com folga: " .. longe)
    -- Referência do jogo (US #30, mesa 16 x 16): estruturas a 22 unidades do
    -- centro com DISTANCIA 70 e DESLOCAMENTO 8 ficaram acima da barra de
    -- inventário.
    local confirmado = C.altura_na_tela(-22, 0, 70, 8)
    T.ok(math.abs(confirmado - 0.193) < 0.001, "referência confirmada no jogo: " .. confirmado)
    T.ok(propria >= confirmado, "estruturas do próprio lado acima do confirmado: " .. propria)
    T.ok(C.altura_na_tela(-estrutura - meio_tile) > 0.15, "e o tile inteiro delas")
    -- Nenhuma fileira sai da tela, e a ordem é a das linhas.
    local antes = -1
    for lin = m.lin_max, m.lin_min, -1 do
      local y, lado = C.altura_na_tela((centro.lin - lin) * Mesa.TILE_SCALE, largura)
      T.ok(y > antes, "linha " .. lin .. " acima da anterior")
      T.ok(y > 0 and y < 1, "linha " .. lin .. " na tela")
      T.ok(lado < 1, "linha " .. lin .. ": os cantos da mesa cabem na largura (16:9)")
      antes = y
    end
    -- Sem o deslocamento, as estruturas desceriam para baixo da referência.
    T.ok(C.altura_na_tela(-estrutura, 0, C.DISTANCIA, 0) < confirmado, "o deslocamento é necessário")
  end },
}
