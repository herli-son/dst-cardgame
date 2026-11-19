-- Testes da US #30: mesa de tiles, números e câmera.
--
-- O jogo não roda aqui. A calibração é Lua puro (scripts/duelo/mod/mesa.lua)
-- e é testada com os números medidos no jogo (issue #30): portal no tile
-- (35, 29) e um ponto do carpete central no tile (29, 28), com o eixo x
-- espelhado pelo gerador (x_tile = 38 - col). O eixo z não foi espelhado
-- (flip_y = 1), mas o deslocamento exato das linhas não foi medido: o portal
-- fica na junção das linhas 9|10, e o tile 29 pode ser a linha 9 ou a 10.
-- Por isso cada caso roda com os dois deslocamentos (lin + 19 e lin + 20),
-- e os dois contêm o tile (29, 28) no carpete.
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

local DESLOCAMENTOS = { 19, 20 }

-- Mundo medido: tile do mapa de cada (col, lin) do layout.
local function tile_do_mapa(col, lin, desl)
  return 38 - col, lin + desl
end

local function centro_mundo(tx, ty)
  return tx * 4 + 2, ty * 4 + 2
end

local function tile_no_ponto(x, z)
  return math.floor(x / 4), math.floor(z / 4)
end

-- Grade do mapa falso: [tx][ty] = uso do layout ("criatura", "carpete"...).
local function mapa_falso(Mesa, desl)
  local grade = {}
  for col = 0, Mesa.LARGURA - 1 do
    for lin = 0, Mesa.ALTURA - 1 do
      local tx, ty = tile_do_mapa(col, lin, desl)
      grade[tx] = grade[tx] or {}
      grade[tx][ty] = Mesa.uso_em(col, lin)
    end
  end
  return grade
end

-- Posição do portal no mundo: centro da coluna 3, junção das linhas 9|10.
local function portal_no_mundo(desl)
  local tx, ty = tile_do_mapa(3, 9, desl)
  local x = centro_mundo(tx, ty)
  local z = ty * 4 + 4 -- borda sul da linha 9 = norte da linha 10
  return x, z
end

-- Coleta os tiles de carpete em volta do portal, como calibracao.lua faz.
local function carpete_em_volta(Mesa, desl)
  local grade = mapa_falso(Mesa, desl)
  local px, pz = portal_no_mundo(desl)
  local ptx, pty = tile_no_ponto(px, pz)
  local lista = {}
  for tx = ptx - 20, ptx + 20 do
    for ty = pty - 20, pty + 20 do
      if grade[tx] and grade[tx][ty] == "centro" then
        lista[#lista + 1] = { x = tx, y = ty }
      end
    end
  end
  return lista, px, pz, ptx, pty
end

local function calibrar_medido(Mesa, desl)
  local lista, px, pz = carpete_em_volta(Mesa, desl)
  local ret = assert(Mesa.achar_carpete(lista))
  return Mesa.calibrar({ carpete = ret, centro_mundo = centro_mundo, portal = { x = px, z = pz } }), ret
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

local WORLD_TILES = { IMPASSABLE = 1, CARPET = 11, CHECKER = 12, MOSAIC_GREY = 47, MOSAIC_BLUE = 49 }
local TILE_POR_USO = {
  fora = WORLD_TILES.IMPASSABLE, chao = WORLD_TILES.CHECKER, centro = WORLD_TILES.CARPET,
  criatura = WORLD_TILES.MOSAIC_GREY, estrutura = WORLD_TILES.MOSAIC_BLUE,
}

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
--   opcoes.servidor, opcoes.dedicado, opcoes.desl (deslocamento das linhas),
--   opcoes.sem_carpete, opcoes.sem_portal.
local function ambiente_jogo(opcoes)
  local reg = { netvars = {}, log = {}, spawns = {}, sim_postinits = {}, prefab_postinits = {},
    player_postinits = {}, component_postinits = {} }
  local Mesa = nova_mesa()
  local desl = opcoes.desl or 20
  local grade = mapa_falso(Mesa, desl)
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
      local uso = grade[tx] and grade[tx][ty] or "fora"
      if opcoes.sem_carpete and uso == "centro" then uso = "chao" end
      return TILE_POR_USO[uso]
    end,
  }
  G.TheWorld.Map.GetTileAtPoint = function(m, x, _, z) return m:GetTile(tile_no_ponto(x, z)) end
  local portal = entidade(reg, "multiplayer_portal")
  portal.entity.AddTransform()
  local ppx, ppz = portal_no_mundo(desl)
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
  amb.Calibracao, amb.Marcadores, amb.Camera = Calibracao, Marcadores, Camera
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

return {
  { "o modelo reproduz o que foi medido: portal (35, 29), carpete com (29, 28)", function(T)
    local Mesa = nova_mesa()
    for _, desl in ipairs(DESLOCAMENTOS) do
      local _, px, pz, ptx, pty = carpete_em_volta(Mesa, desl)
      T.eq(ptx, 35, "portal x")
      T.ok(pty == 29 or pty == 30, "portal y na junção das linhas 9|10")
      local grade = mapa_falso(Mesa, desl)
      T.eq(grade[29][28], "centro", "tile (29, 28) é carpete")
      local _, r = calibrar_medido(Mesa, desl)
      T.ok(r.x_min <= 29 and 29 <= r.x_max and r.y_min <= 28 and 28 <= r.y_max, "retângulo contém (29, 28)")
      T.ok(r.x_max < 35, "carpete com x menor que o portal")
    end
  end },

  { "calibração com os números medidos dá espelhado = true e o portal na coluna 3", function(T)
    local Mesa = nova_mesa()
    for _, desl in ipairs(DESLOCAMENTOS) do
      local calib = calibrar_medido(Mesa, desl)
      T.eq(calib.espelhado, true, "espelhado")
      T.eq(calib.fonte, "carpete", "fonte")
      T.eq(calib.aviso, nil, "sem aviso: o portal está onde o layout diz")
      local px, pz = portal_no_mundo(desl)
      local col, lin = Mesa.tile_do_layout(px, pz, calib)
      T.eq(col, 3, "portal na coluna 3")
      T.ok(lin == 9 or lin == 10, "portal na junção 9|10")
      -- A origem é a junção das colunas e linhas 9|10 do layout.
      local ox, oz = Mesa.centro_abs(calib)
      T.eq(ox, 4 * 29, "origem x entre os tiles 29 e 28 (colunas 9 e 10)")
      T.eq(oz, pz, "origem z na linha do portal")
      -- O centro de cada tile do layout volta para o mesmo tile do mapa.
      for col2 = 0, Mesa.LARGURA - 1 do
        for lin2 = 0, Mesa.ALTURA - 1 do
          local x, z = Mesa.posicao_abs(col2, lin2, calib)
          local tx, ty = tile_no_ponto(x, z)
          local ex, ey = tile_do_mapa(col2, lin2, desl)
          T.eq(tx, ex, "tile x de " .. col2 .. "," .. lin2)
          T.eq(ty, ey, "tile y de " .. col2 .. "," .. lin2)
          local c3, l3 = Mesa.tile_do_layout(x, z, calib)
          T.eq(c3, col2, "ida e volta col")
          T.eq(l3, lin2, "ida e volta lin")
        end
      end
    end
  end },

  { "sem espelhamento o portal fica a oeste e espelhado = false", function(T)
    local Mesa = nova_mesa()
    local lista = {}
    for col = 6, 13 do
      for lin = 8, 11 do lista[#lista + 1] = { x = 100 + col, y = 50 + lin } end
    end
    local r = assert(Mesa.achar_carpete(lista))
    local px = (100 + 3) * 4 + 2
    local pz = (50 + 10) * 4
    local calib = Mesa.calibrar({ carpete = r, centro_mundo = centro_mundo, portal = { x = px, z = pz } })
    T.eq(calib.espelhado, false, "não espelhado")
    T.eq(calib.aviso, nil, "sem aviso")
    T.eq((Mesa.tile_do_layout(px, pz, calib)), 3, "portal na coluna 3")
  end },

  { "achar_carpete recusa carpete incompleto, girado ou vazio", function(T)
    local Mesa = nova_mesa()
    local r, motivo = Mesa.achar_carpete({})
    T.eq(r, nil, "vazio")
    T.eq(type(motivo), "string", "motivo")
    local girado = {}
    for x = 0, 3 do for y = 0, 7 do girado[#girado + 1] = { x = x, y = y } end end
    r, motivo = Mesa.achar_carpete(girado)
    T.eq(r, nil, "girado")
    T.ok(motivo:find("girado"), "motivo diz girado")
    local buraco = {}
    for x = 0, 7 do for y = 0, 3 do
      if not (x == 2 and y == 1) then buraco[#buraco + 1] = { x = x, y = y } end
    end end
    r = Mesa.achar_carpete(buraco)
    T.eq(r, nil, "com buraco")
    local grande = {}
    for x = 0, 8 do for y = 0, 3 do grande[#grande + 1] = { x = x, y = y } end end
    r = Mesa.achar_carpete(grande)
    T.eq(r, nil, "9 x 4")
  end },

  { "calibrar avisa quando o portal não está onde o layout diz", function(T)
    local Mesa = nova_mesa()
    local lista = carpete_em_volta(Mesa, 20)
    local r = assert(Mesa.achar_carpete(lista))
    local calib = Mesa.calibrar({ carpete = r, centro_mundo = centro_mundo, portal = { x = 0, z = 0 } })
    T.eq(type(calib.aviso), "string", "aviso")
    calib = Mesa.calibrar({ carpete = r, centro_mundo = centro_mundo })
    T.eq(type(calib.aviso), "string", "aviso sem portal")
    T.eq(calib.espelhado, false, "sem portal não dá para saber")
  end },

  { "reserva pelo portal dá a mesma origem que o carpete no caso medido", function(T)
    local Mesa = nova_mesa()
    for _, desl in ipairs(DESLOCAMENTOS) do
      local calib = calibrar_medido(Mesa, desl)
      local px, pz = portal_no_mundo(desl)
      local reserva = Mesa.calibrar_pelo_portal(px, pz)
      T.eq(reserva.fonte, "portal", "fonte")
      T.eq(reserva.espelhado, true, "espelhado por padrão (medido)")
      T.eq(type(reserva.aviso), "string", "avisa")
      T.eq(reserva.origem_x, calib.origem_x, "origem x")
      T.eq(reserva.origem_z, calib.origem_z, "origem z")
    end
  end },

  { "16 espaços absolutos sem sobreposição e sobre os tiles certos da mesa", function(T)
    local Mesa = nova_mesa()
    for _, desl in ipairs(DESLOCAMENTOS) do
      local calib = calibrar_medido(Mesa, desl)
      local grade = mapa_falso(Mesa, desl)
      local vistos, total = {}, 0
      local function conferir(x, z, uso, nome)
        T.ok(x ~= nil, nome .. " existe")
        local tx, ty = tile_no_ponto(x, z)
        local cx, cz = centro_mundo(tx, ty)
        T.eq(x, cx, nome .. " no centro do tile (x)")
        T.eq(z, cz, nome .. " no centro do tile (z)")
        T.eq(grade[tx][ty], uso, nome .. " sobre tile de " .. uso)
        local chave = tx .. "," .. ty
        T.ok(not vistos[chave], nome .. " sobrepõe " .. tostring(vistos[chave]))
        vistos[chave] = nome
        total = total + 1
      end
      for p = 1, 2 do
        for n = 1, 6 do
          local x, z = Mesa.espaco_criatura_abs(p, n, calib)
          conferir(x, z, "criatura", "criatura " .. p .. "/" .. n)
        end
        for n = 1, 2 do
          local x, z = Mesa.espaco_estrutura_abs(p, n, calib)
          conferir(x, z, "estrutura", "estrutura " .. p .. "/" .. n)
        end
        T.eq(Mesa.espaco_criatura_abs(p, 7, calib), nil, "não há espaço 7")
        T.eq(Mesa.espaco_estrutura_abs(p, 3, calib), nil, "não há estrutura 3")
      end
      T.eq(total, 16, "16 espaços")
      local ox, oz = Mesa.centro_abs(calib)
      local tx, ty = tile_no_ponto(ox - 1, oz - 1)
      T.eq(grade[tx][ty], "centro", "centro da mesa sobre o carpete")
      -- Cada jogador só tem espaços do seu lado da mesa.
      for n = 1, 6 do
        local _, _, _, lin1 = Mesa.espaco_criatura_abs(1, n, calib)
        local _, _, _, lin2 = Mesa.espaco_criatura_abs(2, n, calib)
        T.eq(lin1, 13, "jogador 1 na linha 13")
        T.eq(lin2, 6, "jogador 2 na linha 6")
      end
    end
  end },

  { "heading: o lado de cada jogador fica embaixo da tela dele", function(T)
    local Mesa = nova_mesa()
    for _, desl in ipairs(DESLOCAMENTOS) do
      local calib = calibrar_medido(Mesa, desl)
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
          local x, z = Mesa.espaco_criatura_abs(p, n, calib)
          T.ok((x - ox) * dx + (z - oz) * dz > 0, "espaço " .. p .. "/" .. n .. " na metade de baixo")
          local x2, z2 = Mesa.espaco_criatura_abs(3 - p, n, calib)
          T.ok((x2 - ox) * dx + (z2 - oz) * dz < 0, "espaço do outro na metade de cima")
        end
      end
    end
  end },

  { "cada jogador conta os espaços da esquerda para a direita da câmera dele", function(T)
    local Mesa = nova_mesa()
    local function confere(calib, rotulo)
      for p = 1, 2 do
        local rx, rz = Mesa.direita(Mesa.heading(p, calib))
        local antes = -math.huge
        for n = 1, 6 do
          local x, z = Mesa.espaco_criatura_abs(p, n, calib)
          local d = x * rx + z * rz
          T.ok(d > antes, rotulo .. ": criatura " .. p .. "/" .. n .. " à direita da anterior")
          antes = d
        end
        local x1, z1 = Mesa.espaco_estrutura_abs(p, 1, calib)
        local x2, z2 = Mesa.espaco_estrutura_abs(p, 2, calib)
        T.ok(x1 * rx + z1 * rz < x2 * rx + z2 * rz, rotulo .. ": estrutura 1 à esquerda da 2")
      end
      -- O espaço n de um fica de frente para o 7 - n do outro.
      for n = 1, 6 do
        local x1 = Mesa.espaco_criatura_abs(1, n, calib)
        local x2 = Mesa.espaco_criatura_abs(2, 7 - n, calib)
        T.eq(x1, x2, rotulo .. ": " .. n .. " de frente para " .. (7 - n))
      end
    end
    for _, desl in ipairs(DESLOCAMENTOS) do
      local calib = calibrar_medido(Mesa, desl)
      confere(calib, "medido")
      -- No caso medido (espelhado) a ordem da câmera é a das listas do layout.
      for p = 1, 2 do
        for n = 1, 6 do
          local _, _, col = Mesa.espaco_criatura_abs(p, n, calib)
          T.eq(col, Mesa.espaco_criatura(p, n).col, "espelhado: coluna do layout " .. p .. "/" .. n)
        end
      end
      -- Sem espelhamento a câmera inverte as colunas, mas a numeração de
      -- quem olha continua da esquerda para a direita.
      local reto = { origem_x = calib.origem_x, origem_z = calib.origem_z, espelhado = false }
      confere(reto, "sem espelhamento")
      local _, _, col = Mesa.espaco_criatura_abs(1, 1, reto)
      T.eq(col, 12, "sem espelhamento o espaço 1 do jogador 1 é a coluna 12")
    end
  end },

  { "a calibração padrão fica em Mesa.calibracao", function(T)
    local Mesa = nova_mesa()
    T.eq(Mesa.calibracao, nil, "nasce sem calibração")
    T.eq(Mesa.espaco_criatura_abs(1, 1), nil, "sem calibração não há posição")
    local calib = calibrar_medido(Mesa, 20)
    Mesa.definir_calibracao(calib)
    T.eq(Mesa.calibracao, calib, "guardada")
    local x, z = Mesa.espaco_criatura_abs(1, 1)
    local x2, z2 = Mesa.espaco_criatura_abs(1, 1, calib)
    T.eq(x, x2, "x igual à explícita")
    T.eq(z, z2, "z igual à explícita")
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
    for _, desl in ipairs(DESLOCAMENTOS) do
      local amb = instalar_tudo(ambiente_jogo({ servidor = true, desl = desl }))
      local recebidas = {}
      amb.Calibracao.quando_calibrar(function(c) recebidas[#recebidas + 1] = c end)
      carregar_mundo(amb)
      local calib = amb.Mesa.calibracao
      T.ok(calib, "Mesa.calibracao definida")
      T.eq(calib.fonte, "carpete", "pelo carpete")
      T.eq(calib.espelhado, true, "espelhado")
      local px, pz = portal_no_mundo(desl)
      T.eq((amb.Mesa.tile_do_layout(px, pz)), 3, "portal na coluna 3")
      T.eq(#recebidas, 1, "inscrito avisado uma vez")
      T.eq(recebidas[1], calib, "com a calibração")
      T.eq(netvar(amb.reg, "duelo.mesa_origem_x"):value(), calib.origem_x, "netvar origem x")
      T.eq(netvar(amb.reg, "duelo.mesa_origem_z"):value(), calib.origem_z, "netvar origem z")
      T.eq(netvar(amb.reg, "duelo.mesa_espelhado"):value(), true, "netvar espelhado")
      T.eq(netvar(amb.reg, "duelo.mesa_fonte"):value(), 1, "netvar fonte = carpete")
      T.ok(no_log(amb.reg, "mesa calibrada pelo carpete"), "log da calibração")
      T.ok(not no_log(amb.reg, "não estão sobre"), "os 16 espaços conferem com o mapa")
      -- Quem se inscreve depois recebe na hora.
      local tarde
      amb.Calibracao.quando_calibrar(function(c) tarde = c end)
      T.eq(tarde, calib, "inscrito tardio")
    end
  end },

  { "sem carpete a origem sai do portal, com aviso; sem portal não calibra", function(T)
    local amb = instalar_tudo(ambiente_jogo({ servidor = true, sem_carpete = true }))
    carregar_mundo(amb)
    local calib = amb.Mesa.calibracao
    T.eq(calib.fonte, "portal", "reserva pelo portal")
    T.eq(calib.espelhado, true, "espelhado medido")
    T.ok(no_log(amb.reg, "carpete da mesa não achado"), "avisa no log")
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
    for _, nome in ipairs({ "duelo.mesa_origem_x", "duelo.mesa_origem_z", "duelo.mesa_espelhado", "duelo.mesa_fonte" }) do
      netvar(cli.reg, nome).valor = netvar(srv.reg, nome):value()
    end
    rede:PushEvent("duelo.mesadirty")
    local c = cli.Mesa.calibracao
    T.ok(c, "calibração no cliente")
    T.eq(c.origem_x, srv.Mesa.calibracao.origem_x, "origem x")
    T.eq(c.origem_z, srv.Mesa.calibracao.origem_z, "origem z")
    T.eq(c.espelhado, true, "espelhado")
    T.eq(c.fonte, "carpete", "fonte")
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
    T.eq(#amb.reg.spawns, 17, "17 SpawnPrefab")
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
      if tipo == 1 then ex, ez = Mesa.espaco_criatura_abs(jog, num, calib)
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
    T.eq(amb.reg.removidos, 17, "os 17 antigos removidos")
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
    T.eq(#cli.reg.netvars, #srv.reg.netvars - 0, "mesmas netvars nos dois lados")

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
    T.eq(ax, cx, "alvo no centro x")
    T.eq(az, cz, "alvo no centro z")
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
}
