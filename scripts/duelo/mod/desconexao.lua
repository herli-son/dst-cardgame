-- Desconexão (US #43): quem cai perde.
--
-- Regra:
--   * Num servidor dedicado, o jogador que sai no meio da partida tem
--     Desconexao.PRAZO segundos (2 minutos) para voltar. Se voltar a tempo, a
--     partida segue (ele recebe a fotografia de novo, US #41). Se não, perde:
--     o outro vence por abandono (Game:forfeit, motivo "desconexao").
--   * No jogo hospedado por um jogador (host), não há prazo: o jogador que
--     sai perde na hora. Se quem cai é o host, o mundo fecha junto e não há
--     nada a fazer.
--   * Se os dois caem, perde quem caiu primeiro (o prazo dele vence antes).
--   * Na partida de teste com um jogador só nos dois lados
--     (Partida.iniciar_teste), ninguém vence: no fim do prazo a partida é só
--     encerrada.
--   * Quem assiste pode sair e voltar à vontade.
--
-- O prazo é contado em tempo real (ctx.agora, GetTimeRealSeconds no jogo), e
-- não no tempo do mundo: o servidor dedicado pausa a simulação quando fica
-- vazio, e o prazo de quem saiu continua correndo. Ele é conferido a cada
-- segundo por uma tarefa do mundo e também sempre que alguém entra ou sai
-- (com o mundo pausado a tarefa não roda; quem volta depois do prazo perde
-- na hora em que entra).
--
-- O que os clientes ficam sabendo: o campo `ausente` da mensagem "sala"
-- ({ lado, prazo }), enquanto alguém está fora, e, no fim, o evento
-- "forfeit" e o campo `abandono` da visão (duelo/mod/visao).
--
-- Interface:
--   Desconexao.instalar{ partida = Partida, sala = Sala, agora = fn,
--                        dedicado = bool, log = fn } -> Desconexao
--   Desconexao.saiu(userid) / Desconexao.entrou(userid)
--   Desconexao.conferir()        aplica os prazos vencidos
--   Desconexao.ausente() -> { lado, prazo, userid, limite } | nil
--       quem está fora com o prazo mais perto de vencer
--
-- Lua puro: tudo do jogo chega por `ctx`. Só é carregado no servidor.

local Desconexao = {}

Desconexao.PRAZO = 120
Desconexao.MOTIVO = "desconexao"

local estado = {
  partida = nil,
  sala = nil,
  agora = nil,
  dedicado = false,
  log = nil,
  -- userid -> { partida = n, limite = segundos (tempo real), ordem = n }
  ausentes = {},
  ordem = 0,
}

local function log(msg)
  if estado.log then estado.log("[duelo] desconexão: " .. tostring(msg)) end
end

local function prazo()
  return estado.dedicado and Desconexao.PRAZO or 0
end

-- Os lados que o usuário ocupa na partida em curso ({}: não joga).
local function lados_de(userid)
  local j = estado.partida.jogadores()
  local out = {}
  if j ~= nil then
    for lado = 1, 2 do
      if j[lado] == userid then out[#out + 1] = lado end
    end
  end
  return out
end

local function em_jogo()
  local P = estado.partida
  return P.em_curso() and not P.terminada()
end

-- Os ausentes da partida em curso, do prazo mais antigo para o mais novo.
-- Esquece os que ficaram de uma partida que já não é a da mesa.
local function fila()
  local P = estado.partida
  local numero, valendo = P.numero(), em_jogo()
  local out = {}
  for userid, a in pairs(estado.ausentes) do
    if not valendo or a.partida ~= numero or #lados_de(userid) == 0 then
      estado.ausentes[userid] = nil
    else
      out[#out + 1] = { userid = userid, limite = a.limite, ordem = a.ordem }
    end
  end
  table.sort(out, function(x, y)
    if x.limite ~= y.limite then return x.limite < y.limite end
    return x.ordem < y.ordem
  end)
  return out
end

function Desconexao.ausente()
  if estado.partida == nil then return nil end
  local primeiro = fila()[1]
  if primeiro == nil then return nil end
  local lados = lados_de(primeiro.userid)
  return { lado = lados[1], prazo = Desconexao.PRAZO, userid = primeiro.userid, limite = primeiro.limite }
end

-- Aplica a derrota de quem estourou o prazo. Devolve true se algo mudou.
function Desconexao.conferir()
  if estado.partida == nil then return false end
  local P = estado.partida
  local agora = estado.agora()
  for _, a in ipairs(fila()) do
    if agora < a.limite then break end
    local lados = lados_de(a.userid)
    if #lados == 2 then
      -- Partida de teste, um jogador nos dois lados: ninguém vence.
      log("o jogador " .. a.userid .. " não voltou; a partida de teste foi encerrada")
      estado.ausentes = {}
      P.encerrar()
      return true
    end
    local ok, err = P.derrotar(lados[1], Desconexao.MOTIVO)
    if ok then
      log("o jogador " .. a.userid .. " (lado " .. lados[1] .. ") não voltou e perdeu a partida")
      estado.ausentes = {}
      return true
    end
    -- Não deu agora (um lote saindo): a próxima conferência tenta de novo.
    log("a derrota do lado " .. lados[1] .. " ficou para depois: " .. tostring(err))
    return false
  end
  return false
end

function Desconexao.saiu(userid)
  if estado.partida == nil or type(userid) ~= "string" or userid == "" then return end
  Desconexao.conferir()
  if not em_jogo() or #lados_de(userid) == 0 then return end
  if estado.ausentes[userid] == nil then
    estado.ordem = estado.ordem + 1
    estado.ausentes[userid] = { partida = estado.partida.numero(), limite = estado.agora() + prazo(), ordem = estado.ordem }
    log("o jogador " .. userid .. " saiu da partida " .. estado.partida.numero()
      .. (prazo() > 0 and (": tem " .. prazo() .. " s para voltar") or ": sem prazo para voltar"))
  end
  Desconexao.conferir()
end

function Desconexao.entrou(userid)
  if estado.partida == nil or type(userid) ~= "string" or userid == "" then return end
  -- Primeiro os prazos: quem volta depois do prazo já perdeu.
  Desconexao.conferir()
  if estado.ausentes[userid] ~= nil then
    estado.ausentes[userid] = nil
    log("o jogador " .. userid .. " voltou a tempo")
  end
end

-- Liga o módulo.
--   ctx.partida: duelo/mod/partida_servidor.lua já instalado;
--   ctx.sala: duelo/mod/sala_servidor.lua já instalado (ouvir, definir_ausente, avisar);
--   ctx.agora: função que devolve o tempo real em segundos;
--   ctx.dedicado: true no servidor dedicado (há prazo para voltar);
--   ctx.log: função de log (opcional).
function Desconexao.instalar(ctx)
  estado.partida = ctx.partida
  estado.sala = ctx.sala
  estado.agora = ctx.agora
  estado.dedicado = ctx.dedicado == true
  estado.log = ctx.log
  estado.ausentes = {}
  estado.ordem = 0
  local S = ctx.sala
  if S ~= nil then
    S.ouvir(function(tipo, userid)
      if tipo == "saiu" then Desconexao.saiu(userid) else Desconexao.entrou(userid) end
    end)
    S.definir_ausente(function()
      local a = Desconexao.ausente()
      return a and { lado = a.lado, prazo = a.prazo } or nil
    end)
  end
  return Desconexao
end

-- A conferência de cada segundo: aplica os prazos e avisa a sala se mudou.
function Desconexao.tique()
  if Desconexao.conferir() and estado.sala ~= nil then estado.sala.avisar() end
end

return Desconexao
