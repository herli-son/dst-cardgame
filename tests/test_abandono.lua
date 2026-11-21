-- Derrota por abandono no motor (US #43): Game:forfeit e a reprodução.
local Game = require("duelo/core/game")
local Replay = require("duelo/core/replay")
local CartasSim = require("cartas_sim")

local function deck(id, n)
  local d = {}
  for i = 1, n do d[i] = { id = id } end
  return d
end

local function jogo_simples(extra)
  CartasSim.define()
  local o = { decks = { deck("sim_rato", 20), deck("sim_lobo", 20) }, first = 1, mulligan = false, seed = 11 }
  for k, v in pairs(extra or {}) do o[k] = v end
  local g = Game.new(o)
  assert(g:start())
  return g
end

return {
  { "motor: quem abandona perde, em qualquer momento da partida", function(T)
    local g = jogo_simples()
    T.eq(g.active, 1)
    -- Fora da vez dele.
    local ok = g:forfeit(2, "desconexao")
    T.ok(ok)
    T.eq(g.winner, 1); T.eq(g.phase, "over")
    T.eq(g.forfeited.p, 2); T.eq(g.forfeited.reason, "desconexao")
    local n = #g.events
    T.eq(g.events[n - 1].t, "forfeit"); T.eq(g.events[n - 1].p, 2); T.eq(g.events[n - 1].reason, "desconexao")
    T.eq(g.events[n].t, "game_over"); T.eq(g.events[n].winner, 1)
    -- Depois do fim, nada mais vale.
    local de_novo, erro = g:forfeit(1, "desconexao")
    T.ok(not de_novo); T.eq(erro, "partida encerrada")
    T.eq(g.winner, 1, "o resultado não muda")
    T.ok(not g:act(1, { type = "pass" }))
    -- Na troca inicial também vale.
    g = jogo_simples{ mulligan = true }
    T.eq(g.phase, "mulligan")
    T.ok(g:forfeit(1))
    T.eq(g.winner, 2); T.eq(g.forfeited.reason, "abandono", "motivo padrão")
  end },

  { "motor: pedidos tortos de abandono são recusados sem mudar nada", function(T)
    local g = jogo_simples()
    for _, p in ipairs({ 0, 3, "1", 1.5 }) do
      local ok = g:forfeit(p, "desconexao")
      T.ok(not ok, "jogador inválido: " .. tostring(p))
    end
    T.ok(not g:forfeit(1, 7), "motivo que não é texto")
    T.ok(not g:forfeit(nil))
    T.eq(g.winner, nil); T.eq(g.phase, "playing"); T.eq(g.forfeited, nil)
    T.eq(#g.log.actions, 0, "nada entrou no registro")
    -- Antes de a partida começar não há o que abandonar.
    CartasSim.define()
    local novo = Game.new{ decks = { deck("sim_rato", 20), deck("sim_lobo", 20) }, seed = 3 }
    T.ok(not novo:forfeit(1))
    T.eq(novo.winner, nil)
  end },

  { "motor: o abandono não é uma jogada que um jogador possa mandar", function(T)
    local g = jogo_simples()
    local ok, erro = g:act(1, { type = "forfeit", reason = "desconexao" })
    T.ok(not ok, "Game:act recusa")
    T.ok(tostring(erro):find("desconhecida", 1, true), tostring(erro))
    T.ok(not g:can_act(1, { type = "forfeit" }))
    T.eq(g.winner, nil)
  end },

  { "motor: a reprodução de uma partida com abandono termina igual", function(T)
    local g = jogo_simples()
    T.ok(g:act(1, { type = "pass" }))
    T.ok(g:forfeit(1, "desconexao"))
    local ultimo = g.log.actions[#g.log.actions]
    T.eq(ultimo.p, 1); T.eq(ultimo.action.type, "forfeit"); T.eq(ultimo.action.reason, "desconexao")
    local r = Replay.run(Replay.log_from_string(Replay.log_to_string(g.log)))
    T.eq(r.winner, 2); T.eq(r.forfeited.p, 1)
    local igual, diferenca = Replay.same_state(g, r)
    T.ok(igual, tostring(diferenca))
    T.eq(Replay.snapshot(r).forfeit.reason, "desconexao")
  end },
}
