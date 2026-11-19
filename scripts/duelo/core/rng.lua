-- Gerador de números ao acaso determinístico do motor. Lua 5.1 puro.
--
-- Park e Miller (MINSTD), só com inteiros exatos em doubles. A mesma semente
-- dá sempre a mesma sequência, o que permite reproduzir uma partida a partir
-- do registro (US #82).
--
-- Interface:
--   local Rng = require("duelo/core/rng")
--   Rng.make(seed) -> rng(n)   rng(n) devolve um inteiro entre 1 e n
--   Rng.MAX_SEED               maior semente distinta (as sementes são
--                              reduzidas módulo MAX_SEED + 1)

local Rng = {}

local M = 2147483647 -- 2^31 - 1
local A = 48271

Rng.MAX_SEED = M - 1

function Rng.make(seed)
  assert(type(seed) == "number" and seed == seed, "semente precisa ser um número")
  local s = math.floor(seed) % M
  if s == 0 then s = 1 end
  return function(n)
    s = (s * A) % M
    return (s % n) + 1
  end
end

return Rng
