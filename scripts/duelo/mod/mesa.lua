-- Geometria da mesa do duelo (US #29; calibração no jogo, US #30; layout
-- aprovado na #30 e refeito no bug #147 depois dos testes em jogo).
--
-- Este módulo é Lua 5.1 puro, sem nada do Don't Starve Together: ele é a
-- única fonte das posições da mesa. O static layout da geração do mundo
-- (duelo/mod/layouts/mesa.lua) é gerado a partir dele, e as US seguintes
-- (#33, criaturas nos espaços; #34, combate; #38, alvos válidos) leem daqui
-- onde fica cada espaço.
--
-- Mapa pedido pelo dono na terceira rodada do #147, visto pelo jogador 1,
-- que fica embaixo (R = paralelepípedos, K = carta, V = criatura,
-- E = estrutura, P = deck principal, X = deck extra, A/D = combate,
-- e = eventos, L = descarte, Z = destruídas):
--
--   R R R R R R R R R R R R R R R
--   R X R R R E R E R R R P R Z R     J2: extra, estruturas, deck | destruídas
--   R X R R R E R E R R R P R Z R
--   R R R R R R R R R R R R R R R
--   R K R K R K R K R K R K R L R     cartas J2 | descarte J2
--   R V R V R V R V R V R V R L R     criaturas J2
--   R R R R R R R R R R R R R R R
--   R D R D R D R D R D R D R e R     combate J2 | eventos
--   R A R A R A R A R A R A R e R     combate J1 | eventos
--   R R R R R R R R R R R R R R R
--   R V R V R V R V R V R V R L R     criaturas J1 | descarte J1
--   R K R K R K R K R K R K R L R     cartas J1
--   R R R R R R R R R R R R R R R
--   R P R R R E R E R R R X R Z R     J1: deck, estruturas, extra | destruídas
--   R P R R R E R E R R R X R Z R
--   R R R R R R R R R R R R R R R
--
-- A mesa tem 15 x 16 tiles:
--   * Espaço de criatura (6 por jogador): 2 tiles, a carta atrás e a
--     criatura na frente, virada para o centro.
--   * Combate: 6 pares de quadrados, um par na frente de cada coluna de
--     espaços (até 6 combates ao mesmo tempo). São duas fileiras de 6, a de
--     cada jogador do seu lado, coladas uma na outra, com paralelepípedos
--     entre as colunas. O quadrado k de um jogador fica na coluna do espaço
--     k dele (Mesa.espaco_combate(jogador, k)), de frente para o quadrado
--     7 - k do outro. No mapa, "A" são os quadrados do jogador 1 e "D" os
--     do jogador 2. Quem luta em cada par é assunto da US #34; aqui só o
--     espaço.
--   * Fileira de trás de cada jogador, com 2 tiles de altura, na numeração
--     dele: deck principal atrás do espaço 1, estruturas atrás dos espaços 3
--     e 4, deck extra atrás do espaço 6. Na estrutura vale a convenção do
--     espaço de criatura: o tile de trás é o da carta (`carta`) e o da
--     frente é onde a estrutura fica em pé (`frente`). Nos decks os 2 tiles
--     são um bloco só (`tras` e `frente`). Como o espaço n de um fica de
--     frente para o 7 - n do outro, o principal de um e o extra do outro
--     ficam na mesma coluna.
--   * Coluna dos eventos, na borda oposta ao portal, com 5 blocos de 2
--     tiles. No meio, alinhado às duas linhas de combate, o espaço de
--     eventos, UM só e neutro: os eventos dos dois jogadores vão para uma
--     pilha só e são sorteados pelo dado; o tile do lado do jogador 2 é a
--     pilha e o do lado do jogador 1 é o evento em vigor. De cada lado dele,
--     o descarte do jogador (nas linhas da carta e da criatura dele) e, na
--     ponta, as destruídas (nas linhas da fileira de trás, ao lado do deck
--     daquela ponta). A coluna sai de COLUNA_EVENTO, abaixo; mudar ali muda
--     o layout, a calibração, os contornos e os rótulos.
--   * Entre os espaços e na borda da mesa só há paralelepípedos: no DST a
--     borda de um turf invade o vizinho, e com o mesmo chão em volta o turf
--     que uma carta de Turf puser embaixo de um espaço aparece inteiro.
--     Só se encostam os 2 tiles de um mesmo bloco e os 2 quadrados de um
--     par de combate.
--   * Em volta da mesa, uma moldura de 1 tile de pedra e o pátio do portal.
--
-- Grade: 21 x 21 tiles, cada tile com TILE_SCALE = 4 unidades do mundo
-- (constants.lua). O layout precisa ser quadrado porque o gerador
-- (map/object_layout.lua, ReserveAndPlaceLayout) usa #ground como tamanho
-- dos dois eixos. Na largura cabem justos o pátio (3), a moldura (1), a mesa
-- (15) e a moldura (1), com a coluna 0 fora; na altura, a moldura (1), a
-- mesa (16) e a moldura (1), com 1 linha fora em cima e 2 embaixo. O
-- tamanho 21 x 21 é o que já foi gerado e confirmado no jogo com world_size
-- "small".
--
-- Objetos no centro de um tile (revalidado para esta grade): o leitor do
-- layout (map/static_layout.lua) converte a posição em pixels de um objeto
-- em tiles relativos ao centro (px / 64 - N / 2), e o gerador
-- (map/object_layout.lua) soma isso, com o sinal do espelhamento, ao canto
-- reservado mais N / 2 - 0,5. Um objeto posto no centro do tile k (pixel
-- (k + 0,5) * 64) dá canto + k ou canto + N - 1 - k: sempre um número inteiro
-- de tiles, com N par ou ímpar. Por isso o tamanho não precisou mudar, e o
-- portal e o spawn continuam no centro do tile (2, 10), como no layout
-- anterior (Mesa.PORTAL em tiles a partir do centro do layout, o centro do
-- tile (10, 10)). A conta não diz se objetos e chão usam a mesma contagem de
-- tiles inteiros; por isso a calibração tira a origem dos tiles do chão e
-- aceita o portal a até meio tile do esperado.
--
-- Convenção de coordenadas:
--   col = coluna do tile, 0..20, cresce para o leste (eixo x do mundo);
--   lin = linha do tile, 0..20, cresce para o sul (eixo z do mundo).
-- As posições em unidades do mundo devolvidas por este módulo são relativas
-- ao centro do tile (10, 10). Para ter posições absolutas, a calibração acha
-- a origem no jogo (Mesa.calibrar e, na falta das estruturas,
-- Mesa.calibrar_pelo_portal).
--
-- Mapa (linhas de cima para baixo; "." = fora, intransitável; "o" = pedra da
-- moldura e do pátio; "R" = paralelepípedos; "K" = carta; "V" = criatura;
-- "E" = estrutura; "P" = deck principal; "X" = deck extra; "A" = combate do
-- jogador 1; "D" = combate do jogador 2; "e" = eventos; "L" = descarte;
-- "Z" = destruídas; "@" = portal sobre a pedra do pátio):
--
--         col           1         2
--             012345678901234567890
--   lin  0    .....................
--        1    ....ooooooooooooooooo   moldura
--        2    ....oRRRRRRRRRRRRRRRo
--        3    ....oRXRRRERERRRPRZRo   fileira de trás do jogador 2 (norte): carta da estrutura, decks, destruídas
--        4    ....oRXRRRERERRRPRZRo   fileira de trás do jogador 2: estrutura em pé, decks, destruídas
--        5    ....oRRRRRRRRRRRRRRRo
--        6    ....oRKRKRKRKRKRKRLRo   cartas do jogador 2; descarte
--        7    ....oRVRVRVRVRVRVRLRo   criaturas do jogador 2; descarte
--        8    ....oRRRRRRRRRRRRRRRo
--        9    .ooooRDRDRDRDRDRDReRo   combate do jogador 2; pilha de eventos
--       10    .o@ooRARARARARARAReRo   combate do jogador 1; evento em vigor
--       11    .ooooRRRRRRRRRRRRRRRo
--       12    ....oRVRVRVRVRVRVRLRo   criaturas do jogador 1 (sul); descarte
--       13    ....oRKRKRKRKRKRKRLRo   cartas do jogador 1; descarte
--       14    ....oRRRRRRRRRRRRRRRo
--       15    ....oRPRRRERERRRXRZRo   fileira de trás do jogador 1: estrutura em pé, decks, destruídas
--       16    ....oRPRRRERERRRXRZRo   fileira de trás do jogador 1: carta da estrutura, decks, destruídas
--       17    ....oRRRRRRRRRRRRRRRo
--       18    ....ooooooooooooooooo   moldura
--       19    .....................
--       20    .....................
--
-- Pátio do portal: o multiplayer_portal e o spawnpoint_master ficam fora da
-- mesa, no centro de um pátio de pedra de 3 x 3 (colunas 1..3, linhas 9..11)
-- encostado na moldura oeste, na altura do combate, do lado oposto aos
-- eventos. O jogador nasce ali e anda até a mesa. No jogo, com o eixo x
-- espelhado, o pátio aparece a leste da mesa.
--
-- Tiles (índices de GROUND_TYPES em map/static_layout.lua, contados um a um;
-- Mesa.TILE). Todos são chão comum de andar (TileRanges.LAND em
-- tiledefs.lua). A ordem dos AddTile de tiledefs.lua é a ordem de desenho
-- ("these are done in RENDER order"): a borda de um tile avança sobre os
-- vizinhos que vêm antes dele.
--   * paralelepípedos = ROAD (índice 2; tiledefs.lua: "Road", textura
--     "cobblestone"). É o chão da mesa, entre os espaços e na borda dela. Na
--     ordem de desenho o ROAD vem antes de todos os outros tiles usados aqui
--     e de todos os turfs das cartas (ROAD, depois MARSH, ROCKY, ..., BRICK,
--     TILES, ..., WOODFLOOR, CHECKER, MOSAIC_GREY, CARPET2, CARPET), então a
--     borda de cada espaço e de cada turf avança sobre os paralelepípedos e
--     o tile do espaço aparece inteiro. Com o ROCKY de antes, o Pântano
--     (MARSH) ficava por baixo; com o ROAD não fica. O ROAD tem `roadways`
--     em tiledefs.lua: quem anda sobre ele ganha o bônus de velocidade de
--     estrada (components/locomotor.lua, GROUND_ROADWAYS; só locomotores com
--     `fasteronroad`, isto é, os jogadores). Só muda o andar do personagem
--     pela mesa.
--   * pedra = ROCKY (índice 3): a moldura em volta da mesa e o pátio do
--     portal. É o turf rochoso natural, com borda irregular, que avança um
--     pouco sobre os paralelepípedos da borda da mesa (nenhum espaço fica
--     nessa borda).
--   * carta e criatura sem turf jogado = CHECKER (índice 11; piso xadrez).
--     O WOODFLOOR foi descartado aqui porque é o turf da carta "Piso de
--     madeira": um espaço com essa carta ficaria igual a um espaço vazio.
--   * estrutura = MOSAIC_GREY (índice 47; mosaico cinza). Só os 8 tiles de
--     estrutura usam esse piso: é o padrão que a calibração procura.
--   * deck = WOODFLOOR (índice 9; piso de madeira). Neutro e diferente dos
--     outros; os decks não recebem carta de Turf, então a madeira não se
--     confunde com a carta "Piso de madeira". Não é MOSAIC_GREY para não
--     entrar no padrão da calibração.
--   * combate = CARPET (índice 10; tapete). Os dois quadrados de um par
--     formam um tapete de 1 x 2 no meio dos paralelepípedos, bem diferente
--     do xadrez dos espaços; o dono de cada quadrado vem do contorno.
--   * eventos = CARPET2 (índice 50; o outro tapete do jogo). Só os 2 tiles
--     do espaço de eventos usam esse piso: é o que a calibração procura para
--     saber de que lado a coluna de eventos ficou.
--   * descarte = TILES (índice 27; tiledefs.lua: "Glowing Tiles", os
--     ladrilhos das ruínas) e destruídas = BRICK (índice 25; "Glowing
--     Bricks", os tijolos das ruínas). São pisos feitos, diferentes entre si
--     e de todos os outros da mesa; nenhum dos dois é MOSAIC_GREY nem
--     CARPET2, que a calibração procura, e os mosaicos vermelho e azul
--     ficaram de fora para não se confundirem com as cores dos jogadores.
--   Os pisos dos decks, do combate, dos eventos, do descarte e das
--   destruídas são escolhas de aparência, a confirmar no jogo; cada um se
--   troca numa linha de Mesa.USO.
--
-- Ordem dos espaços: cada jogador conta os seus espaços da esquerda para a
-- direita olhando para o centro. Nas listas abaixo (que valem para o eixo x
-- espelhado, o caso medido no jogo), o espaço 1 do jogador 1 é a coluna 6 e
-- o 6 é a coluna 16; o do jogador 2 é a coluna 16 e o 6 é a coluna 6. Assim o
-- espaço n de um jogador fica de frente para o espaço 7 - n do outro (o
-- motor não depende disso: quem bloqueia quem é escolhido por jogada,
-- duelo/core/combate.lua). As estruturas (1 atrás do espaço 3, 2 atrás do
-- 4), os decks (principal atrás do 1, extra atrás do 6) e os quadrados de
-- combate (o k na frente do espaço k) seguem a numeração do dono.
--
-- Espelhamento (medido no jogo, US #30): o gerador espelha o eixo x de todo
-- static layout (flip_x = -1 em map/object_layout.lua, ReserveAndPlaceLayout,
-- mesmo com disable_transform; flip_y continua 1). As cartas, as estruturas,
-- os decks e o combate são simétricos no eixo x; a coluna de eventos e o
-- pátio do portal não são, e a posição deles no mundo diz se houve
-- espelhamento. O eixo z não tem nada que denuncie uma inversão, e ela não
-- importaria: só trocaria qual lado se chama "jogador 1".
--
-- Calibração (US #30, refeita no #147): no jogo,
-- scripts/duelo/mod/calibracao.lua acha o portal e, em volta dele, os tiles
-- de estrutura (MOSAIC_GREY) e os de eventos (CARPET2).
--   * Os 8 tiles de estrutura são o padrão inequívoco: só eles usam esse
--     piso, e formam 4 blocos de 1 x 2 nos cantos de um retângulo de 3 x 14
--     tiles (2 colunas e 13 linhas entre os centros dos tiles de fora).
--     Mesa.achar_estruturas confere o padrão (e recusa a mesa girada,
--     14 x 3). O centro do retângulo é o centro do combate e da mesa nas
--     linhas (Mesa.CENTRO); a origem (centro do layout) sai dele.
--   * O espelhamento sai da própria mesa: os 2 tiles de eventos ficam de um
--     lado só do retângulo das estruturas (Mesa.achar_eventos). Assim a
--     geometria não depende do portal, que só serve para dizer onde procurar
--     e para conferir. Sem os tiles de eventos, o espelhamento sai do lado
--     do portal, com aviso; sem os dois, vale o medido (espelhado).
-- O resultado fica em Mesa.calibracao (servidor e clientes) e dá as posições
-- absolutas (Mesa.espaco_criatura_abs, Mesa.espaco_estrutura_abs,
-- Mesa.espaco_deck_abs, Mesa.espaco_combate_abs, Mesa.espaco_descarte_abs,
-- Mesa.espaco_destruidas_abs, Mesa.espaco_evento_abs, Mesa.centro_abs,
-- Mesa.centro_da_mesa_abs, Mesa.rotulo_combate_abs, Mesa.tiles_dos_espacos).
--
-- Esquerda e direita de quem olha: o espelhamento troca leste e oeste, e a
-- tela do DST não mostra o +x à direita (cameras/followcamera.lua,
-- GetRightVec: a direita da tela é (cos(h + 90), sin(h + 90)) para o
-- heading h). Por isso a numeração absoluta não confia na coluna: os espaços
-- de cada jogador são ordenados pela projeção na direita da câmera dele
-- (Mesa.heading). No caso medido (espelhado) a ordem dá a mesma das listas de
-- colunas abaixo; sem espelhamento, daria a inversa, e a numeração absoluta
-- continuaria certa para quem olha (os decks, as estruturas e os quadrados
-- de combate acompanham: o deck principal é sempre o que fica atrás do
-- espaço 1 de quem olha, e o quadrado de combate k o que fica na frente do
-- espaço k).

local Mesa = {}

Mesa.TILE_SCALE = 4
Mesa.LARGURA = 21 -- colunas (eixo x)
Mesa.ALTURA = 21 -- linhas (eixo z)

-- Índice de cada tile na ordem GROUND_TYPES de map/static_layout.lua
-- (1 = primeiro da lista). 0 não é um tile: o gerador deixa o terreno como
-- está, isto é, IMPASSABLE da sala Blank, que é o que fica fora da mesa.
-- Conferido em map/static_layout.lua, contando um a um:
--   1 IMPASSABLE, 2 ROAD, 3 ROCKY, 9 WOODFLOOR, 10 CARPET, 11 CHECKER,
--   25 BRICK, 27 TILES, 47 MOSAIC_GREY, 48 MOSAIC_RED, 49 MOSAIC_BLUE,
--   50 CARPET2.
Mesa.TILE = {
  FORA = 0,
  IMPASSAVEL = 1,
  PARALELEPIPEDO = 2,
  PEDRA = 3,
  MADEIRA = 9,
  TAPETE = 10,
  XADREZ = 11,
  TIJOLO = 25,
  LADRILHO = 27,
  MOSAICO_CINZA = 47,
  TAPETE2 = 50,
}

-- Nome do tile no jogo (WORLD_TILES de constants.lua/tiledefs.lua) de cada
-- índice acima: é o que a calibração compara com TheWorld.Map:GetTile.
Mesa.WORLD_TILE = {
  PARALELEPIPEDO = "ROAD",
  PEDRA = "ROCKY",
  MADEIRA = "WOODFLOOR",
  TAPETE = "CARPET",
  XADREZ = "CHECKER",
  TIJOLO = "BRICK",
  LADRILHO = "TILES",
  MOSAICO_CINZA = "MOSAIC_GREY",
  TAPETE2 = "CARPET2",
}

-- Que tile cada parte da mesa usa. A calibração exige que "estrutura" e
-- "evento" tenham cada um um piso que mais nada usa.
Mesa.USO = {
  fora = "FORA",
  moldura = "PEDRA",
  patio = "PEDRA",
  chao = "PARALELEPIPEDO",
  carta = "XADREZ",
  criatura = "XADREZ",
  estrutura = "MOSAICO_CINZA",
  deck = "MADEIRA",
  combate = "TAPETE",
  evento = "TAPETE2",
  descarte = "LADRILHO",
  destruidas = "TIJOLO",
}

-- Retângulos, em tiles, inclusivos.
Mesa.MESA = { col_min = 5, col_max = 19, lin_min = 2, lin_max = 17 } -- 15 x 16
Mesa.MOLDURA = 1 -- tiles de pedra em volta da mesa
Mesa.PATIO = { col_min = 1, col_max = 3, lin_min = 9, lin_max = 11 } -- pátio do portal

-- Colunas dos 6 espaços de criatura, da esquerda para a direita do jogador 1
-- no caso espelhado (ver o cabeçalho).
local COLUNAS_CRIATURA = { 6, 8, 10, 12, 14, 16 }

-- Linhas de cada lado: a fileira de trás (2 tiles: `fundo` é o de trás,
-- longe do centro, e `fundo_frente` o da frente), a carta, a criatura e o
-- quadrado de combate.
local LINHAS = {
  [1] = { fundo = 16, fundo_frente = 15, carta = 13, criatura = 12, combate = 10 },
  [2] = { fundo = 3, fundo_frente = 4, carta = 6, criatura = 7, combate = 9 },
}

-- Atrás de que espaço de criatura (na numeração do próprio jogador) fica
-- cada coisa da fileira de trás.
local ESPACO_DA_ESTRUTURA = { 3, 4 }
local ESPACO_DO_DECK = { principal = 1, extra = 6 }
Mesa.DECKS = { "principal", "extra" }

-- Coluna dos eventos, do lado oposto ao portal, com 1 coluna de
-- paralelepípedos entre ela e a última coluna de cartas. De cima para baixo
-- ela leva as destruídas e o descarte do jogador 2, o espaço de eventos (nas
-- duas linhas de combate) e o descarte e as destruídas do jogador 1. No
-- espaço de eventos, o tile do lado do jogador 2 é a pilha e o do lado do
-- jogador 1 é o evento em vigor. Para mudar o lado, basta trocar esta coluna
-- (e Mesa.MESA, se ela sair da mesa).
local COLUNA_EVENTO = 18
local LINHAS_EVENTO = { pilha = LINHAS[2].combate, em_vigor = LINHAS[1].combate }
Mesa.PARTES_DO_EVENTO = { "pilha", "em_vigor" }

-- Partes (tiles) de cada bloco de 2 tiles, de trás para a frente.
Mesa.PARTES = {
  criatura = { "carta", "criatura" },
  estrutura = { "carta", "frente" },
  deck = { "tras", "frente" },
  descarte = { "tras", "frente" },
  destruidas = { "tras", "frente" },
}

-- Centro do combate e da mesa nas linhas: o ponto entre as duas fileiras de
-- combate, na coluna do meio das 6 colunas de criatura (uma coluna de
-- paralelepípedos, entre os pares 3 e 4). É o centro do retângulo das
-- estruturas e o ponto de onde sai o heading das câmeras.
Mesa.CENTRO = {
  col = (COLUNAS_CRIATURA[1] + COLUNAS_CRIATURA[#COLUNAS_CRIATURA]) / 2,
  lin = (LINHAS[1].combate + LINHAS[2].combate) / 2,
}

-- Centro geométrico da mesa 15 x 16 (alvo da câmera): com a coluna de
-- eventos, fica 1 coluna para o lado dela em relação ao combate.
Mesa.CENTRO_DA_MESA = {
  col = (Mesa.MESA.col_min + Mesa.MESA.col_max) / 2,
  lin = (Mesa.MESA.lin_min + Mesa.MESA.lin_max) / 2,
}

-- Onde fica o rótulo "Combate": na coluna de paralelepípedos da borda da
-- mesa do lado do portal (a que fica ao lado da primeira coluna de espaços),
-- entre as duas fileiras de combate. Não fica sobre os quadrados porque é
-- em cima deles que as criaturas duelam.
Mesa.ROTULO_COMBATE = { col = Mesa.MESA.col_min, lin = Mesa.CENTRO.lin }

local function invertida(lista)
  local r = {}
  for i = #lista, 1, -1 do r[#r + 1] = lista[i] end
  return r
end

-- Um espaço de criatura: o tile da carta (atrás) e o da criatura (na
-- frente), na mesma coluna.
local function espaco_de_criatura(col, linhas)
  return {
    col = col,
    carta = { col = col, lin = linhas.carta },
    criatura = { col = col, lin = linhas.criatura },
  }
end

-- Um bloco de 2 tiles numa coluna: `atras` e `frente` são os nomes das
-- partes (Mesa.PARTES) e lin_atras e lin_frente as linhas.
local function bloco(col, atras, lin_atras, frente, lin_frente)
  return {
    col = col,
    [atras] = { col = col, lin = lin_atras },
    [frente] = { col = col, lin = lin_frente },
  }
end

local function lado(jogador, nome, colunas_criatura)
  local linhas = LINHAS[jogador]
  local criaturas, estruturas, decks, combate = {}, {}, {}, {}
  for i, col in ipairs(colunas_criatura) do
    criaturas[i] = espaco_de_criatura(col, linhas)
    combate[i] = { col = col, lin = linhas.combate }
  end
  for i, n in ipairs(ESPACO_DA_ESTRUTURA) do
    estruturas[i] = bloco(criaturas[n].col, "carta", linhas.fundo, "frente", linhas.fundo_frente)
  end
  for qual, n in pairs(ESPACO_DO_DECK) do
    decks[qual] = bloco(criaturas[n].col, "tras", linhas.fundo, "frente", linhas.fundo_frente)
  end
  return {
    lado = nome,
    criaturas = criaturas,
    estruturas = estruturas,
    decks = decks,
    combate = combate,
    descarte = bloco(COLUNA_EVENTO, "tras", linhas.carta, "frente", linhas.criatura),
    destruidas = bloco(COLUNA_EVENTO, "tras", linhas.fundo, "frente", linhas.fundo_frente),
  }
end

Mesa.JOGADORES = {
  [1] = lado(1, "sul", COLUNAS_CRIATURA),
  [2] = lado(2, "norte", invertida(COLUNAS_CRIATURA)),
}

-- Espaço de eventos, neutro: { pilha = {col, lin}, em_vigor = {col, lin} }.
Mesa.EVENTO = {
  pilha = { col = COLUNA_EVENTO, lin = LINHAS_EVENTO.pilha },
  em_vigor = { col = COLUNA_EVENTO, lin = LINHAS_EVENTO.em_vigor },
}

-- Portal (multiplayer_portal e o spawnpoint_master junto dele), em tiles,
-- relativo ao centro do layout: centro do tile (2, 10), no meio do pátio.
Mesa.PORTAL = { x = -8, z = 0 }

local function dentro(ret, col, lin, folga)
  folga = folga or 0
  return col >= ret.col_min - folga and col <= ret.col_max + folga
    and lin >= ret.lin_min - folga and lin <= ret.lin_max + folga
end

-- Devolve o uso do tile ("carta", "criatura", "estrutura", "deck",
-- "combate", "evento", "descarte", "destruidas", "chao", "moldura", "patio"
-- ou "fora") e, quando é um espaço:
--   * o jogador (0 no espaço de eventos, que é neutro);
--   * o número do espaço na ordem das listas do layout (nos decks,
--     "principal" ou "extra"; no combate, o número do quadrado; nos eventos,
--     "pilha" ou "em_vigor"; no descarte e nas destruídas, nada);
--   * a parte do bloco de 2 tiles (Mesa.PARTES; nada no combate e nos
--     eventos).
function Mesa.uso_em(col, lin)
  local function parte_em(e, uso)
    for _, parte in ipairs(Mesa.PARTES[uso]) do
      if e[parte].col == col and e[parte].lin == lin then return parte end
    end
    return nil
  end
  for jogador, l in ipairs(Mesa.JOGADORES) do
    for n, e in ipairs(l.criaturas) do
      local parte = parte_em(e, "criatura")
      if parte ~= nil then return parte, jogador, n, parte end
    end
    for n, e in ipairs(l.estruturas) do
      local parte = parte_em(e, "estrutura")
      if parte ~= nil then return "estrutura", jogador, n, parte end
    end
    for _, qual in ipairs(Mesa.DECKS) do
      local parte = parte_em(l.decks[qual], "deck")
      if parte ~= nil then return "deck", jogador, qual, parte end
    end
    for k, e in ipairs(l.combate) do
      if e.col == col and e.lin == lin then return "combate", jogador, k end
    end
    for _, uso in ipairs({ "descarte", "destruidas" }) do
      local parte = parte_em(l[uso], uso)
      if parte ~= nil then return uso, jogador, nil, parte end
    end
  end
  for _, parte in ipairs(Mesa.PARTES_DO_EVENTO) do
    local e = Mesa.EVENTO[parte]
    if e.col == col and e.lin == lin then return "evento", 0, parte end
  end
  if dentro(Mesa.MESA, col, lin) then return "chao" end
  if dentro(Mesa.MESA, col, lin, Mesa.MOLDURA) then return "moldura" end
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
local SIMBOLO = { fora = ".", moldura = "o", patio = "o", chao = "R", carta = "K", criatura = "V",
  estrutura = "E", evento = "e", descarte = "L", destruidas = "Z" }
local SIMBOLO_DECK = { principal = "P", extra = "X" }
local SIMBOLO_COMBATE = { [1] = "A", [2] = "D" }

function Mesa.mapa_ascii()
  local linhas = {}
  local pcol = math.floor(Mesa.PORTAL.x + Mesa.LARGURA / 2)
  local plin = math.floor(Mesa.PORTAL.z + Mesa.ALTURA / 2)
  for lin = 0, Mesa.ALTURA - 1 do
    local s = {}
    for col = 0, Mesa.LARGURA - 1 do
      local uso, jogador, n = Mesa.uso_em(col, lin)
      local c = SIMBOLO[uso]
      if uso == "deck" then c = SIMBOLO_DECK[n] end
      if uso == "combate" then c = SIMBOLO_COMBATE[jogador] end
      if col == pcol and lin == plin then c = "@" end
      s[#s + 1] = c
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
-- { col, carta = {col, lin}, criatura = {col, lin} }.
function Mesa.espaco_criatura(jogador, n)
  return Mesa.JOGADORES[jogador].criaturas[n]
end

-- Espaço de estrutura n (1..2) de um jogador, na ordem do layout:
-- { col, carta = {col, lin}, frente = {col, lin} }. Como no espaço de
-- criatura, o tile de trás é o da carta e o da frente é onde a estrutura
-- fica em pé.
function Mesa.espaco_estrutura(jogador, n)
  return Mesa.JOGADORES[jogador].estruturas[n]
end

-- Deck de um jogador, `qual` = "principal" ou "extra":
-- { col, tras = {col, lin}, frente = {col, lin} }, um bloco só de 2 tiles.
function Mesa.espaco_deck(jogador, qual)
  return Mesa.JOGADORES[jogador].decks[qual]
end

-- Quadrado de combate k (1..6) de um jogador, na ordem do layout: {col, lin}.
-- O quadrado k fica na coluna do espaço de criatura k do mesmo jogador, de
-- frente para o quadrado 7 - k do outro.
function Mesa.espaco_combate(jogador, k)
  return Mesa.JOGADORES[jogador].combate[k]
end

-- Descarte de um jogador: { col, tras = {col, lin}, frente = {col, lin} },
-- na coluna dos eventos, nas linhas da carta e da criatura dele.
function Mesa.espaco_descarte(jogador)
  return Mesa.JOGADORES[jogador].descarte
end

-- Destruídas de um jogador: { col, tras = {col, lin}, frente = {col, lin} },
-- na coluna dos eventos, nas linhas da fileira de trás dele.
function Mesa.espaco_destruidas(jogador)
  return Mesa.JOGADORES[jogador].destruidas
end

-- Espaço de eventos (um só, dos dois jogadores):
-- { pilha = {col, lin}, em_vigor = {col, lin} }.
function Mesa.espaco_evento()
  return Mesa.EVENTO
end

-- ---------------------------------------------------------------------------
-- Calibração no jogo (US #30, refeita no #147)
-- ---------------------------------------------------------------------------

-- Padrão das estruturas: 4 blocos de 1 x 2 tiles (8 tiles), nos cantos de um
-- retângulo. Distância, em tiles, entre as colunas (10 e 12: 2) e entre as
-- linhas de fora (3 e 16: 13), e a altura de cada bloco (2).
Mesa.ESTRUTURAS_DX = math.abs(Mesa.JOGADORES[1].estruturas[2].col - Mesa.JOGADORES[1].estruturas[1].col)
Mesa.ESTRUTURAS_DZ = LINHAS[1].fundo - LINHAS[2].fundo
Mesa.ESTRUTURAS_ALTURA = #Mesa.PARTES.estrutura
Mesa.TILES_DE_ESTRUTURA = 2 * #ESPACO_DA_ESTRUTURA * Mesa.ESTRUTURAS_ALTURA

-- Centro do retângulo das estruturas, em tiles do layout: (11; 9,5), o
-- centro do combate (Mesa.CENTRO).
local CENTRO_ESTRUTURAS = {
  col = (Mesa.JOGADORES[1].estruturas[1].col + Mesa.JOGADORES[1].estruturas[2].col) / 2,
  lin = (LINHAS[1].fundo + LINHAS[2].fundo) / 2,
}

-- Colunas, com sinal, do centro das estruturas até a coluna de eventos
-- (+7: os eventos ficam a leste no layout).
Mesa.EVENTOS_DX = COLUNA_EVENTO - CENTRO_ESTRUTURAS.col

-- Calibração em uso neste lado (servidor ou cliente); nil até o jogo
-- calibrar. Campos: origem_x, origem_z (centro do layout em unidades do
-- mundo), espelhado (eixo x espelhado), fonte ("estruturas" ou "portal"),
-- espelhamento ("eventos", "portal" ou "padrao": de onde saiu `espelhado`;
-- só no servidor) e aviso (texto ou nil).
Mesa.calibracao = nil

function Mesa.definir_calibracao(calib)
  Mesa.calibracao = calib
  return calib
end

-- Tira os repetidos de uma lista de tiles { x, y }.
local function sem_repetidos(tiles)
  local vistos, unicos = {}, {}
  for _, t in ipairs(tiles or {}) do
    local chave = t.x .. "," .. t.y
    if not vistos[chave] then
      vistos[chave] = true
      unicos[#unicos + 1] = t
    end
  end
  return unicos
end

-- Recebe a lista dos tiles de estrutura (MOSAIC_GREY) achados em volta do
-- portal, cada um { x = tile_x, y = tile_y } (coordenadas de TheWorld.Map),
-- e devolve o retângulo { x_min, x_max, y_min, y_max } que os contém se eles
-- forem exatamente os 8 tiles do padrão: 4 blocos de 1 x ESTRUTURAS_ALTURA
-- nos cantos de um retângulo com ESTRUTURAS_DX colunas e ESTRUTURAS_DZ
-- linhas entre os tiles de fora. Senão devolve nil e o motivo.
function Mesa.achar_estruturas(tiles)
  if tiles == nil or #tiles == 0 then return nil, "nenhum tile de estrutura" end
  local unicos = sem_repetidos(tiles)
  if #unicos ~= Mesa.TILES_DE_ESTRUTURA then
    return nil, string.format("%d tiles de estrutura, esperados %d", #unicos, Mesa.TILES_DE_ESTRUTURA)
  end
  local r = { x_min = math.huge, x_max = -math.huge, y_min = math.huge, y_max = -math.huge }
  local achados = {}
  for _, t in ipairs(unicos) do
    if t.x < r.x_min then r.x_min = t.x end
    if t.x > r.x_max then r.x_max = t.x end
    if t.y < r.y_min then r.y_min = t.y end
    if t.y > r.y_max then r.y_max = t.y end
    achados[t.x .. "," .. t.y] = true
  end
  local dx, dy = r.x_max - r.x_min, r.y_max - r.y_min
  if dx == Mesa.ESTRUTURAS_DZ and dy == Mesa.ESTRUTURAS_DX then
    return nil, "estruturas giradas (eixos trocados): o gerador girou a mesa"
  end
  if dx ~= Mesa.ESTRUTURAS_DX or dy ~= Mesa.ESTRUTURAS_DZ then
    return nil, string.format("estruturas a %d x %d tiles uma da outra, esperado %d x %d",
      dx, dy, Mesa.ESTRUTURAS_DX, Mesa.ESTRUTURAS_DZ)
  end
  -- Os tiles têm de ser os dos 4 blocos: nas duas colunas de fora, as
  -- ESTRUTURAS_ALTURA linhas de cada ponta.
  for _, x in ipairs({ r.x_min, r.x_max }) do
    for i = 0, Mesa.ESTRUTURAS_ALTURA - 1 do
      if not achados[x .. "," .. (r.y_min + i)] or not achados[x .. "," .. (r.y_max - i)] then
        return nil, string.format("os %d tiles de estrutura não formam 4 blocos de 1 x %d nos cantos",
          Mesa.TILES_DE_ESTRUTURA, Mesa.ESTRUTURAS_ALTURA)
      end
    end
  end
  return r
end

-- Recebe a lista dos tiles de eventos (CARPET2) achados em volta do portal e
-- o retângulo das estruturas, e devolve o lado em que a coluna de eventos
-- ficou: +1 se o x dela é maior que o do centro das estruturas, -1 se é
-- menor. Os tiles têm de ser exatamente os do espaço de eventos: na mesma
-- coluna, a |EVENTOS_DX| colunas do centro das estruturas e nas linhas que o
-- layout diz (contadas do meio do retângulo, para valer também com o eixo z
-- invertido). Senão devolve nil e o motivo.
function Mesa.achar_eventos(tiles, estruturas)
  local unicos = sem_repetidos(tiles)
  local esperados = #Mesa.PARTES_DO_EVENTO
  if #unicos ~= esperados then
    return nil, string.format("%d tiles de eventos, esperados %d", #unicos, esperados)
  end
  local cx = (estruturas.x_min + estruturas.x_max) / 2
  local cy = (estruturas.y_min + estruturas.y_max) / 2
  local dx = unicos[1].x - cx
  local faltam = {}
  for _, parte in ipairs(Mesa.PARTES_DO_EVENTO) do
    local d = math.abs(Mesa.EVENTO[parte].lin - CENTRO_ESTRUTURAS.lin)
    faltam[d] = (faltam[d] or 0) + 1
  end
  for _, t in ipairs(unicos) do
    if t.x - cx ~= dx then return nil, "tiles de eventos em colunas diferentes" end
    local d = math.abs(t.y - cy)
    if (faltam[d] or 0) == 0 then return nil, "tiles de eventos fora das linhas do combate" end
    faltam[d] = faltam[d] - 1
  end
  if math.abs(dx) ~= math.abs(Mesa.EVENTOS_DX) then
    return nil, string.format("eventos a %s colunas do centro das estruturas, esperado %s",
      tostring(math.abs(dx)), tostring(math.abs(Mesa.EVENTOS_DX)))
  end
  return dx > 0 and 1 or -1
end

local function juntar(aviso, novo)
  if aviso == nil then return novo end
  return aviso .. "; " .. novo
end

-- Calibração pura. `info`:
--   estruturas: retângulo de Mesa.achar_estruturas (coordenadas de tile);
--   centro_mundo(tile_x, tile_y): devolve x, z do centro do tile em unidades
--     do mundo (no jogo, TheWorld.Map:GetTileCenterPoint);
--   eventos: lista dos tiles de eventos achados, { x, y } (pode faltar);
--   portal: { x, z }, posição do multiplayer_portal no mundo (pode faltar).
-- O centro do retângulo das estruturas é Mesa.CENTRO, o centro da mesa e do
-- combate. O espelhamento sai do lado em que a coluna de
-- eventos ficou (no layout, a leste do centro: se no mundo ela aparece com x
-- menor, o eixo x foi espelhado). Sem os eventos, sai do lado do portal (a
-- oeste no layout), com aviso; sem os dois, vale o medido no jogo
-- (espelhado). A origem é o centro do layout, que fica a
-- (CENTRO.col - 10, CENTRO.lin - 10) tiles do centro das estruturas.
function Mesa.calibrar(info)
  local r = info.estruturas
  local x1, z1 = info.centro_mundo(r.x_min, r.y_min)
  local x2, z2 = info.centro_mundo(r.x_max, r.y_max)
  local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
  -- Sentido do mundo em que o x cresce com o x do tile (no jogo, +1).
  local sentido = (x2 >= x1) and 1 or -1
  local calib = { fonte = "estruturas" }

  -- Centro das estruturas e portal, em unidades, a partir do centro do layout.
  local ex_layout, ez_layout = Mesa.centro_do_tile(CENTRO_ESTRUTURAS.col, CENTRO_ESTRUTURAS.lin)
  local px_layout, pz_layout = Mesa.posicao_do_portal()

  local p = info.portal
  local pelo_portal
  if p ~= nil then
    pelo_portal = (p.x - cx > 0) ~= (px_layout - ex_layout > 0)
  end

  local lado_eventos, motivo
  if info.eventos ~= nil then
    lado_eventos, motivo = Mesa.achar_eventos(info.eventos, r)
  else
    motivo = "tiles de eventos não informados"
  end

  if lado_eventos ~= nil then
    calib.espelhado = (lado_eventos * sentido > 0) ~= (Mesa.EVENTOS_DX > 0)
    calib.espelhamento = "eventos"
    if pelo_portal ~= nil and pelo_portal ~= calib.espelhado then
      calib.aviso = juntar(calib.aviso, "o lado do portal não bate com o da coluna de eventos")
    end
  elseif pelo_portal ~= nil then
    calib.espelhado = pelo_portal
    calib.espelhamento = "portal"
    calib.aviso = juntar(calib.aviso, "coluna de eventos não achada (" .. motivo .. "): espelhamento pelo lado do portal")
  else
    calib.espelhado = true
    calib.espelhamento = "padrao"
    calib.aviso = juntar(calib.aviso, "sem coluna de eventos (" .. motivo .. ") e sem portal: espelhamento não conferido")
  end

  calib.origem_x = cx - (calib.espelhado and -ex_layout or ex_layout)
  calib.origem_z = cz - ez_layout

  if p ~= nil then
    -- O portal deve ficar onde o layout diz, com folga de meio tile
    -- (map/object_layout.lua centra objetos e tiles de jeitos diferentes).
    local folga = Mesa.TILE_SCALE / 2
    local esperado_x = calib.origem_x + (calib.espelhado and -px_layout or px_layout)
    if math.abs(p.x - esperado_x) > folga or math.abs(p.z - calib.origem_z - pz_layout) > folga then
      calib.aviso = juntar(calib.aviso, string.format(
        "portal em (%.1f, %.1f), longe do esperado em volta da origem (%.1f, %.1f)",
        p.x, p.z, calib.origem_x, calib.origem_z))
    end
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
    espelhamento = "padrao",
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

-- Posição absoluta do centro do tile (col, lin) com a calibração. Aceita
-- meio tile (lin = 9,5 é a junção das linhas 9 e 10).
function Mesa.posicao_abs(col, lin, calib)
  calib = calib_ou_atual(calib)
  return Mesa.posicao(col, lin, calib.origem_x, calib.origem_z, calib.espelhado)
end

-- Centro do combate (entre as duas fileiras, no meio das 6 colunas), no
-- mundo.
function Mesa.centro_abs(calib)
  calib = calib_ou_atual(calib)
  return Mesa.posicao_abs(Mesa.CENTRO.col, Mesa.CENTRO.lin, calib)
end

-- Centro geométrico da mesa 15 x 16, no mundo (alvo da câmera).
function Mesa.centro_da_mesa_abs(calib)
  calib = calib_ou_atual(calib)
  return Mesa.posicao_abs(Mesa.CENTRO_DA_MESA.col, Mesa.CENTRO_DA_MESA.lin, calib)
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
-- vai do centro (entre as duas fileiras de combate, na coluna do meio das
-- criaturas) até a fileira de criaturas do jogador. Com o eixo z não
-- espelhado, o jogador 1 (sul, z maior) dá 90 e o jogador 2 dá 270.
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
-- pela câmera dele. Devolve { carta, criatura }, cada um { x, z, col, lin }
-- em posição absoluta; nil sem calibração ou sem espaço.
function Mesa.espaco_criatura_abs(jogador, n, calib)
  calib = calib_ou_atual(calib)
  if calib == nil then return nil end
  local item = ordenados(Mesa.JOGADORES[jogador].criaturas, jogador, calib)[n]
  if item == nil then return nil end
  return {
    carta = tile_abs(item.e.carta, calib),
    criatura = tile_abs(item.e.criatura, calib),
  }
end

-- O bloco da lista que fica atrás (na mesma coluna) do espaço de criatura n
-- da numeração da câmera.
local function atras_do_espaco(lista, jogador, n, calib)
  local espaco = Mesa.espaco_criatura_abs(jogador, n, calib)
  if espaco == nil then return nil end
  for _, e in pairs(lista) do
    if e.col == espaco.carta.col then return e end
  end
  return nil
end

-- Bloco de 2 tiles em posição absoluta: cada parte { x, z, col, lin } e
-- centro = { x, z }, a junção dos dois tiles.
local function bloco_abs(e, partes, calib)
  local r = { centro = { x = 0, z = 0 } }
  for _, parte in ipairs(partes) do
    r[parte] = tile_abs(e[parte], calib)
    r.centro.x = r.centro.x + r[parte].x / #partes
    r.centro.z = r.centro.z + r[parte].z / #partes
  end
  return r
end

-- Espaço de estrutura n (1..2): a 1 fica atrás do espaço 3 e a 2 atrás do 4
-- de quem olha. Devolve { carta, frente }, cada um { x, z, col, lin } (a
-- carta no tile de trás, a estrutura em pé no da frente), e centro = { x, z }.
function Mesa.espaco_estrutura_abs(jogador, n, calib)
  calib = calib_ou_atual(calib)
  if calib == nil or ESPACO_DA_ESTRUTURA[n] == nil then return nil end
  local e = atras_do_espaco(Mesa.JOGADORES[jogador].estruturas, jogador, ESPACO_DA_ESTRUTURA[n], calib)
  if e == nil then return nil end
  return bloco_abs(e, Mesa.PARTES.estrutura, calib)
end

-- Deck do jogador, `qual` = "principal" (atrás do espaço 1 de quem olha) ou
-- "extra" (atrás do 6). Devolve { tras, frente }, cada um { x, z, col, lin },
-- e centro = { x, z } (a junção dos 2 tiles, onde fica o rótulo).
function Mesa.espaco_deck_abs(jogador, qual, calib)
  calib = calib_ou_atual(calib)
  if calib == nil or ESPACO_DO_DECK[qual] == nil then return nil end
  local e = atras_do_espaco(Mesa.JOGADORES[jogador].decks, jogador, ESPACO_DO_DECK[qual], calib)
  if e == nil then return nil end
  return bloco_abs(e, Mesa.PARTES.deck, calib)
end

-- Quadrado de combate k (1..6) do jogador, na numeração de quem olha pela
-- câmera dele: o quadrado k fica na coluna do espaço de criatura k, de
-- frente para o quadrado 7 - k do outro. Devolve x, z, col, lin.
function Mesa.espaco_combate_abs(jogador, k, calib)
  calib = calib_ou_atual(calib)
  if calib == nil or Mesa.JOGADORES[jogador] == nil then return nil end
  local e = atras_do_espaco(Mesa.JOGADORES[jogador].combate, jogador, k, calib)
  if e == nil then return nil end
  local t = tile_abs(e, calib)
  return t.x, t.z, t.col, t.lin
end

-- Descarte do jogador. Devolve { tras, frente }, cada um { x, z, col, lin },
-- e centro = { x, z }.
function Mesa.espaco_descarte_abs(jogador, calib)
  calib = calib_ou_atual(calib)
  if calib == nil or Mesa.JOGADORES[jogador] == nil then return nil end
  return bloco_abs(Mesa.JOGADORES[jogador].descarte, Mesa.PARTES.descarte, calib)
end

-- Destruídas do jogador. Devolve { tras, frente }, cada um { x, z, col, lin },
-- e centro = { x, z }.
function Mesa.espaco_destruidas_abs(jogador, calib)
  calib = calib_ou_atual(calib)
  if calib == nil or Mesa.JOGADORES[jogador] == nil then return nil end
  return bloco_abs(Mesa.JOGADORES[jogador].destruidas, Mesa.PARTES.destruidas, calib)
end

-- Espaço de eventos (neutro). Devolve { pilha, em_vigor }, cada um
-- { x, z, col, lin }, e centro = { x, z } (o ponto entre os dois tiles, onde
-- fica o rótulo).
function Mesa.espaco_evento_abs(calib)
  calib = calib_ou_atual(calib)
  if calib == nil then return nil end
  return bloco_abs(Mesa.EVENTO, Mesa.PARTES_DO_EVENTO, calib)
end

-- Ponto do rótulo "Combate" no mundo (Mesa.ROTULO_COMBATE). Devolve x, z.
function Mesa.rotulo_combate_abs(calib)
  calib = calib_ou_atual(calib)
  if calib == nil then return nil end
  return Mesa.posicao_abs(Mesa.ROTULO_COMBATE.col, Mesa.ROTULO_COMBATE.lin, calib)
end

-- Todos os tiles de espaço em posição absoluta, com a numeração da câmera:
-- 12 cartas, 12 criaturas, 8 de estrutura, 8 de deck, 12 de combate, 4 de
-- descarte, 4 de destruídas e 2 de eventos (62). Cada item:
-- { x, z, col, lin, jogador, tipo, n, parte }, com
--   tipo "carta" | "criatura": n = número do espaço;
--   tipo "estrutura": n = número da estrutura, parte = "carta" | "frente";
--   tipo "deck": n = "principal" | "extra", parte = "tras" | "frente";
--   tipo "combate": n = número do quadrado (o do espaço da mesma coluna);
--   tipo "descarte" | "destruidas": sem n, parte = "tras" | "frente";
--   tipo "evento": jogador = 0 (neutro), n = "pilha" | "em_vigor".
-- O `tipo` é o uso do tile (Mesa.USO[tipo] dá o piso esperado).
function Mesa.tiles_dos_espacos(calib)
  calib = calib_ou_atual(calib)
  if calib == nil then return nil end
  local lista = {}
  local function por(t, jogador, tipo, n, parte)
    lista[#lista + 1] = { x = t.x, z = t.z, col = t.col, lin = t.lin, jogador = jogador, tipo = tipo, n = n,
      parte = parte }
  end
  local function por_bloco(e, jogador, tipo, n)
    for _, parte in ipairs(Mesa.PARTES[tipo]) do por(e[parte], jogador, tipo, n, parte) end
  end
  for p = 1, 2 do
    for n = 1, #Mesa.JOGADORES[p].criaturas do
      local e = Mesa.espaco_criatura_abs(p, n, calib)
      for _, tipo in ipairs(Mesa.PARTES.criatura) do por(e[tipo], p, tipo, n) end
    end
    for n = 1, #Mesa.JOGADORES[p].estruturas do
      por_bloco(Mesa.espaco_estrutura_abs(p, n, calib), p, "estrutura", n)
    end
    for _, qual in ipairs(Mesa.DECKS) do
      por_bloco(Mesa.espaco_deck_abs(p, qual, calib), p, "deck", qual)
    end
    for k = 1, #Mesa.JOGADORES[p].combate do
      local x, z, col, lin = Mesa.espaco_combate_abs(p, k, calib)
      por({ x = x, z = z, col = col, lin = lin }, p, "combate", k)
    end
    por_bloco(Mesa.espaco_descarte_abs(p, calib), p, "descarte", nil)
    por_bloco(Mesa.espaco_destruidas_abs(p, calib), p, "destruidas", nil)
  end
  local evento = Mesa.espaco_evento_abs(calib)
  for _, parte in ipairs(Mesa.PARTES_DO_EVENTO) do
    por(evento[parte], 0, "evento", parte)
  end
  return lista
end

return Mesa
