-- Testes da US #43: desconexão. Quem cai perde; no servidor dedicado, depois
-- de 2 minutos sem voltar.
--
-- Usa o transporte falso de tests/rede_falsa.lua, com duelo/mod/desconexao
-- no servidor e o relógio da rede falsa no lugar do tempo real. A derrota por
-- abandono no motor (Game:forfeit) é testada em tests/test_abandono.lua.

local RedeFalsa = require("rede_falsa")

-- Servidor (dedicado ou host), dois jogadores e um espectador, com a partida
-- já começada pelos dois prontos.
local function mesa(tipo)
  local net = RedeFalsa.nova{ sala = true, desconexao = tipo or "dedicado" }
  local s
  if tipo == "host" then
    s = net:maquina{ servidor = true, userid = "KU_um", lado = 1 }
  else
    s = net:maquina{ servidor = true }
  end
  local c1 = tipo == "host" and s or net:maquina{ userid = "KU_um", lado = 1 }
  local c2 = net:maquina{ userid = "KU_dois", lado = 2 }
  local c3 = net:maquina{ userid = "KU_tres", lado = 3 }
  net.relogio = net.relogio + 1
  c1.Cliente.pronto(true); c2.Cliente.pronto(true)
  assert(s.Partida.em_curso(), "a partida começou")
  return net, s, { c1, c2, c3 }
end

-- Como no jogo: quem sai some de AllPlayers e o mundo avisa.
local function sair(net, s, userid)
  for i, j in ipairs(net.jogadores) do
    if j.userid == userid then
      net.saidos = net.saidos or {}
      net.saidos[userid] = table.remove(net.jogadores, i)
      break
    end
  end
  s.Sala.saiu(userid)
end

local function voltar(net, s, userid)
  net.jogadores[#net.jogadores + 1] = net.saidos[userid]
  net.saidos[userid] = nil
  s.Sala.entrou(userid)
end

local PRAZO = RedeFalsa.carregar("desconexao").PRAZO

return {
  { "o prazo para voltar é de 2 minutos", function(T)
    T.eq(PRAZO, 120)
  end },

  { "dedicado: quem cai tem 2 minutos; voltando a tempo, a partida segue", function(T)
    local net, s, cs = mesa()
    local g = s.Partida.jogo()
    sair(net, s, "KU_dois")
    T.eq(g.winner, nil, "ninguém perde na hora")
    local a = s.Desconexao.ausente()
    T.eq(a.lado, 2); T.eq(a.userid, "KU_dois"); T.eq(a.limite, net.relogio + PRAZO)
    -- Quem ficou e quem assiste ficam sabendo.
    T.eq(cs[1].Cliente.sala().ausente.lado, 2)
    T.eq(cs[1].Cliente.sala().ausente.prazo, PRAZO)
    T.eq(cs[1].Tela.modelo().texto, "O outro jogador caiu. Se não voltar em 2 minutos, você vence.")
    T.eq(cs[3].Tela.modelo().texto, "O lado 2 caiu. Se não voltar em 2 minutos, perde a partida.")
    net.relogio = net.relogio + PRAZO - 1
    s.Desconexao.tique()
    T.eq(g.winner, nil, "um segundo antes do prazo ainda vale")
    voltar(net, s, "KU_dois")
    T.eq(s.Desconexao.ausente(), nil)
    T.eq(cs[1].Cliente.sala().ausente, false)
    T.eq(cs[1].Tela.modelo().texto, "Partida em curso. Você joga pelo lado 1.")
    net.relogio = net.relogio + PRAZO * 2
    s.Desconexao.tique()
    T.eq(g.winner, nil, "quem voltou não perde depois")
    T.eq(s.Partida.jogo(), g)
    -- Quem volta recebe a fotografia e continua jogando pelo lado dele.
    cs[2].Cliente.pedir_estado()
    T.eq(cs[2].Cliente.lado(), 2)
  end },

  { "dedicado: quem não volta em 2 minutos perde e o outro vence", function(T)
    local net, s, cs = mesa()
    local g = s.Partida.jogo()
    sair(net, s, "KU_um")
    net.relogio = net.relogio + PRAZO
    s.Desconexao.tique()
    T.eq(g.winner, 2)
    T.eq(g.forfeited.p, 1); T.eq(g.forfeited.reason, "desconexao")
    T.ok(s.Partida.terminada())
    local m2, m3 = cs[2].Tela.modelo(), cs[3].Tela.modelo()
    T.eq(m2.modo, "fim"); T.eq(m2.titulo, "Vitória")
    T.eq(m2.texto, "O outro jogador saiu da partida.")
    T.eq(m2.botao.texto, "Jogar de novo")
    T.eq(m3.titulo, "Lado 2 venceu"); T.eq(m3.texto, "O lado 1 saiu da partida.")
    T.eq(cs[2].Cliente.sala().ausente, false, "o aviso de ausência some com o fim")
    T.eq(s.Desconexao.ausente(), nil)
    -- Quem perdeu, ao voltar, vê a derrota e o motivo.
    voltar(net, s, "KU_um")
    net.relogio = net.relogio + 2
    cs[1].Cliente.pedir_estado()
    local m1 = cs[1].Tela.modelo()
    T.eq(m1.titulo, "Derrota"); T.eq(m1.texto, "Você saiu da partida e não voltou a tempo.")
    -- A mesa não fica presa: quem ficou pode jogar de novo.
    net.relogio = net.relogio + 1
    cs[2].Tela.clicar()
    T.ok(not s.Partida.em_curso(), "a mesa zerou")
    T.eq(s.Sala.prontos()[1], "KU_dois")
  end },

  { "dedicado: quem volta depois do prazo perde na hora em que entra", function(T)
    -- Com o servidor vazio a simulação pausa e a tarefa de cada segundo não roda.
    local net, s, cs = mesa()
    local g = s.Partida.jogo()
    sair(net, s, "KU_dois")
    net.relogio = net.relogio + PRAZO + 30
    voltar(net, s, "KU_dois")
    T.eq(g.winner, 1, "o prazo é em tempo real")
    T.eq(g.forfeited.p, 2)
  end },

  { "dedicado: se os dois caem, perde quem caiu primeiro", function(T)
    local net, s, cs = mesa()
    local g = s.Partida.jogo()
    sair(net, s, "KU_dois")
    net.relogio = net.relogio + 10
    sair(net, s, "KU_um")
    T.eq(s.Desconexao.ausente().userid, "KU_dois", "o prazo mais perto de vencer")
    net.relogio = net.relogio + PRAZO - 10
    s.Desconexao.tique()
    T.eq(g.winner, 1, "o lado 2 caiu primeiro")
    -- O segundo não perde uma partida que já acabou.
    net.relogio = net.relogio + PRAZO
    s.Desconexao.tique()
    T.eq(g.winner, 1)
    -- O primeiro volta a tempo: o prazo que corre é o do segundo.
    net, s, cs = mesa()
    g = s.Partida.jogo()
    sair(net, s, "KU_dois")
    net.relogio = net.relogio + 10
    sair(net, s, "KU_um")
    net.relogio = net.relogio + 10
    voltar(net, s, "KU_dois")
    T.eq(s.Desconexao.ausente().userid, "KU_um")
    T.eq(cs[2].Cliente.sala().ausente.lado, 1)
    net.relogio = net.relogio + PRAZO - 10
    s.Desconexao.tique()
    T.eq(g.winner, 2)
  end },

  { "host: o jogador que cai perde na hora", function(T)
    local net, h, cs = mesa("host")
    local g = h.Partida.jogo()
    sair(net, h, "KU_dois")
    T.eq(g.winner, 1, "sem prazo no jogo hospedado")
    T.eq(g.forfeited.p, 2)
    T.eq(h.Desconexao.ausente(), nil)
    local m = h.Tela.modelo()
    T.eq(m.titulo, "Vitória"); T.eq(m.texto, "O outro jogador saiu da partida.")
    T.eq(h.Cliente.sala().ausente, false)
  end },

  { "quem assiste sai e volta sem mudar a partida", function(T)
    for _, tipo in ipairs({ "dedicado", "host" }) do
      local net, s, cs = mesa(tipo)
      local g = s.Partida.jogo()
      sair(net, s, "KU_tres")
      T.eq(s.Desconexao.ausente(), nil, tipo)
      net.relogio = net.relogio + PRAZO * 2
      s.Desconexao.tique()
      T.eq(g.winner, nil, tipo)
      voltar(net, s, "KU_tres")
      T.eq(g.winner, nil, tipo)
    end
  end },

  { "sem partida em curso, sair não faz nada; partida terminada não muda", function(T)
    local net = RedeFalsa.nova{ sala = true, desconexao = "dedicado" }
    local s = net:maquina{ servidor = true }
    local c1 = net:maquina{ userid = "KU_um", lado = 1 }
    local c2 = net:maquina{ userid = "KU_dois", lado = 2 }
    sair(net, s, "KU_um")
    T.eq(s.Desconexao.ausente(), nil)
    voltar(net, s, "KU_um")
    net.relogio = net.relogio + 1
    c1.Cliente.pronto(true); c2.Cliente.pronto(true)
    local g = s.Partida.jogo()
    g.players[2].life = 0
    g:check_winner()
    T.eq(g.winner, 1)
    sair(net, s, "KU_um")
    net.relogio = net.relogio + PRAZO
    s.Desconexao.tique()
    T.eq(g.winner, 1, "o vencedor que sai depois do fim continua vencedor")
    T.eq(g.forfeited, nil)
    -- Pedidos tortos.
    s.Desconexao.saiu(nil); s.Desconexao.saiu(""); s.Desconexao.saiu(7)
    s.Desconexao.entrou(nil); s.Desconexao.entrou({})
  end },

  { "o prazo de uma partida não passa para a seguinte", function(T)
    local net, s, cs = mesa()
    sair(net, s, "KU_dois")
    -- O servidor encerra a partida e começa outra, com os mesmos jogadores.
    voltar(net, s, "KU_dois")
    sair(net, s, "KU_dois")
    s.Partida.encerrar()
    voltar(net, s, "KU_dois")
    net.relogio = net.relogio + 1
    cs[1].Cliente.pronto(true); cs[2].Cliente.pronto(true)
    local g = s.Partida.jogo()
    T.ok(g ~= nil)
    net.relogio = net.relogio + PRAZO * 2
    s.Desconexao.tique()
    T.eq(g.winner, nil, "a ausência da partida antiga não vale na nova")
    T.eq(s.Desconexao.ausente(), nil)
  end },

  { "partida de teste com um jogador só: no fim do prazo é só encerrada", function(T)
    local net = RedeFalsa.nova{ sala = true, desconexao = "dedicado" }
    local s = net:maquina{ servidor = true }
    local c1 = net:maquina{ userid = "KU_um", lado = 1 }
    T.ok(s.Partida.iniciar_teste(5))
    local g = s.Partida.jogo()
    sair(net, s, "KU_um")
    T.ok(s.Partida.em_curso(), "dentro do prazo a partida fica")
    net.relogio = net.relogio + PRAZO
    s.Desconexao.tique()
    T.ok(not s.Partida.em_curso(), "a partida de teste foi encerrada")
    T.eq(g.winner, nil, "ninguém vence")
  end },

  { "a derrota espera se um lote está saindo e é aplicada na conferência seguinte", function(T)
    local net, s, cs = mesa()
    local g = s.Partida.jogo()
    sair(net, s, "KU_dois")
    net.relogio = net.relogio + PRAZO
    -- De dentro de um ouvinte de eventos de um cliente (um lote saindo), a
    -- derrota é recusada pela partida.
    local resultado
    local cancelar = cs[1].Cliente.quando_evento(function()
      if resultado == nil then resultado = { s.Partida.derrotar(2, "desconexao") } end
    end)
    net.relogio = net.relogio + 1
    T.ok(cs[g.active].Cliente.enviar({ type = "pass" }))
    cancelar()
    T.ok(resultado ~= nil and resultado[1] == false, "recusada durante o envio")
    T.eq(g.winner, nil)
    s.Desconexao.tique()
    T.eq(g.winner, 1, "a conferência seguinte aplica")
  end },

  { "o cliente só aceita uma ausência bem formada", function(T)
    local net = RedeFalsa.nova{ sala = true }
    net:maquina{ servidor = true }
    local c = net:maquina{ userid = "KU_um", lado = 1 }
    for _, a in ipairs({ { lado = 3, prazo = 120 }, { lado = "1" }, "sim", 5, {} }) do
      c.Cliente.receber("sala", { eu = false, prontos = 0, jogadores = 1, ausente = a })
      T.eq(c.Cliente.sala().ausente, false)
    end
    c.Cliente.receber("sala", { eu = false, prontos = 0, jogadores = 1, ausente = { lado = 2, prazo = -5, a_mais = "x" } })
    T.eq(c.Cliente.sala().ausente.lado, 2)
    T.eq(c.Cliente.sala().ausente.prazo, 0, "prazo torto vira 0")
    T.eq(c.Cliente.sala().ausente.a_mais, nil)
  end },

  { "a visão diz quem abandonou, para os dois lados e para quem assiste", function(T)
    local net, s, cs = mesa()
    T.eq(cs[1].Cliente.visao().abandono, false)
    local recebidos = { {}, {}, {} }
    for i = 1, 3 do
      cs[i].Cliente.quando_evento(function(ev) recebidos[i][#recebidos[i] + 1] = ev end)
    end
    sair(net, s, "KU_dois")
    net.relogio = net.relogio + PRAZO
    s.Desconexao.tique()
    for i = 1, 3, 2 do
      local v = cs[i].Cliente.visao()
      T.eq(v.abandono.p, 2); T.eq(v.abandono.motivo, "desconexao")
      T.eq(v.vencedor, 1)
      local achou = false
      for _, ev in ipairs(recebidos[i]) do
        if ev.t == "forfeit" then
          achou = true
          T.eq(ev.p, 2); T.eq(ev.reason, "desconexao")
        end
      end
      T.ok(achou, "o evento forfeit chega ao cliente " .. i)
    end
  end },
}
