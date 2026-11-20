-- A partida vista por um cliente (US #41).
--
-- O cliente NÃO tem o motor: este arquivo (e tudo o que ele carrega) não dá
-- require em duelo/core/game nem nas cartas. Ele só guarda a visão que o
-- servidor manda e envia as ações do jogador:
--   * "estado": a fotografia do que este lado pode ver (duelo/mod/visao,
--     Visao.estado_para) depois do lote `seq`. Substitui a visão local.
--   * "eventos": um lote por ação aceita no servidor, com os eventos (já
--     filtrados para este lado) e as mudanças da fotografia. Os lotes são
--     aplicados em ordem: o lote esperado é sempre `seq + 1`. Um lote
--     repetido ou velho é ignorado; um buraco na sequência (ou um lote de
--     outra partida, ou sem fotografia ainda) faz o cliente pedir "estado" e
--     ignorar os lotes até ela chegar. O pedido ou a resposta podem se
--     perder (ou o servidor pode ignorar o pedido, pelo limite dele de 2 por
--     segundo): enquanto a fotografia não chega, o pedido é repetido a cada
--     ESPERA_PEDIDO segundos (Cliente.tique).
--   * "recusada": o servidor não aceitou uma ação deste jogador, com o motivo.
--   * "sala" (US #42): quem está pronto para começar, visto por este jogador
--     ({ eu, prontos, jogadores, aviso }, de duelo/mod/sala_servidor). Chega
--     junto com a fotografia pedida e a cada mudança.
--
-- Interface:
--   Cliente.instalar{ rede = Rede, GLOBAL = GLOBAL, AddPlayerPostInit = fn,
--                     log = fn, agora = fn } -> Cliente   (agora: relógio
--       em segundos para as retentativas, injetado; ver Cliente.instalar)
--   Cliente.enviar(action) -> n | nil, erro   manda a ação ao servidor; n é o
--       número dela (volta em "recusada"). O resultado chega depois, como um
--       lote de eventos (aceita) ou uma recusa.
--   Cliente.visao() -> fotografia | nil       a visão local (não altere)
--   Cliente.lado() -> 1 | 2 | 3 | nil         Cliente.seq() -> n
--   Cliente.em_partida() -> bool
--   Cliente.quando_evento(fn) -> cancelar     fn(evento, visao): um por
--       evento, na ordem, depois de as mudanças do lote entrarem na visão.
--   Cliente.quando_estado(fn) -> cancelar     fn(visao | nil): chegou uma
--       fotografia (começo, fim de partida ou ressincronia); a tela deve ser
--       refeita a partir dela.
--   Cliente.quando_recusada(fn) -> cancelar   fn(motivo, n)
--   Cliente.partida() -> n | nil              número da partida da visão
--   Cliente.sala() -> { eu, prontos, jogadores, aviso } | nil
--   Cliente.quando_sala(fn) -> cancelar       fn(sala): a sala mudou
--   Cliente.pronto(bool) -> ok, erro          avisa o servidor que este
--       jogador está (ou deixou de estar) pronto
--   Cliente.pedir_estado()                    pede a fotografia ao servidor
--   Cliente.tique()                           repete o pedido de fotografia
--       se ela ainda não chegou e já passou ESPERA_PEDIDO; chamado de tempos
--       em tempos (INTERVALO_TIQUE) por uma tarefa periódica do jogador local
--   Cliente.receber(tipo, tabela)             entrada das mensagens (a rede chama)
--
-- Console do cliente (DUELO.Cliente no modmain.lua), enquanto não há tela:
--   DUELO.Cliente.enviar({ type = "pass" })
--   DUELO.Cliente.imprimir()     a visão local e os últimos eventos
--
-- Lua puro: tudo do jogo chega por `ctx` em `instalar`.

local Visao = require("duelo/mod/visao")

local Cliente = {}

-- Espera, em segundos, antes de repetir um pedido de fotografia que não foi
-- atendido. O servidor atende até 2 pedidos por segundo de cada jogador
-- (Rede.LIMITES.ESTADOS_POR_SEGUNDO): com 1 s o cliente fica dentro do limite.
Cliente.ESPERA_PEDIDO = 1
-- De quanto em quanto tempo, em segundos, a tarefa periódica chama Cliente.tique.
Cliente.INTERVALO_TIQUE = 0.25
-- Quantos eventos recentes ficam guardados para Cliente.imprimir.
Cliente.ULTIMOS = 20

local estado = {
  rede = nil,
  GLOBAL = nil,
  log = nil,
  agora = nil,
  visao = nil,        -- a fotografia local
  partida = nil,      -- número da partida no servidor
  lado = nil,
  seq = 0,
  esperando = false,  -- pediu a fotografia e ainda não chegou
  pedido_em = nil,
  contador = 0,       -- ações enviadas
  ultimos = {},       -- últimos eventos recebidos
  recusas = {},       -- últimas recusas
  sala = nil,         -- a última mensagem "sala"
  ouvintes = { evento = {}, estado = {}, recusada = {}, sala = {} },
}

local function log(msg)
  if estado.log then estado.log("[duelo] cliente: " .. tostring(msg)) end
end

-- Relógio das retentativas, em segundos: o tempo real, que não para com o
-- servidor pausado (GetTimeRealSeconds, mainfunctions.lua; ver rede.lua).
local function agora()
  if estado.agora then return estado.agora() end
  local G = estado.GLOBAL
  if G and G.GetTimeRealSeconds then return G.GetTimeRealSeconds() end
  return nil
end

local function ouvir(tipo, fn)
  local lista = estado.ouvintes[tipo]
  local entrada = { fn = fn }
  lista[#lista + 1] = entrada
  return function()
    for i = #lista, 1, -1 do
      if lista[i] == entrada then table.remove(lista, i) end
    end
  end
end

-- Um ouvinte com erro não impede os outros nem a aplicação do lote.
local function avisar(tipo, ...)
  local lista = {}
  for i, e in ipairs(estado.ouvintes[tipo]) do lista[i] = e end
  for _, e in ipairs(lista) do
    local ok, err = pcall(e.fn, ...)
    if not ok then log("erro num ouvinte de " .. tipo .. ": " .. tostring(err)) end
  end
end

function Cliente.quando_evento(fn) return ouvir("evento", fn) end
function Cliente.quando_estado(fn) return ouvir("estado", fn) end
function Cliente.quando_recusada(fn) return ouvir("recusada", fn) end

function Cliente.quando_sala(fn) return ouvir("sala", fn) end

function Cliente.sala() return estado.sala end
function Cliente.partida() return estado.partida end
function Cliente.visao() return estado.visao end
function Cliente.lado() return estado.lado end
function Cliente.seq() return estado.seq end
function Cliente.em_partida() return estado.visao ~= nil end
function Cliente.esperando_estado() return estado.esperando end

-- Pede a fotografia. Enquanto um pedido está no ar, só repete depois de
-- ESPERA_PEDIDO segundos (ou sempre, se não houver relógio).
function Cliente.pedir_estado()
  if estado.rede == nil then return false end
  local t = agora()
  if estado.esperando and t ~= nil and estado.pedido_em ~= nil
    and t >= estado.pedido_em and t - estado.pedido_em < Cliente.ESPERA_PEDIDO then
    return false
  end
  estado.esperando = true
  estado.pedido_em = t
  estado.rede.pedir_estado()
  return true
end

-- Retentativa por tempo: enquanto a fotografia pedida não chega, repete o
-- pedido (pedir_estado só deixa passar depois de ESPERA_PEDIDO). Devolve true
-- se pediu de novo.
function Cliente.tique()
  if not estado.esperando then return false end
  return Cliente.pedir_estado()
end

local function receber_estado(m)
  estado.esperando = false
  estado.pedido_em = nil
  if m.partida == false or type(m.estado) ~= "table" then
    estado.visao, estado.partida, estado.lado, estado.seq = nil, nil, nil, 0
  else
    -- Uma fotografia mais velha do que a visão local (pedida antes de lotes
    -- que já chegaram) não volta a visão no tempo.
    if estado.visao ~= nil and m.partida == estado.partida and type(m.seq) == "number" and m.seq < estado.seq then
      return
    end
    estado.visao = m.estado
    estado.partida = m.partida
    estado.lado = m.lado
    estado.seq = type(m.seq) == "number" and m.seq or 0
  end
  avisar("estado", estado.visao)
end

local function receber_eventos(m)
  if estado.visao == nil or m.partida ~= estado.partida then
    -- Lote de uma partida de que não se tem a fotografia.
    Cliente.pedir_estado()
    return
  end
  if type(m.seq) ~= "number" then return end
  if m.seq <= estado.seq then return end -- repetido ou velho
  if estado.esperando or m.seq ~= estado.seq + 1 then
    if not estado.esperando then
      log("buraco na sequência (esperava o lote " .. (estado.seq + 1) .. ", veio o " .. m.seq .. "): pedindo o estado")
    end
    Cliente.pedir_estado()
    return
  end
  local ok, err = pcall(Visao.aplicar, estado.visao, m.mudancas)
  if not ok then
    log("lote " .. m.seq .. " não pôde ser aplicado (" .. tostring(err) .. "): pedindo o estado")
    Cliente.pedir_estado()
    return
  end
  estado.seq = m.seq
  for _, ev in ipairs(m.eventos or {}) do
    local u = estado.ultimos
    u[#u + 1] = ev
    if #u > Cliente.ULTIMOS then table.remove(u, 1) end
    avisar("evento", ev, estado.visao)
  end
end

local function receber_recusada(m)
  local motivo = tostring(m.motivo)
  local n = type(m.n) == "number" and m.n or nil
  local r = estado.recusas
  r[#r + 1] = { n = n, motivo = motivo }
  if #r > Cliente.ULTIMOS then table.remove(r, 1) end
  log("ação " .. tostring(n) .. " recusada: " .. motivo)
  avisar("recusada", motivo, n)
end

local function contagem(n)
  if type(n) == "number" and n == n and n >= 0 and n < 2 ^ 31 then return math.floor(n) end
  return 0
end

local function receber_sala(m)
  estado.sala = {
    eu = m.eu == true,
    prontos = contagem(m.prontos),
    jogadores = contagem(m.jogadores),
    aviso = type(m.aviso) == "string" and m.aviso or false,
  }
  avisar("sala", estado.sala)
end

function Cliente.pronto(pronto)
  if estado.rede == nil then return false, "o módulo não foi instalado" end
  if type(pronto) ~= "boolean" then return false, "pedido inválido" end
  return estado.rede.enviar_pronto(pronto)
end

function Cliente.receber(tipo, m)
  if type(m) ~= "table" then return end
  if tipo == "sala" then return receber_sala(m) end
  if tipo == "estado" then return receber_estado(m) end
  if tipo == "eventos" then return receber_eventos(m) end
  if tipo == "recusada" then return receber_recusada(m) end
end

-- A rede perdeu uma mensagem (pedaço fora de ordem): só a fotografia conserta.
function Cliente.falha_de_transporte(tipo)
  if tipo == "recusada" then return end
  estado.esperando = false
  Cliente.pedir_estado()
end

function Cliente.enviar(action)
  if estado.rede == nil then return nil, "o módulo não foi instalado" end
  if type(action) ~= "table" or type(action.type) ~= "string" then return nil, "ação inválida" end
  -- O número é tomado antes do envio: no host o envio é síncrono, e um
  -- ouvinte pode mandar outra ação de dentro dele (ela leva o número seguinte).
  local n = estado.contador + 1
  estado.contador = n
  local ok, err = estado.rede.enviar_acao(action, n)
  if not ok then
    if estado.contador == n then estado.contador = n - 1 end
    return nil, err
  end
  return n
end

----------------------------------------------------------------------------
-- Console
----------------------------------------------------------------------------

local function campos(ev)
  local out = {}
  for k, v in pairs(ev) do
    if k ~= "t" then out[#out + 1] = tostring(k) .. "=" .. (type(v) == "table" and "{...}" or tostring(v)) end
  end
  table.sort(out)
  return tostring(ev.t) .. " " .. table.concat(out, " ")
end

local function cartas(lista)
  local out = {}
  for i, c in ipairs(lista or {}) do
    out[i] = i .. ":" .. tostring(c.id) .. (c.custo and ("(" .. tostring(c.custo) .. ")") or "")
  end
  return table.concat(out, " ")
end

local function campo(j)
  local out = {}
  for s, c in ipairs(j.campo or {}) do
    if c then out[#out + 1] = "c" .. s .. "=" .. tostring(c.id) .. " " .. tostring(c.atk) .. "/" .. tostring(c.hp)
      .. (c.dano and c.dano > 0 and (" (-" .. c.dano .. ")") or "") end
  end
  for s, st in ipairs(j.estruturas or {}) do
    if st then out[#out + 1] = "e" .. s .. "=" .. tostring(st.id) end
  end
  return table.concat(out, ", ")
end

-- A visão local em linhas (Cliente.imprimir as imprime).
function Cliente.resumo()
  local v = estado.visao
  local linhas = {}
  local function add(s) linhas[#linhas + 1] = "[duelo] " .. s end
  local sala = estado.sala
  if sala ~= nil then
    add("sala: eu " .. (sala.eu and "pronto" or "não pronto") .. ", " .. sala.prontos .. " prontos, "
      .. sala.jogadores .. " jogadores" .. (sala.aviso and (", aviso: " .. sala.aviso) or ""))
  end
  if v == nil then
    add("cliente: sem partida" .. (estado.esperando and " (estado pedido ao servidor)" or ""))
    return linhas
  end
  local nomes = { "lado 1", "lado 2", "espectador" }
  add("partida " .. tostring(estado.partida) .. ", eu sou " .. (nomes[estado.lado] or "?") .. ", lote " .. estado.seq
    .. ": fase " .. tostring(v.fase) .. ", rodada " .. tostring(v.rodada) .. ", vez " .. tostring(v.vez)
    .. " (" .. tostring(v.periodo) .. "), ativo " .. tostring(v.ativo))
  if v.vencedor ~= false then add("vencedor: " .. tostring(v.vencedor) .. " (0 = empate)") end
  if v.erro then add("erro do motor: " .. tostring(v.erro)) end
  if v.escolha then
    add("escolha do lado " .. tostring(v.escolha.p) .. " (" .. tostring(v.escolha.motivo) .. ")"
      .. (v.escolha.opcoes and (", " .. tostring(v.escolha.n) .. " opções (minha)") or ""))
  end
  for p = 1, 2 do
    local j = v.jogadores[p]
    add("lado " .. p .. ": vida " .. tostring(j.vida) .. ", mana " .. tostring(j.mana) .. "/" .. tostring(j.mana_max)
      .. ", fogueira " .. tostring(v.fogueira and v.fogueira[p] or "-") .. ", mão " .. tostring(j.mao_n)
      .. ", baralho " .. tostring(j.baralho_n) .. ", descarte " .. #(j.descarte or {}))
    if j.mao then add("  mão: " .. cartas(j.mao)) else add("  mão: escondida (" .. tostring(j.mao_n) .. " cartas)") end
    add("  campo: " .. campo(j))
  end
  if #estado.ultimos > 0 then
    add("últimos eventos:")
    for _, ev in ipairs(estado.ultimos) do add("  " .. campos(ev)) end
  end
  for _, r in ipairs(estado.recusas) do add("recusada (ação " .. tostring(r.n) .. "): " .. r.motivo) end
  return linhas
end

function Cliente.imprimir()
  local imprimir = (estado.GLOBAL and estado.GLOBAL.print) or print
  for _, linha in ipairs(Cliente.resumo()) do imprimir(linha) end
end

-- Liga o módulo.
--   ctx.rede: duelo/mod/rede.lua já instalado (enviar_acao e pedir_estado);
--   ctx.GLOBAL: ambiente global do jogo (ThePlayer, GetTime, print);
--   ctx.AddPlayerPostInit: de modutil.lua (opcional): quando o jogador local
--     ativa ("playeractivated" no próprio jogador, prefabs/player_common.lua),
--     o cliente pede a fotografia, para quem entra com a partida em curso, e
--     liga a tarefa periódica que chama Cliente.tique. A tarefa é
--     `inst:DoStaticPeriodicTask` (entityscript.lua: roda no staticScheduler,
--     que StaticUpdate, em update.lua, executa mesmo com o servidor pausado);
--   ctx.log: função de log (padrão: GLOBAL.print);
--   ctx.agora: relógio em segundos que não para na pausa (o modmain injeta
--     GLOBAL.GetTimeRealSeconds; sem ctx.agora, é ela que vale; os testes
--     injetam um relógio falso).
function Cliente.instalar(ctx)
  estado.rede = ctx.rede
  estado.GLOBAL = ctx.GLOBAL
  estado.log = ctx.log or (ctx.GLOBAL and ctx.GLOBAL.print) or nil
  estado.agora = ctx.agora
  estado.visao, estado.partida, estado.lado, estado.seq = nil, nil, nil, 0
  estado.esperando, estado.pedido_em = false, nil
  estado.contador = 0
  estado.ultimos, estado.recusas = {}, {}
  estado.sala = nil
  estado.ouvintes = { evento = {}, estado = {}, recusada = {}, sala = {} }
  if ctx.rede and ctx.rede.ligar_cliente then ctx.rede.ligar_cliente(Cliente) end
  if ctx.AddPlayerPostInit then
    ctx.AddPlayerPostInit(function(inst)
      inst:ListenForEvent("playeractivated", function()
        if not (ctx.GLOBAL and inst == ctx.GLOBAL.ThePlayer) then return end
        Cliente.pedir_estado()
        if inst.duelo_tique == nil then
          local periodica = inst.DoStaticPeriodicTask or inst.DoPeriodicTask
          if periodica then
            inst.duelo_tique = periodica(inst, Cliente.INTERVALO_TIQUE, function() Cliente.tique() end)
          end
        end
      end)
    end)
  end
  return Cliente
end

return Cliente
