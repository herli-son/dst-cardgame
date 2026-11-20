-- Testes da US #42: início e fim da partida.
--
-- O jogo não roda aqui: o transporte falso de tests/rede_falsa.lua liga um
-- servidor e os clientes, com a sala (duelo/mod/sala_servidor) no servidor e
-- o modelo do painel (duelo/mod/tela_sala) em cada cliente. O "clique" no
-- botão é Tela.clicar().

local RedeFalsa = require("rede_falsa")

-- Servidor dedicado, dois jogadores (lados 1 e 2 da mesa) e um espectador.
local function mesa(opcoes)
  opcoes = opcoes or {}
  local net = RedeFalsa.nova{ sala = true, decks = opcoes.decks }
  local s = net:maquina{ servidor = true }
  local lados = opcoes.lados or { 1, 2, 3 }
  local c1 = net:maquina{ userid = "KU_um", lado = lados[1] or nil }
  local c2 = net:maquina{ userid = "KU_dois", lado = lados[2] or nil }
  local c3 = net:maquina{ userid = "KU_tres", lado = lados[3] or nil }
  return net, s, { c1, c2, c3 }
end

-- Cada chamada anda o relógio: estes testes não são sobre a taxa.
local function pronto(net, c, valor)
  net.relogio = net.relogio + 1
  return c.Cliente.pronto(valor ~= false)
end

local function clicar(net, c)
  net.relogio = net.relogio + 1
  c.Tela.clicar()
end

-- Os dois ficam prontos e a partida começa.
local function comecar(T, net, s, cs)
  pronto(net, cs[1]); pronto(net, cs[2])
  T.ok(s.Partida.em_curso(), "a partida começou")
  return s.Partida.jogo()
end

-- Acaba a partida com a vitória do lado `vencedor` (0 = empate): zera a vida
-- e manda um passe, para o lote com o fim sair pela rede.
local function terminar(T, net, s, cs, vencedor)
  local g = s.Partida.jogo()
  if vencedor ~= 1 then g.players[1].life = 0 end
  if vencedor ~= 2 then g.players[2].life = 0 end
  g:check_winner()
  T.eq(g.winner, vencedor, "o motor deu o resultado")
  -- A ação é recusada (a partida acabou), mas o lote com o fim sai.
  net.relogio = net.relogio + 1
  T.ok(cs[1].Cliente.enviar({ type = "pass" }), "passe enviado")
  T.ok(s.Partida.terminada(), "a partida terminou")
end

-- Um cliente falso para os casos do painel que não dependem da rede.
local function cliente_falso(dados)
  local C = { prontos = {} }
  function C.visao() return dados.visao end
  function C.partida() return dados.partida end
  function C.lado() return dados.lado end
  function C.sala() return dados.sala end
  function C.quando_estado() end
  function C.quando_evento() end
  function C.quando_sala() end
  function C.pronto(v) C.prontos[#C.prontos + 1] = v; return true end
  return C
end

return {
  { "sem partida, o painel oferece o botão Pronto", function(T)
    local net, s, cs = mesa()
    local m = cs[1].Tela.modelo()
    T.eq(m.modo, "sala")
    T.eq(m.botao, false, "sem botão antes de a sala chegar")
    T.eq(m.texto, "Conectando à mesa...")
    -- Ao entrar, o cliente pede a fotografia; a sala vem junto.
    cs[1].Cliente.pedir_estado()
    m = cs[1].Tela.modelo()
    T.eq(m.titulo, "Duelo")
    T.eq(m.texto, "Clique em Pronto para jogar.")
    T.eq(m.botao.texto, "Pronto")
    T.eq(cs[1].Cliente.sala().jogadores, 3, "conta os conectados")
    T.ok(not s.Partida.em_curso())
  end },

  { "um jogador pronto espera o outro; a partida não começa", function(T)
    local net, s, cs = mesa()
    clicar(net, cs[1]) -- sem sala ainda: não há botão, nada acontece
    T.eq(#s.Sala.prontos(), 0)
    cs[1].Cliente.pedir_estado()
    clicar(net, cs[1])
    T.eq(s.Sala.prontos()[1], "KU_um")
    T.ok(not s.Partida.em_curso(), "com um pronto não começa")
    local m1, m2 = cs[1].Tela.modelo(), cs[2].Tela.modelo()
    T.eq(m1.texto, "Você está pronto. Aguardando o outro jogador.")
    T.eq(m1.botao.texto, "Cancelar")
    T.eq(m2.texto, "O outro jogador está pronto. Clique em Pronto para começar.")
    T.eq(m2.botao.texto, "Pronto")
    -- Cada um só sabe de si e dos totais.
    T.eq(cs[2].Cliente.sala().eu, false)
    T.eq(cs[2].Cliente.sala().prontos, 1)
    for _, msg in ipairs(net.mensagens.KU_dois or {}) do
      if msg.tipo == "sala" then
        for k in pairs(msg.m) do
          T.ok(k == "eu" or k == "prontos" or k == "jogadores" or k == "aviso", "campo a mais na sala: " .. tostring(k))
        end
      end
    end
  end },

  { "com dois prontos a partida começa sozinha com os decks fixos", function(T)
    local net, s, cs = mesa()
    local g = comecar(T, net, s, cs)
    local j = s.Partida.jogadores()
    T.eq(j[1], "KU_um"); T.eq(j[2], "KU_dois")
    -- Wilson no lado 1 e Webber no lado 2 (o campeão está no baralho de cada um).
    local function tem(p, id)
      for _, zona in ipairs({ g.players[p].hand, g.players[p].deck }) do
        for _, c in ipairs(zona) do if c.id == id then return true end end
      end
      return false
    end
    T.ok(tem(1, "wilson") and not tem(1, "webber"), "lado 1 joga com o deck do Wilson")
    T.ok(tem(2, "webber") and not tem(2, "wilson"), "lado 2 joga com o deck do Webber")
    T.eq(#s.Sala.prontos(), 0, "a sala esvazia quando a partida começa")
    T.eq(cs[1].Cliente.lado(), 1); T.eq(cs[2].Cliente.lado(), 2); T.eq(cs[3].Cliente.lado(), 3)
    T.eq(cs[1].Tela.modelo().modo, "partida")
    T.eq(cs[1].Tela.modelo().texto, "Partida em curso. Você joga pelo lado 1.")
    T.eq(cs[2].Tela.modelo().texto, "Partida em curso. Você joga pelo lado 2.")
    T.eq(cs[3].Tela.modelo().texto, "Partida em curso. Você está assistindo.")
    T.eq(cs[1].Tela.modelo().botao, false, "sem botão durante a partida")
    T.eq(cs[1].Cliente.sala().eu, false, "ninguém fica marcado como pronto")
  end },

  { "cada um joga pelo lado da mesa em que está, não pela ordem do clique", function(T)
    local net, s, cs = mesa()
    pronto(net, cs[2]); pronto(net, cs[1])
    local j = s.Partida.jogadores()
    T.eq(j[1], "KU_um", "quem está no lado 1 da mesa joga pelo lado 1")
    T.eq(j[2], "KU_dois")
    -- Sem lado na mesa, vale a ordem em que ficaram prontos.
    net, s, cs = mesa{ lados = {} }
    pronto(net, cs[2]); pronto(net, cs[1])
    j = s.Partida.jogadores()
    T.eq(j[1], "KU_dois"); T.eq(j[2], "KU_um")
    -- Um jogador da mesa e um espectador: o da mesa fica no lado dele.
    net, s, cs = mesa()
    pronto(net, cs[3]); pronto(net, cs[2])
    j = s.Partida.jogadores()
    T.eq(j[1], "KU_tres"); T.eq(j[2], "KU_dois")
  end },

  { "quem cancela deixa de estar pronto", function(T)
    local net, s, cs = mesa()
    pronto(net, cs[1])
    clicar(net, cs[1]) -- o botão agora é Cancelar
    T.eq(#s.Sala.prontos(), 0)
    T.eq(cs[1].Tela.modelo().botao.texto, "Pronto")
    pronto(net, cs[2])
    T.ok(not s.Partida.em_curso(), "o outro pronto sozinho não começa")
    -- Pronto duas vezes conta uma.
    pronto(net, cs[2])
    T.eq(#s.Sala.prontos(), 1)
    T.ok(not s.Partida.em_curso())
  end },

  { "com a partida em curso, ninguém fica pronto", function(T)
    local net, s, cs = mesa()
    local g = comecar(T, net, s, cs)
    pronto(net, cs[3]); pronto(net, cs[1])
    T.eq(#s.Sala.prontos(), 0)
    T.eq(s.Partida.jogo(), g, "a partida segue a mesma")
    T.eq(cs[3].Cliente.sala().eu, false)
  end },

  { "no fim cada um vê o resultado e a partida fica na mesa", function(T)
    local net, s, cs = mesa()
    comecar(T, net, s, cs)
    terminar(T, net, s, cs, 1)
    local m1, m2, m3 = cs[1].Tela.modelo(), cs[2].Tela.modelo(), cs[3].Tela.modelo()
    T.eq(m1.modo, "fim"); T.eq(m1.titulo, "Vitória"); T.eq(m1.botao.texto, "Jogar de novo")
    T.eq(m2.titulo, "Derrota"); T.eq(m2.botao.texto, "Jogar de novo")
    T.eq(m3.titulo, "Lado 1 venceu"); T.eq(m3.botao.texto, "Fechar")
    T.ok(s.Partida.em_curso(), "a partida terminada fica até alguém ficar pronto")
    -- Empate.
    net, s, cs = mesa()
    comecar(T, net, s, cs)
    terminar(T, net, s, cs, 0)
    T.eq(cs[1].Tela.modelo().titulo, "Empate")
    T.eq(cs[2].Tela.modelo().titulo, "Empate")
    T.eq(cs[3].Tela.modelo().titulo, "Empate")
  end },

  { "jogar de novo zera a mesa para todos e a partida seguinte começa", function(T)
    local net, s, cs = mesa()
    comecar(T, net, s, cs)
    terminar(T, net, s, cs, 2)
    T.eq(cs[1].Tela.modelo().titulo, "Derrota")
    clicar(net, cs[2]) -- o vencedor clica em Jogar de novo
    T.ok(not s.Partida.em_curso(), "a mesa zerou no servidor")
    for i = 1, 3 do T.eq(cs[i].Cliente.visao(), nil, "a mesa zerou no cliente " .. i) end
    T.eq(s.Sala.prontos()[1], "KU_dois", "quem clicou já está pronto")
    T.eq(cs[2].Tela.modelo().modo, "sala")
    T.eq(cs[2].Tela.modelo().texto, "Você está pronto. Aguardando o outro jogador.")
    -- O outro ainda vê o resultado dele, com o aviso de que o outro quer jogar.
    local m1 = cs[1].Tela.modelo()
    T.eq(m1.modo, "fim"); T.eq(m1.titulo, "Derrota")
    T.eq(m1.texto, "O outro jogador quer jogar de novo.")
    clicar(net, cs[1])
    T.ok(s.Partida.em_curso() and not s.Partida.terminada(), "a segunda partida começou")
    T.eq(cs[1].Cliente.partida(), 2); T.eq(cs[2].Cliente.partida(), 2)
    T.eq(cs[1].Tela.modelo().modo, "partida")
    T.eq(cs[2].Tela.modelo().modo, "partida")
    local g = s.Partida.jogo()
    T.eq(g.players[1].life, 20, "a partida nova começa do zero"); T.eq(g.round, 1)
    -- O espectador que não clicou em nada passa a ver a partida nova.
    T.eq(cs[3].Tela.modelo().modo, "partida")
  end },

  { "quem assiste fecha o resultado sem zerar a mesa nem ficar pronto", function(T)
    local net, s, cs = mesa()
    comecar(T, net, s, cs)
    terminar(T, net, s, cs, 1)
    clicar(net, cs[3])
    T.ok(s.Partida.em_curso(), "a partida terminada continua na mesa")
    T.eq(#s.Sala.prontos(), 0)
    local m = cs[3].Tela.modelo()
    T.eq(m.modo, "sala", "depois de fechar, a sala")
    T.eq(m.botao.texto, "Pronto")
    T.eq(cs[1].Tela.modelo().titulo, "Vitória", "os jogadores continuam vendo o resultado")
    -- O resultado dispensado não volta com uma fotografia nova da mesma partida.
    net.relogio = net.relogio + 2
    cs[3].Cliente.pedir_estado()
    T.eq(cs[3].Tela.modelo().modo, "sala")
  end },

  { "quem sai deixa de estar pronto e os outros ficam sabendo", function(T)
    local net, s, cs = mesa()
    pronto(net, cs[1])
    T.eq(cs[2].Cliente.sala().prontos, 1)
    -- Durante o aviso de saída o jogador ainda está em AllPlayers.
    s.Sala.saiu("KU_um")
    T.eq(#s.Sala.prontos(), 0)
    T.eq(cs[2].Cliente.sala().prontos, 0)
    T.eq(cs[2].Cliente.sala().jogadores, 2, "quem está saindo não conta")
    -- Depois que ele some de AllPlayers, o pronto dele não vale mais.
    table.remove(net.jogadores, 1)
    local ok = s.Sala.receber_pronto("KU_um", true)
    T.ok(not ok, "quem não está conectado não fica pronto")
    pronto(net, cs[2])
    T.ok(not s.Partida.em_curso())
    -- Quem entra faz todos receberem a contagem nova.
    net.jogadores[#net.jogadores + 1] = { userid = "KU_novo" }
    s.Sala.entrou("KU_novo")
    T.eq(cs[2].Cliente.sala().jogadores, 3)
    -- A saída de um jogador não encerra a partida em curso.
    net, s, cs = mesa()
    local g = comecar(T, net, s, cs)
    s.Sala.saiu("KU_dois")
    T.eq(s.Partida.jogo(), g, "a partida continua para ele voltar")
  end },

  { "pedidos tortos e em excesso são ignorados", function(T)
    local net, s, cs = mesa()
    T.ok(not s.Sala.receber_pronto("KU_um", "sim"), "só booleano")
    T.ok(not s.Sala.receber_pronto(nil, true))
    T.ok(not s.Sala.receber_pronto("", true))
    T.ok(not s.Sala.receber_pronto("KU_ninguem", true), "só quem está conectado")
    T.ok(not cs[1].Cliente.pronto("sim"), "o cliente nem envia")
    -- Direto na RPC do servidor, com valores que o cliente não mandaria.
    for _, v in ipairs({ "sim", 1, {} }) do s.srv.pronto(cs[1].jogador, v) end
    s.srv.pronto(nil, true)
    s.srv.pronto({ userid = 7 }, true)
    T.eq(#s.Sala.prontos(), 0)
    -- Taxa: no mesmo segundo, só os primeiros PRONTOS_POR_SEGUNDO valem.
    local limite = s.Rede.LIMITES.PRONTOS_POR_SEGUNDO
    for i = 1, limite do cs[1].Cliente.pronto(i % 2 == 1) end
    T.eq(#s.Sala.prontos(), limite % 2, "os pedidos dentro do limite valeram")
    local antes = #s.Sala.prontos()
    cs[1].Cliente.pronto(antes == 0)
    T.eq(#s.Sala.prontos(), antes, "o excesso foi ignorado")
    net.relogio = net.relogio + 1
    cs[1].Cliente.pronto(antes == 0)
    T.eq(#s.Sala.prontos(), 1 - antes, "no segundo seguinte volta a valer")
  end },

  { "se a partida não puder começar, a sala avisa e esvazia", function(T)
    local net, s, cs = mesa{ decks = function() error("baralho quebrado") end }
    pronto(net, cs[1]); pronto(net, cs[2])
    T.ok(not s.Partida.em_curso())
    T.eq(#s.Sala.prontos(), 0)
    T.eq(cs[1].Tela.modelo().texto, "Não foi possível começar a partida.")
    T.eq(cs[1].Tela.modelo().botao.texto, "Pronto")
    local achou = false
    for _, linha in ipairs(s.logs) do
      if linha:find("baralho quebrado", 1, true) then achou = true end
    end
    T.ok(achou, "o motivo fica no log do servidor")
    for _, msg in ipairs(net.mensagens.KU_um) do
      if msg.tipo == "sala" then
        T.ok(not tostring(msg.m.aviso):find("quebrado", 1, true), "o detalhe não vai para o cliente")
      end
    end
    -- O aviso some quando alguém fica pronto de novo.
    pronto(net, cs[2])
    T.eq(cs[1].Cliente.sala().aviso, false)
  end },

  { "uma partida começada pelo console esvazia a sala", function(T)
    local net, s, cs = mesa()
    pronto(net, cs[1])
    T.ok(s.Partida.iniciar_teste(5))
    T.eq(#s.Sala.prontos(), 0)
    T.eq(cs[1].Cliente.sala().eu, false)
    T.eq(cs[1].Tela.modelo().modo, "partida")
  end },

  { "host: o jogador local e um amigo ficam prontos e jogam", function(T)
    local net = RedeFalsa.nova{ sala = true }
    local h = net:maquina{ servidor = true, userid = "KU_host", lado = 1 }
    local a = net:maquina{ userid = "KU_amigo", lado = 2 }
    h.Cliente.pedir_estado()
    T.eq(h.Tela.modelo().botao.texto, "Pronto")
    h.Tela.clicar()
    T.eq(h.Sala.prontos()[1], "KU_host")
    T.eq(net.rpcs_servidor.pronto, nil, "o pronto do host não passa pela RPC")
    T.eq(a.Tela.modelo().texto, "O outro jogador está pronto. Clique em Pronto para começar.")
    a.Tela.clicar()
    T.ok(h.Partida.em_curso())
    T.eq(h.Cliente.lado(), 1); T.eq(a.Cliente.lado(), 2)
    T.eq(h.Tela.modelo().modo, "partida"); T.eq(a.Tela.modelo().modo, "partida")
  end },

  { "erro do motor: o painel diz que a partida foi interrompida", function(T)
    local dados = {
      partida = 4, lado = 2,
      visao = { vencedor = false, erro = "erro interno" },
      sala = { eu = false, prontos = 0, jogadores = 2, aviso = false },
    }
    local C = cliente_falso(dados)
    local Tela = RedeFalsa.carregar("tela_sala").instalar({ cliente = C })
    local m = Tela.modelo()
    T.eq(m.modo, "fim"); T.eq(m.titulo, "Partida interrompida")
    T.eq(m.texto, "O jogo encontrou um erro e a partida foi encerrada.")
    T.eq(m.botao.texto, "Jogar de novo")
    Tela.clicar()
    T.eq(C.prontos[1], true, "jogar de novo deixa pronto")
    T.eq(Tela.modelo().modo, "sala")
    -- Uma partida nova terminada mostra o resultado dela.
    dados.partida, dados.visao = 5, { vencedor = 2, erro = false }
    T.eq(Tela.modelo().titulo, "Vitória")
  end },

  { "o painel só é atualizado pelo modelo e sobrevive a um widget morto", function(T)
    local dados = { sala = { eu = false, prontos = 0, jogadores = 1, aviso = false } }
    local C = cliente_falso(dados)
    local logs = {}
    local Tela = RedeFalsa.carregar("tela_sala").instalar({ cliente = C, log = function(s) logs[#logs + 1] = s end })
    local vistos = {}
    Tela.ligar_widget({ Atualizar = function(_, m) vistos[#vistos + 1] = m end })
    T.eq(#vistos, 1, "ao ligar, o widget recebe o modelo")
    T.eq(vistos[1].texto, "Aguardando um segundo jogador entrar no mundo.")
    Tela.clicar()
    T.eq(C.prontos[1], true)
    T.eq(#vistos, 2, "o clique atualiza o painel")
    Tela.ligar_widget({ Atualizar = function() error("widget morto") end })
    T.eq(#logs, 1, "o erro vira um aviso")
    Tela.atualizar() -- desligado: não tenta de novo
    T.eq(#logs, 1)
  end },

  { "widgets/duelo_sala mostra o título, o texto e o botão do modelo", function(T)
    -- Classes de tela falsas, no lugar das do jogo.
    local function classe()
      local c = {}
      c.__index = c
      function c:AddChild(w) return w end
      function c:SetPosition(x, y) self.pos = { x, y } end
      function c:Show() self.visivel = true end
      function c:Hide() self.visivel = false end
      function c:SetString(s) self.texto = s end
      function c:SetText(s) self.texto = s end
      return c
    end
    local Widget, Text = classe(), classe()
    Widget._ctor = function(self, nome) self.nome = nome end
    local clique
    local salvos = {
      widget = package.loaded["widgets/widget"], text = package.loaded["widgets/text"],
      templates = package.loaded["widgets/redux/templates"], Class = _G.Class, fonte = _G.NEWFONT_OUTLINE,
    }
    package.loaded["widgets/widget"] = Widget
    package.loaded["widgets/text"] = setmetatable({}, { __call = function() return setmetatable({}, Text) end })
    package.loaded["widgets/redux/templates"] = {
      StandardButton = function(fn, txt, tam)
        clique = fn
        return setmetatable({ texto = txt, tam = tam }, classe())
      end,
    }
    _G.NEWFONT_OUTLINE = "fonte"
    _G.Class = function(base, ctor)
      local c = setmetatable({}, { __index = base, __call = function(c, ...)
        local o = setmetatable({}, c); ctor(o, ...); return o
      end })
      c.__index = c
      return c
    end
    local ok, err = pcall(function()
      local DueloSala = assert(loadfile(RedeFalsa.RAIZ .. "scripts/widgets/duelo_sala.lua"))()
      local cliques = 0
      local w = DueloSala(function() cliques = cliques + 1 end)
      T.eq(w.nome, "DueloSala")
      T.eq(w.titulo.visivel, false); T.eq(w.botao.visivel, false)
      w:Atualizar({ titulo = "Duelo", texto = "Clique em Pronto para jogar.", botao = { texto = "Pronto" } })
      T.eq(w.titulo.texto, "Duelo"); T.eq(w.titulo.visivel, true)
      T.eq(w.texto.texto, "Clique em Pronto para jogar."); T.eq(w.texto.visivel, true)
      T.eq(w.botao.texto, "Pronto"); T.eq(w.botao.visivel, true)
      clique()
      T.eq(cliques, 1, "o clique chega a quem criou o painel")
      w:Atualizar({ titulo = false, texto = "Partida em curso. Você joga pelo lado 1.", botao = false })
      T.eq(w.titulo.visivel, false); T.eq(w.botao.visivel, false)
      T.eq(w.texto.visivel, true)
      T.ok(w.texto.pos[2] > -95, "sem título, o texto sobe")
      w:Atualizar(nil)
      T.eq(w.texto.visivel, false)
    end)
    package.loaded["widgets/widget"], package.loaded["widgets/text"] = salvos.widget, salvos.text
    package.loaded["widgets/redux/templates"] = salvos.templates
    _G.Class, _G.NEWFONT_OUTLINE = salvos.Class, salvos.fonte
    T.ok(ok, tostring(err))
  end },

  { "o painel não carrega o motor nem as cartas", function(T)
    local pedidos, original = {}, require
    _G.require = function(nome) pedidos[nome] = true; return original(nome) end
    local ok, err = pcall(function() RedeFalsa.carregar("tela_sala") end)
    _G.require = original
    T.ok(ok, tostring(err))
    T.eq(next(pedidos), nil, "duelo/mod/tela_sala não pede nenhum módulo")
  end },
}
