-- Testes do simulador de partidas (#26): determinismo, muitas partidas sem
-- falha e invariantes que pegam estados quebrados de propósito.
local Game = require("duelo/core/game")
local Simulador = require("duelo/sim/simulador")
local Invariantes = require("duelo/sim/invariantes")
local CartasSim = require("cartas_sim")

local function opts(extra)
  CartasSim.define()
  local o = { decks = CartasSim.decks(), extra_decks = CartasSim.extra_decks() }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

-- Partida pronta para quebrar à mão: duas criaturas de cada lado, uma
-- estrutura e um equipamento, com o estado válido.
local function scenario()
  CartasSim.define()
  local g = Game.new{ decks = CartasSim.decks(), extra_decks = CartasSim.extra_decks(), first = 1, mulligan = false,
    rng = Simulador.make_rng(3) }
  g:start()
  g:place_creature(1, { id = "sim_sobrevivente", uid = g:next_uid() }, 1)
  g:place_creature(1, { id = "sim_lobo", uid = g:next_uid() }, 2)
  g:place_creature(2, { id = "sim_porco", uid = g:next_uid() }, 1)
  g:place_creature(2, { id = "sim_muro", uid = g:next_uid() }, 3)
  g:put_structure(1, { id = "sim_tocha", uid = g:next_uid() })
  g:equip(g:creature_at(1, 1), { id = "sim_machado", uid = g:next_uid() })
  return g
end

local function broken(T, g, expected_part, card_total)
  local ok, msg = Invariantes.check(g, { card_total = card_total })
  T.eq(ok, false, "a invariante não pegou: " .. expected_part)
  T.ok(tostring(msg):find(expected_part, 1, true) ~= nil, "mensagem esperada com '" .. expected_part .. "', veio: " .. tostring(msg))
end

local function summarize(rep)
  return table.concat({ rep.resultado, tostring(rep.vencedor), rep.rodadas, rep.jogadas,
    rep.ultima and Simulador.describe_action(rep.ultima.action) or "" }, "|")
end

return {
  { "o cenário montado passa nas invariantes", function(T)
    local g = scenario()
    local ok, msg = Invariantes.check(g, { card_total = Invariantes.count_cards(g) })
    T.eq(ok, true, tostring(msg))
  end },

  { "uma partida com a mesma seed repete o mesmo relatório", function(T)
    local a, ga = Simulador.run_game(opts{ seed = 42, log = true })
    local b, gb = Simulador.run_game(opts{ seed = 42, log = true })
    T.eq(summarize(a), summarize(b))
    T.eq(#a.log, #b.log)
    for i = 1, #a.log do
      T.eq(Simulador.describe_action(a.log[i].action), Simulador.describe_action(b.log[i].action), "jogada " .. i)
    end
    T.eq(#ga.events, #gb.events)
    T.ok(a.resultado == "vitoria" or a.resultado == "empate" or a.resultado == "limite_rodadas", a.resultado)
    T.eq(a.seed, 42)
    T.ok(a.jogadas > 0)
    -- Outra seed muda alguma coisa.
    local c = Simulador.run_game(opts{ seed = 43 })
    T.ok(summarize(a) ~= summarize(c), "seeds diferentes deram a mesma partida")
  end },

  { "bot contra bot também é determinístico", function(T)
    local a = Simulador.run_game(opts{ seed = 7, players = { "bot", "bot" } })
    local b = Simulador.run_game(opts{ seed = 7, players = { "bot", "bot" } })
    T.eq(summarize(a), summarize(b))
  end },

  { "o relatório traz a seed e o passo de uma falha e o erro do motor", function(T)
    CartasSim.define()
    local Cards = require("duelo/core/cards")
    -- Carta com bug: o efeito de entrada estoura.
    Cards.define{ id = "sim_bug", kind = "criatura", cost = 0, atk = 1, hp = 1,
      on_play = function() error("bug de propósito") end }
    local deck = {}
    for i = 1, 10 do deck[i] = { id = "sim_bug" } end
    local rep = Simulador.run_game{ decks = { deck, deck }, seed = 1 }
    T.eq(rep.resultado, "erro")
    T.eq(rep.seed, 1)
    T.ok(rep.passo ~= nil and rep.passo >= 1, "passo da falha")
    T.ok(rep.erro ~= nil and tostring(rep.erro.message):find("bug de propósito", 1, true) ~= nil, tostring(rep.erro and rep.erro.message))
    T.ok(rep.erro.traceback ~= nil, "traceback do motor")
    T.ok(rep.ultima ~= nil and rep.ultima.action.type == "play", "última jogada")
  end },

  { "o simulador relata travamento quando ninguém tem jogada", function(T)
    CartasSim.define()
    local Cards = require("duelo/core/cards")
    -- Escolha sem opções e sem "nenhuma": não há jogada válida.
    Cards.define{ id = "sim_trava", kind = "criatura", cost = 0, atk = 1, hp = 1,
      on_play = function(g, c)
        g:set_choice(c.owner, { reason = "trava", options = {}, resolve = function() end })
      end }
    local deck = {}
    for i = 1, 10 do deck[i] = { id = "sim_trava" } end
    local rep = Simulador.run_game{ decks = { deck, deck }, seed = 1, invariants = false }
    T.eq(rep.resultado, "travamento")
    T.ok(tostring(rep.motivo):find("nenhuma jogada", 1, true) ~= nil, tostring(rep.motivo))
    -- Com as invariantes ligadas, a escolha sem opção é pega antes.
    rep = Simulador.run_game{ decks = { deck, deck }, seed = 1 }
    T.eq(rep.resultado, "invariante")
    T.ok(tostring(rep.invariante):find("sem opção", 1, true) ~= nil, tostring(rep.invariante))
  end },

  { "run_many agrega resultados, vitórias e falhas", function(T)
    local agg = Simulador.run_many(opts{ n = 6, seed_base = 100, alternar = true })
    T.eq(agg.n, 6)
    local total = 0
    for _, r in ipairs(Simulador.RESULTS) do total = total + agg.por_resultado[r] end
    T.eq(total, 6)
    T.eq(agg.vitorias_por_lado[1] + agg.vitorias_por_lado[2], agg.por_resultado.vitoria)
    T.eq(agg.vitorias_por_deck[1] + agg.vitorias_por_deck[2], agg.por_resultado.vitoria)
    T.eq(agg.empates, agg.por_resultado.empate)
    T.ok(agg.rodadas.max >= agg.rodadas.media and agg.rodadas.media > 0)
    T.ok(agg.jogadas.max >= agg.jogadas.media and agg.jogadas.media > 0)
    T.eq(#agg.falhas, 0)
    local text = Simulador.format_report(agg)
    T.ok(text:find("6 partidas", 1, true) ~= nil, text)
    T.ok(text:find("falhas: nenhuma", 1, true) ~= nil, text)
    -- Falhas aparecem na lista com a seed.
    local Cards = require("duelo/core/cards")
    Cards.define{ id = "sim_bug2", kind = "criatura", cost = 0, atk = 1, hp = 1, on_play = function() error("x") end }
    local deck = {}
    for i = 1, 10 do deck[i] = { id = "sim_bug2" } end
    local bad = Simulador.run_many{ n = 3, seed_base = 10, decks = { deck, deck } }
    T.eq(#bad.falhas, 3)
    T.eq(bad.falhas[1].seed, 11)
    T.eq(bad.falhas[1].resultado, "erro")
    T.ok(Simulador.format_report(bad):find("seed 11", 1, true) ~= nil)
  end },

  { "200 partidas random contra random terminam sem falha", function(T)
    local agg = Simulador.run_many(opts{ n = 200, seed_base = 1000, alternar = true })
    T.eq(#agg.falhas, 0, Simulador.format_report(agg))
    T.eq(agg.por_resultado.erro + agg.por_resultado.travamento + agg.por_resultado.invariante, 0)
    T.eq(agg.por_resultado.vitoria + agg.por_resultado.empate + agg.por_resultado.limite_rodadas, 200)
    T.ok(agg.por_resultado.vitoria > 0, "alguma partida teve vencedor")
  end },

  { "100 partidas bot contra random terminam sem falha", function(T)
    local agg = Simulador.run_many(opts{ n = 100, seed_base = 5000, players = { "bot", "random" }, alternar = true })
    T.eq(#agg.falhas, 0, Simulador.format_report(agg))
    T.eq(agg.por_resultado.vitoria + agg.por_resultado.empate + agg.por_resultado.limite_rodadas, 100)
  end },

  { "as invariantes pegam um uid duplicado", function(T)
    local g = scenario()
    local total = Invariantes.count_cards(g)
    local p1 = g.players[1]
    p1.hand[#p1.hand + 1] = p1.deck[1]
    broken(T, g, "repetido")
    -- A mesma carta na mão e no descarte do outro jogador também.
    g = scenario()
    g.players[2].discard[1] = g.players[1].hand[1]
    broken(T, g, "repetido")
    -- Carta que sumiu.
    g = scenario()
    table.remove(g.players[1].deck)
    broken(T, g, "caiu", total)
    -- Carta criada do nada.
    g = scenario()
    g.players[2].deck[#g.players[2].deck + 1] = { id = "sim_rato", uid = g:next_uid() }
    broken(T, g, "subiu", total)
  end },

  { "as invariantes pegam dano negativo, dano letal parado e espaço incoerente", function(T)
    local g = scenario()
    g:creature_at(1, 2).damage = -1
    broken(T, g, "dano inválido")
    g = scenario()
    g:creature_at(1, 2).damage = 2.5
    broken(T, g, "dano inválido")
    g = scenario()
    g:creature_at(1, 2).damage = 99
    broken(T, g, "dano letal")
    g = scenario()
    g:creature_at(1, 2).slot = 5
    broken(T, g, "com slot 5")
    g = scenario()
    g:creature_at(1, 2).owner = 2
    broken(T, g, "com owner 2")
    g = scenario()
    g.players[1].field[9] = g:creature_at(1, 2)
    broken(T, g, "fora dos espaços")
    g = scenario()
    g:creature_at(2, 1).link = { uid = 999 }
    broken(T, g, "ligada a uma estrutura fora de campo")
  end },

  { "as invariantes pegam vida, mana e mão fora da regra", function(T)
    local g = scenario()
    g.players[1].life = 2.5
    broken(T, g, "não é inteira")
    g = scenario()
    g.players[2].life = 25
    broken(T, g, "acima do máximo")
    g = scenario()
    g.players[2].life = 0
    broken(T, g, "partida em andamento")
    g = scenario()
    g.players[1].mana = g.players[1].max_mana + 1
    broken(T, g, "mana do jogador 1 fora da faixa")
    g = scenario()
    g.players[1].mana = -1
    broken(T, g, "mana do jogador 1 fora da faixa")
    g = scenario()
    g.players[1].max_mana = Game.MAX_MANA + 1
    g.players[1].mana = 0
    broken(T, g, "mana máxima")
    g = scenario()
    for _ = 1, 20 do table.insert(g.players[1].hand, table.remove(g.players[1].deck)) end
    broken(T, g, "limite")
    g = scenario()
    g.players[1].hand[7] = { id = "sim_rato", uid = g:next_uid() }
    broken(T, g, "com buracos")
  end },

  { "as invariantes pegam escolha, pilha, combate, fogueira e equipamento inconsistentes", function(T)
    local g = scenario()
    g.pending_choice = { player = 3, options = { 1 }, resolve = function() end }
    broken(T, g, "sem jogador válido")
    g = scenario()
    g.pending_choice = { player = 1, options = {}, resolve = function() end }
    broken(T, g, "sem opção possível")
    g = scenario()
    g.combat = { attacker = 1, defender = 2, attackers = { g:creature_at(1, 2) } }
    broken(T, g, "pilha vazia")
    g = scenario()
    T.ok(g:act(1, { type = "attack", attackers = { 2 } }))
    g.combat.attacker, g.combat.defender = 2, 1
    broken(T, g, "quem não tem o token")
    g = scenario()
    g.stack = { { owner = 1, label = "x", resolve = function() end } }
    g.stack_opener = nil
    broken(T, g, "sem quem a abriu")
    g = scenario()
    g.fogueira = { 3, 3 }
    broken(T, g, "acesa de dia")
    g = scenario()
    g.vez = 5
    broken(T, g, "noite sem fogueira")
    g = scenario()
    g.vez = 5
    g.fogueira = { 3, -1 }
    broken(T, g, "fogueira do jogador 2 inválida")
    g = scenario()
    g:creature_at(1, 1).equips.mao.durability = 0
    broken(T, g, "durabilidade 0")
    g = scenario()
    local e = g:creature_at(1, 1).equips.mao
    g:creature_at(1, 1).equips.mao = nil
    g:creature_at(1, 1).equips.peito = e
    broken(T, g, "no espaço peito")
    g = scenario()
    g:to_discard(1, table.remove(g.players[1].deck))
    g.players[1].discard[1].durability = 2
    broken(T, g, "durability = 2")
    g = scenario()
    g.active = 3
    broken(T, g, "active inválido")
    g = scenario()
    g.phase = "over"
    broken(T, g, "over sem vencedor")
  end },
}
