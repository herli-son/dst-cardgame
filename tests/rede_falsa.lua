-- Transporte falso em memória para os testes do mod (US #41 e US #42): faz o
-- papel das RPCs de mod e liga várias "máquinas" (um servidor, dedicado ou
-- host, e os clientes). Cada máquina carrega cópias novas dos módulos de
-- scripts/duelo/mod (eles guardam estado em locais do arquivo), com um GLOBAL
-- falso. As RPCs são entregues na hora, na ordem.
--
--   RedeFalsa.nova{ sala = true, decks = fn } -> net
--       sala: instala também duelo/mod/sala_servidor no servidor e
--       duelo/mod/tela_sala em cada cliente (US #42).
--   net:maquina{ servidor = bool, userid = texto, lado = n } -> máquina

local Serial = require("duelo/core/serial")

local RAIZ = "./"

local function carregar(nome)
  local fn, err = loadfile(RAIZ .. "scripts/duelo/mod/" .. nome .. ".lua")
  assert(fn, err)
  return fn()
end

----------------------------------------------------------------------------
-- Transporte falso
----------------------------------------------------------------------------

local function nova_rede(opcoes)
  opcoes = opcoes or {}
  local net = {
    maquinas = {},      -- todas, na ordem de criação
    servidor = nil,     -- a máquina que é servidor
    jogadores = {},     -- AllPlayers do servidor
    relogio = 0,
    perder = nil,       -- fn(userid, tipo, id, i, total) -> true: o pedaço some
    mensagens = {},     -- userid -> lista de { tipo = , m = tabela } recebidas
    pedacos = {},       -- todos os pedaços enviados: { userid, tipo, bytes }
    rpcs_servidor = {}, -- nome -> quantas chegaram ao servidor
    _juntando = {},
  }

  local function observar(userid, tipo, id, i, total, pedaco)
    net.pedacos[#net.pedacos + 1] = { userid = userid, tipo = tipo, bytes = #pedaco }
    local chave = userid .. "/" .. tipo
    if i == 1 then net._juntando[chave] = {} end
    local partes = net._juntando[chave]
    partes[i] = pedaco
    if i == total then
      net.mensagens[userid] = net.mensagens[userid] or {}
      table.insert(net.mensagens[userid], { tipo = tipo, m = Serial.deserialize(table.concat(partes)) })
    end
  end

  -- opts.servidor: roda a partida; opts.userid: tem jogador local (cliente
  -- ou host); opts.lado: valor da netvar duelo_lado do jogador.
  function net:maquina(opts)
    local m = { net = net, userid = opts.userid, logs = {}, srv = {}, cli = {} }
    local jogador = nil
    if opts.userid then
      jogador = { userid = opts.userid }
      if opts.lado then jogador.duelo_lado = { value = function() return opts.lado end } end
      function jogador:ListenForEvent(nome, fn) self.eventos = self.eventos or {}; self.eventos[nome] = fn end
      net.jogadores[#net.jogadores + 1] = jogador
    end
    m.jogador = jogador
    m.GLOBAL = {
      TheNet = { GetIsServer = function() return opts.servidor == true end },
      ThePlayer = jogador,
      AllPlayers = opts.servidor and net.jogadores or {},
      -- O relógio da simulação fica parado (servidor pausado): a taxa e as
      -- retentativas usam o tempo real.
      GetTime = function() return 0 end,
      GetTimeRealSeconds = function() return net.relogio end,
      print = function(s) m.logs[#m.logs + 1] = tostring(s) end,
    }
    local ctx = {
      GLOBAL = m.GLOBAL,
      AddModRPCHandler = function(ns, nome, fn) m.srv[nome] = fn; m.ordem = (m.ordem or "") .. "s:" .. nome .. ";" end,
      AddClientModRPCHandler = function(ns, nome, fn) m.cli[nome] = fn; m.ordem = (m.ordem or "") .. "c:" .. nome .. ";" end,
      GetModRPC = function(ns, nome) assert(m.srv[nome], "RPC não registrada: " .. nome); return { namespace = ns, id = nome } end,
      GetClientModRPC = function(ns, nome) assert(m.cli[nome], "RPC não registrada: " .. nome); return { namespace = ns, id = nome } end,
      SendModRPCToServer = function(rpc, ...)
        assert(not opts.servidor, "o servidor não manda RPC para si mesmo")
        net.rpcs_servidor[rpc.id] = (net.rpcs_servidor[rpc.id] or 0) + 1
        net.servidor.srv[rpc.id](jogador, ...)
      end,
      SendModRPCToClient = function(rpc, users, id, i, total, pedaco)
        assert(opts.servidor, "só o servidor manda RPC de cliente")
        if type(users) ~= "table" then users = { users } end
        for _, userid in ipairs(users) do
          assert(userid ~= m.userid, "o host não manda RPC para o próprio jogador")
          observar(userid, rpc.id, id, i, total, pedaco)
          if not (net.perder and net.perder(userid, rpc.id, id, i, total)) then
            for _, outra in ipairs(net.maquinas) do
              if outra.userid == userid and outra ~= m then outra.cli[rpc.id](id, i, total, pedaco) end
            end
          end
        end
      end,
    }
    m.ctx = ctx
    m.Rede = carregar("rede").instalar(ctx)
    if opts.servidor then
      m.Partida = carregar("partida_servidor").instalar({ rede = m.Rede, GLOBAL = m.GLOBAL })
      if opcoes.sala then
        m.Sala = carregar("sala_servidor").instalar({ rede = m.Rede, partida = m.Partida, GLOBAL = m.GLOBAL,
          decks = opcoes.decks })
      end
      net.servidor = m
    end
    if opts.userid then
      m.Cliente = carregar("partida_cliente").instalar({ rede = m.Rede, GLOBAL = m.GLOBAL })
      if opcoes.sala then m.Tela = carregar("tela_sala").instalar({ cliente = m.Cliente }) end
    end
    net.maquinas[#net.maquinas + 1] = m
    return m
  end

  return net
end

return { nova = nova_rede, carregar = carregar, RAIZ = RAIZ }
