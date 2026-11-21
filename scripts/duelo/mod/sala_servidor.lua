-- A sala de espera no servidor (US #42): quem está pronto, o começo e o
-- recomeço da partida.
--
-- Cada jogador avisa que está pronto pelo botão da tela (duelo/mod/tela_sala
-- e widgets/duelo_sala). Quando dois jogadores conectados estão prontos, a
-- partida começa sozinha com os decks fixos: Wilson no lado 1 e Webber no
-- lado 2. Quem já está sentado num lado da mesa (netvar `duelo_lado` de
-- duelo/mod/camera.lua) joga por ele; quem não está (espectador) fica com o
-- lado que sobrar, e sem ninguém sentado vale a ordem em que ficaram prontos.
-- Ao começar, o lado da mesa de todos é acertado pela partida
-- (ctx.definir_lados, Camera.definir_lados): os dois jogadores veem a mesa
-- pelo lado em que jogam e os outros viram espectadores.
--
-- Fim da partida: a partida terminada (com vencedor, empate ou erro do motor)
-- fica na mesa até alguém ficar pronto de novo. O primeiro "pronto" depois do
-- fim zera a mesa para todos (Partida.encerrar) e já conta como pronto. O
-- resultado continua na tela de cada cliente até ele o dispensar
-- (duelo/mod/tela_sala).
--
-- Com uma partida em curso (sem resultado), ninguém fica pronto: o pedido é
-- ignorado. Quem sai do servidor deixa de estar pronto. A saída de um
-- jogador da partida em curso é tratada por duelo/mod/desconexao (US #43):
-- quem cai perde, na hora ou depois do prazo para voltar.
--
-- Qualquer jogador conectado pode ficar pronto, também quem assistia: depois
-- do fim, um espectador pode zerar a mesa e entrar na partida seguinte.
--
-- Mensagem "sala", uma por destinatário (cada um só sabe de si e dos totais):
--   { eu = bool, prontos = n, jogadores = n, aviso = texto | false,
--     ausente = { lado = n, prazo = segundos } | false }
--     eu:        este jogador está pronto;
--     prontos:   quantos estão prontos (0, 1 ou 2);
--     jogadores: quantos estão conectados;
--     aviso:     texto para mostrar (falha ao começar), ou false;
--     ausente:   US #43: um jogador da partida em curso caiu; o lado dele e
--                o prazo que ele tem para voltar (duelo/mod/desconexao).
--
-- Interface:
--   Sala.instalar{ rede = Rede, partida = Partida, GLOBAL = GLOBAL,
--                  log = fn, decks = fn, definir_lados = fn } -> Sala
--       decks() -> { d1, d2 }, { e1, e2 } (padrão: Wilson x Webber).
--       definir_lados(um, dois): acerta o lado da mesa de cada jogador.
--   Sala.receber_pronto(userid, pronto) -> ok, erro
--   Sala.pedir(userid)      manda a sala só a ele (quem acabou de entrar)
--   Sala.entrou(userid)     alguém entrou: avisa a todos
--   Sala.saiu(userid)       alguém saiu: deixa de estar pronto e avisa
--   Sala.prontos() -> lista de userids, na ordem em que ficaram prontos
--   Sala.avisar()           manda a sala a todos (algo de fora mudou)
--   Sala.ouvir(fn)          fn("entrou" | "saiu", userid) a cada entrada e saída
--   Sala.definir_ausente(fn)  fn() -> { lado, prazo } | nil, para o campo
--                           `ausente` da mensagem (duelo/mod/desconexao)
--
-- Lua puro: tudo do jogo chega por `ctx` em `instalar`. Só é carregado no
-- servidor (modmain.lua): o baralho carrega as cartas e o motor.

local Sala = {}

local estado = {
  rede = nil,
  partida = nil,
  GLOBAL = nil,
  log = nil,
  decks = nil,
  definir_lados = nil,
  prontos = {},   -- userids, na ordem em que ficaram prontos
  aviso = false,  -- texto do último problema ao começar (some no próximo pronto)
  ouvintes = {},  -- fn(tipo, userid) a cada entrada e saída
  ausente = nil,  -- fn() -> { lado, prazo } | nil
}

local function log(msg)
  if estado.log then estado.log("[duelo] sala: " .. tostring(msg)) end
end

local function userid_valido(userid)
  return type(userid) == "string" and userid ~= ""
end

local function decks_fixos()
  local Decks = require("duelo/decks/init")
  local d1, e1 = Decks.build("wilson")
  local d2, e2 = Decks.build("webber")
  return { d1, d2 }, { e1, e2 }
end

-- Userids conectados, sem repetição e sem `fora` (quem está saindo: no jogo
-- ele já saiu de AllPlayers quando o "ms_playerleft" dispara, em
-- prefabs/player_common.lua, mas a sala não depende dessa ordem).
local function conectados(fora)
  local out, vistos = {}, {}
  for _, userid in ipairs(estado.rede.usuarios() or {}) do
    if userid_valido(userid) and userid ~= fora and not vistos[userid] then
      vistos[userid] = true
      out[#out + 1] = userid
    end
  end
  return out, vistos
end

local function posicao(userid)
  for i, u in ipairs(estado.prontos) do
    if u == userid then return i end
  end
  return nil
end

-- Tira da lista quem não está mais conectado.
local function podar(vistos)
  for i = #estado.prontos, 1, -1 do
    if not vistos[estado.prontos[i]] then table.remove(estado.prontos, i) end
  end
end

local function ausente()
  if estado.ausente == nil then return false end
  local ok, a = pcall(estado.ausente)
  if not ok or type(a) ~= "table" then return false end
  return { lado = a.lado, prazo = a.prazo }
end

local function avisar_ouvintes(tipo, userid)
  for _, fn in ipairs(estado.ouvintes) do
    local ok, err = pcall(fn, tipo, userid)
    if not ok then log("erro num ouvinte de " .. tipo .. ": " .. tostring(err)) end
  end
end

local function mensagem(userid, total)
  return {
    ausente = ausente(),
    eu = posicao(userid) ~= nil,
    prontos = #estado.prontos,
    jogadores = total,
    aviso = estado.aviso or false,
  }
end

local function avisar_todos(fora)
  local lista, vistos = conectados(fora)
  podar(vistos)
  for _, userid in ipairs(lista) do
    estado.rede.enviar({ userid }, "sala", mensagem(userid, #lista))
  end
end

function Sala.pedir(userid)
  if not userid_valido(userid) or estado.rede == nil then return false end
  local lista = conectados()
  estado.rede.enviar({ userid }, "sala", mensagem(userid, #lista))
  return true
end

function Sala.prontos()
  local out = {}
  for i, u in ipairs(estado.prontos) do out[i] = u end
  return out
end

-- O lado da mesa do jogador (1 ou 2), ou nil.
local function lado_da_mesa(userid)
  local G = estado.GLOBAL or {}
  for _, jogador in ipairs(G.AllPlayers or {}) do
    if jogador.userid == userid then
      local lado = jogador.duelo_lado ~= nil and jogador.duelo_lado:value() or nil
      if lado == 1 or lado == 2 then return lado end
      return nil
    end
  end
  return nil
end

-- Os dois primeiros prontos, já no lado em que cada um joga.
local function lados()
  local um, dois = estado.prontos[1], estado.prontos[2]
  local l1, l2 = lado_da_mesa(um), lado_da_mesa(dois)
  if (l1 == 2 and l2 ~= 2) or (l2 == 1 and l1 ~= 1) then um, dois = dois, um end
  return um, dois
end

local function comecar()
  local um, dois = lados()
  estado.prontos = {}
  local ok, a, b = pcall(function()
    local decks, extras = (estado.decks or decks_fixos)()
    return estado.partida.iniciar{ decks = decks, extra_decks = extras, jogadores = { um, dois } }
  end)
  if ok and a then
    estado.aviso = false
    if estado.definir_lados then
      local certo, erro = pcall(estado.definir_lados, um, dois)
      if not certo then log("os lados da mesa não foram acertados: " .. tostring(erro)) end
    end
    return true
  end
  log("a partida não começou: " .. tostring(ok and b or a))
  estado.aviso = "Não foi possível começar a partida."
  return false
end

function Sala.receber_pronto(userid, pronto)
  if estado.rede == nil or estado.partida == nil then return false, "o módulo não foi instalado" end
  if not userid_valido(userid) or type(pronto) ~= "boolean" then return false, "pedido inválido" end
  local lista, vistos = conectados()
  if not vistos[userid] then return false, "jogador não conectado" end
  local P = estado.partida
  if P.em_curso() then
    if not P.terminada() then
      estado.prontos = {}
      Sala.pedir(userid)
      return false, "há uma partida em curso"
    end
    -- A partida acabou: o primeiro pronto zera a mesa para todos.
    if pronto then P.encerrar() end
  end
  podar(vistos)
  local i = posicao(userid)
  if pronto then
    estado.aviso = false
    if i == nil then estado.prontos[#estado.prontos + 1] = userid end
  elseif i ~= nil then
    table.remove(estado.prontos, i)
  end
  if #estado.prontos >= 2 then comecar() end
  avisar_todos()
  return true
end

function Sala.entrou(userid)
  if estado.rede == nil then return end
  avisar_ouvintes("entrou", userid)
  avisar_todos()
end

function Sala.saiu(userid)
  if estado.rede == nil then return end
  local i = posicao(userid)
  if i ~= nil then table.remove(estado.prontos, i) end
  avisar_ouvintes("saiu", userid)
  avisar_todos(userid)
end

function Sala.avisar()
  if estado.rede == nil then return end
  avisar_todos()
end

function Sala.ouvir(fn)
  estado.ouvintes[#estado.ouvintes + 1] = fn
end

function Sala.definir_ausente(fn)
  estado.ausente = fn
end

-- Liga o módulo.
--   ctx.rede: duelo/mod/rede.lua já instalado (enviar, usuarios, ligar_sala);
--   ctx.partida: duelo/mod/partida_servidor.lua já instalado;
--   ctx.GLOBAL: ambiente global do jogo (AllPlayers, print);
--   ctx.log: função de log (padrão: GLOBAL.print);
--   ctx.decks: função que devolve os baralhos (padrão: Wilson x Webber);
--   ctx.definir_lados: Camera.definir_lados (opcional).
function Sala.instalar(ctx)
  estado.rede = ctx.rede
  estado.partida = ctx.partida
  estado.GLOBAL = ctx.GLOBAL
  estado.log = ctx.log or (ctx.GLOBAL and ctx.GLOBAL.print) or nil
  estado.decks = ctx.decks
  estado.definir_lados = ctx.definir_lados
  estado.prontos = {}
  estado.aviso = false
  estado.ouvintes = {}
  estado.ausente = nil
  -- Uma partida começada por outro caminho (console) esvazia a sala.
  if ctx.partida and ctx.partida.quando_iniciar then
    ctx.partida.quando_iniciar(function()
      if #estado.prontos == 0 then return end
      estado.prontos = {}
      avisar_todos()
    end)
  end
  if ctx.rede and ctx.rede.ligar_sala then ctx.rede.ligar_sala(Sala) end
  return Sala
end

return Sala
