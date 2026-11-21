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
      -- A figura animada: banco, build, animação e os arquivos de anim/.
      T.ok(type(c.figura) == "table", "figura de " .. id)
      for _, campo in ipairs({ "banco", "build", "anim" }) do
        T.ok(type(c.figura[campo]) == "string" and c.figura[campo] ~= "", campo .. " da figura de " .. id)
      end
      T.eq(type(c.figura.arquivos), "table", "arquivos da figura de " .. id)
      for _, arquivo in ipairs(c.figura.arquivos) do
        T.ok(type(arquivo) == "string" and not arquivo:find("[/%.]"), "arquivo sem pasta nem extensão: " .. tostring(arquivo))
      end
      if c.tipo == "criatura" then
        T.ok(type(c.ataque) == "number" and type(c.vida) == "number", "ataque e vida de " .. id)
      end
    end
    local no_catalogo = 0
    for _ in pairs(Catalogo) do no_catalogo = no_catalogo + 1 end
    T.eq(no_catalogo, n, "o catálogo não tem carta a mais")
    -- Os campeões usam o retrato; o resto, o Álbum.
    T.eq(Catalogo.wilson.imagem.tipo, "avatar"); T.eq(Catalogo.wilson.campeao, true)
    T.eq(Catalogo.wilson.sobrevivente, true); T.eq(Catalogo.porco.sobrevivente, nil)
    T.eq(Catalogo.webber.figura.build, "webber"); T.eq(Catalogo.webber.figura.banco, "wilson")
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
    T.eq(c[1].esquerda.valor, "4"); T.eq(c[1].esquerda.rotulo, "ataque")
    T.eq(c[1].direita.valor, "5"); T.eq(c[1].direita.rotulo, "vida")
    T.eq(c[1].figura.banco, "pigman", "a figura animada vem do catálogo")
    T.eq(c[2].esquerda.valor, "+3"); T.eq(c[2].direita.valor, "6"); T.eq(c[2].direita.rotulo, "dur.")
    T.eq(c[3].esquerda.valor, "+2"); T.eq(c[3].esquerda.rotulo, "vida")
    T.eq(c[3].direita.valor, "1", "a durabilidade de agora")
    T.eq(c[4].esquerda, false); T.eq(c[4].direita, false)
    T.eq(c[2].atributos, "+3 ataque · dur. 6"); T.eq(c[2].tipo_nome, "Equipamento"); T.eq(c[2].pagavel, true)
    T.eq(c[3].atributos, "+2 vida · dur. 1", "a durabilidade é a de agora")
    T.eq(c[4].atributos, false); T.eq(c[4].tipo_nome, "Feitiço")
    T.eq(c[5].atributos, false); T.eq(c[5].tipo_nome, "Estrutura")
    T.eq(c[6].tipo_nome, "Campeão · Sobrevivente"); T.eq(c[6].atributos, "1 / 3")
    T.eq(c[6].custo, 3, "o custo da visão vale mais que o do catálogo")
    -- Uma carta que o catálogo não conhece aparece pelo id, sem quebrar.
    T.eq(c[7].nome, "carta_nova"); T.eq(c[7].texto, false); T.eq(c[7].imagem, false); T.eq(c[7].custo, 1)
    T.eq(c[7].figura, false); T.eq(c[7].tipo_nome, false); T.eq(c[7].esquerda, false)
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
    -- Uma entrada da mão que não é tabela não derruba o modelo.
    dados.visao = visao_com_mao({ 7, true, { id = "porco", card_uid = 1, custo = 4 } })
    m = Mao.modelo()
    T.eq(m.total, 3); T.eq(m.cartas[1].nome, "nil"); T.eq(m.cartas[3].nome, "Porco")
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
    -- Um widget cuja entidade o jogo já desfez nem é chamado.
    local chamado, valido = 0, true
    Mao.ligar_widget({ inst = { IsValid = function() return valido end }, Atualizar = function() chamado = chamado + 1 end })
    T.eq(chamado, 1)
    valido = false
    Mao.atualizar()
    T.eq(chamado, 1, "a tela foi desfeita: o widget morto não é atualizado")
    valido = true
    Mao.atualizar()
    T.eq(chamado, 1, "e fica desligado até a próxima tela")
  end },

  { "widgets/duelo_mao desenha as cartas, troca de página pelas setas e ergue a carta sob o mouse", function(T)
    -- Classes de tela falsas, no lugar das do jogo.
    local frente = 0
    local function classe(nome)
      local c = { nome_da_classe = nome }
      c.__index = c
      function c:AddChild(w) w.pai = self; return w end
      function c:SetPosition(x, y) self.pos = { x, y } end
      function c:SetScale(e) self.escala = e end
      function c:SetRotation(r) self.rot = r end
      function c:SetClickable(v) self.clicavel = v end
      function c:Show() self.visivel = true end
      function c:Hide() self.visivel = false end
      function c:Kill() self.morto = true end
      function c:MoveToFront() frente = frente + 1; self.ordem = frente end
      function c:SetString(s) self.texto = s end
      function c:SetSize(t) self.tamanho_fonte = t end
      function c:SetAutoSizingString(s, largura) self.texto = s; self.largura = largura end
      function c:SetMultilineTruncatedString(s, linhas, largura, _, _, encolhe, minimo)
        self.texto = s; self.linhas = linhas; self.largura = largura; self.encolhe = encolhe; self.minimo = minimo
      end
      function c:SetColour() end
      function c:SetTexture(atlas, tex) self.atlas = atlas; self.tex = tex end
      function c:ScaleToSize(w, h) self.tamanho = { w, h } end
      function c:SetTint(r) self.tom = r end
      function c:SetOnClick(fn) self.ao_clicar = fn end
      function c:SetFacing(f) self.face = f end
      function c:GetAnimState() return self.anim end
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
    -- A caixa visual que o "jogo" informa para cada banco: (x1, y1, x2, y2).
    local caixas = { pigman = { -100, 0, 100, 300 }, wilson = { -60, -10, 60, 230 } }
    local nomes = { "widgets/widget", "widgets/text", "widgets/image", "widgets/imagebutton", "widgets/uianim" }
    local GLOBAIS = { "Class", "HEADERFONT", "FACING_DOWN", "PLANTREGISTRYUICOLOURS", "GetScrapbookIconAtlas", "TheSim" }
    local salvos, globais = {}, {}
    for _, n in ipairs(nomes) do salvos[n] = package.loaded[n] end
    for _, n in ipairs(GLOBAIS) do globais[n] = _G[n] end
    package.loaded["widgets/widget"] = setmetatable(Widget, { __call = function(_, nome)
      local o = setmetatable({}, Widget); o.nome = nome; return o
    end })
    package.loaded["widgets/text"] = construtor(classe("Text"), function(o, fonte, tamanho) o.fonte = fonte; o.tamanho_fonte = tamanho end)
    package.loaded["widgets/image"] = construtor(classe("Image"), function(o, atlas, tex) o.atlas = atlas; o.tex = tex end)
    package.loaded["widgets/imagebutton"] = construtor(classe("ImageButton"), function(o, atlas, normal, foco, desligado, baixo)
      o.atlas = atlas; o.texturas = { normal, foco, desligado, baixo }
    end)
    package.loaded["widgets/uianim"] = construtor(classe("UIAnim"), function(o)
      o.anim = {}
      function o.anim:SetBank(b) self.banco = b end
      function o.anim:SetBuild(b) self.build = b end
      function o.anim:PlayAnimation(a, laco) self.animacao = a; self.laco = laco end
      function o.anim:GetVisualBB()
        local c = caixas[self.banco]
        if c == nil then return 0, 0, 0, 0 end
        return c[1], c[2], c[3], c[4]
      end
    end)
    _G.HEADERFONT, _G.FACING_DOWN = "hammerhead", 3
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
      local catalogo = {}
      for id, c in pairs(Catalogo) do catalogo[id] = c end
      -- Uma carta com imagem e sem figura, para a reserva.
      catalogo.so_imagem = { nome = "Só imagem", tipo = "feitico", custo = 1, texto = "Teste.",
        imagem = { tipo = "album", tex = "axe.tex" } }
      local dados = { lado = 1, visao = visao_com_mao({
        { id = "porco", card_uid = 1, custo = 4 },
        { id = "wilson", card_uid = 2, custo = 4 },
        { id = "lanca", card_uid = 3, custo = 1 },
        { id = "so_imagem", card_uid = 4, custo = 1 },
      }, 1) }
      local Mao = RedeFalsa.carregar("mao").instalar({ cliente = cliente_falso(dados), catalogo = catalogo })
      local w = DueloMao()
      T.eq(w.visivel, false, "nasce escondida")
      Mao.ligar_widget(w)
      T.eq(w.visivel, true)
      T.eq(#w.cartas, 4)
      local porco, wilson, lanca, reserva = w.cartas[1], w.cartas[2], w.cartas[3], w.cartas[4]

      -- Cabeçalho: custo centralizado no alto, nome embaixo.
      T.eq(porco.custo.texto, "4"); T.eq(porco.custo.pos[1], 0, "custo ao centro")
      T.ok(porco.custo.pos[2] > porco.nome.pos[2], "custo acima do nome")
      T.eq(porco.nome.texto, "Porco")
      T.eq(porco.moldura.atlas, "images/plantregistry.xml"); T.eq(porco.moldura.tex, "plant_entry_active.tex")

      -- Página 1: o boneco animado, com ataque à esquerda, tipo ao centro e vida à direita.
      T.eq(porco.pagina, 1); T.eq(porco.frente.visivel, true); T.eq(porco.verso.visivel, false)
      T.eq(porco.figura.anim.banco, "pigman"); T.eq(porco.figura.anim.build, "pig_build")
      T.eq(porco.figura.anim.animacao, "idle_loop"); T.eq(porco.figura.anim.laco, true, "em laço")
      T.eq(porco.figura.visivel, true); T.eq(porco.imagem.visivel, false, "com figura, o ícone não aparece")
      T.eq(porco.figura.clicavel, false)
      T.eq(porco.esquerda.texto, "4"); T.eq(porco.esquerda_rotulo.texto, "ataque")
      T.eq(porco.direita.texto, "5"); T.eq(porco.direita_rotulo.texto, "vida")
      T.ok(porco.esquerda.pos[1] < 0 and porco.direita.pos[1] > 0, "ataque à esquerda, vida à direita")
      T.eq(porco.tipo.texto, "Criatura"); T.eq(porco.tipo.pos[1], 0)
      T.ok(math.abs(porco.tipo.pos[2] - porco.esquerda.pos[2]) <= 8, "o tipo na mesma linha dos valores")
      T.eq(wilson.tipo.texto, "Campeão · Sobrevivente")
      T.eq(wilson.esquerda.texto, "1"); T.eq(wilson.direita.texto, "3")
      T.eq(wilson.figura.anim.banco, "wilson"); T.eq(wilson.figura.anim.build, "wilson")
      T.eq(lanca.esquerda.texto, "+3"); T.eq(lanca.direita.texto, "6"); T.eq(lanca.direita_rotulo.texto, "dur.")

      -- O boneco cabe inteiro na caixa da figura e fica centrado nela.
      local function caixa_na_carta(carta, banco)
        local c, e, p = caixas[banco], carta.figura.escala, carta.figura.pos
        return p[1] + e * c[1], p[2] + e * c[2], p[1] + e * c[3], p[2] + e * c[4]
      end
      for _, par in ipairs({ { porco, "pigman" }, { wilson, "wilson" } }) do
        local x1, y1, x2, y2 = caixa_na_carta(par[1], par[2])
        T.ok(x2 - x1 <= 124 + 1e-6 and y2 - y1 <= 92 + 1e-6, "cabe na caixa: " .. par[2])
        T.ok(math.abs((x1 + x2) / 2) < 1e-6, "centrado na horizontal: " .. par[2])
        T.ok(y2 < porco.nome.pos[2] - 10, "abaixo do nome: " .. par[2])
        T.ok(y1 > porco.esquerda.pos[2], "acima da linha de valores: " .. par[2])
      end
      -- Sem caixa visual (lança, banco sem medida no teste): um tamanho padrão, sem erro.
      T.ok(lanca.figura.escala > 0); T.eq(lanca.figura.visivel, true)
      -- Sem figura no catálogo: o ícone do Álbum.
      T.eq(reserva.figura.visivel, false); T.eq(reserva.imagem.visivel, true)
      T.eq(reserva.imagem.atlas, "images/scrapbook_icons1.xml"); T.eq(reserva.imagem.tex, "axe.tex")
      T.eq(reserva.esquerda.visivel, false); T.eq(reserva.direita.visivel, false)

      -- Página 2: o texto, que encolhe para caber.
      T.eq(wilson.texto.texto, Catalogo.wilson.texto)
      T.eq(wilson.texto.encolhe, true); T.ok(wilson.texto.linhas >= 6); T.ok(wilson.texto.minimo < 15)
      -- As setas do rodapé são as das fichas de plantas e trocam a página.
      T.eq(wilson.seta_esq.atlas, "images/plantregistry.xml")
      T.eq(wilson.seta_esq.texturas[1], "arrow2_left.tex"); T.eq(wilson.seta_dir.texturas[1], "arrow2_right.tex")
      T.ok(wilson.seta_esq.pos[1] < 0 and wilson.seta_dir.pos[1] > 0)
      T.eq(wilson.pagina_nome.texto, "Carta")
      wilson.seta_dir.ao_clicar()
      T.eq(wilson.pagina, 2); T.eq(wilson.frente.visivel, false); T.eq(wilson.verso.visivel, true)
      T.eq(wilson.pagina_nome.texto, "Efeito")
      T.eq(porco.pagina, 1, "cada carta tem a sua página")
      wilson.seta_esq.ao_clicar()
      T.eq(wilson.pagina, 1, "as duas setas alternam entre as duas páginas")
      wilson.seta_dir.ao_clicar()

      -- A carta que a mana não paga fica escura.
      T.eq(porco.moldura.tom, 0.68); T.eq(lanca.moldura.tom, 1)
      -- No leque: em ordem, a da direita por cima.
      T.ok(porco.pos[1] < wilson.pos[1] and wilson.pos[1] < lanca.pos[1])
      T.ok(porco.rot < 0 and reserva.rot > 0)
      T.ok(lanca.ordem > wilson.ordem and wilson.ordem > porco.ordem, "a da direita por cima")

      -- O mouse sobre a primeira: ela cresce, fica reta, sobe e vem para a frente.
      local escala, y = porco.escala, porco.pos[2]
      porco.ongainfocusfn()
      T.ok(porco.escala > escala, "cresce"); T.ok(porco.pos[2] > y, "sobe"); T.eq(porco.rot, 0)
      T.eq(porco.moldura.tex, "plant_entry_focus.tex", "moldura de foco")
      T.eq(porco.linha.tex, "plant_entry_seperator_focus.tex")
      T.ok(porco.ordem > reserva.ordem, "vem para a frente")
      -- Erguida, ela ainda cobre a borda de baixo da tela (o mouse não fica sem carta embaixo).
      T.ok(porco.pos[2] - 230 * porco.escala / 2 <= 0, "a carta erguida chega à borda de baixo")
      -- O mouse passa para a segunda sem aviso de saída da primeira.
      wilson.ongainfocusfn()
      T.eq(porco.escala, escala, "a primeira volta"); T.eq(porco.moldura.tex, "plant_entry_active.tex")
      T.ok(wilson.escala > escala)
      porco.onlosefocusfn() -- aviso atrasado da primeira: não mexe na segunda
      T.ok(wilson.escala > escala)
      wilson.onlosefocusfn()
      T.eq(wilson.escala, escala)
      T.ok(lanca.ordem > wilson.ordem and wilson.ordem > porco.ordem, "a ordem volta")

      -- A mão muda com o mouse em cima de uma carta que continua nela: a carta
      -- segue erguida, e a página escolhida acompanha a carta, não a posição.
      wilson.focus = true
      table.remove(dados.visao.jogadores[1].mao, 1) -- o porco sai; o Wilson passa a ser a primeira
      Mao.atualizar()
      T.eq(#w.cartas, 3, "a carta que saiu da mão some")
      T.eq(reserva.morto, true, "sobra um widget, que é desfeito")
      -- Os widgets são reaproveitados por posição: o primeiro agora mostra o Wilson.
      T.eq(porco.nome.texto, "Wilson")
      T.eq(porco.pagina, 2, "o Wilson continua na página do texto")
      T.eq(wilson.nome.texto, "Lança"); T.eq(wilson.pagina, 1)
      T.eq(w.erguida, wilson, "a carta sob o mouse continua erguida")
      T.ok(wilson.escala > escala); T.eq(wilson.moldura.tex, "plant_entry_focus.tex")
      T.eq(porco.escala, escala, "as outras ficam no leque")
      wilson.focus = false
      -- O nome volta ao tamanho normal antes de encolher (o widget já teve outro nome).
      T.eq(porco.nome.tamanho_fonte, 15)
      -- Uma carta que saiu e voltou começa de novo na página 1.
      dados.visao.jogadores[1].mao = { { id = "porco", card_uid = 1, custo = 4 } }
      Mao.atualizar()
      dados.visao.jogadores[1].mao = { { id = "wilson", card_uid = 2, custo = 4 } }
      Mao.atualizar()
      T.eq(w.cartas[1].pagina, 1)
      -- Carta fora do catálogo: sem figura, sem ícone e sem texto, sem quebrar.
      dados.visao.jogadores[1].mao = { { id = "nao_esta_no_catalogo", card_uid = 9, custo = 2 } }
      Mao.atualizar()
      T.eq(w.cartas[1].nome.texto, "nao_esta_no_catalogo")
      T.eq(w.cartas[1].figura.visivel, false); T.eq(w.cartas[1].imagem.visivel, false)
      T.eq(w.cartas[1].texto.texto, ""); T.eq(w.cartas[1].tipo.visivel, false)
      -- Sem partida: tudo some.
      dados.visao = nil
      Mao.atualizar()
      T.eq(#w.cartas, 0); T.eq(w.visivel, false)
      w:Atualizar(nil)
      T.eq(w.visivel, false)
    end)
    for _, n in ipairs(nomes) do package.loaded[n] = salvos[n] end
    for _, n in ipairs(GLOBAIS) do _G[n] = globais[n] end
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
      Asset = function(tipo, arquivo) return { tipo = tipo, arquivo = arquivo } end,
      AddPlayerPostInit = nada, AddComponentPostInit = nada, AddPrefabPostInit = nada, AddSimPostInit = nada,
      AddClassPostConstruct = function(classe, fn) construtores[#construtores + 1] = { classe = classe, fn = fn } end,
      AddModRPCHandler = nada, AddClientModRPCHandler = nada,
      GetModRPC = nada, GetClientModRPC = nada, SendModRPCToServer = nada, SendModRPCToClient = nada,
    }, { __index = _G })
    local chunk = assert(loadfile(RedeFalsa.RAIZ .. "modmain.lua"))
    setfenv(chunk, env)
    chunk()
    T.eq(type(env.DUELO.Mao.modelo), "function", "DUELO.Mao no cliente")
    -- As animações das figuras entram como assets do mod, sem repetição.
    T.eq(type(env.Assets), "table", "o mod declara os assets das figuras")
    local vistos = {}
    for _, a in ipairs(env.Assets) do
      T.eq(a.tipo, "ANIM"); T.ok(a.arquivo:find("^anim/[%w_]+%.zip$"), a.arquivo)
      T.ok(not vistos[a.arquivo], "asset repetido: " .. a.arquivo)
      vistos[a.arquivo] = true
    end
    T.ok(vistos["anim/pig_build.zip"] and vistos["anim/ds_pig_basic.zip"], "o porco")
    T.ok(vistos["anim/ds_spider_basic.zip"] and vistos["anim/spider_wolf_build.zip"], "a curandeira")
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
      inv = { Hide = function(self) self.escondida = true end, Show = function() mostrou = mostrou + 1 end,
        OpenControllerInventory = function() mostrou = mostrou + 1 end },
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
    controles.inv:OpenControllerInventory()
    T.eq(mostrou, 0, "e o jogo não consegue mostrá-la de novo, nem pelo controle")
    -- Sem barra de inventário (outro modo de jogo), o construtor não quebra.
    package.loaded["widgets/duelo_mao"] = setmetatable({}, { __call = function() return { Atualizar = nada } end })
    local ok2, err2 = pcall(construtores[2].fn, { bottom_root = { AddChild = function(_, w) return w end } })
    package.loaded["widgets/duelo_mao"] = salvo
    T.ok(ok2, tostring(err2))
  end },
}
