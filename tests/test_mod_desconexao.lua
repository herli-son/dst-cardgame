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
    T.eq(cs[1].Cliente.sala().ausente.userid, nil, "o userid de quem caiu não vai para os outros")
    T.eq(cs[1].Tela.modelo().texto, "O outro jogador caiu. Se não voltar em 2:00, você vence.")
    T.eq(cs[3].Tela.modelo().texto, "O lado 2 caiu. Se não voltar em 2:00, perde a partida.")
    -- A contagem anda na tela pelo relógio do cliente, sem mensagem nova.
    local vistos = {}
    cs[1].Tela.ligar_widget({ Atualizar = function(_, m) vistos[#vistos + 1] = m.texto end })
    local enviadas = #net.mensagens.KU_um
    net.relogio = net.relogio + 25
    cs[1].Cliente.tique()
    T.eq(vistos[#vistos], "O outro jogador caiu. Se não voltar em 1:35, você vence.")
    net.relogio = net.relogio + 40
    cs[1].Cliente.tique()
    T.eq(vistos[#vistos], "O outro jogador caiu. Se não voltar em 55 s, você vence.")
    T.eq(#net.mensagens.KU_um, enviadas, "o servidor não mandou nada")
    cs[1].Tela.ligar_widget(nil)
    -- Uma sala reenviada no meio do prazo leva os segundos que faltam.
    s.Sala.avisar()
    T.eq(cs[1].Cliente.sala().ausente.prazo, PRAZO - 65)
    net.relogio = net.relogio + PRAZO - 66
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
    -- Caso a tarefa de cada segundo não rode com o servidor vazio.
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

  { "host: o jogador que cai perde em 10 segundos", function(T)
    local PRAZO_HOST = RedeFalsa.carregar("desconexao").PRAZO_HOST
    T.eq(PRAZO_HOST, 10)
    local net, h, cs = mesa("host")
    local g = h.Partida.jogo()
    -- O boneco recriado (troca de personagem): sai e volta em seguida, sem perder.
    sair(net, h, "KU_dois")
    T.eq(g.winner, nil)
    T.eq(h.Cliente.sala().ausente.prazo, PRAZO_HOST)
    net.relogio = net.relogio + 1
    voltar(net, h, "KU_dois")
    net.relogio = net.relogio + PRAZO_HOST * 3
    h.Desconexao.tique()
    T.eq(g.winner, nil, "quem voltou em seguida não perde")
    -- A queda de verdade.
    sair(net, h, "KU_dois")
    net.relogio = net.relogio + PRAZO_HOST - 1
    h.Desconexao.tique()
    T.eq(g.winner, nil)
    net.relogio = net.relogio + 1
    h.Desconexao.tique()
    T.eq(g.winner, 1, "no jogo hospedado o prazo é curto")
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
    -- Com o jogador ainda fora, o servidor começa outra partida pelo console,
    -- com os mesmos dois jogadores.
    local Decks = require("duelo/decks/init")
    local d1, e1 = Decks.build("wilson")
    local d2, e2 = Decks.build("webber")
    T.ok(s.Partida.iniciar{ decks = { d1, d2 }, extra_decks = { e1, e2 }, jogadores = { "KU_um", "KU_dois" } })
    local g = s.Partida.jogo()
    T.eq(s.Desconexao.ausente(), nil, "a ausência era da partida anterior")
    T.eq(cs[1].Cliente.sala().ausente, false, "o aviso sai da tela de quem ficou")
    net.relogio = net.relogio + PRAZO * 2
    s.Desconexao.tique()
    T.eq(g.winner, nil, "a ausência da partida antiga não vale na nova")
  end },

  { "quem está conectado não perde por desconexão", function(T)
    -- O aviso de entrada não chega com o servidor pausado: o jogador voltou
    -- (está entre os conectados), mas ninguém avisou.
    local net, s, cs = mesa()
    local g = s.Partida.jogo()
    sair(net, s, "KU_dois")
    net.relogio = net.relogio + 30
    net.jogadores[#net.jogadores + 1] = net.saidos.KU_dois
    net.relogio = net.relogio + PRAZO
    s.Desconexao.tique()
    T.eq(g.winner, nil, "conectado não perde")
    T.eq(s.Desconexao.ausente(), nil, "a ausência foi desfeita")
    -- Avisos fora de ordem: o boneco novo entra antes de o velho sair.
    net, s, cs = mesa()
    g = s.Partida.jogo()
    s.Sala.entrou("KU_dois")
    s.Sala.saiu("KU_dois")
    T.eq(s.Desconexao.ausente(), nil, "quem ainda está no servidor não fica ausente")
    net.relogio = net.relogio + PRAZO * 2
    s.Desconexao.tique()
    T.eq(g.winner, nil)
  end },

  { "quem volta retoma o lado dele na mesa", function(T)
    local chamadas = {}
    local net = RedeFalsa.nova{ sala = true, desconexao = "dedicado",
      definir_lados = function(um, dois) chamadas[#chamadas + 1] = um .. "/" .. dois end }
    local s = net:maquina{ servidor = true }
    local c1 = net:maquina{ userid = "KU_um", lado = 1 }
    local c2 = net:maquina{ userid = "KU_dois", lado = 2 }
    net.relogio = net.relogio + 1
    c1.Cliente.pronto(true); c2.Cliente.pronto(true)
    T.eq(#chamadas, 1)
    sair(net, s, "KU_dois")
    -- Outro jogador entra durante o prazo: os lados continuam os da partida.
    net.jogadores[#net.jogadores + 1] = { userid = "KU_novo" }
    s.Sala.entrou("KU_novo")
    T.eq(chamadas[#chamadas], "KU_um/KU_dois")
    voltar(net, s, "KU_dois")
    T.eq(#chamadas, 3, "a cada entrada com a partida em curso")
    T.eq(chamadas[3], "KU_um/KU_dois")
    -- Sem partida em curso, a entrada não mexe nos lados.
    s.Partida.encerrar()
    s.Sala.entrou("KU_novo")
    T.eq(#chamadas, 3)
  end },

  { "abandono com uma escolha aberta: a visão final não mostra a escolha", function(T)
    local net, s, cs = mesa()
    local g = s.Partida.jogo()
    g.pending_choice = { player = 2, reason = "teste", options = { { kind = "player", p = 1 } } }
    sair(net, s, "KU_dois")
    net.relogio = net.relogio + PRAZO
    s.Desconexao.tique()
    T.eq(g.winner, 1, "a derrota vale com a escolha aberta")
    T.eq(cs[1].Cliente.visao().escolha, false)
  end },

  { "modmain: a conferência de cada segundo roda como tarefa estática do mundo", function(T)
    local RAIZ = RedeFalsa.RAIZ
    local sim_postinits, logs, tarefas = {}, {}, {}
    local mundo = { ismastersim = true }
    function mundo:DoStaticPeriodicTask(t, fn) tarefas[#tarefas + 1] = { tipo = "estatica", t = t, fn = fn } end
    function mundo:DoPeriodicTask(t, fn) tarefas[#tarefas + 1] = { tipo = "comum", t = t, fn = fn } end
    function mundo:ListenForEvent() end
    local G = setmetatable({
      require = require, pcall = pcall, ipairs = ipairs, tostring = tostring,
      print = function(s) logs[#logs + 1] = tostring(s) end,
      TheNet = { GetIsServer = function() return true end, IsDedicated = function() return true end },
      AllPlayers = {}, GetTimeRealSeconds = function() return 0 end,
    }, { __index = _G })
    local nada = function() end
    local env = setmetatable({
      GLOBAL = G, modname = "dst-cardgame", GetModConfigData = function() return nil end,
      AddPlayerPostInit = nada, AddComponentPostInit = nada, AddPrefabPostInit = nada,
      AddSimPostInit = function(fn) sim_postinits[#sim_postinits + 1] = fn end,
      AddClassPostConstruct = nada, AddModRPCHandler = nada, AddClientModRPCHandler = nada,
      GetModRPC = nada, GetClientModRPC = nada, SendModRPCToServer = nada, SendModRPCToClient = nada,
    }, { __index = _G })
    local ok, err = pcall(function()
      local chunk = assert(loadfile(RAIZ .. "modmain.lua"))
      setfenv(chunk, env)
      chunk()
      T.eq(type(env.DUELO.Desconexao.tique), "function", "DUELO.Desconexao no servidor")
      -- Sem mundo, ou num mundo de cliente, nada é agendado.
      for _, fn in ipairs(sim_postinits) do pcall(fn) end
      T.eq(#tarefas, 0, "sem TheWorld não há tarefa")
      G.TheWorld = mundo
      for _, fn in ipairs(sim_postinits) do pcall(fn) end
      local da_desconexao = {}
      for _, tarefa in ipairs(tarefas) do
        if tarefa.t == 1 then da_desconexao[#da_desconexao + 1] = tarefa end
      end
      T.eq(#da_desconexao, 1, "uma tarefa de 1 segundo")
      T.eq(da_desconexao[1].tipo, "estatica", "estática: roda com o servidor pausado")
      da_desconexao[1].fn() -- sem partida: não faz nada e não dá erro
      -- Um erro na conferência vira um aviso.
      local original = env.DUELO.Desconexao.tique
      env.DUELO.Desconexao.tique = function() error("quebrou") end
      da_desconexao[1].fn()
      env.DUELO.Desconexao.tique = original
      local achou = false
      for _, linha in ipairs(logs) do
        if linha:find("erro na conferência", 1, true) then achou = true end
      end
      T.ok(achou, "o erro da conferência vai para o log")
    end)
    T.ok(ok, tostring(err))
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
