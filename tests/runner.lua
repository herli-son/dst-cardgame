-- Executor de testes mínimo, compatível com Lua 5.1.
-- Uso, a partir da raiz do repositório: lua tests/runner.lua

package.path = "scripts/?.lua;tests/?.lua;" .. package.path

local T = { passed = 0, failed = 0, failures = {} }

function T.eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "valor diferente") .. ": esperado " .. tostring(expected) .. ", veio " .. tostring(actual), 2)
  end
end

function T.ok(cond, msg)
  if not cond then error(msg or "condição falsa", 2) end
end

-- Cada caso roda isolado: o estado global do motor é salvo antes e restaurado
-- depois, mesmo quando o caso falha. Isso cobre o módulo Game inteiro (constantes,
-- métodos e tabelas, em qualquer profundidade), o registro de cartas e o conteúdo
-- de cada definição registrada. Variáveis locais dos módulos ficam de fora.
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local function shallow(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

-- Guarda uma cópia rasa de cada tabela alcançável a partir de Game, indexada pela
-- própria tabela. Restaurar devolve o conteúdo de cada uma no lugar, então as
-- referências guardadas pelos módulos continuam válidas.
local function snapshot()
  local contents = {}
  local function walk(t)
    if contents[t] then return end
    contents[t] = shallow(t)
    for k, v in pairs(t) do
      if type(k) == "table" then walk(k) end
      if type(v) == "table" then walk(v) end
    end
  end
  walk(Game)
  local cards = Cards.snapshot()
  for _, def in pairs(cards) do walk(def) end
  return { contents = contents, cards = cards }
end

local function restore(snap)
  for t, copy in pairs(snap.contents) do
    for k in pairs(t) do
      if copy[k] == nil then t[k] = nil end
    end
    for k, v in pairs(copy) do t[k] = v end
  end
  Cards.restore(snap.cards)
end

-- Expostos para o teste que confere o próprio isolamento.
T.snapshot, T.restore = snapshot, restore

local function run_file(name)
  local tests = require(name)
  for _, case in ipairs(tests) do
    local snap = snapshot()
    local ok, err = pcall(case[2], T)
    restore(snap)
    if ok then
      T.passed = T.passed + 1
    else
      T.failed = T.failed + 1
      T.failures[#T.failures + 1] = name .. " > " .. case[1] .. ": " .. tostring(err)
    end
  end
end

local files = { "test_rodada", "test_periodo", "test_fogueira", "test_mana_mao", "test_criaturas", "test_estruturas", "test_equipamentos", "test_pilha", "test_fichas", "test_regressoes", "test_erros", "test_combate", "test_velocidade", "test_cura", "test_bloqueio_obrigatorio", "test_escolha_pausa", "test_ordem_combate", "test_baralho_extra", "test_substituir", "test_bot", "test_terminal", "test_simulador", "test_limite_mao", "test_neutras", "test_numeros", "test_feiticos", "test_webber", "test_wilson", "test_ganchos_vida", "test_curandeira", "test_decks", "test_efeitos_rodada" }
for _, f in ipairs(files) do run_file(f) end

for _, f in ipairs(T.failures) do print("FALHOU  " .. f) end
print(string.format("%d passaram, %d falharam", T.passed, T.failed))
if T.failed > 0 then os.exit(1) end
