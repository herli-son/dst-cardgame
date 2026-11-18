-- Testes do bot (#63): Game:can_act sem efeitos colaterais, gerador de jogadas
-- válidas e partidas bot contra bot.
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")
local Jogadas = require("duelo/bot/jogadas")
local Bot = require("duelo/bot/bot")

local function define()
  Cards.define{ id = "bot_rato", kind = "criatura", cost = 1, atk = 1, hp = 1 }
  Cards.define{ id = "bot_lobo", kind = "criatura", cost = 2, atk = 3, hp = 2 }
  Cards.define{ id = "bot_urso", kind = "criatura", cost = 4, atk = 4, hp = 5 }
  Cards.define{ id = "bot_coelho", kind = "criatura", cost = 1, atk = 2, hp = 1, kw = { fragil = true } }
  Cards.define{ id = "bot_cao", kind = "criatura", cost = 2, atk = 2, hp = 2, kw = { agressivo = true } }
  Cards.define{ id = "bot_raio", kind = "feitico", speed = "rapido", cost = 1,
    targets = function(g, p, action, objects)
      local o = objects[1]
      if o == nil or o.uid == nil or o.def.kind ~= "criatura" then return false, "escolha uma criatura" end
      return true
    end,
    on_cast = function(g, p, action, card, objects) g:damage_creature(objects[1], 2, nil, "raio") end }
  Cards.define{ id = "bot_tocha", kind = "estrutura", cost = 2,
    activation = { speed = "instantaneo", once_per_round = true },
    activate = function(g, p) g:damage_player(g.other(p), 1, "tocha") end }
  -- Criatura que abre uma escolha ao entrar: duas opções ou nenhuma.
  Cards.define{ id = "bot_duvida", kind = "criatura", cost = 0, atk = 1, hp = 1,
    on_play = function(g, c)
      g:set_choice(c.owner, { reason = "duvida", options = { "a", "b" }, allow_none = true,
        resolve = function() end })
    end }
end

local IDS = { "bot_rato", "bot_lobo", "bot_urso", "bot_coelho", "bot_cao", "bot_raio", "bot_tocha" }

-- Gerador determinístico (Park e Miller), só com inteiros exatos em doubles.
local function make_rng(seed)
  local s = seed % 2147483647
  if s == 0 then s = 1 end
  return function(n)
    s = (s * 48271) % 2147483647
    return (s % n) + 1
  end
end

-- Monta a mesma partida sempre que recebe a mesma semente.
local function setup(seed)
  define()
  local d1, d2 = {}, {}
  for i = 1, 30 do
    d1[i] = { id = IDS[(i % #IDS) + 1] }
    d2[i] = { id = IDS[((i + 3) % #IDS) + 1] }
  end
  local g = Game.new{ decks = { d1, d2 }, first = 1, mulligan = false, rng = make_rng(seed) }
  g:start()
  local bots = { Bot.new{ rng = make_rng(seed + 1) }, Bot.new{ rng = make_rng(seed + 2) } }
  return g, bots
end

local function whose_turn(g)
  return g.pending_choice and g.pending_choice.player or g.active
end

-- Joga uma partida bot contra bot até o fim ou até o limite de rodadas.
-- on_step(g, p, jogadas, acao) roda antes de cada jogada. Devolve a lista de
-- jogadas feitas (com quem jogou) e um erro, se houver.
local function play_game(g, bots, max_rounds, on_step)
  local log = {}
  local steps = 0
  while g.winner == nil and g.phase == "playing" and g.round <= max_rounds do
    steps = steps + 1
    if steps > 20000 then return log, "laço sem fim" end
    local p = whose_turn(g)
    local jogadas = Jogadas.list(g, p)
    local a = bots[p]:choose(g, p, jogadas)
    if on_step then on_step(g, p, jogadas, a) end
    if a == nil then return log, "sem jogada para o jogador " .. p end
    log[#log + 1] = { p = p, action = a }
    local ok, err = g:act(p, a)
    if not ok then return log, tostring(err) .. " (fase " .. g.phase .. ")" end
  end
  return log
end

-- Serialização simples e determinística do estado: tabelas em ordem de chave,
-- funções de fora, referências repetidas marcadas.
local function dump(v, seen, out)
  local t = type(v)
  if t == "table" then
    if seen[v] then out[#out + 1] = "<ref>"; return end
    seen[v] = true
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return type(a) .. ":" .. tostring(a) < type(b) .. ":" .. tostring(b) end)
    out[#out + 1] = "{"
    for _, k in ipairs(keys) do
      if type(v[k]) ~= "function" and type(k) ~= "function" then
        out[#out + 1] = tostring(k) .. "="
        dump(v[k], seen, out)
        out[#out + 1] = ","
      end
    end
    out[#out + 1] = "}"
  elseif t ~= "function" then
    out[#out + 1] = tostring(v)
  end
end

local function snapshot(g)
  local out = {}
  dump(g, {}, out)
  return table.concat(out)
end

-- Partida sem as mãos iniciais, para montar o cenário à mão.
local function bare(seed)
  local g = setup(seed)
  g.players[1].hand, g.players[2].hand = {}, {}
  return g
end

local function put(g, p, id, slot)
  return g:place_creature(p, { id = id, uid = g:next_uid() }, slot)
end

local function give(g, p, id)
  local pl = g.players[p]
  pl.hand[#pl.hand + 1] = { id = id, uid = g:next_uid() }
  return #pl.hand
end

local function has(jogadas, fn)
  for _, a in ipairs(jogadas) do if fn(a) then return true end end
  return false
end

local function count(jogadas, t)
  local n = 0
  for _, a in ipairs(jogadas) do if a.type == t then n = n + 1 end end
  return n
end

return {
  { "can_act não muda o estado nem emite eventos", function(T)
    local g = bare(7)
    g.players[1].mana = 10
    put(g, 1, "bot_lobo", 1); put(g, 2, "bot_rato", 2)
    g:put_structure(1, { id = "bot_tocha", uid = g:next_uid() })
    give(g, 1, "bot_raio"); give(g, 1, "bot_urso"); give(g, 1, "bot_tocha")
    local before, events = snapshot(g), #g.events
    local list = Jogadas.list(g, 1)
    T.ok(#list > 5, "há jogadas para testar")
    -- Ações inválidas também não mexem em nada.
    T.eq(g:can_act(1, { type = "attack", attackers = { 3 } }), false)
    T.eq(g:can_act(1, { type = "play", hand_index = 99 }), false)
    T.eq(g:can_act(2, { type = "pass" }), false)
    T.eq(g:can_act(1, { type = "activate", structure = 1, target = { p = 9 } }), false)
    T.eq(snapshot(g), before, "o estado é o mesmo")
    T.eq(#g.events, events, "nenhum evento")
    T.eq(g.context, nil, "o contexto volta ao que era")
  end },

  { "can_act aceita o que act aceita e recusa com o mesmo erro", function(T)
    local g = bare(7)
    put(g, 1, "bot_lobo", 1)
    T.eq(g:can_act(1, { type = "attack", attackers = { 1 } }), true)
    local ok, err = g:can_act(1, { type = "attack", attackers = { 2 } })
    local ok2, err2 = g:act(1, { type = "attack", attackers = { 2 } })
    T.eq(ok, false); T.eq(ok2, false); T.eq(err, err2)
    T.ok(g:act(1, { type = "attack", attackers = { 1 } }))
    T.eq(g:can_act(1, { type = "attack", attackers = { 1 } }), false, "já houve ataque")
  end },

  { "can_act não encerra a partida quando a validação de uma carta falha", function(T)
    local g = bare(7)
    Cards.define{ id = "bot_bug", kind = "feitico", speed = "rapido", cost = 0,
      targets = function() error("bug na carta") end, on_cast = function() end }
    local i = give(g, 1, "bot_bug")
    local ok, err = g:can_act(1, { type = "play", hand_index = i })
    T.eq(ok, false)
    T.ok(err:find("bug na carta", 1, true) ~= nil, err)
    T.eq(g.phase, "playing")
    T.eq(g.context, nil)
  end },

  { "a lista traz choose para cada opção e nenhuma quando a escolha permite", function(T)
    local g = bare(7)
    T.ok(g:act(1, { type = "play", hand_index = give(g, 1, "bot_duvida"), slot = 1 }))
    T.ok(g.pending_choice ~= nil, "a escolha abriu")
    local list = Jogadas.list(g, 1)
    T.eq(#list, 3)
    T.eq(count(list, "choose"), 3)
    T.ok(has(list, function(a) return a.index == 0 end), "nenhuma")
    T.eq(#Jogadas.list(g, 2), 0, "o outro jogador não tem jogadas")
    T.ok(g:act(1, list[1]))
  end },

  { "a lista traz as jogadas do estado: pass, play, attack, activate e block", function(T)
    local g = bare(7)
    g.players[1].mana = 10
    put(g, 1, "bot_lobo", 1); put(g, 1, "bot_rato", 2); put(g, 2, "bot_rato", 1)
    g:put_structure(1, { id = "bot_tocha", uid = g:next_uid() })
    give(g, 1, "bot_raio"); give(g, 1, "bot_urso")
    local list = Jogadas.list(g, 1)
    T.ok(has(list, function(a) return a.type == "pass" end))
    T.eq(count(list, "attack"), 3, "cada uma sozinha e as duas juntas")
    T.eq(count(list, "activate"), 1)
    -- O raio mira só criaturas: três em campo.
    local raios = 0
    for _, a in ipairs(list) do
      if a.type == "play" and g.players[1].hand[a.hand_index].id == "bot_raio" then raios = raios + 1 end
    end
    T.eq(raios, 3)
    T.eq(#Jogadas.list(g, 2), 0, "fora da vez não há jogadas")
    -- Bloqueio: na primeira resposta do defensor.
    T.ok(g:act(1, { type = "attack", attackers = { 1, 2 } }))
    T.ok(g:act(1, { type = "pass" }))
    local blocks = Jogadas.list(g, 2)
    T.eq(count(blocks, "block"), 3, "nenhum, rato no lobo, rato no rato")
    T.ok(has(blocks, function(a) return a.type == "pass" end))
    T.eq(count(blocks, "attack"), 0)
  end },

  { "com bloqueio obrigatório, a lista só traz bloqueios válidos", function(T)
    local g = bare(7)
    put(g, 1, "bot_coelho", 1)                -- Frágil ataca
    put(g, 2, "bot_cao", 1); put(g, 2, "bot_rato", 2) -- Agressivo deve bloquear
    T.ok(g:act(1, { type = "attack", attackers = { 1 } }))
    T.ok(g:act(1, { type = "pass" }))
    local list = Jogadas.list(g, 2)
    T.eq(count(list, "block"), 1)
    for _, a in ipairs(list) do
      if a.type == "block" then T.eq(a.blocks[1].blocker, 1, "só a Agressiva") end
    end
  end },

  { "toda jogada listada é aceita por act numa partida montada do mesmo jeito", function(T)
    local seed = 11
    local g, bots = setup(seed)
    local checked, budget = 0, 400
    local done = {}
    local _, err = play_game(g, bots, 60, function(gg, p, jogadas, chosen)
      for _, a in ipairs(jogadas) do
        if checked >= budget then break end
        local g2 = setup(seed)
        for i, step in ipairs(done) do
          T.ok(g2:act(step.p, step.action), "reproduzir o passo " .. i)
        end
        local ok, why = g2:act(p, a)
        T.ok(ok, "jogada listada recusada: " .. a.type .. " (" .. tostring(why) .. ")")
        checked = checked + 1
      end
      done[#done + 1] = { p = p, action = chosen }
    end)
    T.eq(err, nil)
    T.ok(checked > 50, "conferiu jogadas suficientes: " .. checked)
  end },

  { "a lista nunca é vazia quando é a vez do jogador", function(T)
    local g, bots = setup(3)
    local _, err = play_game(g, bots, 60, function(gg, p, jogadas)
      T.ok(#jogadas > 0, "lista vazia na rodada " .. gg.round)
      if gg.pending_choice == nil then
        T.ok(has(jogadas, function(a) return a.type == "pass" end), "pass sempre presente")
      end
    end)
    T.eq(err, nil)
  end },

  { "o bot bloqueia quando o dano mataria", function(T)
    local g = bare(7)
    put(g, 1, "bot_lobo", 1); put(g, 2, "bot_rato", 1); put(g, 2, "bot_urso", 2)
    g.players[2].life = 3
    T.ok(g:act(1, { type = "attack", attackers = { 1 } }))
    T.ok(g:act(1, { type = "pass" }))
    local bot = Bot.new{ rng = make_rng(1) }
    local a = bot:choose(g, 2, Jogadas.list(g, 2))
    T.eq(a.type, "block")
    T.eq(a.blocks[1].blocker, 2, "bloqueia com quem sobrevive")
    T.ok(g:act(2, a))
  end },

  { "com 4 atacantes contra 3 bloqueadores, o bot acha o bloqueio que salva", function(T)
    local g = bare(7)
    define()
    Cards.define{ id = "bot_gigante", kind = "criatura", cost = 0, atk = 6, hp = 6 }
    Cards.define{ id = "bot_muro", kind = "criatura", cost = 0, atk = 0, hp = 3 }
    for s = 1, 3 do put(g, 1, "bot_rato", s) end
    put(g, 1, "bot_gigante", 4)
    for s = 1, 3 do put(g, 2, "bot_muro", s) end
    g.players[2].life = 3
    T.ok(g:act(1, { type = "attack", attackers = { 1, 2, 3, 4 } }))
    T.ok(g:act(1, { type = "pass" }))
    local bot = Bot.new{ rng = make_rng(1) }
    local a = bot:choose(g, 2, Jogadas.list(g, 2))
    T.eq(a.type, "block")
    T.eq(#a.blocks, 3)
    T.ok(g:act(2, a))
    g:act(2, { type = "pass" }); g:act(1, { type = "pass" })
    T.ok(g.players[2].life > 0, "sobrevive")
  end },

  { "o bot não conta como morto o atacante mais rápido que o bloqueador", function(T)
    define()
    Cards.define{ id = "bot_veloz", kind = "criatura", cost = 0, atk = 2, hp = 2, speed = 2 }
    Cards.define{ id = "bot_lento", kind = "criatura", cost = 0, atk = 2, hp = 2 }
    Cards.define{ id = "bot_muro2", kind = "criatura", cost = 0, atk = 2, hp = 2 }
    for seed = 1, 6 do
      local g = bare(7)
      put(g, 1, "bot_veloz", 1); put(g, 1, "bot_lento", 2); put(g, 2, "bot_muro2", 1)
      g.players[2].life = 2
      T.ok(g:act(1, { type = "attack", attackers = { 1, 2 } }))
      T.ok(g:act(1, { type = "pass" }))
      local bot = Bot.new{ rng = make_rng(seed) }
      local a = bot:choose(g, 2, Jogadas.list(g, 2))
      T.eq(a.type, "block")
      T.eq(a.blocks[1].attacker, 2, "bloqueia o lento, que ele consegue matar")
    end
  end },

  { "velocidade 3 contra 2 morrem juntas, e a 3 soma o dano das duas fases", function(T)
    define()
    Cards.define{ id = "bot_v3", kind = "criatura", cost = 0, atk = 2, hp = 2, speed = 3 }
    Cards.define{ id = "bot_v2", kind = "criatura", cost = 0, atk = 2, hp = 2, speed = 2 }
    Cards.define{ id = "bot_muro4", kind = "criatura", cost = 0, atk = 0, hp = 4 }
    Cards.define{ id = "bot_muro5", kind = "criatura", cost = 0, atk = 0, hp = 5 }
    -- v3 ataca sem risco de morte: o muro de 4 morreria (2 + 2), então não bloqueia;
    -- o de 5 sobrevive, então bloqueia.
    local g = bare(7)
    put(g, 1, "bot_v3", 1); put(g, 2, "bot_muro4", 1)
    T.ok(g:act(1, { type = "attack", attackers = { 1 } })); T.ok(g:act(1, { type = "pass" }))
    local a = Bot.new{ rng = make_rng(1) }:choose(g, 2, Jogadas.list(g, 2))
    T.eq(a.type, "pass", "o muro de 4 morreria com os dois golpes")
    g = bare(7)
    put(g, 1, "bot_v3", 1); put(g, 2, "bot_muro5", 1)
    T.ok(g:act(1, { type = "attack", attackers = { 1 } })); T.ok(g:act(1, { type = "pass" }))
    a = Bot.new{ rng = make_rng(1) }:choose(g, 2, Jogadas.list(g, 2))
    T.eq(a.type, "block")
    -- v3 ataca; v2 bloqueando morre junto, então não vale como bloqueador que sobrevive.
    g = bare(7)
    put(g, 1, "bot_v3", 1); put(g, 2, "bot_v2", 1)
    T.ok(g:act(1, { type = "attack", attackers = { 1 } })); T.ok(g:act(1, { type = "pass" }))
    a = Bot.new{ rng = make_rng(1) }:choose(g, 2, Jogadas.list(g, 2))
    T.eq(a.type, "pass", "sem risco, não troca o bloqueador")
  end },

  { "listar bloqueios de 6 contra 6 com Frágeis e Agressivas é rápido", function(T)
    define()
    Cards.define{ id = "bot_fr1", kind = "criatura", cost = 0, atk = 1, hp = 1, kw = { fragil = true } }
    Cards.define{ id = "bot_ag1", kind = "criatura", cost = 0, atk = 1, hp = 1, kw = { agressivo = true } }
    local g = bare(7)
    for s = 1, 6 do put(g, 1, "bot_fr1", s); put(g, 2, "bot_ag1", s) end
    T.ok(g:act(1, { type = "attack", attackers = { 1, 2, 3, 4, 5, 6 } })); T.ok(g:act(1, { type = "pass" }))
    local t0 = os.clock()
    local list = Jogadas.list(g, 2)
    local dt = os.clock() - t0
    T.ok(#list > 700, "lista os emparelhamentos que atendem as obrigações")
    T.ok(dt < 5, "demorou " .. dt .. "s")
  end },

  { "sem risco de morrer, o bot não sacrifica bloqueadores", function(T)
    local g = bare(7)
    put(g, 1, "bot_lobo", 1); put(g, 2, "bot_rato", 1)
    T.ok(g:act(1, { type = "attack", attackers = { 1 } }))
    T.ok(g:act(1, { type = "pass" }))
    local bot = Bot.new{ rng = make_rng(1) }
    local a = bot:choose(g, 2, Jogadas.list(g, 2))
    T.eq(a.type, "pass")
  end },

  { "o bot joga a carta mais cara que cabe na mana e ataca só com vantagem", function(T)
    local g = bare(7)
    local bot = Bot.new{ rng = make_rng(1) }
    g.players[1].mana = 3
    give(g, 1, "bot_rato"); give(g, 1, "bot_lobo"); give(g, 1, "bot_urso")
    local a = bot:choose(g, 1, Jogadas.list(g, 1))
    T.eq(a.type, "play")
    T.eq(g.players[1].hand[a.hand_index].id, "bot_lobo", "o urso não cabe")
    -- Sem mana, com uma criatura fraca contra uma forte: passa.
    g.players[1].mana = 0
    put(g, 1, "bot_rato", 1); put(g, 2, "bot_urso", 1)
    T.eq(bot:choose(g, 1, Jogadas.list(g, 1)).type, "pass")
    -- Sem bloqueadores do outro lado: ataca.
    g.players[2].field[1] = nil
    a = bot:choose(g, 1, Jogadas.list(g, 1))
    T.eq(a.type, "attack")
  end },

  { "o bot é determinístico dado o rng", function(T)
    local function run(seed)
      local g, bots = setup(seed)
      local log, err = play_game(g, bots, 60)
      T.eq(err, nil)
      return #log, g.winner, #g.events
    end
    local a1, a2, a3 = run(5)
    local b1, b2, b3 = run(5)
    T.eq(a1, b1); T.eq(a2, b2); T.eq(a3, b3)
  end },

  { "bot contra bot: 50 partidas terminam sem erro", function(T)
    local finished = 0
    for seed = 1, 50 do
      local g, bots = setup(seed)
      local _, err = play_game(g, bots, 60)
      T.eq(err, nil, "semente " .. seed .. ": " .. tostring(err))
      T.ok(g.phase ~= "error", "semente " .. seed .. ": erro do motor")
      T.ok(g.winner ~= nil or g.round > 60, "semente " .. seed .. ": parou sem terminar")
      if g.winner ~= nil then finished = finished + 1 end
    end
    T.ok(finished > 0, "alguma partida terminou")
  end },
}
