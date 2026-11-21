-- A mão do jogador (US #37): as cartas em leque, na parte de baixo da tela.
-- Só desenha: o conteúdo e a posição de cada carta vêm prontos de
-- duelo/mod/mao (Mao.modelo).
--
-- Este arquivo roda no ambiente do jogo (carregado por `require` a partir de
-- modmain.lua, num AddClassPostConstruct de "widgets/controls").
--
-- Cada carta reaproveita a moldura das fichas de adubo do livro de jardinagem
-- do jogo (widgets/redux/fertilizerspage.lua): `plant_entry.tex` e a linha
-- `plant_entry_seperator.tex`, do atlas images/plantregistry.xml, com 160 por
-- 230, a fonte HEADERFONT e o marrom PLANTREGISTRYUICOLOURS. A carta sob o
-- mouse usa a moldura clara (`plant_entry_active.tex`), cresce, fica reta e
-- sobe, para o texto dar para ler. A imagem é o ícone do Álbum
-- (GetScrapbookIconAtlas, simutil.lua) ou, nos campeões, o retrato do
-- personagem (images/avatars.xml). Todos esses atlas já vêm carregados com o
-- jogo (prefabs/global.lua).

local Widget = require "widgets/widget"
local Text = require "widgets/text"
local Image = require "widgets/image"

local ATLAS = "images/plantregistry.xml"
local ATLAS_AVATARES = "images/avatars.xml"

-- Medidas dentro da carta (160 x 230, origem no centro), como na ficha de adubo.
local Y_NOME, Y_LINHA = 93, 75
local LADO_IMAGEM = 64
local Y_IMAGEM = Y_LINHA - 5 - LADO_IMAGEM / 2
local LARGURA_NOME = 112

-- Em repouso e sob o mouse: escala e altura do centro acima da borda de baixo.
local ESCALA, ESCALA_FOCO = 0.72, 1.3
local Y_REPOUSO, Y_FOCO = 58, 160

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

  -- Só a moldura recebe o mouse; o resto fica por cima sem clique.
  self.moldura = self:AddChild(Image(ATLAS, "plant_entry.tex"))
  self.linha = self:AddChild(Image(ATLAS, "plant_entry_seperator.tex"))
  self.linha:SetPosition(0, Y_LINHA)
  self.linha:SetClickable(false)

  self.nome = novo_texto(self, 15, 6, Y_NOME)
  self.custo = novo_texto(self, 24, -62, Y_NOME + 2)

  self.imagem = self:AddChild(Image(ATLAS, "missing.tex"))
  self.imagem:SetPosition(0, Y_IMAGEM)
  self.imagem:SetClickable(false)

  self.tipo = novo_texto(self, 13, 0, -6)
  self.atributos = novo_texto(self, 17, 0, -26)

  self.texto = novo_texto(self, 12, 0, -72)
  self.texto:SetRegionSize(132, 64)
  self.texto:EnableWordWrap(true)
  self.texto:SetHAlign(ANCHOR_MIDDLE)
  self.texto:SetVAlign(ANCHOR_TOP)

  self.moldura.ongainfocusfn = function() self.mao:Focar(self) end
  self.moldura.onlosefocusfn = function() self.mao:Desfocar(self) end
end)

local function texto_ou_nada(w, s)
  if s then
    w:SetString(tostring(s))
    w:Show()
  else
    w:Hide()
  end
end

function Carta:Preencher(c)
  self.dados = c
  self.nome:SetAutoSizingString(tostring(c.nome), LARGURA_NOME)
  self.custo:SetString(tostring(c.custo))
  texto_ou_nada(self.tipo, c.tipo_nome)
  texto_ou_nada(self.atributos, c.atributos)
  texto_ou_nada(self.texto, c.texto)
  local atlas, tex = atlas_da_imagem(c.imagem)
  if atlas ~= nil then
    self.imagem:SetTexture(atlas, tex)
    self.imagem:ScaleToSize(LADO_IMAGEM, LADO_IMAGEM)
    self.imagem:Show()
  else
    self.imagem:Hide()
  end
  -- A carta que a mana de agora não paga fica escurecida.
  local tom = c.pagavel and 1 or 0.68
  self.moldura:SetTint(tom, tom, tom, 1)
  self:Pousar()
end

-- No lugar dela no leque.
function Carta:Pousar()
  local c = self.dados
  self.moldura:SetTexture(ATLAS, "plant_entry.tex")
  self.linha:SetTexture(ATLAS, "plant_entry_seperator.tex")
  self:SetScale(ESCALA)
  self:SetRotation(c.rot)
  self:SetPosition(c.x, Y_REPOUSO + c.y)
end

-- Sob o mouse: maior, reta e mais alta.
function Carta:Erguer()
  local c = self.dados
  self.moldura:SetTexture(ATLAS, "plant_entry_active.tex")
  self.linha:SetTexture(ATLAS, "plant_entry_seperator_active.tex")
  self:SetScale(ESCALA_FOCO)
  self:SetRotation(0)
  self:SetPosition(c.x, Y_FOCO)
  self:MoveToFront()
end

local DueloMao = Class(Widget, function(self)
  Widget._ctor(self, "DueloMao")
  self.cartas = {}
  self.erguida = nil
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

-- modelo: { visivel, cartas = { { nome, custo, x, y, rot, ... }, ... } } (Mao.modelo).
function DueloMao:Atualizar(modelo)
  modelo = modelo or {}
  local lista = modelo.visivel and modelo.cartas or {}
  self.erguida = nil
  for i, c in ipairs(lista) do
    if self.cartas[i] == nil then self.cartas[i] = self:AddChild(Carta(self)) end
    self.cartas[i]:Preencher(c)
  end
  for i = #self.cartas, #lista + 1, -1 do
    self.cartas[i]:Kill()
    self.cartas[i] = nil
  end
  -- A carta que continua sob o mouse depois da mudança volta a ficar erguida
  -- (o jogo não avisa o foco de novo se o mouse não saiu de cima dela).
  for _, carta in ipairs(self.cartas) do
    if carta.moldura.focus then
      self.erguida = carta
      carta:Erguer()
      break
    end
  end
  self:Ordenar()
  if #lista > 0 then self:Show() else self:Hide() end
end

return DueloMao
