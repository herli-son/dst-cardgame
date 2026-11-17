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

local function run_file(name)
  local tests = require(name)
  for _, case in ipairs(tests) do
    local ok, err = pcall(case[2], T)
    if ok then
      T.passed = T.passed + 1
    else
      T.failed = T.failed + 1
      T.failures[#T.failures + 1] = name .. " > " .. case[1] .. ": " .. tostring(err)
    end
  end
end

local files = { "test_rodada", "test_periodo", "test_fogueira", "test_mana_mao", "test_criaturas", "test_estruturas", "test_equipamentos" }
for _, f in ipairs(files) do run_file(f) end

for _, f in ipairs(T.failures) do print("FALHOU  " .. f) end
print(string.format("%d passaram, %d falharam", T.passed, T.failed))
if T.failed > 0 then os.exit(1) end
