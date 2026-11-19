-- Roda muitas partidas simuladas fora dos testes (#26). Lua 5.1 puro.
--
-- Uso, a partir da raiz do repositório:
--   lua scripts/duelo/sim/rodar.lua [n] [seed] [log]
--   python3 run_lua51.py scripts/duelo/sim/rodar.lua [n] [seed] [log]   (runner lupa)
--
-- n (padrão 3000) é o total de partidas, dividido em quatro lotes: random x
-- random (com a troca inicial), bot x random, random x bot e bot x bot, cada um
-- com os lados dos baralhos alternados pela paridade da seed. seed (padrão 0) é
-- a base das sementes. Termina com código 1 se alguma partida falhar (erro do
-- motor, travamento, invariante ou erro do simulador). Para reproduzir uma
-- falha: Simulador.run_game com a seed, os jogadores na ordem impressa (ela já é
-- a da partida), mulligan = true quando a linha diz "com troca inicial", e os
-- baralhos trocados de lado quando a linha diz "baralhos trocados". Com "log"
-- como terceiro argumento, cada falha vem seguida do registro da partida (US
-- #82), serializado por Replay.log_to_string: Replay.run(Replay.log_from_string(s))
-- repete a partida até a falha.

package.path = "scripts/?.lua;tests/?.lua;" .. package.path

local Simulador = require("duelo/sim/simulador")
local Replay = require("duelo/core/replay")
local CartasSim = require("cartas_sim")

-- Argumentos: `arg` no interpretador lua; no runner lupa, sys.argv do Python.
local function args()
  if arg then return arg[1], arg[2], arg[3] end
  if python and python.eval then
    local argv = python.eval("__import__('sys').argv")
    local n = python.builtins.len(argv)
    return n > 2 and argv[2] or nil, n > 3 and argv[3] or nil, n > 4 and argv[4] or nil
  end
end

local a1, a2, a3 = args()
local total = tonumber(a1) or 3000
local seed = tonumber(a2) or 0
local print_log = a3 == "log"

CartasSim.define()

local lotes = {
  { players = { "random", "random" }, mulligan = true },
  { players = { "bot", "random" } },
  { players = { "random", "bot" } },
  { players = { "bot", "bot" } },
}
local per = math.floor(total / #lotes)
local resto = total - per * #lotes
local falhas = 0
local soma = { n = 0, por_resultado = {}, vitorias_por_lado = { 0, 0 }, vitorias_por_deck = { 0, 0 }, empates = 0,
  rodadas = { media = 0, max = 0 }, jogadas = { media = 0, max = 0 }, jogadas_por_tipo = {}, falhas = {},
  players = { "misto", "misto" }, tempo = 0 }
for _, r in ipairs(Simulador.RESULTS) do soma.por_resultado[r] = 0 end

for i, lote in ipairs(lotes) do
  local n = per + (i <= resto and 1 or 0)
  local agg = Simulador.run_many{
    n = n, seed_base = seed + (i - 1) * 1000000, players = lote.players, mulligan = lote.mulligan, alternar = true,
    decks = CartasSim.decks(), extra_decks = CartasSim.extra_decks(),
  }
  if lote.mulligan then print("(lote com a troca inicial)") end
  print(Simulador.format_report(agg))
  if print_log then
    for _, f in ipairs(agg.falhas) do
      if f.log then
        local ok, text = pcall(Replay.log_to_string, f.log)
        print(string.format("registro da seed %d: %s", f.seed, ok and text or ("não serializável: " .. tostring(text))))
      end
    end
  end
  print("")
  falhas = falhas + #agg.falhas
  -- Soma para o resumo geral.
  soma.rodadas.media = (soma.rodadas.media * soma.n + agg.rodadas.media * agg.n)
  soma.jogadas.media = (soma.jogadas.media * soma.n + agg.jogadas.media * agg.n)
  soma.n = soma.n + agg.n
  if soma.n > 0 then
    soma.rodadas.media = soma.rodadas.media / soma.n
    soma.jogadas.media = soma.jogadas.media / soma.n
  end
  for _, r in ipairs(Simulador.RESULTS) do soma.por_resultado[r] = soma.por_resultado[r] + (agg.por_resultado[r] or 0) end
  for p = 1, 2 do
    soma.vitorias_por_lado[p] = soma.vitorias_por_lado[p] + agg.vitorias_por_lado[p]
    soma.vitorias_por_deck[p] = soma.vitorias_por_deck[p] + agg.vitorias_por_deck[p]
  end
  soma.empates = soma.empates + agg.empates
  soma.rodadas.max = math.max(soma.rodadas.max, agg.rodadas.max)
  soma.jogadas.max = math.max(soma.jogadas.max, agg.jogadas.max)
  for t, k in pairs(agg.jogadas_por_tipo) do soma.jogadas_por_tipo[t] = (soma.jogadas_por_tipo[t] or 0) + k end
  -- f.players é a ordem da própria partida (já trocada quando for o caso); o
  -- lote fica à parte.
  for _, f in ipairs(agg.falhas) do
    f.lote = i
    soma.falhas[#soma.falhas + 1] = f
  end
  soma.tempo = soma.tempo + agg.tempo
end

print("RESUMO GERAL")
print(Simulador.format_report(soma))
if falhas > 0 then os.exit(1) end
