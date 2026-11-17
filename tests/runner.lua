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

-- Tabelas globais do motor que um teste poderia alterar.
local GLOBAL_TABLES = { "actions", "period_hooks", "play_rules", "allowed_at_zero_fogueira", "allowed_with_stack" }

local function refill(dst, src)
  for k in pairs(dst) do dst[k] = nil end
  for k, v in pairs(src) do dst[k] = v end
end

local function snapshot()
  local snap = { tables = {}, constants = {}, cards = Cards.snapshot() }
  for _, name in ipairs(GLOBAL_TABLES) do snap.tables[name] = shallow(Game[name]) end
  -- Constantes (números e textos) do módulo Game.
  for k, v in pairs(Game) do
    if type(v) == "number" or type(v) == "string" then snap.constants[k] = v end
  end
  return snap
end

local function restore(snap)
  for _, name in ipairs(GLOBAL_TABLES) do refill(Game[name], snap.tables[name]) end
  for k, v in pairs(Game) do
    if (type(v) == "number" or type(v) == "string") and snap.constants[k] == nil then Game[k] = nil end
  end
  for k, v in pairs(snap.constants) do Game[k] = v end
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
