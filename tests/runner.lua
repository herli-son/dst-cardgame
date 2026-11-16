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

local function snapshot()
  return { actions = shallow(Game.actions), hooks = shallow(Game.period_hooks), cards = Cards.snapshot() }
end

local function restore(snap)
  for k in pairs(Game.actions) do Game.actions[k] = nil end
  for k, v in pairs(snap.actions) do Game.actions[k] = v end
  for k in pairs(Game.period_hooks) do Game.period_hooks[k] = nil end
  for k, v in pairs(snap.hooks) do Game.period_hooks[k] = v end
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
