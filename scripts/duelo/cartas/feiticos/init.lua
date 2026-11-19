-- Cartas do tipo "feiticos": um arquivo por carta nesta pasta. Lua 5.1 puro.
-- Carregar este módulo registra todas no motor (Cards.define) e devolve os ids.

local ids = {
  "dardo",
  "dardo_do_sono",
  "pomada",
}

for _, id in ipairs(ids) do
  -- Recarrega sempre: o registro de cartas pode ter sido restaurado entre partidas.
  package.loaded["duelo/cartas/feiticos/" .. id] = nil
  require("duelo/cartas/feiticos/" .. id)
end

return ids
