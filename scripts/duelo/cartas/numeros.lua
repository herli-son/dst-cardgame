-- Número oficial de cada carta (US #125: código de deck). Lua 5.1 puro.
--
-- Esta lista só cresce. Um número nunca muda nem é reaproveitado, mesmo que a
-- carta saia do jogo ou mude de nome: o código de um deck compartilhado precisa
-- abrir sempre o mesmo deck. Toda carta registrada precisa de um número igual ao
-- daqui (tests/test_numeros.lua confere).

return {
  porco = 1,
  porco_guarda = 2,
  sapo = 3,
  morcego = 4,
  passaro = 5,
  borboleta = 6,
  cao_de_caca = 7,
  dardo = 30,
  pomada = 31,
}
