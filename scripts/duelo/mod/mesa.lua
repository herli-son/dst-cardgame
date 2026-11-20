-- Geometria da mesa do duelo (US #29; calibração no jogo, US #30; layout
-- aprovado na #30 e corrigido no bug #147).
--
-- Este módulo é Lua 5.1 puro, sem nada do Don't Starve Together: ele é a
-- única fonte das posições da mesa. O static layout da geração do mundo
-- (duelo/mod/layouts/mesa.lua) é gerado a partir dele, e as US seguintes
-- (#33, criaturas nos espaços; #38, alvos válidos) leem daqui onde fica
-- cada espaço.
--
-- Layout aprovado (#30), por lado, 13 tiles de largura (C = cascalho,
-- K = carta, V = criatura, E = estrutura), com a fileira de cima
-- compartilhada pelos dois lados:
--
--   C C C C C C C C C C C C C   <- zona de combate
--   C V C V C V C V C V C V C
--   C K C K C K C K C K C K C
--   C C C C C C C C C C C C C
--   C C C E C C C C C E C C C
--   C C C C C C C C C C C C C
--
-- A mesa inteira tem 13 x 11 tiles. Cada espaço de criatura tem 2 tiles: a
-- carta atrás e a criatura na frente, virada para a zona de combate; no
-- ataque a criatura vai para o tile da zona de combate à frente dela e
-- volta. Cada estrutura tem 1 tile. Entre os espaços e em volta da mesa só
-- há cascalho: no DST a borda de um turf invade o vizinho, e com cascalho em
-- volta o turf que uma carta de Turf puser embaixo de um espaço (2 tiles)
-- aparece inteiro.
--
-- Grade: 21 x 21 tiles, cada tile com TILE_SCALE = 4 unidades do mundo
-- (constants.lua). O layout precisa ser quadrado porque o gerador
-- (map/object_layout.lua, ReserveAndPlaceLayout) usa #ground como tamanho
-- dos dois eixos. Com 21 (ímpar) a mesa fica exatamente no meio: 4 colunas
-- e 5 linhas de cada lado, e o centro do layout é o centro do tile (10, 10),
-- que é o centro da zona de combate. Há layouts da Klei com lado ímpar e
-- tilewidth 64 (map/static_layouts/monkeyisland_01_small.lua, 27 x 27).
--
-- Convenção de coordenadas:
--   col = coluna do tile, 0..20, cresce para o leste (eixo x do mundo);
--   lin = linha do tile, 0..20, cresce para o sul (eixo z do mundo).
-- As posições em unidades do mundo devolvidas por este módulo são relativas
-- ao centro do tile (10, 10). Para ter posições absolutas, a calibração acha
-- a origem no jogo (Mesa.calibrar e, na falta das estruturas,
-- Mesa.calibrar_pelo_portal).
--
-- Mapa (linhas de cima para baixo; "." = fora da mesa, intransitável;
-- "C" = cascalho, "-" = zona de combate (também cascalho), "K" = carta,
-- "V" = criatura, "E" = estrutura, "P" = portal sobre o cascalho do pátio):
--
--         col           1         2
--             012345678901234567890
--   lin  0    .....................
--        1    .....................
--        2    .....................
--        3    .....................
--        4    .....................
--        5    ....CCCCCCCCCCCCC....   borda
--        6    ....CCCECCCCCECCC....   estruturas do jogador 2 (norte)
--        7    ....CCCCCCCCCCCCC....
--        8    ....CKCKCKCKCKCKC....   cartas do jogador 2
--        9    .CCCCVCVCVCVCVCVC....   criaturas do jogador 2
--       10    .CPC-------------....   zona de combate
--       11    .CCCCVCVCVCVCVCVC....   criaturas do jogador 1 (sul)
--       12    ....CKCKCKCKCKCKC....   cartas do jogador 1
--       13    ....CCCCCCCCCCCCC....
--       14    ....CCCECCCCCECCC....   estruturas do jogador 1
--       15    ....CCCCCCCCCCCCC....   borda
--       16    .....................
--       17    .....................
--       18    .....................
--       19    .....................
--       20    .....................
--
-- Pátio do portal: o multiplayer_portal e o spawnpoint_master ficam fora da
-- mesa, no centro de um pátio de cascalho de 3 x 3 (colunas 1..3, linhas
-- 9..11) encostado na borda oeste da mesa, na altura da zona de combate. O
-- jogador nasce ali e anda até a mesa. O oeste foi escolhido porque o portal
-- precisa ficar fora do eixo x para denunciar o espelhamento (ver abaixo) e,
-- de lado, fica fora do enquadramento da câmera (que olha ao longo do eixo z)
-- e longe das fileiras dos dois jogadores. No jogo, com o eixo x espelhado,
-- o pátio aparece a leste da mesa.
--
-- Tiles (índices de GROUND_TYPES em map/static_layout.lua; Mesa.TILE):
--   * cascalho = ROCKY (tiledefs.lua: "Rocky", textura "rocky", ruído
--     noise_rocky). É o turf rochoso natural do jogo, o mesmo da carta de
--     Turf "Cascalho". A borda dele é a borda irregular dos turfs naturais,
--     que só aparece no encontro com outro tile; como o cascalho é contínuo
--     em volta da mesa, isso não atrapalha. Na ordem de desenho
--     (tiledefs.lua, ordem dos AddTile) o ROCKY vem antes de quase todos os
--     turfs e pisos, então a borda deles avança sobre o cascalho e o tile do
--     espaço continua inteiro; a exceção conhecida é o MARSH (antes do
--     ROCKY): o cascalho avança um pouco sobre um Pântano (a conferir no
--     jogo, #30).
--   * carta e criatura sem turf jogado = CHECKER (piso xadrez, "blocky", com
--     borda reta). Liso, regular e bem diferente do cascalho. O WOODFLOOR foi
--     descartado porque é o turf da carta "Piso de madeira": um espaço com
--     essa carta ficaria igual a um espaço vazio.
--   * estrutura = MOSAIC_GREY (mosaico cinza, "blocky"). Outro piso,
--     diferente do xadrez e do cascalho, e de cor neutra: o MOSAIC_BLUE e o
--     CARPET (avermelhado) lembrariam a cor de um dos donos (azul J1,
--     vermelho J2), que vem dos contornos e dos rótulos.
--
-- Ordem dos espaços: cada jogador conta os seus espaços da esquerda para a
-- direita olhando para o centro. Nas listas abaixo (que valem para o eixo x
-- espelhado, o caso medido no jogo), o espaço 1 do jogador 1 é a coluna 5 e
-- o 6 é a coluna 15; o do jogador 2 é a coluna 15 e o 6 é a coluna 5. Assim o
-- espaço n de um jogador fica de frente para o espaço 7 - n do outro (o
-- motor não depende disso: quem bloqueia quem é escolhido por jogada,
-- duelo/core/combate.lua). As estruturas seguem a mesma regra (1 à
-- esquerda, 2 à direita): colunas 7 e 13.
--
-- Espelhamento (medido no jogo, US #30): o gerador espelha o eixo x de todo
-- static layout (flip_x = -1 em map/object_layout.lua, ReserveAndPlaceLayout,
-- mesmo com disable_transform; flip_y continua 1). Os tiles da mesa são
-- simétricos nos dois eixos, então o espelhamento só muda a ordem das
-- colunas; o portal é o único elemento fora do eixo x, e a sua posição no
-- mundo diz se houve espelhamento (Mesa.calibrar). O eixo z não tem nada que
-- denuncie uma inversão, e ela não importaria: só trocaria qual lado se
-- chama "jogador 1".
--
-- Calibração (US #30, refeita no #147): no jogo,
-- scripts/duelo/mod/calibracao.lua acha o portal e, em volta dele, os tiles
-- de estrutura (MOSAIC_GREY). Os 4 tiles de estrutura são o padrão
-- inequívoco: só eles usam esse piso, e formam os cantos de um retângulo de
-- 7 x 9 tiles (6 colunas e 8 linhas entre os centros) cujo centro é o
-- centro da zona de combate. Mesa.achar_estruturas confere o padrão (e
-- recusa a mesa girada, 9 x 7), Mesa.calibrar tira a origem do centro do
-- retângulo e o espelhamento do lado do portal. O resultado fica em
-- Mesa.calibracao (servidor e clientes) e dá as posições absolutas
-- (Mesa.espaco_criatura_abs, Mesa.espaco_estrutura_abs, Mesa.centro_abs,
-- Mesa.tiles_dos_espacos).
--
-- Esquerda e direita de quem olha: o espelhamento troca leste e oeste, e a
-- tela do DST não mostra o +x à direita (cameras/followcamera.lua,
-- GetRightVec: a direita da tela é (cos(h + 90), sin(h + 90)) para o
-- heading h). Por isso a numeração absoluta não confia na coluna: os espaços
-- de cada jogador são ordenados pela projeção na direita da câmera dele
-- (Mesa.heading). No caso medido (espelhado) a ordem dá a mesma das listas de
-- colunas abaixo; sem espelhamento, daria a inversa, e a numeração absoluta
-- continuaria certa para quem olha.

local Mesa = {}

Mesa.TILE_SCALE = 4
Mesa.LARGURA = 21 -- colunas (eixo x)
Mesa.ALTURA = 21 -- linhas (eixo z)

-- Índice de cada tile na ordem GROUND_TYPES de map/static_layout.lua
-- (1 = primeiro da lista). 0 não é um tile: o gerador deixa o terreno como
-- está, isto é, IMPASSABLE da sala Blank, que é o que fica fora da mesa.
-- Conferido em map/static_layout.lua:
--   1 IMPASSABLE, 3 ROCKY, 9 WOODFLOOR, 10 CARPET, 11 CHECKER,
--   47 MOSAIC_GREY, 48 MOSAIC_RED, 49 MOSAIC_BLUE, 50 CARPET2.
Mesa.TILE = {
  FORA = 0,
  IMPASSAVEL = 1,
  CASCALHO = 3,
  XADREZ = 11,
  MOSAICO_CINZA = 47,
}

-- Nome do tile no jogo (WORLD_TILES de constants.lua/tiledefs.lua) de cada
-- índice acima: é o que a calibração compara com TheWorld.Map:GetTile.
Mesa.WORLD_TILE = {
  CASCALHO = "ROCKY",
  XADREZ = "CHECKER",
  MOSAICO_CINZA = "MOSAIC_GREY",
}

-- Que tile cada parte da mesa usa.
Mesa.USO = {
  fora = "FORA",
  cascalho = "CASCALHO",
  combate = "CASCALHO",
  patio = "CASCALHO",
  carta = "XADREZ",
  criatura = "XADREZ",
  estrutura = "MOSAICO_CINZA",
}

-- Retângulos, em tiles, inclusivos.
Mesa.MESA = { col_min = 4, col_max = 16, lin_min = 5, lin_max = 15 } -- 13 x 11
Mesa.COMBATE = { col_min = 4, col_max = 16, lin_min = 10, lin_max = 10 } -- zona de combate
Mesa.PATIO = { col_min = 1, col_max = 3, lin_min = 9, lin_max = 11 } -- pátio do portal

-- Centro da zona de combate (rótulo "Combate", alvo da câmera). É o centro
-- do layout.
Mesa.CENTRO_COMBATE = { col = 10, lin = 10 }

-- Colunas dos 6 espaços de criatura e das 2 estruturas, da esquerda para a
-- direita do jogador 1 no caso espelhado (ver o cabeçalho).
local COLUNAS_CRIATURA = { 5, 7, 9, 11, 13, 15 }
local COLUNAS_ESTRUTURA = { 7, 13 }

-- Linhas de cada lado: estrutura, carta, criatura (a criatura fica do lado
-- da zona de combate, linha 10).
local LINHAS = {
  [1] = { estrutura = 14, carta = 12, criatura = 11 },
  [2] = { estrutura = 6, carta = 8, criatura = 9 },
}

local function invertida(lista)
  local r = {}
  for i = #lista, 1, -1 do r[#r + 1] = lista[i] end
  return r
end

-- Um espaço de criatura: o tile da carta (atrás), o da criatura (na frente)
-- e o tile da zona de combate à frente da criatura (para onde ela vai no
-- ataque). Todos na mesma coluna.
local function espaco_de_criatura(col, linhas)
  return {
    col = col,
    carta = { col = col, lin = linhas.carta },
    criatura = { col = col, lin = linhas.criatura },
    combate = { col = col, lin = Mesa.COMBATE.lin_min },
  }
end

local function lado(jogador, nome, colunas_criatura, colunas_estrutura)
  local linhas = LINHAS[jogador]
  local criaturas, estruturas = {}, {}
  for i, col in ipairs(colunas_criatura) do criaturas[i] = espaco_de_criatura(col, linhas) end
  for i, col in ipairs(colunas_estrutura) do estruturas[i] = { col = col, lin = linhas.estrutura } end
  return { lado = nome, criaturas = criaturas, estruturas = estruturas }
end

Mesa.JOGADORES = {
  [1] = lado(1, "sul", COLUNAS_CRIATURA, COLUNAS_ESTRUTURA),
  [2] = lado(2, "norte", invertida(COLUNAS_CRIATURA), invertida(COLUNAS_ESTRUTURA)),
}

-- Portal (multiplayer_portal e o spawnpoint_master junto dele), em tiles,
-- relativo ao centro do layout: centro do tile (2, 10), no meio do pátio.
Mesa.PORTAL = { x = -8, z = 0 }

local function dentro(ret, col, lin)
  return col >= ret.col_min and col <= ret.col_max and lin >= ret.lin_min and lin <= ret.lin_max
end

-- Devolve o uso do tile ("carta", "criatura", "estrutura", "combate",
-- "cascalho", "patio" ou "fora") e, quando é um espaço, o jogador e o número
-- do espaço (ordem das listas do layout).
function Mesa.uso_em(col, lin)
  for jogador, l in pairs(Mesa.JOGADORES) do
    for n, e in ipairs(l.criaturas) do
      if e.carta.col == col and e.carta.lin == lin then return "carta", jogador, n end
      if e.criatura.col == col and e.criatura.lin == lin then return "criatura", jogador, n end
    end
    for n, e in ipairs(l.estruturas) do
      if e.col == col and e.lin == lin then return "estrutura", jogador, n end
    end
  end
  if dentro(Mesa.COMBATE, col, lin) then return "combate" end
  if dentro(Mesa.MESA, col, lin) then return "cascalho" end
  if dentro(Mesa.PATIO, col, lin) then return "patio" end
  return "fora"
end

-- Índice GROUND_TYPES do tile em (col, lin).
function Mesa.indice_em(col, lin)
  return Mesa.TILE[Mesa.USO[Mesa.uso_em(col, lin)]]
end

-- Camada BG_TILES do layout: LARGURA * ALTURA índices, linha a linha, de
-- cima para baixo, como o Tiled exporta.
function Mesa.dados_bg_tiles()
  local dados = {}
  for lin = 0, Mesa.ALTURA - 1 do
    for col = 0, Mesa.LARGURA - 1 do
      dados[#dados + 1] = Mesa.indice_em(col, lin)
    end
  end
  return dados
end

-- Mapa ASCII da grade (o mesmo do cabeçalho), uma string por linha.
local SIMBOLO = { fora = ".", cascalho = "C", combate = "-", patio = "C", carta = "K", criatura = "V", estrutura = "E" }

function Mesa.mapa_ascii()
  local linhas = {}
  local pcol = math.floor(Mesa.PORTAL.x + Mesa.LARGURA / 2)
  local plin = math.floor(Mesa.PORTAL.z + Mesa.ALTURA / 2)
  for lin = 0, Mesa.ALTURA - 1 do
    local s = {}
    for col = 0, Mesa.LARGURA - 1 do
      s[#s + 1] = (col == pcol and lin == plin) and "P" or SIMBOLO[Mesa.uso_em(col, lin)]
    end
    linhas[#linhas + 1] = table.concat(s)
  end
  return linhas
end

-- Centro do tile (col, lin) em unidades do mundo, relativo ao centro do
-- layout (centro do tile (10, 10)). O tile (0, 0) é o canto noroeste.
function Mesa.centro_do_tile(col, lin)
  local x = (col + 0.5 - Mesa.LARGURA / 2) * Mesa.TILE_SCALE
  local z = (lin + 0.5 - Mesa.ALTURA / 2) * Mesa.TILE_SCALE
  return x, z
end

-- Posição do portal em unidades do mundo, relativa ao centro do layout.
function Mesa.posicao_do_portal()
  return Mesa.PORTAL.x * Mesa.TILE_SCALE, Mesa.PORTAL.z * Mesa.TILE_SCALE
end

-- Dada a posição absoluta do portal no mundo, devolve a origem (centro do
-- layout) em unidades do mundo. `espelhado` = true quando o gerador
-- espelhou o eixo x (ver o aviso no cabeçalho).
function Mesa.origem_pelo_portal(px, pz, espelhado)
  local ox, oz = Mesa.posicao_do_portal()
  if espelhado then ox = -ox end
  return px - ox, pz - oz
end

-- Posição absoluta do centro do tile (col, lin), dada a origem do layout.
function Mesa.posicao(col, lin, origem_x, origem_z, espelhado)
  local x, z = Mesa.centro_do_tile(col, lin)
  if espelhado then x = -x end
  return origem_x + x, origem_z + z
end

-- Espaço de criatura n (1..6) de um jogador, na ordem do layout:
-- { col, carta = {col, lin}, criatura = {col, lin}, combate = {col, lin} }.
function Mesa.espaco_criatura(jogador, n)
  return Mesa.JOGADORES[jogador].criaturas[n]
end

-- Espaço de estrutura n (1..2) de um jogador, na ordem do layout: {col, lin}.
function Mesa.espaco_estrutura(jogador, n)
  return Mesa.JOGADORES[jogador].estruturas[n]
end

-- ---------------------------------------------------------------------------
-- Calibração no jogo (US #30, refeita no #147)
-- ---------------------------------------------------------------------------

-- Distância, em tiles, entre as colunas e entre as linhas das estruturas:
-- 6 colunas (7 e 13) e 8 linhas (6 e 14).
Mesa.ESTRUTURAS_DX = COLUNAS_ESTRUTURA[2] - COLUNAS_ESTRUTURA[1]
Mesa.ESTRUTURAS_DZ = LINHAS[1].estrutura - LINHAS[2].estrutura

-- Calibração em uso neste lado (servidor ou cliente); nil até o jogo
-- calibrar. Campos: origem_x, origem_z (centro do layout em unidades do
-- mundo), espelhado (eixo x espelhado), fonte ("estruturas" ou "portal") e
-- aviso (texto ou nil).
Mesa.calibracao = nil

function Mesa.definir_calibracao(calib)
  Mesa.calibracao = calib
  return calib
end

-- Recebe a lista dos tiles de estrutura (MOSAIC_GREY) achados em volta do
-- portal, cada um { x = tile_x, y = tile_y } (coordenadas de TheWorld.Map),
-- e devolve o retângulo { x_min, x_max, y_min, y_max } se eles forem
-- exatamente os 4 cantos de um retângulo com ESTRUTURAS_DX colunas e
-- ESTRUTURAS_DZ linhas entre eles. Senão devolve nil e o motivo.
function Mesa.achar_estruturas(tiles)
  if tiles == nil or #tiles == 0 then return nil, "nenhum tile de estrutura" end
  local vistos, unicos = {}, {}
  local xs, ys, nx, ny = {}, {}, 0, 0
  for _, t in ipairs(tiles) do
    local chave = t.x .. "," .. t.y
    if not vistos[chave] then
      vistos[chave] = true
      unicos[#unicos + 1] = t
      if not xs[t.x] then xs[t.x] = true; nx = nx + 1 end
      if not ys[t.y] then ys[t.y] = true; ny = ny + 1 end
    end
  end
  if #unicos ~= 4 then
    return nil, string.format("%d tiles de estrutura, esperados 4", #unicos)
  end
  if nx ~= 2 or ny ~= 2 then
    return nil, "os 4 tiles de estrutura não formam um retângulo"
  end
  local r = { x_min = math.huge, x_max = -math.huge, y_min = math.huge, y_max = -math.huge }
  for _, t in ipairs(unicos) do
    if t.x < r.x_min then r.x_min = t.x end
    if t.x > r.x_max then r.x_max = t.x end
    if t.y < r.y_min then r.y_min = t.y end
    if t.y > r.y_max then r.y_max = t.y end
  end
  local dx, dy = r.x_max - r.x_min, r.y_max - r.y_min
  if dx == Mesa.ESTRUTURAS_DZ and dy == Mesa.ESTRUTURAS_DX then
    return nil, "estruturas giradas (eixos trocados): o gerador girou a mesa"
  end
  if dx ~= Mesa.ESTRUTURAS_DX or dy ~= Mesa.ESTRUTURAS_DZ then
    return nil, string.format("estruturas a %d x %d tiles uma da outra, esperado %d x %d",
      dx, dy, Mesa.ESTRUTURAS_DX, Mesa.ESTRUTURAS_DZ)
  end
  return r
end

-- Calibração pura. `info`:
--   estruturas: retângulo de Mesa.achar_estruturas (coordenadas de tile);
--   centro_mundo(tile_x, tile_y): devolve x, z do centro do tile em unidades
--     do mundo (no jogo, TheWorld.Map:GetTileCenterPoint);
--   portal: { x, z }, posição do multiplayer_portal no mundo.
-- O centro do retângulo das estruturas é o centro do layout (colunas 7 e 13,
-- linhas 6 e 14, em volta do tile (10, 10)). O portal fica a oeste do
-- centro no layout (Mesa.PORTAL.x < 0): se no mundo ele aparece com x maior
-- que a origem, o eixo x foi espelhado.
function Mesa.calibrar(info)
  local r = info.estruturas
  local x1, z1 = info.centro_mundo(r.x_min, r.y_min)
  local x2, z2 = info.centro_mundo(r.x_max, r.y_max)
  local calib = {
    origem_x = (x1 + x2) / 2,
    origem_z = (z1 + z2) / 2,
    espelhado = false,
    fonte = "estruturas",
  }
  local p = info.portal
  if p ~= nil then
    local dx = p.x - calib.origem_x
    local px_layout = Mesa.PORTAL.x * Mesa.TILE_SCALE
    local pz_layout = Mesa.PORTAL.z * Mesa.TILE_SCALE
    calib.espelhado = (dx > 0) == (px_layout < 0)
    -- O portal deve ficar a |PORTAL.x| tiles do centro, na linha do centro,
    -- com folga de meio tile (map/object_layout.lua centra objetos e tiles de
    -- jeitos diferentes).
    local folga = Mesa.TILE_SCALE / 2
    if math.abs(math.abs(dx) - math.abs(px_layout)) > folga
      or math.abs(p.z - calib.origem_z - pz_layout) > folga then
      calib.aviso = string.format("portal em (%.1f, %.1f), longe do esperado em volta da origem (%.1f, %.1f)",
        p.x, p.z, calib.origem_x, calib.origem_z)
    end
  else
    calib.aviso = "sem portal: espelhamento não conferido"
  end
  return calib
end

-- Calibração de reserva, sem as estruturas: só pelo portal. `espelhado`
-- padrão é true, o que foi medido no jogo.
function Mesa.calibrar_pelo_portal(px, pz, espelhado)
  if espelhado == nil then espelhado = true end
  local ox, oz = Mesa.origem_pelo_portal(px, pz, espelhado)
  return {
    origem_x = ox,
    origem_z = oz,
    espelhado = espelhado,
    fonte = "portal",
    aviso = "estruturas da mesa não achadas: origem pela posição do portal",
  }
end

local function calib_ou_atual(calib)
  return calib or Mesa.calibracao
end

-- Tile do layout (col, lin) que contém o ponto absoluto (x, z).
function Mesa.tile_do_layout(x, z, calib)
  calib = calib_ou_atual(calib)
  local rx = x - calib.origem_x
  if calib.espelhado then rx = -rx end
  local rz = z - calib.origem_z
  local col = math.floor(rx / Mesa.TILE_SCALE + Mesa.LARGURA / 2)
  local lin = math.floor(rz / Mesa.TILE_SCALE + Mesa.ALTURA / 2)
  return col, lin
end

-- Posição absoluta do centro do tile (col, lin) com a calibração.
function Mesa.posicao_abs(col, lin, calib)
  calib = calib_ou_atual(calib)
  return Mesa.posicao(col, lin, calib.origem_x, calib.origem_z, calib.espelhado)
end

-- Centro da zona de combate no mundo.
function Mesa.centro_abs(calib)
  calib = calib_ou_atual(calib)
  return Mesa.posicao_abs(Mesa.CENTRO_COMBATE.col, Mesa.CENTRO_COMBATE.lin, calib)
end

-- Lado da câmera: 1 e 2 são os jogadores; qualquer outro valor (espectador,
-- lado ainda desconhecido) olha como o jogador 1.
local function lado_da_camera(jogador)
  if jogador == 2 then return 2 end
  return 1
end

-- Heading da câmera (graus, 0..360) que põe o lado do jogador embaixo da
-- tela. Em cameras/followcamera.lua, GetDownVec = (cos h, sin h) é a direção
-- do mundo que aponta para baixo na tela (a câmera olha para (-cos h, -sin h)
-- e fica atrás do alvo nessa direção). Então h = atan2(dz, dx) do vetor que
-- vai do centro da mesa até a fileira de criaturas do jogador. Com o eixo z
-- não espelhado, o jogador 1 (sul, z maior) dá 90 e o jogador 2 dá 270.
function Mesa.heading(jogador, calib)
  calib = calib_ou_atual(calib)
  local l = Mesa.JOGADORES[lado_da_camera(jogador)]
  local sx, sz = 0, 0
  for _, e in ipairs(l.criaturas) do
    local x, z = Mesa.posicao_abs(e.criatura.col, e.criatura.lin, calib)
    sx, sz = sx + x, sz + z
  end
  local n = #l.criaturas
  local cx, cz = Mesa.centro_abs(calib)
  local dx, dz = sx / n - cx, sz / n - cz
  local h = math.deg(math.atan2(dz, dx))
  if h < 0 then h = h + 360 end
  -- Arredonda para tirar o ruído de ponto flutuante (89.999... -> 90).
  return math.floor(h * 1000 + 0.5) / 1000
end

-- Direita da tela para o heading h (cameras/followcamera.lua, GetRightVec).
function Mesa.direita(heading)
  local r = math.rad(heading + 90)
  return math.cos(r), math.sin(r)
end

-- Tile em posição absoluta: { x, z, col, lin }.
local function tile_abs(t, calib)
  local x, z = Mesa.posicao_abs(t.col, t.lin, calib)
  return { x = x, z = z, col = t.col, lin = t.lin }
end

-- Espaços de um jogador ordenados da esquerda para a direita de quem olha
-- pela câmera desse jogador (projeção da coluna na direita da tela).
local function ordenados(lista, jogador, calib)
  local rx, rz = Mesa.direita(Mesa.heading(jogador, calib))
  local copia = {}
  for _, e in ipairs(lista) do
    local x, z = Mesa.posicao_abs(e.col, e.lin or e.carta.lin, calib)
    copia[#copia + 1] = { e = e, d = x * rx + z * rz }
  end
  table.sort(copia, function(a, b) return a.d < b.d end)
  return copia
end

-- Espaço de criatura n (1..6) do jogador, contado da esquerda de quem olha
-- pela câmera dele. Devolve { carta, criatura, combate }, cada um
-- { x, z, col, lin } em posição absoluta; nil sem calibração ou sem espaço.
function Mesa.espaco_criatura_abs(jogador, n, calib)
  calib = calib_ou_atual(calib)
  if calib == nil then return nil end
  local item = ordenados(Mesa.JOGADORES[jogador].criaturas, jogador, calib)[n]
  if item == nil then return nil end
  return {
    carta = tile_abs(item.e.carta, calib),
    criatura = tile_abs(item.e.criatura, calib),
    combate = tile_abs(item.e.combate, calib),
  }
end

-- Espaço de estrutura n (1..2), mesma regra. Devolve x, z, col, lin.
function Mesa.espaco_estrutura_abs(jogador, n, calib)
  calib = calib_ou_atual(calib)
  if calib == nil then return nil end
  local item = ordenados(Mesa.JOGADORES[jogador].estruturas, jogador, calib)[n]
  if item == nil then return nil end
  local t = tile_abs(item.e, calib)
  return t.x, t.z, t.col, t.lin
end

-- Todos os tiles de espaço (12 cartas, 12 criaturas e 4 estruturas) em
-- posição absoluta, com a numeração da câmera. Cada item:
-- { x, z, col, lin, jogador, tipo ("carta" | "criatura" | "estrutura"), n }.
function Mesa.tiles_dos_espacos(calib)
  calib = calib_ou_atual(calib)
  if calib == nil then return nil end
  local lista = {}
  for p = 1, 2 do
    for n = 1, #Mesa.JOGADORES[p].criaturas do
      local e = Mesa.espaco_criatura_abs(p, n, calib)
      for _, tipo in ipairs({ "carta", "criatura" }) do
        local t = e[tipo]
        lista[#lista + 1] = { x = t.x, z = t.z, col = t.col, lin = t.lin, jogador = p, tipo = tipo, n = n }
      end
    end
    for n = 1, #Mesa.JOGADORES[p].estruturas do
      local x, z, col, lin = Mesa.espaco_estrutura_abs(p, n, calib)
      lista[#lista + 1] = { x = x, z = z, col = col, lin = lin, jogador = p, tipo = "estrutura", n = n }
    end
  end
  return lista
end

return Mesa
