-- O que a tela mostra antes e depois da partida (US #42).
--
-- Este módulo decide o conteúdo (título, texto e botão) a partir do que o
-- cliente sabe (duelo/mod/partida_cliente: a visão da partida e a sala); o
-- desenho fica em widgets/duelo_sala.lua, que só mostra o modelo. Lua puro,
-- testado sem o jogo (tests/test_mod_sala.lua).
--
-- Três modos:
--   "sala"     não há partida (ou o resultado já foi dispensado): o botão
--              "Pronto" (ou "Cancelar", para quem já está pronto) e quantos
--              estão prontos. Com dois prontos o servidor começa a partida.
--   "partida"  partida em curso: só uma linha dizendo por qual lado se joga.
--              Se um jogador caiu (US #43), a linha diz quanto tempo ele tem
--              para voltar antes de perder.
--   "fim"      a partida acabou: "Vitória", "Derrota", "Empate" (ou, para
--              quem assiste, "Lado N venceu"; ou "Partida interrompida", se
--              o motor deu erro). Se a partida acabou porque um jogador caiu
--              (US #43), o texto diz isso. O resultado fica na tela até o jogador
--              clicar, mesmo que o outro já tenha zerado a mesa no servidor,
--              ou até uma partida nova começar (aí o painel passa a ela).
--              Jogador: botão "Jogar de novo" (dispensa o resultado e fica
--              pronto; o primeiro pronto zera a mesa para todos). Quem
--              assiste: botão "Fechar" (só dispensa).
--
-- Interface:
--   Tela.instalar{ cliente = Cliente, log = fn } -> Tela
--   Tela.modelo() -> { modo, titulo = texto | false, texto = texto | false,
--                      botao = { texto, acao } | false }
--   Tela.clicar()             faz a ação do botão do modelo atual
--   Tela.ligar_widget(w)      w:Atualizar(modelo) a cada mudança (nil desliga)
--   Tela.atualizar()          recalcula e manda o modelo ao widget

local Tela = {}

local ESPECTADOR = 3

local estado = {
  cliente = nil,
  log = nil,
  widget = nil,
  resultado = nil,   -- { partida = n, titulo = , texto = , jogador = bool }
  dispensada = nil,  -- número da partida cujo resultado já foi dispensado
}

local function log(msg)
  if estado.log then estado.log("[duelo] tela: " .. tostring(msg)) end
end

local function prazo_por_extenso(s)
  if s >= 120 then return math.floor(s / 60) .. " minutos" end
  if s >= 60 then return "1 minuto" end
  return s .. " segundos"
end

-- Texto do abandono (US #43), para quem ganhou, para quem perdeu e para quem assiste.
local function texto_do_abandono(v, lado, jogador)
  local a = v.abandono
  if type(a) ~= "table" then return false end
  if not jogador then return "O lado " .. tostring(a.p) .. " saiu da partida." end
  if a.p == lado then return "Você saiu da partida e não voltou a tempo." end
  return "O outro jogador saiu da partida."
end

local function resultado_de(v, lado, partida)
  local jogador = lado == 1 or lado == 2
  local r = { partida = partida, jogador = jogador, texto = false }
  if v.vencedor == false then
    r.titulo = "Partida interrompida"
    r.texto = "O jogo encontrou um erro e a partida foi encerrada."
  elseif v.vencedor == 0 then
    r.titulo = "Empate"
  elseif not jogador then
    r.titulo = "Lado " .. tostring(v.vencedor) .. " venceu"
  elseif v.vencedor == lado then
    r.titulo = "Vitória"
  else
    r.titulo = "Derrota"
  end
  if not r.texto then r.texto = texto_do_abandono(v, lado, jogador) end
  return r
end

-- Guarda o resultado quando a visão mostra uma partida terminada e o esquece
-- quando uma partida nova está em curso.
local function acompanhar()
  local C = estado.cliente
  local v = C.visao()
  if v == nil then return end
  local partida = C.partida()
  if v.vencedor ~= false or v.erro then
    if partida ~= estado.dispensada and (estado.resultado == nil or estado.resultado.partida ~= partida) then
      estado.resultado = resultado_de(v, C.lado(), partida)
    end
  else
    estado.resultado = nil
  end
end

local function texto_da_sala(sala)
  if sala.aviso then return sala.aviso end
  if sala.eu then return "Você está pronto. Aguardando o outro jogador." end
  if sala.prontos >= 1 then return "O outro jogador está pronto. Clique em Pronto para começar." end
  if sala.jogadores < 2 then return "Aguardando um segundo jogador entrar no mundo." end
  return "Clique em Pronto para jogar."
end

function Tela.modelo()
  local C = estado.cliente
  if C == nil then return { modo = "sala", titulo = false, texto = false, botao = false } end
  acompanhar()
  local sala = C.sala()
  local r = estado.resultado
  if r ~= nil then
    local texto = r.texto
    if not texto and sala ~= nil and sala.prontos >= 1 and not sala.eu then
      texto = "O outro jogador quer jogar de novo."
    end
    return {
      modo = "fim", titulo = r.titulo, texto = texto,
      botao = r.jogador and { texto = "Jogar de novo", acao = "de_novo" } or { texto = "Fechar", acao = "fechar" },
    }
  end
  local v = C.visao()
  if v ~= nil and v.vencedor == false and not v.erro then
    local lado = C.lado()
    local texto = "Partida em curso. Você está assistindo."
    if lado == 1 or lado == 2 then texto = "Partida em curso. Você joga pelo lado " .. lado .. "." end
    local a = sala ~= nil and sala.ausente or false
    if a then
      local prazo = prazo_por_extenso(a.prazo)
      if a.lado == lado then
        texto = "Você caiu da partida. Volte em até " .. prazo .. " para não perder."
      elseif lado == 1 or lado == 2 then
        texto = "O outro jogador caiu. Se não voltar em " .. prazo .. ", você vence."
      else
        texto = "O lado " .. a.lado .. " caiu. Se não voltar em " .. prazo .. ", perde a partida."
      end
    end
    return { modo = "partida", titulo = false, texto = texto, botao = false }
  end
  if sala == nil then
    return { modo = "sala", titulo = "Duelo", texto = "Conectando à mesa...", botao = false }
  end
  return {
    modo = "sala", titulo = "Duelo", texto = texto_da_sala(sala),
    botao = sala.eu and { texto = "Cancelar", acao = "cancelar" } or { texto = "Pronto", acao = "pronto" },
  }
end

function Tela.atualizar()
  local w = estado.widget
  if w == nil then return end
  -- Um erro ao montar o modelo não desliga o painel: só esta atualização se perde.
  local ok, modelo = pcall(Tela.modelo)
  if not ok then
    log("erro ao montar o painel: " .. tostring(modelo))
    return
  end
  local err
  ok, err = pcall(function() w:Atualizar(modelo) end)
  if not ok then
    -- O widget morreu (a tela do jogo foi desfeita): desliga até o próximo.
    estado.widget = nil
    log("o painel não pôde ser atualizado (desligado): " .. tostring(err))
  end
end

function Tela.clicar()
  local C = estado.cliente
  if C == nil then return end
  local botao = Tela.modelo().botao
  if not botao then return end
  local acao = botao.acao
  if acao == "de_novo" or acao == "fechar" then
    estado.dispensada = estado.resultado and estado.resultado.partida or estado.dispensada
    estado.resultado = nil
  end
  if acao == "pronto" or acao == "de_novo" then
    C.pronto(true)
  elseif acao == "cancelar" then
    C.pronto(false)
  end
  Tela.atualizar()
end

function Tela.ligar_widget(w)
  estado.widget = w
  Tela.atualizar()
end

-- Liga o módulo.
--   ctx.cliente: duelo/mod/partida_cliente.lua já instalado;
--   ctx.log: função de log (opcional).
function Tela.instalar(ctx)
  estado.cliente = ctx.cliente
  estado.log = ctx.log
  estado.widget = nil
  estado.resultado = nil
  estado.dispensada = nil
  local C = ctx.cliente
  C.quando_estado(Tela.atualizar)
  C.quando_evento(function(ev)
    -- Só o que muda o painel: o começo e o fim.
    if type(ev) == "table" and (ev.t == "game_over" or ev.t == "start" or ev.t == "engine_error") then
      Tela.atualizar()
    end
  end)
  C.quando_sala(Tela.atualizar)
  return Tela
end

return Tela
