-- Todas as cartas de conteúdo, por tipo. Lua 5.1 puro.
-- Carregar este módulo registra todas no motor e devolve a lista de ids.
-- Os decks (listas de ids e quantidades) ficam em scripts/duelo/decks/.

local TIPOS = { "criaturas", "campeoes", "feiticos", "estruturas", "equipamentos" }

local ids = {}
for _, tipo in ipairs(TIPOS) do
  package.loaded["duelo/cartas/" .. tipo .. "/init"] = nil
  for _, id in ipairs(require("duelo/cartas/" .. tipo .. "/init")) do ids[#ids + 1] = id end
end

return ids
