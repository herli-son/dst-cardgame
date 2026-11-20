-- Painel da sala e do fim da partida (US #42): um título, uma linha de texto
-- e um botão, no alto da tela. Só desenha: o conteúdo vem pronto de
-- duelo/mod/tela_sala (Tela.modelo), e o clique volta por `ao_clicar`.
--
-- Este arquivo roda no ambiente do jogo (é carregado por `require` a partir
-- de modmain.lua, num AddClassPostConstruct de "widgets/controls"): usa as
-- classes de tela do jogo (widgets/widget, widgets/text) e o botão padrão de
-- widgets/redux/templates (TEMPLATES.StandardButton).

local Widget = require "widgets/widget"
local Text = require "widgets/text"
local TEMPLATES = require "widgets/redux/templates"

local TAMANHO_TITULO = 46
local TAMANHO_TEXTO = 26
local BOTAO = { 220, 54 }
-- Abaixo dos anúncios do jogo (entradas e saídas de jogadores), que ocupam o
-- alto da tela, ao centro, por alguns segundos (widgets/eventannouncer.lua).
local Y_TITULO, Y_TEXTO, Y_BOTAO = -135, -175, -225

local DueloSala = Class(Widget, function(self, ao_clicar)
  Widget._ctor(self, "DueloSala")
  self.ao_clicar = ao_clicar

  self.titulo = self:AddChild(Text(NEWFONT_OUTLINE, TAMANHO_TITULO, ""))
  self.titulo:SetPosition(0, Y_TITULO)

  self.texto = self:AddChild(Text(NEWFONT_OUTLINE, TAMANHO_TEXTO, ""))
  self.texto:SetPosition(0, Y_TEXTO)

  self.botao = self:AddChild(TEMPLATES.StandardButton(function()
    if self.ao_clicar then self.ao_clicar() end
  end, "", BOTAO))
  self.botao:SetPosition(0, Y_BOTAO)

  self.titulo:Hide()
  self.texto:Hide()
  self.botao:Hide()
end)

local function mostrar_texto(w, texto)
  if texto then
    w:SetString(texto)
    w:Show()
  else
    w:Hide()
  end
end

-- modelo: { titulo = texto | false, texto = texto | false,
--           botao = { texto = ... } | false } (Tela.modelo).
function DueloSala:Atualizar(modelo)
  modelo = modelo or {}
  mostrar_texto(self.titulo, modelo.titulo)
  mostrar_texto(self.texto, modelo.texto)
  -- Sem título, o texto sobe para o lugar dele.
  self.texto:SetPosition(0, modelo.titulo and Y_TEXTO or Y_TITULO)
  if modelo.botao then
    self.botao:SetText(modelo.botao.texto)
    self.botao:Show()
  else
    self.botao:Hide()
  end
end

return DueloSala
