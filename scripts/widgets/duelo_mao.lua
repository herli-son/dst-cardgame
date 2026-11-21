-- A mão do jogador (US #37): as cartas em leque, na parte de baixo da tela.
-- Só desenha: o conteúdo e a posição de cada carta vêm prontos de
-- duelo/mod/mao (Mao.modelo).
--
-- Este arquivo roda no ambiente do jogo (carregado por `require` a partir de
-- modmain.lua, num AddClassPostConstruct de "widgets/controls").
--
-- Cada carta reaproveita as fichas do livro de jardinagem do jogo
-- (widgets/redux/fertilizerspage.lua e plantspage.lua), do atlas
-- images/plantregistry.xml: a moldura das fichas de adubo (160 por 230), a
-- linha sob o nome e as setas de trocar de página; a fonte é HEADERFONT e a
-- cor, o marrom PLANTREGISTRYUICOLOURS.
--
-- A carta tem duas páginas, trocadas pelas setas do rodapé:
--   1. a figura: custo (no alto, ao centro), nome, o boneco animado parado e,
--      na linha de baixo, ataque à esquerda, tipo ao centro e vida à direita
--      (nos equipamentos, bônus e durabilidade);
--   2. o texto: o que a carta faz, na área inteira da carta.
-- A página escolhida fica guardada por carta enquanto ela está na mão.
--
-- O boneco é um UIAnim (widgets/uianim.lua) com o banco, o build e a
-- animação de parado do prefab do jogo; o tamanho e a posição saem da caixa
-- visual que o próprio jogo informa (GetVisualBB). Sem figura no catálogo, a
-- carta mostra o ícone do Álbum (GetScrapbookIconAtlas, simutil.lua) ou o
-- retrato do personagem (images/avatars.xml).
--
-- A carta sob o mouse usa a moldura de foco, cresce, fica reta e sobe. O
-- foco é o da carta inteira (ela ou qualquer filho, como as setas): passar
-- da moldura para uma seta não a derruba.

local Widget = require "widgets/widget"
local Text = require "widgets/text"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local UIAnim = require "widgets/uianim"

local ATLAS = "images/plantregistry.xml"
local ATLAS_AVATARES = "images/avatars.xml"

-- Medidas dentro da carta (160 x 230, origem no centro).
local Y_CUSTO, Y_NOME, Y_LINHA = 99, 80, 66
local LARGURA_NOME = 124
-- A caixa do boneco: centro e tamanho máximo.
local X_FIGURA, Y_FIGURA, L_FIGURA, A_FIGURA = 0, 8, 124, 92
-- A linha de ataque, tipo e vida.
local Y_VALORES, Y_ROTULOS, X_VALORES = -56, -72, 56
local LARGURA_TIPO = 74
-- O rodapé: as setas e o nome da página.
local Y_RODAPE, X_SETA = -96, 56
-- O texto da segunda página.
local Y_TEXTO, LARGURA_TEXTO, LINHAS_TEXTO, FONTE_TEXTO, FONTE_TEXTO_MIN = -6, 132, 9, 15, 10

local NOMES_DAS_PAGINAS = { "Carta", "Efeito" }

-- Em repouso e sob o mouse: escala e altura do centro acima da borda de
-- baixo. A carta erguida continua cobrindo a borda de baixo da tela (metade
-- da altura dela, 230 * 1.3 / 2, é maior que Y_FOCO): o mouse parado embaixo
-- não a faz subir e descer sem parar.
local ESCALA, ESCALA_FOCO = 0.72, 1.3
local Y_REPOUSO, Y_FOCO = 58, 145

local function marrom()
  local c = PLANTREGISTRYUICOLOURS and PLANTREGISTRYUICOLOURS.UNLOCKEDBROWN or { 76 / 255, 50 / 255, 34 / 255, 1 }
  return c[1], c[2], c[3], c[4] or 1
end

local function novo_texto(pai, tamanho, x, y)
  local t = pai:AddChild(Text(HEADERFONT, tamanho, ""))
  t:SetPosition(x, y)
  t:SetColour(marrom())
  t:SetClickable(false)
  return t
end

local function texto_ou_nada(w, s)
  if s then
    w:SetString(tostring(s))
    w:Show()
  else
    w:Hide()
  end
end

-- O atlas e o nome da imagem de uma carta, ou nil se o jogo não a tiver.
local function atlas_da_imagem(imagem)
  if type(imagem) ~= "table" or type(imagem.tex) ~= "string" then return nil end
  if imagem.tipo == "album" then
    local atlas = GetScrapbookIconAtlas(imagem.tex)
    if atlas ~= nil then return atlas, imagem.tex end
  elseif imagem.tipo == "avatar" then
    if TheSim:AtlasContains(ATLAS_AVATARES, imagem.tex) then return ATLAS_AVATARES, imagem.tex end
  end
  return nil
end

local Carta = Class(Widget, function(self, mao)
  Widget._ctor(self, "DueloCarta")
  self.mao = mao
  self.pagina = 1

  -- A moldura recebe o mouse; textos e figura ficam por cima sem clique.
  self.moldura = self:AddChild(Image(ATLAS, "plant_entry_active.tex"))
  self.linha = self:AddChild(Image(ATLAS, "plant_entry_seperator_active.tex"))
  self.linha:SetPosition(0, Y_LINHA)
  self.linha:SetClickable(false)

  self.custo = novo_texto(self, 22, 0, Y_CUSTO)
  self.nome = novo_texto(self, 15, 0, Y_NOME)

  -- Página 1: a figura e os valores.
  self.frente = self:AddChild(Widget("frente"))
  self.figura = self.frente:AddChild(UIAnim())
  self.figura:SetClickable(false)
  self.imagem = self.frente:AddChild(Image(ATLAS, "missing.tex"))
  self.imagem:SetPosition(X_FIGURA, Y_FIGURA)
  self.imagem:SetClickable(false)
  self.esquerda = novo_texto(self.frente, 22, -X_VALORES, Y_VALORES)
  self.esquerda_rotulo = novo_texto(self.frente, 11, -X_VALORES, Y_ROTULOS)
  self.direita = novo_texto(self.frente, 22, X_VALORES, Y_VALORES)
  self.direita_rotulo = novo_texto(self.frente, 11, X_VALORES, Y_ROTULOS)
  self.tipo = novo_texto(self.frente, 12, 0, Y_VALORES - 6)

  -- Página 2: o texto.
  self.verso = self:AddChild(Widget("verso"))
  self.texto = novo_texto(self.verso, FONTE_TEXTO, 0, Y_TEXTO)

  -- Rodapé: as setas de página das fichas de plantas e o nome da página.
  local function trocar() self:TrocarPagina() end
  self.seta_esq = self:AddChild(ImageButton(ATLAS, "arrow2_left.tex", "arrow2_left_over.tex",
    "arrow_left_disabled.tex", "arrow2_left_down.tex", nil, { 1, 1 }, { 0, 0 }))
  self.seta_esq:SetPosition(-X_SETA, Y_RODAPE)
  self.seta_esq:SetOnClick(trocar)
  self.seta_dir = self:AddChild(ImageButton(ATLAS, "arrow2_right.tex", "arrow2_right_over.tex",
    "arrow_right_disabled.tex", "arrow2_right_down.tex", nil, { 1, 1 }, { 0, 0 }))
  self.seta_dir:SetPosition(X_SETA, Y_RODAPE)
  self.seta_dir:SetOnClick(trocar)
  self.pagina_nome = novo_texto(self, 14, 0, Y_RODAPE)

  -- O foco da carta inteira (widgets/widget.lua: um filho com foco deixa o
  -- pai com foco; ClearFocus no pai quando o mouse sai de todos).
  self.ongainfocusfn = function() self.mao:Focar(self) end
  self.onlosefocusfn = function() self.mao:Desfocar(self) end
end)

-- Põe o boneco animado na caixa da figura. Devolve false se não deu.
function Carta:MostrarFigura(figura)
  if type(figura) ~= "table" or type(figura.banco) ~= "string" or type(figura.build) ~= "string"
    or type(figura.anim) ~= "string" then
    return false
  end
  local anim = self.figura:GetAnimState()
  anim:SetBank(figura.banco)
  anim:SetBuild(figura.build)
  anim:PlayAnimation(figura.anim, true)
  -- De frente para a tela, como no mundo visto de baixo.
  self.figura:SetFacing(FACING_DOWN)
  self.figura:SetScale(1)
  -- A caixa visual, na escala 1: daí saem a escala e a posição que deixam o
  -- boneco inteiro dentro da caixa da figura, centrado.
  local x1, y1, x2, y2 = anim:GetVisualBB()
  local largura, altura = (x2 or 0) - (x1 or 0), (y2 or 0) - (y1 or 0)
  if largura > 0 and altura > 0 then
    local escala = math.min(L_FIGURA / largura, A_FIGURA / altura)
    self.figura:SetScale(escala)
    self.figura:SetPosition(X_FIGURA - escala * (x1 + x2) / 2, Y_FIGURA - escala * (y1 + y2) / 2)
  else
    -- Sem caixa (animação ainda não medida): um tamanho que serve à maioria,
    -- com os pés na base da caixa.
    self.figura:SetScale(0.3)
    self.figura:SetPosition(X_FIGURA, Y_FIGURA - A_FIGURA / 2)
  end
  self.figura:Show()
  return true
end

function Carta:Preencher(c, pagina)
  self.dados = c
  self.custo:SetString(tostring(c.custo))
  -- O tamanho volta ao normal antes de encolher para caber (o widget é
  -- reaproveitado por outra carta, com outro nome).
  self.nome:SetSize(15)
  self.nome:SetAutoSizingString(tostring(c.nome), LARGURA_NOME)

  if self:MostrarFigura(c.figura) then
    self.imagem:Hide()
  else
    self.figura:Hide()
    local atlas, tex = atlas_da_imagem(c.imagem)
    if atlas ~= nil then
      self.imagem:SetTexture(atlas, tex)
      self.imagem:ScaleToSize(A_FIGURA, A_FIGURA)
      self.imagem:Show()
    else
      self.imagem:Hide()
    end
  end

  local esq, dir = c.esquerda or false, c.direita or false
  texto_ou_nada(self.esquerda, esq and esq.valor)
  texto_ou_nada(self.esquerda_rotulo, esq and esq.rotulo)
  texto_ou_nada(self.direita, dir and dir.valor)
  texto_ou_nada(self.direita_rotulo, dir and dir.rotulo)
  if c.tipo_nome then
    self.tipo:SetSize(12)
    self.tipo:SetAutoSizingString(tostring(c.tipo_nome), (esq or dir) and LARGURA_TIPO or LARGURA_NOME)
    self.tipo:Show()
  else
    self.tipo:Hide()
  end

  if c.texto then
    self.texto:SetMultilineTruncatedString(tostring(c.texto), LINHAS_TEXTO, LARGURA_TEXTO, nil, true, true,
      FONTE_TEXTO_MIN)
  else
    self.texto:SetString("")
  end

  -- A carta que a mana de agora não paga fica escurecida.
  local tom = c.pagavel and 1 or 0.68
  self.moldura:SetTint(tom, tom, tom, 1)
  self:MostrarPagina(pagina or 1)
  self:Pousar()
end

function Carta:MostrarPagina(pagina)
  self.pagina = pagina == 2 and 2 or 1
  if self.pagina == 1 then
    self.frente:Show()
    self.verso:Hide()
  else
    self.frente:Hide()
    self.verso:Show()
  end
  self.pagina_nome:SetString(NOMES_DAS_PAGINAS[self.pagina])
end

function Carta:TrocarPagina()
  self:MostrarPagina(self.pagina == 1 and 2 or 1)
  self.mao:GuardarPagina(self)
end

-- No lugar dela no leque.
function Carta:Pousar()
  local c = self.dados
  self.moldura:SetTexture(ATLAS, "plant_entry_active.tex")
  self.linha:SetTexture(ATLAS, "plant_entry_seperator_active.tex")
  self:SetScale(ESCALA)
  self:SetRotation(c.rot)
  self:SetPosition(c.x, Y_REPOUSO + c.y)
end

-- Sob o mouse: maior, reta e mais alta.
function Carta:Erguer()
  local c = self.dados
  self.moldura:SetTexture(ATLAS, "plant_entry_focus.tex")
  self.linha:SetTexture(ATLAS, "plant_entry_seperator_focus.tex")
  self:SetScale(ESCALA_FOCO)
  self:SetRotation(0)
  self:SetPosition(c.x, Y_FOCO)
  self:MoveToFront()
end

local DueloMao = Class(Widget, function(self)
  Widget._ctor(self, "DueloMao")
  self.cartas = {}
  self.erguida = nil
  -- uid da carta -> página escolhida (só das cartas que estão na mão).
  self.paginas = {}
  self:Hide()
end)

-- A ordem de desenho segue a da mão: a carta mais à direita por cima.
function DueloMao:Ordenar()
  for _, carta in ipairs(self.cartas) do carta:MoveToFront() end
  if self.erguida ~= nil then self.erguida:MoveToFront() end
end

function DueloMao:Focar(carta)
  if self.erguida ~= nil and self.erguida ~= carta then self.erguida:Pousar() end
  self.erguida = carta
  carta:Erguer()
end

function DueloMao:Desfocar(carta)
  if self.erguida ~= carta then return end
  self.erguida = nil
  carta:Pousar()
  self:Ordenar()
end

function DueloMao:GuardarPagina(carta)
  local uid = carta.dados and carta.dados.uid
  if uid ~= nil then self.paginas[uid] = carta.pagina end
end

-- modelo: { visivel, cartas = { { nome, custo, x, y, rot, ... }, ... } } (Mao.modelo).
function DueloMao:Atualizar(modelo)
  modelo = modelo or {}
  local lista = modelo.visivel and modelo.cartas or {}
  self.erguida = nil
  -- Só as cartas que continuam na mão guardam a página.
  local paginas = {}
  for i, c in ipairs(lista) do
    if self.cartas[i] == nil then self.cartas[i] = self:AddChild(Carta(self)) end
    local pagina = c.uid ~= nil and self.paginas[c.uid] or 1
    if c.uid ~= nil then paginas[c.uid] = pagina end
    self.cartas[i]:Preencher(c, pagina)
  end
  self.paginas = paginas
  for i = #self.cartas, #lista + 1, -1 do
    self.cartas[i]:Kill()
    self.cartas[i] = nil
  end
  -- A carta que continua sob o mouse depois da mudança volta a ficar erguida
  -- (o jogo não avisa o foco de novo se o mouse não saiu de cima dela).
  for _, carta in ipairs(self.cartas) do
    if carta.focus then
      self.erguida = carta
      carta:Erguer()
      break
    end
  end
  self:Ordenar()
  if #lista > 0 then self:Show() else self:Hide() end
end

return DueloMao
