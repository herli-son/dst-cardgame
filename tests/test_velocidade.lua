local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")

local log

local function define_test_cards()
  log = {}
  Cards.define{ id = "v_comum", kind = "criatura", cost = 0, atk = 2, hp = 2 }
  Cards.define{ id = "v_rapida", kind = "criatura", cost = 0, atk = 2, hp = 2, speed = 2 }
  Cards.define{ id = "v_relampago", kind = "criatura", cost = 0, atk = 1, hp = 5, speed = 3 }
  Cards.define{ id = "v_parada", kind = "criatura", cost = 0, atk = 5, hp = 5, speed = 0 }
  Cards.define{ id = "v_tentaculo", kind = "criatura", cost = 0, atk = 1, hp = 6, block_speed = 3, no_attack = true }
  Cards.define{ id = "v_golpeia", kind = "criatura", cost = 0, atk = 1, hp = 5,
    on_strike = function(g, c, target)
      log[#log + 1] = "golpe:" .. (target.player and ("jogador" .. target.player) or target.def.id)
    end }
  Cards.define{ id = "v_sobrev", kind = "criatura", cost = 0, atk = 1, hp = 5, sobrevivente = true }
  Cards.define{ id = "v_pa", kind = "equipamento", slot = "mao", cost = 0,
    on_strike = function(g, c, target, e) log[#log + 1] = "pa" end }
end

local function new_game()
  define_test_cards()
  local d1, d2 = {}, {}
  for i = 1, 20 do d1[i] = { id = "v_comum" }; d2[i] = { id = "v_comum" } end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = function(n) return n end }
  g:start()
  return g
end

local function put(g, p, id, slot)
  return g:place_creature(p, { id = id, uid = g:next_uid() }, slot)
end

-- Ataque do jogador 1 com bloqueios do jogador 2, resolvido até o fim.
local function fight(g, attackers, blocks)
  g:act(1, { type = "attack", attackers = attackers })
  g:act(1, { type = "pass" })
  if blocks then g:act(2, { type = "block", blocks = blocks }) end
  g:act(2, { type = "pass" })
  if blocks and #blocks > 0 then g:act(1, { type = "pass" }) end
end

return {
  { "velocidade 2 golpeia antes: a comum morre sem golpear", function(T)
    local g = new_game()
    local rapida = put(g, 1, "v_rapida", 1)
    put(g, 2, "v_comum", 1)
    fight(g, { 1 }, { { attacker = 1, blocker = 1 } })
    T.eq(g:creature_at(2, 1), nil)
    T.eq(rapida.damage, 0, "a comum morreu antes de golpear")
  end },

  { "mesma velocidade golpeia ao mesmo tempo", function(T)
    local g = new_game()
    put(g, 1, "v_comum", 1); put(g, 2, "v_comum", 1)
    fight(g, { 1 }, { { attacker = 1, blocker = 1 } })
    T.eq(g:creature_at(1, 1), nil)
    T.eq(g:creature_at(2, 1), nil)
  end },

  { "velocidade 0 não golpeia, nem o jogador", function(T)
    local g = new_game()
    put(g, 1, "v_parada", 1)
    local life = g.players[2].life
    fight(g, { 1 })
    T.eq(g.players[2].life, life)
  end },

  { "velocidade 3 golpeia duas vezes uma criatura", function(T)
    local g = new_game()
    put(g, 1, "v_relampago", 1)
    local muro = put(g, 2, "v_parada", 1)
    fight(g, { 1 }, { { attacker = 1, blocker = 1 } })
    T.eq(muro.damage, 2)
  end },

  { "velocidade 3 golpeia o jogador uma vez só", function(T)
    local g = new_game()
    put(g, 1, "v_relampago", 1)
    local life = g.players[2].life
    fight(g, { 1 })
    T.eq(g.players[2].life, life - 1)
  end },

  { "velocidade de bloqueio vale só bloqueando", function(T)
    local g = new_game()
    local atacante = put(g, 1, "v_sobrev", 1)
    local t = put(g, 2, "v_tentaculo", 1)
    fight(g, { 1 }, { { attacker = 1, blocker = 1 } })
    T.eq(atacante.damage, 2, "o tentáculo golpeou duas vezes")
    T.eq(t.damage, 1)
    T.eq(g:speed(t, "attack"), 1)
    T.eq(g:speed(t, "block"), 3)
  end },

  { "velocidade forçada substitui a da carta", function(T)
    local g = new_game()
    local r = put(g, 1, "v_relampago", 1)
    g:add_speed_mod(r, { set = 0, until_round = g.round })
    T.eq(g:speed(r, "attack"), 0)
    local life = g.players[2].life
    fight(g, { 1 })
    T.eq(g.players[2].life, life)
  end },

  { "Golpear dispara a cada golpe, inclusive no jogador", function(T)
    local g = new_game()
    Cards.define{ id = "v_golpeia3", kind = "criatura", cost = 0, atk = 1, hp = 5, speed = 3,
      on_strike = function(gg, c, target) log[#log + 1] = "g3" end }
    put(g, 1, "v_golpeia3", 1)
    put(g, 2, "v_parada", 1)
    fight(g, { 1 }, { { attacker = 1, blocker = 1 } })
    T.eq(#log, 2, "dois golpes, dois disparos")
    g = new_game()
    put(g, 1, "v_golpeia", 1)
    fight(g, { 1 })
    T.eq(log[1], "golpe:jogador2")
  end },

  { "Golpear não dispara sem dano", function(T)
    local g = new_game()
    Cards.define{ id = "v_zero", kind = "criatura", cost = 0, atk = 0, hp = 5,
      on_strike = function() log[#log + 1] = "nao" end }
    put(g, 1, "v_zero", 1)
    fight(g, { 1 })
    T.eq(#log, 0)
  end },

  { "Golpear dos equipamentos dispara com a criatura", function(T)
    local g = new_game()
    local c = put(g, 1, "v_sobrev", 1)
    g:equip(c, { id = "v_pa", uid = g:next_uid() })
    fight(g, { 1 })
    T.eq(log[1], "pa")
  end },

  { "criatura morta na fase rápida não golpeia na normal", function(T)
    local g = new_game()
    put(g, 1, "v_rapida", 1); put(g, 1, "v_comum", 2)
    put(g, 2, "v_comum", 1); put(g, 2, "v_comum", 2)
    fight(g, { 1, 2 }, { { attacker = 1, blocker = 1 }, { attacker = 2, blocker = 2 } })
    T.eq(g:creature_at(2, 1), nil)
    T.eq(g:creature_at(1, 1).damage, 0)
    T.eq(g:creature_at(1, 2), nil, "a troca comum continua simultânea")
    T.eq(g:creature_at(2, 2), nil)
  end },

  { "vitória na fase rápida encerra o combate", function(T)
    local g = new_game()
    put(g, 1, "v_rapida", 1); put(g, 2, "v_comum", 1); put(g, 1, "v_comum", 2)
    g.players[2].life = 2
    fight(g, { 1, 2 }, { { attacker = 2, blocker = 1 } })
    T.eq(g.winner, 1)
    T.eq(g:creature_at(1, 2).damage, 0, "o par seguinte não aconteceu")
  end },

  { "bloqueador de velocidade 2 golpeia antes do atacante de velocidade 1", function(T)
    local g = new_game()
    put(g, 1, "v_comum", 1)
    local d = put(g, 2, "v_rapida", 1)
    fight(g, { 1 }, { { attacker = 1, blocker = 1 } })
    T.eq(g:creature_at(1, 1), nil)
    T.eq(d.damage, 0)
  end },

  { "atacante de velocidade 0 bloqueado leva o golpe sem revidar", function(T)
    local g = new_game()
    local a = put(g, 1, "v_parada", 1)
    local d = put(g, 2, "v_comum", 1)
    fight(g, { 1 }, { { attacker = 1, blocker = 1 } })
    T.eq(a.damage, 2)
    T.eq(d.damage, 0)
  end },

  { "velocidade que cai entre as fases não dá um segundo golpe", function(T)
    local g = new_game()
    Cards.define{ id = "v_abelha", kind = "criatura", cost = 0, atk = 1, hp = 1, speed = 3,
      on_strike = function(gg, c) gg:add_speed_mod(c, { set = 1, until_round = gg.round }) end }
    put(g, 1, "v_abelha", 1)
    local muro = put(g, 2, "v_parada", 1)
    fight(g, { 1 }, { { attacker = 1, blocker = 1 } })
    T.eq(muro.damage, 1)
  end },

  { "velocidade que sobe entre as fases não tira o golpe", function(T)
    local g = new_game()
    Cards.define{ id = "v_acelera", kind = "criatura", cost = 0, atk = 1, hp = 5 }
    local a = put(g, 1, "v_acelera", 1)
    -- As fases são do par: quem acelera a criatura é o próprio bloqueador dela.
    Cards.define{ id = "v_gatilho", kind = "criatura", cost = 0, atk = 1, hp = 5, speed = 2,
      on_strike = function(gg) gg:add_speed_mod(a, { set = 2, until_round = gg.round }) end }
    local d = put(g, 2, "v_gatilho", 1)
    fight(g, { 1 }, { { attacker = 1, blocker = 1 } })
    T.eq(a.damage, 1)
    T.eq(d.damage, 1, "a criatura acelerada golpeou uma vez, na fase normal")
  end },

  { "escolha aberta na fase rápida: o morto não revida na normal", function(T)
    local g = new_game()
    Cards.define{ id = "v_pa_viva", kind = "criatura", cost = 0, atk = 2, hp = 2, speed = 2,
      on_strike = function(gg, c)
        gg:set_choice(c.owner, { reason = "comprar", options = { "sim" }, allow_none = true, resolve = function() end })
      end }
    local a = put(g, 1, "v_pa_viva", 1)
    put(g, 2, "v_comum", 1)
    fight(g, { 1 }, { { attacker = 1, blocker = 1 } })
    T.eq(a.damage, 0, "o bloqueador morto não golpeou")
    g:act(1, { type = "choose", index = 0 })
    T.eq(g:creature_at(2, 1), nil)
  end },

  { "Golpear dos dois lados do mesmo golpe e de quem morre nele", function(T)
    local g = new_game()
    Cards.define{ id = "v_g1", kind = "criatura", cost = 0, atk = 2, hp = 2,
      on_strike = function() log[#log + 1] = "a" end }
    Cards.define{ id = "v_g2", kind = "criatura", cost = 0, atk = 2, hp = 2,
      on_strike = function() log[#log + 1] = "d" end }
    put(g, 1, "v_g1", 1); put(g, 2, "v_g2", 1)
    fight(g, { 1 }, { { attacker = 1, blocker = 1 } })
    T.eq(#log, 2)
    T.eq(g:creature_at(1, 1), nil); T.eq(g:creature_at(2, 1), nil)
  end },

  { "Golpear não dispara quando o dano aplicado é zero", function(T)
    local g = new_game()
    Cards.define{ id = "v_g3", kind = "criatura", cost = 0, atk = 2, hp = 5,
      on_strike = function() log[#log + 1] = "x" end }
    put(g, 1, "v_g3", 1)
    g.damage_player = function() return 0 end
    fight(g, { 1 })
    T.eq(#log, 0)
  end },

  { "cada efeito de Golpear conta separadamente: o primeiro que decide encerra", function(T)
    local g = new_game()
    Cards.define{ id = "v_fim", kind = "criatura", cost = 0, atk = 1, hp = 5,
      on_strike = function(gg) log[#log + 1] = "fim"; gg:damage_player(2, 99, "teste") end }
    Cards.define{ id = "v_outro", kind = "criatura", cost = 0, atk = 1, hp = 5,
      on_strike = function(gg) log[#log + 1] = "outro"; gg:damage_player(1, 99, "teste") end }
    put(g, 1, "v_fim", 1); put(g, 1, "v_outro", 2)
    fight(g, { 1, 2 })
    T.eq(#log, 1)
    T.eq(g.winner, 1)
  end },

  { "um efeito de Golpear que deixa os dois jogadores sem vida é empate", function(T)
    local g = new_game()
    Cards.define{ id = "v_ambos", kind = "criatura", cost = 0, atk = 1, hp = 5,
      on_strike = function(gg) gg:damage_player(2, 99, "teste"); gg:damage_player(1, 99, "teste") end }
    put(g, 1, "v_ambos", 1)
    fight(g, { 1 })
    T.eq(g.winner, 0)
  end },

  { "feitiço que deixa os dois jogadores sem vida é empate", function(T)
    local g = new_game()
    Cards.define{ id = "v_explosao", kind = "feitico", speed = "instantaneo", cost = 0,
      on_cast = function(gg) gg:damage_player(1, 99, "teste"); gg:damage_player(2, 99, "teste") end }
    local pl = g.players[1]
    pl.hand[#pl.hand + 1] = { id = "v_explosao", uid = g:next_uid() }
    g:act(1, { type = "play", hand_index = #pl.hand })
    T.eq(g.winner, 0)
  end },

  { "feitiços diferentes contam separadamente", function(T)
    local g = new_game()
    Cards.define{ id = "v_mata2", kind = "feitico", speed = "rapido", cost = 0,
      on_cast = function(gg) gg:damage_player(2, 99, "teste") end }
    Cards.define{ id = "v_mata1", kind = "feitico", speed = "rapido", cost = 0,
      on_cast = function(gg) gg:damage_player(1, 99, "teste") end }
    local pl = g.players[1]
    pl.hand[#pl.hand + 1] = { id = "v_mata1", uid = g:next_uid() }
    pl.hand[#pl.hand + 1] = { id = "v_mata2", uid = g:next_uid() }
    g:act(1, { type = "play", hand_index = #pl.hand - 1 })   -- v_mata1, embaixo
    g:act(1, { type = "play", hand_index = #pl.hand })       -- v_mata2, em cima
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g.winner, 1, "o de cima resolve primeiro e decide")
    T.ok(g.players[1].life > 0)
  end },

  { "modificador de velocidade expira com a rodada", function(T)
    local g = new_game()
    local c = put(g, 1, "v_comum", 1)
    g:add_speed_mod(c, { set = 0, until_round = g.round })
    g:add_speed_mod(c, { delta = 1 })
    T.eq(g:speed(c, "attack"), 0)
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g:speed(c, "attack"), 2, "o fixo expirou; o relativo continua")
  end },

  { "erro num efeito de Golpear não deixa efeitos abertos", function(T)
    local g = new_game()
    Cards.define{ id = "v_bug", kind = "criatura", cost = 0, atk = 1, hp = 5,
      on_strike = function() error("falha") end }
    local c = put(g, 1, "v_bug", 1)
    -- Direto na fase, sem passar pela entrada pública (que também zera a contagem).
    T.eq(pcall(g.strike_phase, g, { { c, { player = 2 } } }), false)
    T.eq(g.effect_depth, 0)
    g:damage_player(2, 99, "teste")
    T.eq(g.winner, 1)
  end },

  { "morte que espera uma escolha guarda quem matou e o motivo", function(T)
    local g = new_game()
    Cards.define{ id = "v_escolhe", kind = "criatura", cost = 0, atk = 2, hp = 2, speed = 2,
      on_strike = function(gg, c)
        gg:set_choice(c.owner, { reason = "x", options = { "a" }, resolve = function() end })
      end }
    local a = put(g, 1, "v_escolhe", 1)
    put(g, 2, "v_comum", 1)
    fight(g, { 1 }, { { attacker = 1, blocker = 1 } })
    g:act(1, { type = "choose", index = 1 })
    local death
    for _, ev in ipairs(g.events) do if ev.t == "death" then death = ev end end
    T.ok(death ~= nil)
    T.eq(death.reason, "combate")
    T.eq(death.killer_uid, a.uid)
  end },

  { "escolha aberta na fase rápida: o bloqueador letal não é golpeado de novo", function(T)
    local g = new_game()
    Cards.define{ id = "v_tres", kind = "criatura", cost = 0, atk = 2, hp = 5, speed = 3,
      on_strike = function(gg, c)
        log[#log + 1] = "g"
        gg:set_choice(c.owner, { reason = "x", options = { "a" }, resolve = function() end })
      end }
    put(g, 1, "v_tres", 1)
    local d = put(g, 2, "v_comum", 1)
    fight(g, { 1 }, { { attacker = 1, blocker = 1 } })
    T.eq(#log, 1)
    T.eq(d.damage, 2)
  end },

  { "quem matou deixa de valer se o dano mudar antes da morte", function(T)
    local g = new_game()
    local a = put(g, 1, "v_comum", 1)
    local x = put(g, 2, "v_comum", 1)
    g:set_choice(1, { reason = "x", options = { "a" }, resolve = function() end })
    x.damage = 2
    g:check_lethal({ [x] = a }, "combate")
    x.damage = 0
    x.damage = 3
    g:act(1, { type = "choose", index = 1 })
    local death
    for _, ev in ipairs(g.events) do if ev.t == "death" then death = ev end end
    T.eq(death.reason, "dano")
    T.eq(death.killer_uid, nil)
  end },

  { "morte causada por um feitiço é um efeito à parte: o feitiço decide primeiro", function(T)
    local g = new_game()
    Cards.define{ id = "v_vinga", kind = "criatura", cost = 0, atk = 0, hp = 1,
      on_death = function(gg) gg:damage_player(1, 99, "teste") end }
    Cards.define{ id = "v_fulmina", kind = "feitico", speed = "instantaneo", cost = 0,
      on_cast = function(gg)
        gg:damage_player(2, 99, "teste")
        gg:kill(gg:creature_at(2, 1), "teste")
      end }
    put(g, 2, "v_vinga", 1)
    local pl = g.players[1]
    pl.hand[#pl.hand + 1] = { id = "v_fulmina", uid = g:next_uid() }
    g:act(1, { type = "play", hand_index = #pl.hand })
    T.eq(g.winner, 1, "o efeito de morte não acontece")
    T.ok(g.players[1].life > 0)
  end },

  { "morte causada por um feitiço decide sozinha se vier antes", function(T)
    local g = new_game()
    Cards.define{ id = "v_vinga2", kind = "criatura", cost = 0, atk = 0, hp = 1,
      on_death = function(gg) gg:damage_player(1, 99, "teste") end }
    Cards.define{ id = "v_fulmina2", kind = "feitico", speed = "instantaneo", cost = 0,
      on_cast = function(gg)
        gg:kill(gg:creature_at(2, 1), "teste")
        gg:damage_player(2, 99, "teste")
      end }
    put(g, 2, "v_vinga2", 1)
    local pl = g.players[1]
    pl.hand[#pl.hand + 1] = { id = "v_fulmina2", uid = g:next_uid() }
    g:act(1, { type = "play", hand_index = #pl.hand })
    T.eq(g.winner, 2)
  end },

  { "efeito ao morrer que deixa os dois jogadores sem vida é empate", function(T)
    local g = new_game()
    Cards.define{ id = "v_bomba", kind = "criatura", cost = 0, atk = 0, hp = 1,
      on_death = function(gg) gg:damage_player(2, 99, "teste"); gg:damage_player(1, 99, "teste") end }
    local c = put(g, 1, "v_bomba", 1)
    g:kill(c, "teste")
    T.eq(g.winner, 0)
  end },

  { "resolução de escolha que deixa os dois jogadores sem vida é empate", function(T)
    local g = new_game()
    g:set_choice(1, { reason = "x", options = { "a" }, resolve = function(gg)
      gg:damage_player(1, 99, "teste"); gg:damage_player(2, 99, "teste")
    end })
    g:act(1, { type = "choose", index = 1 })
    T.eq(g.winner, 0)
  end },

  { "Golpear da criatura e do equipamento contam separadamente", function(T)
    local g = new_game()
    Cards.define{ id = "v_sob", kind = "criatura", cost = 0, atk = 1, hp = 5, sobrevivente = true,
      on_strike = function(gg) gg:damage_player(2, 99, "teste") end }
    Cards.define{ id = "v_arma", kind = "equipamento", slot = "mao", cost = 0,
      on_strike = function(gg) gg:damage_player(1, 99, "teste") end }
    local c = put(g, 1, "v_sob", 1)
    g:equip(c, { id = "v_arma", uid = g:next_uid() })
    fight(g, { 1 })
    T.eq(g.winner, 1)
  end },

  { "efeito ativado que deixa os dois jogadores sem vida é empate", function(T)
    local g = new_game()
    Cards.define{ id = "v_bomba_est", kind = "estrutura", cost = 0, activation = { speed = "instantaneo" },
      activate = function(gg) gg:damage_player(1, 99, "teste"); gg:damage_player(2, 99, "teste") end }
    g:put_structure(1, { id = "v_bomba_est", uid = g:next_uid() }, 1)
    g:act(1, { type = "activate", structure = 1 })
    T.eq(g.winner, 0)
  end },

  { "feitiço de cima que fere os dois é empate, mesmo ferindo primeiro quem jogou", function(T)
    local g = new_game()
    Cards.define{ id = "v_auto", kind = "feitico", speed = "rapido", cost = 0,
      on_cast = function(gg) gg:damage_player(1, 99, "teste"); gg:damage_player(2, 99, "teste") end }
    local pl = g.players[1]
    pl.hand[#pl.hand + 1] = { id = "v_auto", uid = g:next_uid() }
    g:act(1, { type = "play", hand_index = #pl.hand })
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    T.eq(g.winner, 0)
  end },

  { "efeito que dá erro encerra a partida com estado de erro, mesmo depois de zerar um jogador", function(T)
    local g = new_game()
    Cards.define{ id = "v_quebra", kind = "estrutura", cost = 0, activation = { speed = "instantaneo" },
      activate = function(gg) gg:damage_player(2, 99, "teste"); error("falha") end }
    g:put_structure(1, { id = "v_quebra", uid = g:next_uid() }, 1)
    T.eq(g:act(1, { type = "activate", structure = 1 }), false)
    T.eq(g.phase, "error")
    T.eq(g.winner, nil, "erro de carta: sem vencedor")
    T.eq(g.error.context.id, "v_quebra")
  end },

  { "efeito aninhado que decide a partida para o efeito de fora", function(T)
    local g = new_game()
    Cards.define{ id = "v_fim3", kind = "criatura", cost = 0, atk = 0, hp = 1,
      on_death = function(gg) gg:damage_player(2, 99, "teste") end }
    Cards.define{ id = "v_depois", kind = "feitico", speed = "instantaneo", cost = 0,
      on_cast = function(gg)
        gg:kill(gg:creature_at(2, 1), "teste")
        gg:damage_player(1, 99, "teste")
        log[#log + 1] = "continuou"
      end }
    put(g, 2, "v_fim3", 1)
    local pl = g.players[1]
    pl.hand[#pl.hand + 1] = { id = "v_depois", uid = g:next_uid() }
    g:act(1, { type = "play", hand_index = #pl.hand })
    T.eq(g.winner, 1)
    T.eq(#log, 0, "o resto do feitiço não aconteceu")
    T.ok(g.players[1].life > 0)
    T.eq(g.events[#g.events].t, "game_over")
  end },

  { "erro em efeito aninhado traz um traceback só", function(T)
    local g = new_game()
    local function CARTA_COM_BUG() error("falha") end
    Cards.define{ id = "v_err", kind = "criatura", cost = 0, atk = 0, hp = 1,
      on_death = function() CARTA_COM_BUG() end }
    Cards.define{ id = "v_mata", kind = "feitico", speed = "instantaneo", cost = 0,
      on_cast = function(gg) gg:kill(gg:creature_at(2, 1), "teste") end }
    put(g, 2, "v_err", 1)
    local pl = g.players[1]
    pl.hand[#pl.hand + 1] = { id = "v_mata", uid = g:next_uid() }
    T.eq(g:act(1, { type = "play", hand_index = #pl.hand }), false)
    T.eq(g.error.message:find("stack traceback", 1, true), nil, "mensagem limpa")
    T.ok(g.error.traceback:find("CARTA_COM_BUG", 1, true) ~= nil, "o traceback chega à carta")
    local _, count = g.error.traceback:gsub("stack traceback", "")
    T.eq(count, 1)
    T.eq(g.error.context.id, "v_err")
  end },

  { "estrutura quebrada por feitiço vai ao descarte mesmo se o efeito ao quebrar decidir", function(T)
    local g = new_game()
    Cards.define{ id = "v_relogio", kind = "estrutura", cost = 0,
      on_break = function(gg) gg:damage_player(1, 99, "teste") end }
    Cards.define{ id = "v_marreta", kind = "feitico", speed = "instantaneo", cost = 0,
      on_cast = function(gg) gg:break_structure(2, 1, "teste") end }
    g:put_structure(2, { id = "v_relogio", uid = g:next_uid() }, 1)
    local pl = g.players[1]
    pl.hand[#pl.hand + 1] = { id = "v_marreta", uid = g:next_uid() }
    g:act(1, { type = "play", hand_index = #pl.hand })
    T.eq(g.winner, 2)
    local d = g.players[2].discard
    T.eq(d[#d].id, "v_relogio")
  end },

  { "substituição: o ao quebrar da antiga não dispara", function(T)
    local g = new_game()
    Cards.define{ id = "v_relogio2", kind = "estrutura", cost = 0,
      on_break = function(gg) gg:damage_player(1, 99, "teste") end }
    Cards.define{ id = "v_nova", kind = "estrutura", cost = 0 }
    Cards.define{ id = "v_obra", kind = "feitico", speed = "instantaneo", cost = 0,
      on_cast = function(gg) gg:put_structure(1, { id = "v_nova", uid = gg:next_uid() }, 1) end }
    g:put_structure(1, { id = "v_relogio2", uid = g:next_uid() }, 1)
    g:put_structure(1, { id = "v_relogio2", uid = g:next_uid() }, 2)
    local pl = g.players[1]
    pl.hand[#pl.hand + 1] = { id = "v_obra", uid = g:next_uid() }
    g:act(1, { type = "play", hand_index = #pl.hand })
    T.eq(g.winner, nil)
    T.eq(g:structure_at(1, 1).def.id, "v_nova")
  end },

  { "erro na resolução de uma escolha traz um traceback só", function(T)
    local g = new_game()
    local function ESCOLHA_COM_BUG() error("direto") end
    g:set_choice(1, { reason = "x", options = { "a" }, resolve = function() ESCOLHA_COM_BUG() end })
    T.eq(g:act(1, { type = "choose", index = 1 }), false)
    T.eq(g.error.message:find("stack traceback", 1, true), nil)
    T.ok(g.error.traceback:find("ESCOLHA_COM_BUG", 1, true) ~= nil)
  end },

  { "o efeito ao quebrar vê os marcadores guardados da estrutura", function(T)
    local g = new_game()
    local seen
    Cards.define{ id = "v_usada", kind = "estrutura", cost = 0, activation = { speed = "instantaneo", once_per_round = true },
      activate = function() end,
      on_break = function(gg, st) seen = st.marks.used_round end }
    g:put_structure(1, { id = "v_usada", uid = g:next_uid() }, 1)
    g:act(1, { type = "activate", structure = 1 })
    g:break_structure(1, 1, "teste")
    T.eq(seen, g.round)
  end },

  { "erro em tabela guarda o traceback da carta", function(T)
    local g = new_game()
    local function CARTA_TABELA() error({ message = "codigo" }) end
    Cards.define{ id = "v_tab", kind = "criatura", cost = 0, atk = 0, hp = 1,
      on_death = function() CARTA_TABELA() end }
    local c = put(g, 1, "v_tab", 1)
    c.damage = 5
    g:act(1, { type = "pass" })
    T.eq(g.phase, "error")
    T.eq(g.error.message, "codigo")
    T.ok(g.error.traceback:find("CARTA_TABELA", 1, true) ~= nil)
  end },

  { "erro na velocidade de uma carta aponta a carta", function(T)
    local g = new_game()
    Cards.define{ id = "v_vel_bug", kind = "criatura", cost = 0, atk = 1, hp = 5,
      speed_fn = function() error("falha") end }
    put(g, 1, "v_vel_bug", 1)
    g:act(1, { type = "attack", attackers = { 1 } }); g:act(1, { type = "pass" })
    g:act(2, { type = "pass" })
    T.eq(g.phase, "error")
    T.eq(g.error.context.id, "v_vel_bug")
  end },

  { "continuação que deixa os dois jogadores sem vida é empate", function(T)
    local g = new_game()
    g:set_choice(1, { reason = "x", options = { "a" }, resolve = function() end })
    g:after_choices(function(gg) gg:damage_player(2, 99, "teste"); gg:damage_player(1, 99, "teste") end)
    g:act(1, { type = "choose", index = 1 })
    T.eq(g.winner, 0)
  end },

  { "escolha com preparo não abre quando um jogador está sem vida", function(T)
    local g = new_game()
    local prepared = false
    g.players[2].life = 0
    g:set_choice(1, { reason = "x", options = nil,
      prepare = function(_, spec) prepared = true; spec.options = { "a" } end,
      resolve = function() end })
    T.eq(prepared, false)
    T.eq(g.pending_choice, nil)
  end },
}
