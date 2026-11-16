local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local log
local IDS = { "t_bicho", "t_sobrev", "t_raio", "t_flecha", "t_cura", "t_lento", "t_lento2",
  "t_pergunta", "t_forcado" }

-- Alvo: { p = jogador, slot = espaço } de uma criatura em campo.
local function creature_target(g, p, action)
  local t = action.target
  if t == nil or g:creature_at(t.p, t.slot) == nil then return false, "escolha uma criatura" end
  return true
end

local function define_test_cards()
  log = {}
  Cards.define{ id = "t_bicho", kind = "criatura", cost = 0, atk = 1, hp = 2 }
  Cards.define{ id = "t_sobrev", kind = "criatura", cost = 0, atk = 1, hp = 2, sobrevivente = true }
  Cards.define{ id = "t_raio", kind = "feitico", speed = "instantaneo", cost = 0,
    on_cast = function(g, p) log[#log + 1] = "raio" end }
  Cards.define{ id = "t_flecha", kind = "feitico", speed = "rapido", cost = 0, targets = creature_target,
    on_cast = function(g, p, a) log[#log + 1] = "flecha:" .. a.target.slot end }
  Cards.define{ id = "t_cura", kind = "feitico", speed = "rapido", cost = 0,
    on_cast = function(g, p) log[#log + 1] = "cura:" .. p end }
  Cards.define{ id = "t_lento", kind = "feitico", speed = "lento", cost = 0,
    on_cast = function(g, p) log[#log + 1] = "lento:" .. p end }
  Cards.define{ id = "t_lento2", kind = "feitico", speed = "lento", cost = 0,
    on_cast = function(g, p) log[#log + 1] = "lento2:" .. p end }
  Cards.define{ id = "t_pergunta", kind = "feitico", speed = "rapido", cost = 0,
    on_cast = function(g, p)
      g:set_choice(2, { reason = "teste", options = { "a", "b" },
        resolve = function(gg, idx) log[#log + 1] = "p2 escolheu:" .. idx end })
    end }
  Cards.define{ id = "t_forcado", kind = "equipamento", slot = "mao", cost = 0, durability = 2,
    activation = { speed = "rapido", once_per_period = true },
    activate = function(g, p) log[#log + 1] = "forcado" end }
end

local function clear_test_cards()
  for _, id in ipairs(IDS) do Cards.remove(id) end
end

local function new_game(hand1, hand2)
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "t_bicho" }; d2[i] = { id = "t_bicho" } end
  for _, id in ipairs(hand1 or {}) do d1[#d1 + 1] = { id = id } end
  for _, id in ipairs(hand2 or {}) do d2[#d2 + 1] = { id = id } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function cast(g, p, id, fields)
  local a = { type = "play" }
  for i, card in ipairs(g.players[p].hand) do if card.id == id then a.hand_index = i; break end end
  for k, v in pairs(fields or {}) do a[k] = v end
  return g:act(p, a)
end

return {
  { "Instantâneo resolve na hora, não gasta a vez e vai para o descarte", function(T)
    local g = new_game({ "t_raio" })
    T.ok(cast(g, 1, "t_raio"))
    T.eq(log[1], "raio")
    T.eq(g.active, 1)
    T.eq(g:stack_open(), false)
    local d = g.players[1].discard
    T.eq(d[#d].id, "t_raio")
    clear_test_cards()
  end },

  { "Rápidos empilham, o outro responde e a pilha resolve do último para o primeiro", function(T)
    local g = new_game({ "t_cura", "t_lento" }, { "t_cura" })
    local vez = g.vez
    T.ok(cast(g, 1, "t_lento"))
    T.ok(cast(g, 1, "t_cura"), "depois do Lento, o mesmo jogador empilha Rápidos")
    T.eq(g.active, 1)
    T.ok(g:act(1, { type = "pass" }))          -- pronto
    T.eq(g.active, 2)
    T.ok(cast(g, 2, "t_cura"))                  -- resposta
    T.ok(g:act(2, { type = "pass" }))          -- pronto
    T.eq(g.active, 1)
    T.eq(g.vez, vez, "as respostas não contam para o período")
    T.ok(g:act(1, { type = "pass" }))          -- não pôs nada: resolve
    T.eq(log[1], "cura:2")
    T.eq(log[2], "cura:1")
    T.eq(log[3], "lento:1")
    T.eq(g.active, 2, "a vez é de quem não abriu a pilha")
    T.eq(g.vez, vez + 1, "a vez de quem abriu conta uma vez só")
    clear_test_cards()
  end },

  { "Lento só abre a pilha", function(T)
    local g = new_game({ "t_cura" }, { "t_lento" })
    cast(g, 1, "t_cura")
    g:act(1, { type = "pass" })
    local ok = cast(g, 2, "t_lento")
    T.eq(ok, false, "Lento como resposta")
    g = new_game({ "t_lento", "t_lento2" })
    cast(g, 1, "t_lento")
    ok = cast(g, 1, "t_lento2")
    T.eq(ok, false, "segundo Lento na mesma pilha")
    clear_test_cards()
  end },

  { "com a pilha aberta não dá para jogar criatura", function(T)
    local g = new_game({ "t_cura" }, {})
    cast(g, 1, "t_cura")
    g:act(1, { type = "pass" })
    local ok = cast(g, 2, "t_bicho", { slot = 1 })
    T.eq(ok, false)
    clear_test_cards()
  end },

  { "passar com a pilha aberta não encerra a rodada", function(T)
    local g = new_game({ "t_cura" })
    local round = g.round
    cast(g, 1, "t_cura")
    g:act(1, { type = "pass" })
    g:act(2, { type = "pass" })
    T.eq(g.round, round)
    T.eq(g.passes, 0)
    clear_test_cards()
  end },

  { "alvo que sai de campo antes de resolver: o feitiço perde o efeito", function(T)
    local g = new_game({ "t_flecha" }, { "t_bicho" })
    g:act(1, { type = "pass" })
    cast(g, 2, "t_bicho", { slot = 3 })
    T.ok(cast(g, 1, "t_flecha", { target = { p = 2, slot = 3 } }))
    g.players[2].field[3] = nil
    g:act(1, { type = "pass" })
    g:act(2, { type = "pass" })
    T.eq(#log, 0)
    local d = g.players[1].discard
    T.eq(d[#d].id, "t_flecha", "vai para o descarte mesmo sem efeito")
    clear_test_cards()
  end },

  { "feitiço com alvo inválido é recusado na jogada", function(T)
    local g = new_game({ "t_flecha" })
    local ok = cast(g, 1, "t_flecha", { target = { p = 2, slot = 5 } })
    T.eq(ok, false)
    clear_test_cards()
  end },

  { "escolha durante a resolução: o jogador escolhe fora da vez e a pilha continua", function(T)
    local g = new_game({ "t_lento", "t_pergunta" })
    cast(g, 1, "t_lento")
    cast(g, 1, "t_pergunta")
    g:act(1, { type = "pass" })
    g:act(2, { type = "pass" })                 -- resolve: a pergunta abre escolha do jogador 2
    T.ok(g.pending_choice ~= nil)
    T.eq(#log, 0)
    local ok = g:act(1, { type = "choose", index = 1 })
    T.eq(ok, false, "a escolha é do jogador 2")
    T.ok(g:act(2, { type = "choose", index = 2 }))
    T.eq(log[1], "p2 escolheu:2")
    T.eq(log[2], "lento:1")
    T.eq(g:stack_open(), false)
    T.eq(g.active, 2)
    clear_test_cards()
  end },

  { "efeito Rápido de equipamento: 1 vez por período e gasta durabilidade", function(T)
    local g = new_game({ "t_sobrev", "t_forcado" })
    cast(g, 1, "t_sobrev", { slot = 1 }); g:act(2, { type = "pass" })
    cast(g, 1, "t_forcado", { target = 1 }); g:act(2, { type = "pass" })
    T.ok(g:act(1, { type = "activate", creature = 1, equip = "mao" }))
    T.eq(g:creature_at(1, 1).equips.mao.durability, 1)
    local ok = g:act(1, { type = "activate", creature = 1, equip = "mao" })
    T.eq(ok, false, "segunda vez no mesmo período")
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(log[1], "forcado")
    clear_test_cards()
  end },
}
