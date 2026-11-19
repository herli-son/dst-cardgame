-- Cartas do tipo "estruturas": um arquivo por carta nesta pasta. Lua 5.1 puro.
-- Carregar este módulo registra todas no motor (Cards.define) e devolve os ids.

local ids = {
  "maquina_de_ciencia",
}

for _, id in ipairs(ids) do
  -- Recarrega sempre: o registro de cartas pode ter sido restaurado entre partidas.
  package.loaded["duelo/cartas/estruturas/" .. id] = nil
  require("duelo/cartas/estruturas/" .. id)
end

return ids
