-- Transporte da partida entre os clientes e o servidor (US #41): RPCs de mod.
--
-- O que é do jogo e onde se confirma (networkclientrpc.lua; modutil.lua só
-- repassa as mesmas funções para o ambiente do mod):
--   * `AddModRPCHandler(namespace, nome, fn)`: RPC do cliente para o servidor.
--     No servidor, `fn(player, ...)`: o primeiro argumento é a entidade do
--     jogador que mandou (HandleModRPC só enfileira quando o remetente é uma
--     tabela, e HandleRPCQueue ignora o jogador que deixou de ser válido). O
--     servidor identifica quem mandou por `player.userid`, nunca por um dado
--     que venha nos argumentos.
--   * `AddClientModRPCHandler(namespace, nome, fn)`: RPC do servidor para o
--     cliente; `fn(...)` recebe só os argumentos (HandleClientModRPC).
--   * `SendModRPCToServer(GetModRPC(namespace, nome), ...)` e
--     `SendModRPCToClient(GetClientModRPC(namespace, nome), users, ...)`, em
--     que `users` é nil (todos), um userid ou uma lista de userids
--     (comentário acima de SendRPCToClient). As duas conferem com `assert`
--     que o handler existe em quem envia, e os ids saem da ordem de registro:
--     por isso TODAS as RPCs são registradas nos dois lados, na mesma ordem,
--     mesmo as que aquele lado nunca recebe.
--   * Limite do jogo: cada remetente tem uma fila de 20 RPCs por tick, mais 5
--     por RPC de mod registrada (RPC_QUEUE_RATE_LIMIT e
--     RPC_QUEUE_RATE_LIMIT_PER_MOD); o excesso é descartado pelo jogo com um
--     aviso no log. O limite daqui (ACOES_POR_SEGUNDO) é bem mais baixo.
--   * Tamanho de string: os scripts do jogo não declaram limite para os
--     argumentos de uma RPC (a serialização é do motor em C++, fora dos
--     scripts). Por precaução as mensagens do servidor saem em pedaços de no
--     máximo FRAGMENTO bytes; o valor é conservador e fica a confirmar no
--     jogo (docs/mod.md).
--
-- RPCs (namespace "duelo"):
--   cliente -> servidor
--     "acao"          (texto, n)  a ação serializada por duelo/core/serial e
--                                 o número dela no cliente (volta na recusa;
--                                 só vale inteiro finito em [0, 2^31), senão
--                                 volta false).
--     "pedir_estado"  ()          pede a fotografia da partida (e a sala).
--     "pronto"        (1 | 0)     US #42: o jogador está (1) ou deixou de
--                                 estar (0) pronto para começar; vai para
--                                 duelo/mod/sala_servidor. É um número, não
--                                 um booleano: no jogo, o `false` de uma RPC
--                                 de mod não chegou ao servidor (o "Cancelar"
--                                 não fazia nada no servidor dedicado).
--   servidor -> cliente, todas com (id, i, total, pedaco): a mensagem `id`
--   serializada e cortada em `total` pedaços, mandados em ordem
--     "eventos"   { partida, seq, eventos, mudancas }
--     "estado"    { partida, seq, lado, estado } ou { partida = false }
--     "recusada"  { n, motivo }   só para quem enviou a ação
--     "sala"      { eu, prontos, jogadores, aviso, ausente }   US #42 e #43, uma por jogador
--
-- O servidor NUNCA executa nada que venha do cliente: o texto da ação é lido
-- por Serial.deserialize (caractere a caractere, sem loadstring; no máximo 8
-- níveis de tabela e 256 valores; número não finito é recusado), depois de
-- conferido o tamanho, e a tabela que sai ainda passa pela conferência de
-- forma de duelo/mod/partida_servidor. Todos os handlers, do servidor e do
-- cliente, rodam dentro de pcall: um erro vira um aviso no log e nunca sobe
-- para a fila de RPCs do jogo.
--
-- Limites (Rede.LIMITES):
--   ACAO_BYTES            tamanho máximo do texto de uma ação;
--   ACOES_POR_SEGUNDO     ações aceitas por jogador a cada segundo; o excesso
--                         é descartado sem chegar à partida, com um aviso no
--                         log e uma recusa ao jogador por janela;
--   ESTADOS_POR_SEGUNDO   pedidos de fotografia atendidos por jogador a cada
--                         segundo (o excesso é ignorado; o cliente repete);
--   PRONTOS_POR_SEGUNDO   avisos de "pronto" aceitos por jogador a cada
--                         segundo (o excesso é ignorado);
--   FRAGMENTO             bytes de cada pedaço das mensagens do servidor;
--   MENSAGEM_BYTES        maior mensagem que o cliente aceita remontar.
--
-- Relógio das janelas de taxa: `GetTimeRealSeconds()` (mainfunctions.lua,
-- "TIME FUNCTIONS": `TheSim:GetRealTime() / 1000`, o tempo real em segundos).
-- Não é `GetTime()` (`TheSim:GetTick() * ticktime`, na mesma seção): com o
-- servidor pausado o tick da simulação não anda, mas as RPCs continuam a ser
-- tratadas (`StaticUpdate`, em update.lua, chama `TickRPCQueue()` também com
-- `TheNet:IsServerPaused()`), e uma janela aberta na pausa nunca venceria: o
-- jogador ficaria bloqueado, ou sem limite, até o fim da pausa. O relógio
-- chega por `ctx.agora`. As janelas vencidas são apagadas a cada pedido, e as
-- de um jogador, quando ele sai: `ms_playerleft`, que o servidor dispara no
-- TheWorld com a entidade do jogador (prefabs/player_common.lua, ao remover
-- o jogador; é o mesmo evento que os componentes do mundo, como hounded.lua,
-- escutam).
--
-- Host (servidor com tela): os dois lados convivem na mesma máquina. Para
-- não depender de o jogo entregar a própria RPC de volta, o que é do jogador
-- local vai direto de um lado ao outro, por chamada de função, passando pela
-- mesma serialização.
--
-- Lua puro: tudo do jogo chega por `ctx` em `instalar`.

local Serial = require("duelo/core/serial")

local Rede = {}

Rede.NAMESPACE = "duelo"

Rede.LIMITES = {
  ACAO_BYTES = 1024,
  ACOES_POR_SEGUNDO = 10,
  ESTADOS_POR_SEGUNDO = 2,
  PRONTOS_POR_SEGUNDO = 5,
  FRAGMENTO = 1000,
  MENSAGEM_BYTES = 262144,
}

-- Limites da leitura do texto de uma ação (Serial.deserialize): mais folgados
-- do que a conferência de forma de partida_servidor (que dá a recusa com o
-- motivo certo), e muito abaixo do padrão do serializador.
local LEITURA_DA_ACAO = { profundidade = 8, elementos = 256 }

-- Mensagens do servidor para o cliente, na ordem de registro.
Rede.MENSAGENS = { "eventos", "estado", "recusada", "sala" }

local estado = {
  ctx = nil,
  GLOBAL = nil,
  log = nil,
  servidor = nil,   -- duelo/mod/partida_servidor (só no servidor)
  sala = nil,       -- duelo/mod/sala_servidor (só no servidor)
  cliente = nil,    -- duelo/mod/partida_cliente (só onde há tela)
  id_mensagem = 0,  -- servidor: contador das mensagens enviadas
  taxa = {},        -- servidor: userid -> { acao = janela, estado = janela }
  remontagem = {},  -- cliente: tipo -> { id, total, partes }
}

local function log(msg)
  if estado.log then estado.log("[duelo] rede: " .. tostring(msg)) end
end

-- Relógio das janelas de taxa, em segundos (ver "Relógio" no cabeçalho).
local function agora()
  local G = estado.GLOBAL
  if estado.ctx and estado.ctx.agora then return estado.ctx.agora() end
  if G and G.GetTimeRealSeconds then return G.GetTimeRealSeconds() end
  return 0
end

local function e_servidor()
  local G = estado.GLOBAL
  return G ~= nil and G.TheNet ~= nil and G.TheNet:GetIsServer() == true
end

-- userid do jogador desta máquina (nil no servidor dedicado).
local function userid_local()
  local G = estado.GLOBAL
  local jogador = G and G.ThePlayer or nil
  local userid = jogador and jogador.userid or nil
  if type(userid) == "string" and userid ~= "" then return userid end
  return nil
end

----------------------------------------------------------------------------
-- Servidor
----------------------------------------------------------------------------

-- Userids dos jogadores conectados (AllPlayers, mainfunctions.lua).
function Rede.usuarios()
  local out = {}
  local G = estado.GLOBAL
  for _, jogador in ipairs(G and G.AllPlayers or {}) do
    if type(jogador.userid) == "string" and jogador.userid ~= "" then out[#out + 1] = jogador.userid end
  end
  return out
end

-- Um handler de RPC nunca propaga erro: o jogo o chama de dentro da fila de
-- RPCs (HandleRPCQueue, networkclientrpc.lua), e um erro ali derrubaria o
-- servidor (ou o cliente). O erro vai para o log e a RPC é abandonada.
local function protegido(nome, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then pcall(log, "erro ao tratar \"" .. nome .. "\" (ignorado): " .. tostring(err)) end
  end
end

-- Entrega ao cliente desta máquina (host), sem passar pela RPC.
local entregar_local = protegido("entrega local", function(tipo, texto)
  local ok, tabela = pcall(Serial.deserialize, texto)
  if ok and estado.cliente then estado.cliente.receber(tipo, tabela) end
end)

-- Manda uma mensagem (tabela) a uma lista de userids. A tabela é serializada
-- uma vez; o que sai nunca é a tabela de quem chamou.
function Rede.enviar(userids, tipo, tabela)
  if type(userids) ~= "table" then userids = { userids } end
  local texto = Serial.serialize(tabela)
  local eu = estado.cliente ~= nil and userid_local() or nil
  local remotos = {}
  local para_mim = false
  for _, userid in ipairs(userids) do
    if userid == eu then para_mim = true else remotos[#remotos + 1] = userid end
  end
  if #remotos > 0 then
    local ctx = estado.ctx
    local rpc = ctx.GetClientModRPC(Rede.NAMESPACE, tipo)
    estado.id_mensagem = estado.id_mensagem + 1
    local id = estado.id_mensagem
    local tam = Rede.LIMITES.FRAGMENTO
    local total = math.max(1, math.ceil(#texto / tam))
    for i = 1, total do
      ctx.SendModRPCToClient(rpc, remotos, id, i, total, texto:sub((i - 1) * tam + 1, i * tam))
    end
  end
  if para_mim then entregar_local(tipo, texto) end
end

local function janela_vencida(j, t)
  return t - j.inicio >= 1 or t < j.inicio
end

-- Joga fora as janelas que já venceram (de todos os jogadores): a tabela só
-- guarda quem mandou algo no último segundo.
local function limpar_taxa(t)
  for userid, por_usuario in pairs(estado.taxa) do
    for tipo, j in pairs(por_usuario) do
      if janela_vencida(j, t) then por_usuario[tipo] = nil end
    end
    if next(por_usuario) == nil then estado.taxa[userid] = nil end
  end
end

-- Esquece as janelas de um jogador (ele saiu do servidor).
function Rede.esquecer(userid)
  if userid ~= nil then estado.taxa[userid] = nil end
end

-- Quantos jogadores têm janela de taxa guardada (para os testes e o console).
function Rede.janelas()
  local n = 0
  for _ in pairs(estado.taxa) do n = n + 1 end
  return n
end

-- Uma janela de 1 segundo por jogador e por tipo de pedido. Devolve se o
-- pedido cabe e se é o primeiro excesso da janela (para avisar uma vez só).
local function cabe_na_taxa(userid, tipo, maximo)
  local t = agora()
  limpar_taxa(t)
  local por_usuario = estado.taxa[userid]
  if por_usuario == nil then
    por_usuario = {}
    estado.taxa[userid] = por_usuario
  end
  local j = por_usuario[tipo]
  if j == nil then
    j = { inicio = t, n = 0, avisado = false }
    por_usuario[tipo] = j
  end
  j.n = j.n + 1
  if j.n <= maximo then return true, false end
  local primeiro = not j.avisado
  j.avisado = true
  return false, primeiro
end

local function userid_de(player)
  local userid = type(player) == "table" and player.userid or nil
  if type(userid) == "string" and userid ~= "" then return userid end
  return nil
end

-- O número da ação vem do cliente e volta na recusa: só vale um inteiro
-- finito em [0, 2^31); qualquer outra coisa (texto, fração, NaN, infinito,
-- que o serializador nem aceita escrever) vira false.
local function numero_da_acao(n)
  if type(n) == "number" and n == n and n ~= math.huge and n >= 0 and n < 2 ^ 31 and n % 1 == 0 then return n end
  return false
end

local function recusar(userid, n, motivo)
  Rede.enviar({ userid }, "recusada", { n = numero_da_acao(n), motivo = motivo })
end

-- Handler da RPC "acao" no servidor.
local ao_receber_acao = protegido("acao", function(player, texto, n)
  if estado.servidor == nil then return end
  n = numero_da_acao(n)
  local userid = userid_de(player)
  if userid == nil then return end
  local cabe, avisar = cabe_na_taxa(userid, "acao", Rede.LIMITES.ACOES_POR_SEGUNDO)
  if not cabe then
    if avisar then
      log("ações demais de " .. userid .. " (mais de " .. Rede.LIMITES.ACOES_POR_SEGUNDO .. " por segundo): descartadas")
      recusar(userid, n, "ações demais por segundo")
    end
    return
  end
  if type(texto) ~= "string" then return recusar(userid, n, "ação inválida") end
  if #texto > Rede.LIMITES.ACAO_BYTES then return recusar(userid, n, "ação grande demais") end
  local ok, action = pcall(Serial.deserialize, texto, LEITURA_DA_ACAO)
  if not ok then return recusar(userid, n, "ação inválida") end
  local r = estado.servidor.receber_acao(userid, action, n)
  if not r.ok then recusar(userid, n, r.erro) end
end)

-- Handler da RPC "pedir_estado" no servidor.
local ao_pedir_estado = protegido("pedir_estado", function(player)
  if estado.servidor == nil then return end
  local userid = userid_de(player)
  if userid == nil then return end
  if not cabe_na_taxa(userid, "estado", Rede.LIMITES.ESTADOS_POR_SEGUNDO) then return end
  estado.servidor.pedir_estado(userid)
  if estado.sala ~= nil then estado.sala.pedir(userid) end
end)

-- Handler da RPC "pronto" no servidor (US #42).
local ao_receber_pronto = protegido("pronto", function(player, pronto)
  if estado.sala == nil then return end
  local userid = userid_de(player)
  if pronto == 1 then pronto = true elseif pronto == 0 then pronto = false else return end
  if userid == nil then return end
  if not cabe_na_taxa(userid, "pronto", Rede.LIMITES.PRONTOS_POR_SEGUNDO) then return end
  estado.sala.receber_pronto(userid, pronto)
end)

function Rede.ligar_servidor(partida)
  estado.servidor = partida
end

function Rede.ligar_sala(sala)
  estado.sala = sala
end

----------------------------------------------------------------------------
-- Cliente
----------------------------------------------------------------------------

-- Junta os pedaços de uma mensagem. Um pedaço fora de ordem joga a mensagem
-- fora e avisa o cliente, que pede a fotografia.
local function ao_receber_pedaco(tipo, id, i, total, pedaco)
  if estado.cliente == nil then return end
  local function falha(motivo)
    estado.remontagem[tipo] = nil
    log("mensagem \"" .. tipo .. "\" descartada: " .. motivo)
    if estado.cliente.falha_de_transporte then estado.cliente.falha_de_transporte(tipo) end
  end
  if type(id) ~= "number" or type(i) ~= "number" or type(total) ~= "number" or type(pedaco) ~= "string"
    or i < 1 or i > total or i % 1 ~= 0 then
    return falha("pedaço inválido")
  end
  local r = estado.remontagem[tipo]
  if i == 1 then
    r = { id = id, total = total, partes = {}, bytes = 0 }
    estado.remontagem[tipo] = r
  elseif r == nil or r.id ~= id or r.total ~= total or #r.partes ~= i - 1 then
    return falha("pedaço " .. i .. " de " .. total .. " fora de ordem")
  end
  r.partes[i] = pedaco
  r.bytes = r.bytes + #pedaco
  if r.bytes > Rede.LIMITES.MENSAGEM_BYTES then return falha("grande demais") end
  if i < total then return end
  estado.remontagem[tipo] = nil
  local ok, tabela = pcall(Serial.deserialize, table.concat(r.partes))
  if not ok then return falha("texto inválido") end
  estado.cliente.receber(tipo, tabela)
end

-- Manda uma ação ao servidor. `n` é o número dela no cliente. Devolve ok, erro.
function Rede.enviar_acao(action, n)
  local ok, texto = pcall(Serial.serialize, action)
  if not ok then return false, "ação não serializável" end
  if #texto > Rede.LIMITES.ACAO_BYTES then return false, "ação grande demais" end
  if estado.servidor ~= nil and e_servidor() then
    -- Host: direto para o handler do servidor, com o jogador local.
    local G = estado.GLOBAL
    if G.ThePlayer == nil then return false, "sem jogador local" end
    ao_receber_acao(G.ThePlayer, texto, n)
    return true
  end
  local ctx = estado.ctx
  ctx.SendModRPCToServer(ctx.GetModRPC(Rede.NAMESPACE, "acao"), texto, n)
  return true
end

function Rede.pedir_estado()
  if estado.servidor ~= nil and e_servidor() then
    local G = estado.GLOBAL
    if G.ThePlayer == nil then return false end
    ao_pedir_estado(G.ThePlayer)
    return true
  end
  local ctx = estado.ctx
  ctx.SendModRPCToServer(ctx.GetModRPC(Rede.NAMESPACE, "pedir_estado"))
  return true
end

-- Avisa o servidor que este jogador está (ou deixou de estar) pronto.
function Rede.enviar_pronto(pronto)
  if type(pronto) ~= "boolean" then return false, "pedido inválido" end
  if estado.sala ~= nil and e_servidor() then
    local G = estado.GLOBAL
    if G.ThePlayer == nil then return false, "sem jogador local" end
    ao_receber_pronto(G.ThePlayer, pronto and 1 or 0)
    return true
  end
  local ctx = estado.ctx
  ctx.SendModRPCToServer(ctx.GetModRPC(Rede.NAMESPACE, "pronto"), pronto and 1 or 0)
  return true
end

function Rede.ligar_cliente(cliente)
  estado.cliente = cliente
end

----------------------------------------------------------------------------
-- Instalação
----------------------------------------------------------------------------

-- Liga o módulo: registra todas as RPCs, nos dois lados, sempre na mesma ordem.
--   ctx.GLOBAL: ambiente global do jogo (TheNet, ThePlayer, AllPlayers,
--     TheWorld, GetTimeRealSeconds);
--   ctx.AddModRPCHandler, ctx.AddClientModRPCHandler, ctx.SendModRPCToServer,
--   ctx.SendModRPCToClient, ctx.GetModRPC, ctx.GetClientModRPC: de modutil.lua;
--   ctx.log: função de log (padrão: GLOBAL.print);
--   ctx.agora: relógio em segundos, que não para com o servidor pausado
--     (o modmain injeta GLOBAL.GetTimeRealSeconds; sem ctx.agora, é ela que
--     vale; os testes injetam um relógio falso);
--   ctx.AddSimPostInit: de modutil.lua (opcional): no servidor, liga a
--     limpeza das janelas de taxa de quem sai ("ms_playerleft" no TheWorld)
--     e avisa a sala de quem entra ("ms_playerjoined") e de quem sai.
function Rede.instalar(ctx)
  estado.ctx = ctx
  estado.GLOBAL = ctx.GLOBAL
  estado.log = ctx.log or (ctx.GLOBAL and ctx.GLOBAL.print) or nil
  estado.servidor = nil
  estado.sala = nil
  estado.cliente = nil
  estado.id_mensagem = 0
  estado.taxa = {}
  estado.remontagem = {}
  ctx.AddModRPCHandler(Rede.NAMESPACE, "acao", ao_receber_acao)
  ctx.AddModRPCHandler(Rede.NAMESPACE, "pedir_estado", ao_pedir_estado)
  ctx.AddModRPCHandler(Rede.NAMESPACE, "pronto", ao_receber_pronto)
  if ctx.AddSimPostInit then
    ctx.AddSimPostInit(function()
      local G = estado.GLOBAL
      if not e_servidor() or G.TheWorld == nil then return end
      G.TheWorld:ListenForEvent("ms_playerleft", protegido("ms_playerleft", function(_, jogador)
        local userid = userid_de(jogador)
        Rede.esquecer(userid)
        if estado.sala ~= nil then estado.sala.saiu(userid) end
      end))
      G.TheWorld:ListenForEvent("ms_playerjoined", protegido("ms_playerjoined", function(_, jogador)
        if estado.sala ~= nil then estado.sala.entrou(userid_de(jogador)) end
      end))
    end)
  end
  for _, tipo in ipairs(Rede.MENSAGENS) do
    ctx.AddClientModRPCHandler(Rede.NAMESPACE, tipo, protegido(tipo, function(id, i, total, pedaco)
      ao_receber_pedaco(tipo, id, i, total, pedaco)
    end))
  end
  return Rede
end

return Rede
