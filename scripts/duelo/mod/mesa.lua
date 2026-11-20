-- Geometria da mesa do duelo (US #29; calibração no jogo, US #30).
--
-- Este módulo é Lua 5.1 puro, sem nada do Don't Starve Together: ele é a
-- única fonte das posições da mesa. O static layout da geração do mundo
-- (duelo/mod/layouts/mesa.lua) é gerado a partir dele, e as US seguintes
-- (#30, tiles e câmera; #33, criaturas nos espaços) leem daqui onde fica
-- cada espaço.
--
-- Grade: 20 x 20 tiles, cada tile com TILE_SCALE = 4 unidades do mundo
-- (constants.lua). O layout precisa ser quadrado porque o gerador
-- (map/object_layout.lua) usa o número de linhas como tamanho dos dois eixos.
--
-- Convenção de coordenadas:
--   col = coluna do tile, 0..19, cresce para o leste (eixo x do mundo);
--   lin = linha do tile, 0..19, cresce para o sul (eixo z do mundo).
-- O centro do layout fica na junção das colunas 9|10 e das linhas 9|10; as
-- posições em unidades do mundo devolvidas por este módulo são relativas a
-- esse centro. Para ter posições absolutas, a US #30 descobre a origem no
-- jogo (ver Mesa.calibrar e, na falta do carpete, Mesa.origem_pelo_portal).
--
-- Mapa (linhas de cima para baixo; "." = fora da mesa, "x" = chão XADREZ,
-- "E" = estrutura MOSAICO_AZUL, "C" = criatura MOSAICO_CINZA, "#" = centro
-- CARPETE, "P" = portal):
--
--         col 0         1         1
--             01234567890123456789
--   lin  0    ....................
--        1    ....................
--        2    ..xxxxxxxxxxxxxxxx..
--        3    ..xxxxxxxxxxxxxxxx..
--        4    ..xxxxxxExxExxxxxx..   estruturas do jogador 2 (norte)
--        5    ..xxxxxxxxxxxxxxxx..
--        6    ..xxxxxCCCCCCxxxxx..   criaturas do jogador 2
--        7    ..xxxxxxxxxxxxxxxx..
--        8    ..xxxx########xxxx..
--        9    ..xPxx########xxxx..   área central de combate
--       10    ..xPxx########xxxx..   (portal entre as linhas 9 e 10)
--       11    ..xxxx########xxxx..
--       12    ..xxxxxxxxxxxxxxxx..
--       13    ..xxxxxCCCCCCxxxxx..   criaturas do jogador 1 (sul)
--       14    ..xxxxxxxxxxxxxxxx..
--       15    ..xxxxxxExxExxxxxx..   estruturas do jogador 1
--       16    ..xxxxxxxxxxxxxxxx..
--       17    ..xxxxxxxxxxxxxxxx..
--       18    ....................
--       19    ....................
--
-- Ordem dos espaços: cada jogador conta os seus espaços da esquerda para a
-- direita olhando para o centro. O jogador 1 olha para o norte, então o seu
-- espaço 1 é a coluna 7 e o 6 é a coluna 12; o jogador 2 olha para o sul, e
-- o seu espaço 1 é a coluna 12 e o 6 é a coluna 7. Assim o espaço n de um
-- jogador fica de frente para o espaço 7 - n do outro (o motor não depende
-- disso: quem bloqueia quem é escolhido por jogada, duelo/core/combate.lua).
-- As estruturas seguem a mesma regra (1 à esquerda, 2 à direita).
--
-- Espelhamento (medido no jogo, US #30): o gerador espelha o eixo x de todo
-- static layout (flip_x = -1 em map/object_layout.lua, ReserveAndPlaceLayout,
-- mesmo com disable_transform; flip_y continua 1). No jogo o portal ficou no
-- tile (35, 29) e o carpete em volta do tile (29, 28), isto é,
-- x_tile = 38 - col: o carpete tem x menor que o portal. A mesa é simétrica
-- nos dois eixos, então o espelhamento só muda o lado do portal e a ordem das
-- colunas; como o portal é o único elemento fora do eixo, a sua posição no
-- mundo diz se houve espelhamento (Mesa.calibrar). O eixo z não tem nada que
-- denuncie uma inversão, e ela não importaria: só trocaria qual lado se
-- chama "jogador 1".
--
-- Calibração (US #30): no jogo, scripts/duelo/mod/calibracao.lua acha o
-- portal e os tiles do carpete e chama Mesa.calibrar; o resultado fica em
-- Mesa.calibracao (servidor e clientes) e dá as posições absolutas dos
-- espaços (Mesa.espaco_criatura_abs, Mesa.espaco_estrutura_abs,
-- Mesa.centro_abs).
--
-- Esquerda e direita de quem olha: o espelhamento troca leste e oeste, e a
-- tela do DST não mostra o +x à direita (cameras/followcamera.lua,
-- GetRightVec: a direita da tela é (cos(h + 90), sin(h + 90)) para o
-- heading h). Por isso a numeração absoluta não confia na coluna: os espaços
-- de cada jogador são ordenados pela projeção na direita da câmera dele
-- (Mesa.heading). No caso medido (espelhado) a ordem dá a mesma das listas de
-- colunas acima; sem espelhamento, daria a inversa, e a numeração absoluta
-- continuaria certa para quem olha.

local Mesa = {}

Mesa.TILE_SCALE = 4
Mesa.LARGURA = 20 -- colunas (eixo x)
Mesa.ALTURA = 20 -- linhas (eixo z)

-- Índice de cada tile na ordem GROUND_TYPES de map/static_layout.lua
-- (1 = primeiro da lista). 0 não é um tile: o gerador deixa o terreno como
-- está, isto é, IMPASSABLE da sala Blank, que é o que fica fora da mesa.
-- Conferido em map/static_layout.lua:
--   1 IMPASSABLE, 9 WOODFLOOR, 10 CARPET, 11 CHECKER, 25 BRICK, 27 TILES,
--   29 TRIM, 38 LAVAARENA_FLOOR, 39 LAVAARENA_TRIM, 47 MOSAIC_GREY,
--   48 MOSAIC_RED, 49 MOSAIC_BLUE, 50 CARPET2.
Mesa.TILE = {
  FORA = 0,
  IMPASSAVEL = 1,
  CARPETE = 10,
  XADREZ = 11,
  MOSAICO_CINZA = 47,
  MOSAICO_AZUL = 49,
}

-- Que tile cada parte da mesa usa.
Mesa.USO = {
  fora = "FORA",
  chao = "XADREZ",
  criatura = "MOSAICO_CINZA",
  estrutura = "MOSAICO_AZUL",
  centro = "CARPETE",
}

-- Retângulos, em tiles, inclusivos.
Mesa.PISO = { col_min = 2, col_max = 17, lin_min = 2, lin_max = 17 }
Mesa.CENTRO = { col_min = 6, col_max = 13, lin_min = 8, lin_max = 11 }

local function linha_de_espacos(lin, colunas)
  local espacos = {}
  for i, col in ipairs(colunas) do
    espacos[i] = { col = col, lin = lin }
  end
  return espacos
end

Mesa.JOGADORES = {
  [1] = {
    lado = "sul",
    criaturas = linha_de_espacos(13, { 7, 8, 9, 10, 11, 12 }),
    estruturas = linha_de_espacos(15, { 8, 11 }),
  },
  [2] = {
    lado = "norte",
    criaturas = linha_de_espacos(6, { 12, 11, 10, 9, 8, 7 }),
    estruturas = linha_de_espacos(4, { 11, 8 }),
  },
}

-- Portal (multiplayer_portal e o spawnpoint_master junto dele), em tiles,
-- relativo ao centro do layout: no meio da coluna 3, na junção das linhas
-- 9|10. Fica na margem oeste, fora do caminho das criaturas.
Mesa.PORTAL = { x = -6.5, z = 0 }

local function dentro(ret, col, lin)
  return col >= ret.col_min and col <= ret.col_max and lin >= ret.lin_min and lin <= ret.lin_max
end

-- Devolve o uso do tile ("chao", "criatura", "estrutura", "centro" ou "fora")
-- e, quando é um espaço, o jogador e o número do espaço.
function Mesa.uso_em(col, lin)
  for jogador, lados in pairs(Mesa.JOGADORES) do
    for n, e in ipairs(lados.criaturas) do
      if e.col == col and e.lin == lin then return "criatura", jogador, n end
    end
    for n, e in ipairs(lados.estruturas) do
      if e.col == col and e.lin == lin then return "estrutura", jogador, n end
    end
  end
  if dentro(Mesa.CENTRO, col, lin) then return "centro" end
  if dentro(Mesa.PISO, col, lin) then return "chao" end
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

-- Centro do tile (col, lin) em unidades do mundo, relativo ao centro do
-- layout. O tile (0, 0) é o canto noroeste.
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

-- Espaço de criatura n (1..6) ou de estrutura n (1..2) de um jogador.
function Mesa.espaco_criatura(jogador, n)
  return Mesa.JOGADORES[jogador].criaturas[n]
end

function Mesa.espaco_estrutura(jogador, n)
  return Mesa.JOGADORES[jogador].estruturas[n]
end

-- ---------------------------------------------------------------------------
-- Calibração no jogo (US #30)
-- ---------------------------------------------------------------------------

-- Tamanho do carpete central, em tiles: 8 colunas (x) por 4 linhas (z).
Mesa.CARPETE_LARGURA = Mesa.CENTRO.col_max - Mesa.CENTRO.col_min + 1
Mesa.CARPETE_ALTURA = Mesa.CENTRO.lin_max - Mesa.CENTRO.lin_min + 1

-- Calibração em uso neste lado (servidor ou cliente); nil até o jogo
-- calibrar. Campos: origem_x, origem_z (centro do layout em unidades do
-- mundo), espelhado (eixo x espelhado), fonte ("carpete" ou "portal") e
-- aviso (texto ou nil).
Mesa.calibracao = nil

function Mesa.definir_calibracao(calib)
  Mesa.calibracao = calib
  return calib
end

-- Recebe a lista dos tiles de carpete achados em volta do portal, cada um
-- { x = tile_x, y = tile_y } (coordenadas de TheWorld.Map), e devolve o
-- retângulo { x_min, x_max, y_min, y_max } se eles formarem exatamente o
-- carpete 8 x 4 da mesa. Senão devolve nil e o motivo.
function Mesa.achar_carpete(tiles)
  if tiles == nil or #tiles == 0 then return nil, "nenhum tile de carpete" end
  local r = { x_min = math.huge, x_max = -math.huge, y_min = math.huge, y_max = -math.huge }
  local vistos = {}
  for _, t in ipairs(tiles) do
    local chave = t.x .. "," .. t.y
    if not vistos[chave] then
      vistos[chave] = true
      if t.x < r.x_min then r.x_min = t.x end
      if t.x > r.x_max then r.x_max = t.x end
      if t.y < r.y_min then r.y_min = t.y end
      if t.y > r.y_max then r.y_max = t.y end
    end
  end
  local largura = r.x_max - r.x_min + 1
  local altura = r.y_max - r.y_min + 1
  if largura == Mesa.CARPETE_ALTURA and altura == Mesa.CARPETE_LARGURA then
    return nil, "carpete girado (4 x 8): o gerador trocou os eixos"
  end
  if largura ~= Mesa.CARPETE_LARGURA or altura ~= Mesa.CARPETE_ALTURA then
    return nil, string.format("carpete de %d x %d tiles, esperado %d x %d",
      largura, altura, Mesa.CARPETE_LARGURA, Mesa.CARPETE_ALTURA)
  end
  for x = r.x_min, r.x_max do
    for y = r.y_min, r.y_max do
      if not vistos[x .. "," .. y] then
        return nil, "carpete com buraco no tile " .. x .. "," .. y
      end
    end
  end
  return r
end

-- Calibração pura. `info`:
--   carpete: retângulo de Mesa.achar_carpete (coordenadas de tile);
--   centro_mundo(tile_x, tile_y): devolve x, z do centro do tile em unidades
--     do mundo (no jogo, TheWorld.Map:GetTileCenterPoint);
--   portal: { x, z }, posição do multiplayer_portal no mundo.
-- O centro do carpete é o centro do layout (CENTRO é simétrico em volta da
-- junção 9|10 das colunas e das linhas). O portal fica a oeste do centro no
-- layout (Mesa.PORTAL.x < 0): se no mundo ele aparece com x maior que a
-- origem, o eixo x foi espelhado.
function Mesa.calibrar(info)
  local c = info.carpete
  local x1, z1 = info.centro_mundo(c.x_min, c.y_min)
  local x2, z2 = info.centro_mundo(c.x_max, c.y_max)
  local calib = {
    origem_x = (x1 + x2) / 2,
    origem_z = (z1 + z2) / 2,
    espelhado = false,
    fonte = "carpete",
  }
  local p = info.portal
  if p ~= nil then
    local dx = p.x - calib.origem_x
    local px_layout = Mesa.PORTAL.x * Mesa.TILE_SCALE
    calib.espelhado = (dx > 0) == (px_layout < 0)
    -- O portal deve ficar a |PORTAL.x| tiles do centro (com folga de meio
    -- tile, map/object_layout.lua centra objetos e tiles de jeitos
    -- diferentes) e na linha do centro.
    local folga = Mesa.TILE_SCALE / 2
    if math.abs(math.abs(dx) - math.abs(px_layout)) > folga
      or math.abs(p.z - calib.origem_z) > folga then
      calib.aviso = string.format("portal em (%.1f, %.1f), longe do esperado em volta da origem (%.1f, %.1f)",
        p.x, p.z, calib.origem_x, calib.origem_z)
    end
  else
    calib.aviso = "sem portal: espelhamento não conferido"
  end
  return calib
end

-- Calibração de reserva, sem o carpete: só pelo portal. `espelhado` padrão é
-- true, o que foi medido no jogo.
function Mesa.calibrar_pelo_portal(px, pz, espelhado)
  if espelhado == nil then espelhado = true end
  local ox, oz = Mesa.origem_pelo_portal(px, pz, espelhado)
  return {
    origem_x = ox,
    origem_z = oz,
    espelhado = espelhado,
    fonte = "portal",
    aviso = "carpete não achado: origem pela posição do portal",
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

-- Centro da mesa (área de combate) no mundo.
function Mesa.centro_abs(calib)
  calib = calib_ou_atual(calib)
  return calib.origem_x, calib.origem_z
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
  local lado = Mesa.JOGADORES[lado_da_camera(jogador)]
  local sx, sz = 0, 0
  for _, e in ipairs(lado.criaturas) do
    local x, z = Mesa.posicao_abs(e.col, e.lin, calib)
    sx, sz = sx + x, sz + z
  end
  local n = #lado.criaturas
  local dx, dz = sx / n - calib.origem_x, sz / n - calib.origem_z
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

-- Espaços de um jogador em posição absoluta, ordenados da esquerda para a
-- direita de quem olha pela câmera desse jogador. Cada item:
-- { x, z, col, lin }.
local function espacos_abs(lista, jogador, calib)
  local rx, rz = Mesa.direita(Mesa.heading(jogador, calib))
  local espacos = {}
  for _, e in ipairs(lista) do
    local x, z = Mesa.posicao_abs(e.col, e.lin, calib)
    espacos[#espacos + 1] = { x = x, z = z, col = e.col, lin = e.lin, d = x * rx + z * rz }
  end
  table.sort(espacos, function(a, b) return a.d < b.d end)
  return espacos
end

-- Espaço de criatura n (1..6) do jogador, contado da esquerda de quem olha
-- pela câmera dele. Devolve x, z, col, lin.
function Mesa.espaco_criatura_abs(jogador, n, calib)
  calib = calib_ou_atual(calib)
  if calib == nil then return nil end
  local e = espacos_abs(Mesa.JOGADORES[jogador].criaturas, jogador, calib)[n]
  if e == nil then return nil end
  return e.x, e.z, e.col, e.lin
end

-- Espaço de estrutura n (1..2), mesma regra.
function Mesa.espaco_estrutura_abs(jogador, n, calib)
  calib = calib_ou_atual(calib)
  if calib == nil then return nil end
  local e = espacos_abs(Mesa.JOGADORES[jogador].estruturas, jogador, calib)[n]
  if e == nil then return nil end
  return e.x, e.z, e.col, e.lin
end

return Mesa
