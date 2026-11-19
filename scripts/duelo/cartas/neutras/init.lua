-- Criaturas neutras do MVP (#22): cartas comuns aos dois baralhos. Lua 5.1 puro.
-- Cada carta fica no próprio arquivo desta pasta. Carregar este módulo carrega
-- todas (Cards.define) e devolve a lista dos ids, na ordem do documento.

local ids = {
  "porco",
  "porco_guarda",
  "sapo",
  "morcego",
  "passaro",
  "borboleta",
  "cao_de_caca",
}

for _, id in ipairs(ids) do
  -- Recarrega sempre: o registro de cartas pode ter sido restaurado entre partidas.
  package.loaded["duelo/cartas/neutras/" .. id] = nil
  require("duelo/cartas/neutras/" .. id)
end

return ids
