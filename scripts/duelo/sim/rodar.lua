-- Roda muitas partidas simuladas fora dos testes (#26). Lua 5.1 puro.
--
-- Uso, a partir da raiz do repositório:
--   lua scripts/duelo/sim/rodar.lua [n] [seed]
--   python3 run_lua51.py scripts/duelo/sim/rodar.lua [n] [seed]   (runner lupa)
--
-- n (padrão 3000) é o total de partidas, dividido em quatro lotes: random x
-- random, bot x random, random x bot e bot x bot, cada um com os lados dos
-- baralhos alternados pela paridade da seed. seed (padrão 0) é
-- a base das sementes. Termina com código 1 se alguma partida falhar (erro do
-- motor, travamento, invariante ou erro do simulador). Para reproduzir uma
-- falha: Simulador.run_game com a seed, os jogadores e os baralhos impressos
-- (trocados de lado quando a linha diz "lados trocados").

package.path = "scripts/?.lua;tests/?.lua;" .. package.path

local Simulador = require("duelo/sim/simulador")
local CartasSim = require("cartas_sim")

-- Argumentos: `arg` no interpretador lua; no runner lupa, sys.argv do Python.
local function args()
  if arg then return arg[1], arg[2] end
  if python and python.eval then
    local argv = python.eval("__import__('sys').argv")
    local n = python.builtins.len(argv)
    return n > 2 and argv[2] or nil, n > 3 and argv[3] or nil
  end
end

local a1, a2 = args()
local total = tonumber(a1) or 3000
local seed = tonumber(a2) or 0

CartasSim.define()

local lotes = {
  { players = { "random", "random" } },
  { players = { "bot", "random" } },
  { players = { "random", "bot" } },
  { players = { "bot", "bot" } },
}
local per = math.floor(total / #lotes)
local resto = total - per * #lotes
local falhas = 0
local soma = { n = 0, por_resultado = {}, vitorias_por_lado = { 0, 0 }, vitorias_por_deck = { 0, 0 }, empates = 0,
  rodadas = { media = 0, max = 0 }, jogadas = { media = 0, max = 0 }, falhas = {}, players = { "misto", "misto" }, tempo = 0 }
for _, r in ipairs(Simulador.RESULTS) do soma.por_resultado[r] = 0 end

for i, lote in ipairs(lotes) do
  local n = per + (i <= resto and 1 or 0)
  local agg = Simulador.run_many{
    n = n, seed_base = seed + (i - 1) * 1000000, players = lote.players, alternar = true,
    decks = CartasSim.decks(), extra_decks = CartasSim.extra_decks(),
  }
  print(Simulador.format_report(agg))
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
