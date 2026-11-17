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

-- Cada caso roda isolado: o estado global do motor (ações, ganchos de período e
-- registro de cartas) é salvo antes e restaurado depois, mesmo quando o caso falha.
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local function shallow(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

-- Todo o módulo Game é salvo: chaves de qualquer tipo (constantes, métodos e
-- tabelas) e uma cópia rasa de cada tabela, para desfazer alterações dentro delas.
local function snapshot()
  local snap = { keys = {}, tables = {}, cards = Cards.snapshot() }
  for k, v in pairs(Game) do
    snap.keys[k] = v
    if type(v) == "table" and k ~= "__index" then snap.tables[k] = shallow(v) end
  end
  return snap
end

local function restore(snap)
  for k in pairs(Game) do
    if snap.keys[k] == nil then Game[k] = nil end
  end
  for k, v in pairs(snap.keys) do Game[k] = v end
  for k, copy in pairs(snap.tables) do
    local t = Game[k]
    for x in pairs(t) do t[x] = nil end
    for x, y in pairs(copy) do t[x] = y end
  end
  Cards.restore(snap.cards)
end

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

local files = { "test_rodada", "test_periodo", "test_fogueira", "test_mana_mao", "test_criaturas", "test_estruturas", "test_equipamentos", "test_pilha", "test_fichas", "test_regressoes" }
for _, f in ipairs(files) do run_file(f) end

for _, f in ipairs(T.failures) do print("FALHOU  " .. f) end
print(string.format("%d passaram, %d falharam", T.passed, T.failed))
if T.failed > 0 then os.exit(1) end
