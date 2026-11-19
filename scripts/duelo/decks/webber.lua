-- Deck do Webber (MVP, Feature #19). 40 cartas, até 3 cópias. Lua 5.1 puro.
-- Os equipamentos básicos são neutros (doc, "Equipamentos básicos").
return {
  principal = {
    { "webber", 3 },
    { "aranha", 3 },
    { "aranha_guerreira", 3 },
    { "curandeira", 3 },
    { "porco", 3 },
    { "porco_guarda", 2 },
    { "sapo", 3 },
    { "morcego", 3 },
    { "passaro", 2 },
    { "cao_de_caca", 2 },
    { "lanca", 3 },
    { "armadura_de_grama", 2 },
    { "dardo", 3 },
    { "pomada", 3 },
    { "dardo_do_sono", 2 },
  },
  -- Fichas: uma Aranha para cada Webber (ao jogar, o Webber cria 1 Aranha).
  extra = {
    { "aranha", 3 },
  },
}
