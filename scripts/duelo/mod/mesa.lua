-- Geometria da mesa do duelo (US #29).
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
-- jogo (ver Mesa.origem_pelo_portal).
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
-- Atenção (a confirmar no jogo, US #30): o gerador espelha o eixo x de todo
-- static layout (flip_x = -1 em map/object_layout.lua, mesmo com
-- disable_transform). A mesa é simétrica, então só o lado do portal e a
-- ordem das colunas podem aparecer invertidos; como o portal é o único
-- elemento fora do eixo, a sua posição no mundo diz se houve espelhamento.

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

return Mesa
