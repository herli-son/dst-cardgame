local Game = require("duelo/core/game")

local function deck(n, prefix)
  local d = {}
  for i = 1, n do d[i] = { id = (prefix or "c") .. i } end
  return d
end

local function new_game(opts)
  opts = opts or {}
  local g = Game.new{
    decks = { opts.d1 or deck(40), opts.d2 or deck(40) },
    first = 1,
    mulligan = opts.mulligan,
    rng = function(n) return n end, -- embaralhar mantém a ordem
  }
  g:start()
  return g
end

local function pass_round(g)
  g:act(g.active, { type = "pass" })
  g:act(g.active, { type = "pass" })
end

return {
  { "mana começa em 1, cresce 1 por rodada e recarrega", function(T)
    local g = new_game{ mulligan = false }
    T.eq(g.players[1].mana, 1)
    T.eq(g.players[2].max_mana, 1)
    g:spend_mana(1, 1)
    T.eq(g.players[1].mana, 0)
    pass_round(g)
    T.eq(g.players[1].max_mana, 2)
    T.eq(g.players[1].mana, 2, "recarrega no início da rodada")
  end },

  { "mana para de crescer em 10", function(T)
    local g = new_game{ mulligan = false }
    for _ = 1, 14 do pass_round(g) end
    T.eq(g.round, 15)
    T.eq(g.players[1].max_mana, 10)
  end },

  { "cada jogador compra 1 carta no início de cada rodada", function(T)
    local g = new_game{ mulligan = false }
    T.eq(#g.players[1].hand, 5)
    pass_round(g)
    T.eq(#g.players[1].hand, 6)
    T.eq(#g.players[2].hand, 6)
  end },

  { "limite de mão 10 contando Inventário e separadas; o excedente vai para as destruídas", function(T)
    local g = new_game{ mulligan = false }
    local pl = g.players[1]
    pl.inventory = { { id = "inv1" }, { id = "inv2" } }
    pl.separated = { { id = "sep1" } }
    -- mão 5 + 3 fora = 8; mais duas compras chegam a 10
    pass_round(g)
    pass_round(g)
    T.eq(g:hand_count(1), 10)
    pass_round(g)
    T.eq(g:hand_count(1), 10, "não passa de 10")
    T.eq(#pl.destroyed, 1, "a carta comprada acima do limite é destruída")
    T.eq(#pl.discard, 0, "destruir não é descartar")
  end },

  { "troca inicial: a partida só começa depois que os dois decidem", function(T)
    local g = new_game{}
    T.eq(g.phase, "mulligan")
    T.eq(g.round, 0)
    local ok = g:act(1, { type = "pass" })
    T.eq(ok, false, "não dá para jogar antes da troca")
    T.ok(g:mulligan(1, {}))
    T.eq(g.round, 0)
    T.ok(g:mulligan(2, { 1, 2 }))
    T.eq(g.phase, "playing")
    T.eq(g.round, 1)
  end },

  { "troca inicial devolve as escolhidas e compra a mesma quantidade, uma vez só", function(T)
    local g = new_game{}
    local pl = g.players[1]
    local before = {}
    for i, c in ipairs(pl.hand) do before[i] = c end
    T.ok(g:mulligan(1, { 2, 4 }))
    T.eq(#pl.hand, 4)
    T.eq(pl.hand[1], before[1], "as não escolhidas ficam")
    T.eq(pl.hand[2], before[3])
    T.eq(#pl.deck, 36)
    local ok = g:mulligan(1, { 1 })
    T.eq(ok, false, "só uma troca")
  end },

  { "troca com índice inválido é recusada", function(T)
    local g = new_game{}
    local ok = g:mulligan(1, { 9 })
    T.eq(ok, false)
    ok = g:mulligan(1, { 1, 1 })
    T.eq(ok, false, "índice repetido")
  end },

  { "Fome: baralho vazio causa 1, depois 2, depois 3", function(T)
    local g = new_game{ mulligan = false, d1 = deck(5) }
    -- 4 na mão inicial e 1 na rodada 1: baralho do jogador 1 vazio
    T.eq(#g.players[1].deck, 0)
    T.eq(g.players[1].life, 20)
    pass_round(g)
    T.eq(g.players[1].life, 19)
    pass_round(g)
    T.eq(g.players[1].life, 17)
    pass_round(g)
    T.eq(g.players[1].life, 14)
    T.eq(g.players[2].life, 20)
  end },

  { "Fome pode encerrar a partida", function(T)
    local g = new_game{ mulligan = false, d1 = deck(5) }
    g.players[1].life = 1
    pass_round(g)
    T.eq(g.winner, 2)
    T.eq(g.phase, "over")
  end },
}
