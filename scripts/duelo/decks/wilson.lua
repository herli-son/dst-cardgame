-- Deck do Wilson (MVP, Feature #19). 40 cartas, até 3 cópias. Lua 5.1 puro.
-- Os equipamentos básicos são neutros (doc, "Equipamentos básicos"); só Wilson
-- e a Máquina de Ciência são do deck.
return {
  principal = {
    { "wilson", 3 },
    { "maquina_de_ciencia", 2 },
    { "lanca", 3 },
    { "machado", 3 },
    { "pa", 3 },
    { "armadura_de_grama", 2 },
    { "armadura_de_madeira", 2 },
    { "porco", 3 },
    { "porco_guarda", 3 },
    { "sapo", 3 },
    { "cao_de_caca", 3 },
    { "morcego", 2 },
    { "passaro", 2 },
    { "dardo", 3 },
    { "pomada", 3 },
  },
  -- Nenhuma carta do deck cria fichas.
  extra = {},
}
