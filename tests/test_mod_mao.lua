-- Testes da US #37: a mão do jogador na tela.
--
-- O catálogo de cartas dos clientes (duelo/mod/catalogo), o modelo da mão
-- (duelo/mod/mao) sobre o transporte falso de tests/rede_falsa.lua, e o
-- widget (widgets/duelo_mao) com classes de tela falsas.

local RedeFalsa = require("rede_falsa")
local Catalogo = require("duelo/mod/catalogo")

local function ler(caminho)
  local f = assert(io.open(RedeFalsa.RAIZ .. caminho, "r"))
  local s = f:read("*a")
  f:close()
  return s
end

-- Servidor dedicado, dois jogadores e um espectador, com a mão de cada cliente.
local function mesa()
  local net = RedeFalsa.nova{ sala = true }
  local s = net:maquina{ servidor = true }
  local cs = {
    net:maquina{ userid = "KU_um", lado = 1 },
    net:maquina{ userid = "KU_dois", lado = 2 },
    net:maquina{ userid = "KU_tres", lado = 3 },
  }
  for _, c in ipairs(cs) do
    c.Mao = RedeFalsa.carregar("mao").instalar({ cliente = c.Cliente, catalogo = Catalogo })
  end
  return net, s, cs
end

local function comecar(net, s, cs)
  net.relogio = net.relogio + 1
  cs[1].Cliente.pronto(true); cs[2].Cliente.pronto(true)
  assert(s.Partida.em_curso(), "a partida começou")
  return s.Partida.jogo()
end

local function cliente_falso(dados)
  local C = {}
  function C.visao() return dados.visao end
  function C.lado() return dados.lado end
  function C.quando_estado() end
  function C.quando_lote() end
  return C
end

local function visao_com_mao(mao, mana)
  return {
    vencedor = false, erro = false,
    jogadores = { { mana = mana or 0, limite_mao = 10, mao = mao }, { mana = 0, limite_mao = 10 } },
  }
end

return {
  { "o catálogo dos clientes bate com as cartas do motor", function(T)
    local Gerador = require("duelo/mod/catalogo_gerador")
    T.eq(ler("scripts/duelo/mod/catalogo.lua"), Gerador.texto(),
      "catálogo desatualizado: rode `lua tools/gerar_catalogo.lua`")
    -- Toda carta tem número, nome, tipo, custo, texto e imagem.
    local Numeros = require("duelo/cartas/numeros")
    local n = 0
    for id, numero in pairs(Numeros) do
      n = n + 1
      local c = Catalogo[id]
      T.ok(c ~= nil, "carta fora do catálogo: " .. id)
      T.eq(c.numero, numero, id)
      T.ok(type(c.nome) == "string" and c.nome ~= "", "nome de " .. id)
      T.ok(type(c.tipo) == "string", "tipo de " .. id)
      T.ok(type(c.custo) == "number", "custo de " .. id)
      T.ok(type(c.texto) == "string" and c.texto ~= "", "texto de " .. id)
      T.ok(type(c.imagem) == "table" and (c.imagem.tipo == "album" or c.imagem.tipo == "avatar"), "imagem de " .. id)
      T.ok(c.imagem.tex:find("%.tex$"), "nome da imagem de " .. id)
      if c.tipo == "criatura" then
        T.ok(type(c.ataque) == "number" and type(c.vida) == "number", "ataque e vida de " .. id)
      end
    end
    local no_catalogo = 0
    for _ in pairs(Catalogo) do no_catalogo = no_catalogo + 1 end
    T.eq(no_catalogo, n, "o catálogo não tem carta a mais")
    -- Os campeões usam o retrato; o resto, o Álbum.
    T.eq(Catalogo.wilson.imagem.tipo, "avatar"); T.eq(Catalogo.wilson.campeao, true)
    T.eq(Catalogo.porco.imagem.tex, "pigman.tex")
  end },

  { "o catálogo é só dados: sem funções e sem pedir o motor", function(T)
    local pedidos, original = {}, require
    _G.require = function(nome) pedidos[nome] = true; return original(nome) end
    local ok, tabela = pcall(function() return assert(loadfile(RedeFalsa.RAIZ .. "scripts/duelo/mod/catalogo.lua"))() end)
    local ok2, err2 = pcall(RedeFalsa.carregar, "mao")
    _G.require = original
    T.ok(ok, tostring(tabela)); T.ok(ok2, tostring(err2))
    T.eq(next(pedidos), nil, "o catálogo e a mão não pedem nenhum módulo")
    local function so_dados(v, onde)
      local t = type(v)
      T.ok(t == "string" or t == "number" or t == "boolean" or t == "table", "valor que não é dado em " .. onde)
      if t == "table" then
        for k, x in pairs(v) do so_dados(x, onde .. "." .. tostring(k)) end
      end
    end
    so_dados(tabela, "catalogo")
  end },

  { "sem partida, ou para quem assiste, a mão não aparece", function(T)
    local net, s, cs = mesa()
    T.eq(cs[1].Mao.modelo().visivel, false, "sem partida")
    T.eq(#cs[1].Mao.modelo().cartas, 0)
    comecar(net, s, cs)
    T.eq(cs[1].Mao.modelo().visivel, true)
    T.eq(cs[3].Mao.modelo().visivel, false, "o espectador não tem mão")
    T.eq(#cs[3].Mao.modelo().cartas, 0)
  end },

  { "cada jogador vê a própria mão, com os dados da carta", function(T)
    local net, s, cs = mesa()
    local g = comecar(net, s, cs)
    for lado = 1, 2 do
      local m = cs[lado].Mao.modelo()
      local mao = g.players[lado].hand
      T.eq(m.total, #mao, "quantidade do lado " .. lado)
      T.eq(m.limite, 10, "limite de mão")
      for i, carta in ipairs(m.cartas) do
        T.eq(carta.indice, i)
        T.eq(carta.id, mao[i].id, "a carta " .. i .. " do lado " .. lado)
        T.eq(carta.uid, mao[i].uid)
        T.eq(carta.nome, Catalogo[carta.id].nome)
        T.eq(carta.texto, Catalogo[carta.id].texto)
        T.eq(carta.custo, g:card_cost(lado, mao[i]), "custo de agora")
        T.eq(carta.pagavel, carta.custo <= g.players[lado].mana)
        T.eq(carta.imagem.tex, Catalogo[carta.id].imagem.tex)
      end
    end
    -- Nenhuma carta do outro lado aparece na mão de um jogador.
    local ids_do_2 = {}
    for _, c in ipairs(g.players[2].hand) do ids_do_2[c.uid] = true end
    for _, carta in ipairs(cs[1].Mao.modelo().cartas) do
      T.ok(not ids_do_2[carta.uid], "carta do lado 2 na mão do lado 1")
    end
  end },

  { "a mão acompanha a partida: comprar muda o painel", function(T)
    local net, s, cs = mesa()
    local g = comecar(net, s, cs)
    local vistos = {}
    cs[1].Mao.ligar_widget({ Atualizar = function(_, m) vistos[#vistos + 1] = m end })
    T.eq(#vistos, 1, "ao ligar, o widget recebe a mão")
    local antes = vistos[1].total
    -- Os dois passam: a rodada vira e cada um compra uma carta.
    for _ = 1, 2 do
      net.relogio = net.relogio + 1
      T.ok(cs[g.active].Cliente.enviar({ type = "pass" }))
    end
    T.eq(g.round, 2)
    local m = vistos[#vistos]
    T.eq(m.total, antes + 1, "a carta comprada entrou na mão")
    T.eq(m.total, #g.players[1].hand)
    T.ok(#vistos <= 1 + 2, "uma atualização por lote, não por evento")
    -- No fim da partida a mão sai da tela.
    g.players[2].life = 0
    g:check_winner()
    net.relogio = net.relogio + 1
    cs[1].Cliente.enviar({ type = "pass" })
    T.eq(vistos[#vistos].visivel, false)
    -- Mesa zerada: continua sem mão.
    s.Partida.encerrar()
    T.eq(vistos[#vistos].visivel, false)
  end },

  { "atributos por tipo de carta e custo de agora", function(T)
    local dados = { lado = 1, visao = visao_com_mao({
      { id = "porco", card_uid = 1, custo = 4 },
      { id = "lanca", card_uid = 2, custo = 1 },
      { id = "armadura_de_grama", card_uid = 3, custo = 2, durabilidade = 1 },
      { id = "dardo", card_uid = 4, custo = 2 },
      { id = "maquina_de_ciencia", card_uid = 5, custo = 4 },
      { id = "wilson", card_uid = 6, custo = 3 },
      { id = "carta_nova", card_uid = 7, custo = 1 },
    }, 2) }
    local Mao = RedeFalsa.carregar("mao").instalar({ cliente = cliente_falso(dados), catalogo = Catalogo })
    local c = Mao.modelo().cartas
    T.eq(c[1].atributos, "4 / 5"); T.eq(c[1].tipo_nome, "Criatura"); T.eq(c[1].pagavel, false)
    T.eq(c[2].atributos, "+3 ataque · dur. 6"); T.eq(c[2].tipo_nome, "Equipamento"); T.eq(c[2].pagavel, true)
    T.eq(c[3].atributos, "+2 vida · dur. 1", "a durabilidade é a de agora")
    T.eq(c[4].atributos, false); T.eq(c[4].tipo_nome, "Feitiço")
    T.eq(c[5].atributos, false); T.eq(c[5].tipo_nome, "Estrutura")
    T.eq(c[6].tipo_nome, "Campeão"); T.eq(c[6].atributos, "1 / 3")
    T.eq(c[6].custo, 3, "o custo da visão vale mais que o do catálogo")
    -- Uma carta que o catálogo não conhece aparece pelo id, sem quebrar.
    T.eq(c[7].nome, "carta_nova"); T.eq(c[7].texto, false); T.eq(c[7].imagem, false); T.eq(c[7].custo, 1)
  end },

  { "visões tortas não quebram a mão", function(T)
    local dados = { lado = 1 }
    local Mao = RedeFalsa.carregar("mao").instalar({ cliente = cliente_falso(dados), catalogo = Catalogo })
    for _, v in ipairs({ {}, { jogadores = "x" }, { jogadores = { {} } }, { jogadores = { { mao = "x" } } } }) do
      dados.visao = v
      T.eq(Mao.modelo().visivel, false)
    end
    dados.visao = visao_com_mao({ { id = "porco", card_uid = 1 } })
    dados.visao.jogadores[1].mana = "muita"
    local m = Mao.modelo()
    T.eq(m.cartas[1].custo, 4, "sem custo na visão, vale o do catálogo")
    T.eq(m.cartas[1].pagavel, false)
    dados.lado = 3
    T.eq(Mao.modelo().visivel, false)
  end },

  { "o leque: centrado, em ordem, e sempre dentro da largura", function(T)
    local Mao = RedeFalsa.carregar("mao")
    local L = Mao.LEQUE
    T.eq(#Mao.leque(0), 0); T.eq(#Mao.leque(-1), 0); T.eq(#Mao.leque("x"), 0)
    local um = Mao.leque(1)
    T.eq(um[1].x, 0); T.eq(um[1].y, 0); T.eq(um[1].rot, 0)
    for _, n in ipairs({ 2, 5, 10, 13, 20 }) do
      local p = Mao.leque(n)
      T.eq(#p, n)
      for i = 2, n do T.ok(p[i].x > p[i - 1].x, "em ordem, da esquerda para a direita (" .. n .. ")") end
      T.ok(math.abs(p[1].x + p[n].x) < 1e-9, "centrado (" .. n .. ")")
      T.ok(p[n].x - p[1].x <= L.largura + 1e-9, "dentro da largura (" .. n .. ")")
      T.ok(math.abs(p[1].rot + p[n].rot) < 1e-9, "inclinação simétrica")
      T.ok(p[n].rot <= L.giro_max and p[1].rot >= -L.giro_max, "inclinação limitada")
      T.ok(p[1].y <= 0 and p[n].y <= 0, "as pontas descem")
      T.ok(p[1].y >= -L.queda - 1e-9, "a queda é limitada")
    end
    -- Até caberem, as cartas ficam no passo normal; depois apertam.
    local cinco, vinte = Mao.leque(5), Mao.leque(20)
    T.eq(cinco[2].x - cinco[1].x, L.passo)
    T.ok(vinte[2].x - vinte[1].x < L.passo, "com a Mochila as cartas ficam mais juntas")
    -- 10 cartas (a mão cheia) ainda deixam cada carta com um bom pedaço à vista.
    local dez = Mao.leque(10)
    T.ok(dez[2].x - dez[1].x >= 80, "na mão cheia o passo ainda é largo")
  end },

  { "o painel sobrevive a um widget morto e a um modelo com erro", function(T)
    local dados = { lado = 1, visao = visao_com_mao({ { id = "porco", card_uid = 1, custo = 4 } }) }
    local logs = {}
    local Mao = RedeFalsa.carregar("mao").instalar({ cliente = cliente_falso(dados), catalogo = Catalogo,
      log = function(s) logs[#logs + 1] = s end })
    local n = 0
    Mao.ligar_widget({ Atualizar = function() n = n + 1 end })
    T.eq(n, 1)
    local visao = dados.visao
    dados.visao = setmetatable({}, { __index = function() error("visão quebrada") end })
    Mao.atualizar()
    T.eq(#logs, 1, "o erro do modelo vira um aviso"); T.eq(n, 1)
    dados.visao = visao
    Mao.atualizar()
    T.eq(n, 2, "o painel continua ligado")
    Mao.ligar_widget({ Atualizar = function() error("widget morto") end })
    T.eq(#logs, 2)
    Mao.atualizar()
    T.eq(#logs, 2, "desligado: não tenta de novo")
  end },

  { "widgets/duelo_mao desenha as cartas do modelo e ergue a que está sob o mouse", function(T)
    -- Classes de tela falsas, no lugar das do jogo.
    local function classe(nome)
      local c = { nome_da_classe = nome }
      c.__index = c
      function c:AddChild(w) w.pai = self; self.filhos = self.filhos or {}; self.filhos[#self.filhos + 1] = w; return w end
      function c:SetPosition(x, y) self.pos = { x, y } end
      function c:SetScale(e) self.escala = e end
      function c:SetRotation(r) self.rot = r end
      function c:SetClickable(v) self.clicavel = v end
      function c:Show() self.visivel = true end
      function c:Hide() self.visivel = false end
      function c:Kill() self.morto = true end
      function c:MoveToFront() c.frente = (c.frente or 0) + 1; self.ordem = c.frente end
      function c:SetString(s) self.texto = s end
      function c:SetAutoSizingString(s, largura) self.texto = s; self.largura = largura end
      function c:SetColour() end
      function c:SetRegionSize(w, h) self.regiao = { w, h } end
      function c:EnableWordWrap(v) self.quebra = v end
      function c:SetHAlign() end
      function c:SetVAlign() end
      function c:SetTexture(atlas, tex) self.atlas = atlas; self.tex = tex end
      function c:ScaleToSize(w, h) self.tamanho = { w, h } end
      function c:SetTint(r) self.tom = r end
      return c
    end
    local Widget = classe("Widget")
    Widget._ctor = function(self, nome) self.nome = nome end
    local function construtor(c, init)
      return setmetatable({}, { __call = function(_, ...)
        local o = setmetatable({}, c)
        if init then init(o, ...) end
        return o
      end })
    end
    local Text = classe("Text")
    local Image = classe("Image")
    local nomes = { "widgets/widget", "widgets/text", "widgets/image" }
    local salvos, globais = {}, {}
    for _, n in ipairs(nomes) do salvos[n] = package.loaded[n] end
    for _, n in ipairs({ "Class", "HEADERFONT", "ANCHOR_MIDDLE", "ANCHOR_TOP", "PLANTREGISTRYUICOLOURS",
      "GetScrapbookIconAtlas", "TheSim" }) do globais[n] = _G[n] end
    package.loaded["widgets/widget"] = Widget
    package.loaded["widgets/text"] = construtor(Text, function(o, fonte, tamanho) o.fonte = fonte; o.tamanho_fonte = tamanho end)
    package.loaded["widgets/image"] = construtor(Image, function(o, atlas, tex) o.atlas = atlas; o.tex = tex end)
    _G.HEADERFONT, _G.ANCHOR_MIDDLE, _G.ANCHOR_TOP = "hammerhead", 0, 1
    _G.PLANTREGISTRYUICOLOURS = { UNLOCKEDBROWN = { 0.3, 0.2, 0.13, 1 } }
    _G.GetScrapbookIconAtlas = function(tex) return tex ~= "nao_existe.tex" and "images/scrapbook_icons1.xml" or nil end
    _G.TheSim = { AtlasContains = function(_, atlas, tex) return tex == "avatar_wilson.tex" end }
    _G.Class = function(base, ctor)
      local c = setmetatable({}, { __index = base, __call = function(c, ...)
        local o = setmetatable({}, c); ctor(o, ...); return o
      end })
      c.__index = c
      return c
    end
    local ok, err = pcall(function()
      local DueloMao = assert(loadfile(RedeFalsa.RAIZ .. "scripts/widgets/duelo_mao.lua"))()
      local dados = { lado = 1, visao = visao_com_mao({
        { id = "porco", card_uid = 1, custo = 4 },
        { id = "wilson", card_uid = 2, custo = 4 },
        { id = "lanca", card_uid = 3, custo = 1 },
      }, 1) }
      local Mao = RedeFalsa.carregar("mao").instalar({ cliente = cliente_falso(dados), catalogo = Catalogo })
      local w = DueloMao()
      T.eq(w.visivel, false, "nasce escondida")
      Mao.ligar_widget(w)
      T.eq(w.visivel, true)
      T.eq(#w.cartas, 3)
      local porco, wilson, lanca = w.cartas[1], w.cartas[2], w.cartas[3]
      T.eq(porco.nome.texto, "Porco"); T.eq(porco.custo.texto, "4")
      T.eq(porco.atributos.texto, "4 / 5"); T.eq(porco.tipo.texto, "Criatura")
      T.eq(porco.texto.texto, Catalogo.porco.texto)
      T.eq(porco.moldura.atlas, "images/plantregistry.xml"); T.eq(porco.moldura.tex, "plant_entry.tex")
      T.eq(porco.imagem.atlas, "images/scrapbook_icons1.xml"); T.eq(porco.imagem.tex, "pigman.tex")
      T.eq(porco.imagem.visivel, true)
      T.eq(wilson.imagem.atlas, "images/avatars.xml"); T.eq(wilson.imagem.tex, "avatar_wilson.tex")
      T.eq(porco.moldura.tom, 0.68, "a carta que a mana não paga fica escura")
      T.eq(lanca.moldura.tom, 1)
      -- Só a moldura recebe o mouse.
      T.eq(porco.moldura.clicavel, nil); T.eq(porco.nome.clicavel, false); T.eq(porco.imagem.clicavel, false)
      -- No leque: a do meio reta, as pontas inclinadas para fora.
      T.ok(porco.pos[1] < wilson.pos[1] and wilson.pos[1] < lanca.pos[1])
      T.eq(wilson.rot, 0); T.ok(porco.rot < 0 and lanca.rot > 0)
      T.ok(lanca.ordem > wilson.ordem and wilson.ordem > porco.ordem, "a da direita por cima")
      -- O mouse sobre a primeira: ela cresce, fica reta, sobe e vem para a frente.
      local escala, y = porco.escala, porco.pos[2]
      porco.moldura.ongainfocusfn()
      T.ok(porco.escala > escala, "cresce"); T.ok(porco.pos[2] > y, "sobe"); T.eq(porco.rot, 0)
      T.eq(porco.moldura.tex, "plant_entry_active.tex", "moldura clara")
      T.ok(porco.ordem > lanca.ordem, "vem para a frente")
      -- O mouse passa para a segunda sem aviso de saída da primeira.
      wilson.moldura.ongainfocusfn()
      T.eq(porco.escala, escala, "a primeira volta"); T.eq(porco.moldura.tex, "plant_entry.tex")
      T.ok(wilson.escala > escala)
      porco.moldura.onlosefocusfn() -- aviso atrasado da primeira: não mexe na segunda
      T.ok(wilson.escala > escala)
      wilson.moldura.onlosefocusfn()
      T.eq(wilson.escala, escala)
      T.ok(lanca.ordem > wilson.ordem and wilson.ordem > porco.ordem, "a ordem volta")
      -- A mão muda com o mouse em cima de uma carta: ela continua erguida.
      lanca.moldura.focus = true
      table.remove(dados.visao.jogadores[1].mao, 1)
      dados.visao.jogadores[1].mao[1].id = "nao_esta_no_catalogo"
      Mao.atualizar()
      T.eq(#w.cartas, 2, "a carta que saiu da mão some")
      T.eq(lanca.morto, true)
      T.eq(w.cartas[1].nome.texto, "nao_esta_no_catalogo")
      T.eq(w.cartas[1].imagem.visivel, false, "sem imagem conhecida, nada é desenhado no lugar")
      T.eq(w.cartas[1].texto.visivel, false)
      -- Sem partida: tudo some.
      dados.visao = nil
      Mao.atualizar()
      T.eq(#w.cartas, 0); T.eq(w.visivel, false)
      w:Atualizar(nil)
      T.eq(w.visivel, false)
    end)
    for _, n in ipairs(nomes) do package.loaded[n] = salvos[n] end
    for n, v in pairs(globais) do _G[n] = v end
    for _, n in ipairs({ "Class", "HEADERFONT", "ANCHOR_MIDDLE", "ANCHOR_TOP", "PLANTREGISTRYUICOLOURS",
      "GetScrapbookIconAtlas", "TheSim" }) do
      if globais[n] == nil then _G[n] = nil end
    end
    T.ok(ok, tostring(err))
  end },

  { "modmain: a mão entra na raiz de baixo e a barra de inventário some", function(T)
    local construtores = {}
    local G = setmetatable({
      require = require, print = function() end,
      TheNet = { GetIsServer = function() return false end, IsDedicated = function() return false end },
    }, { __index = _G })
    local nada = function() end
    local env = setmetatable({
      GLOBAL = G, modname = "dst-cardgame", GetModConfigData = function() return nil end,
      AddPlayerPostInit = nada, AddComponentPostInit = nada, AddPrefabPostInit = nada, AddSimPostInit = nada,
      AddClassPostConstruct = function(classe, fn) construtores[#construtores + 1] = { classe = classe, fn = fn } end,
      AddModRPCHandler = nada, AddClientModRPCHandler = nada,
      GetModRPC = nada, GetClientModRPC = nada, SendModRPCToServer = nada, SendModRPCToClient = nada,
    }, { __index = _G })
    local chunk = assert(loadfile(RedeFalsa.RAIZ .. "modmain.lua"))
    setfenv(chunk, env)
    chunk()
    T.eq(type(env.DUELO.Mao.modelo), "function", "DUELO.Mao no cliente")
    T.eq(#construtores, 2, "o painel da sala e a mão")
    T.eq(construtores[2].classe, "widgets/controls")
    -- Roda o construtor da mão com controles falsos e um widget falso.
    local criado
    local salvo = package.loaded["widgets/duelo_mao"]
    package.loaded["widgets/duelo_mao"] = setmetatable({}, { __call = function()
      criado = { Atualizar = function(self, m) self.modelo = m end }
      return criado
    end })
    local mostrou = 0
    local controles = {
      inv = { Hide = function(self) self.escondida = true end, Show = function() mostrou = mostrou + 1 end },
      bottom_root = { AddChild = function(self, w) self.filho = w; return w end },
    }
    local ok, err = pcall(construtores[2].fn, controles)
    package.loaded["widgets/duelo_mao"] = salvo
    T.ok(ok, tostring(err))
    T.eq(controles.bottom_root.filho, criado, "a mão entra na raiz de baixo da tela")
    T.eq(controles.duelo_mao, criado)
    T.eq(criado.modelo.visivel, false, "o widget já recebe o modelo (sem partida)")
    T.eq(controles.inv.escondida, true, "a barra de inventário do jogo some")
    controles.inv:Show()
    T.eq(mostrou, 0, "e o jogo não consegue mostrá-la de novo")
    -- Sem barra de inventário (outro modo de jogo), o construtor não quebra.
    package.loaded["widgets/duelo_mao"] = setmetatable({}, { __call = function() return { Atualizar = nada } end })
    local ok2, err2 = pcall(construtores[2].fn, { bottom_root = { AddChild = function(_, w) return w end } })
    package.loaded["widgets/duelo_mao"] = salvo
    T.ok(ok2, tostring(err2))
  end },
}
