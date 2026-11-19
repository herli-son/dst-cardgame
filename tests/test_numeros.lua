-- Números das cartas (US #125): únicos, permanentes e iguais aos das definições.
local Cards = require("duelo/core/cards")

local function load_all()
  package.loaded["duelo/cartas/init"] = nil
  package.loaded["duelo/cartas/numeros"] = nil
  return require("duelo/cartas/init"), require("duelo/cartas/numeros")
end

return {
  { "todo número é único e inteiro positivo", function(T)
    local _, numeros = load_all()
    local seen = {}
    for id, n in pairs(numeros) do
      T.ok(type(n) == "number" and n >= 1 and n % 1 == 0, id .. ": número inválido")
      T.eq(seen[n], nil, id .. ": número " .. n .. " repetido com " .. tostring(seen[n]))
      seen[n] = id
    end
  end },

  { "toda carta registrada tem o número da lista oficial", function(T)
    local ids, numeros = load_all()
    for _, id in ipairs(ids) do
      local def = Cards.get(id)
      T.ok(def ~= nil, id)
      T.eq(def.numero, numeros[id], id .. ": numero da carta difere da lista")
    end
    for id in pairs(numeros) do
      T.ok(Cards.get(id) ~= nil, id .. ": está na lista mas não é uma carta registrada")
    end
  end },
}
