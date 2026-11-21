-- Fuzz determinístico das ações (US #41): o jogador não derruba a partida.
--
-- A invariante do motor: toda ação que Game:can_act aceita resolve em
-- Game:act sem erro por causa da forma da ação, e nenhuma ação torta encerra
-- a partida. No jogo, as ações chegam de um cliente que pode mandar qualquer
-- coisa (duelo/mod/partida_servidor só chama Game:act depois de Game:can_act
-- dizer que sim).
--
-- Como: partidas com os decks reais (Wilson e Webber) andam com jogadas
-- sorteadas entre as válidas (duelo/bot/jogadas). Em cada passo, ações
-- válidas são copiadas e estragadas (tipos trocados, campos a mais, números
-- negativos, fracionários, enormes e não finitos, strings, tabelas vazias) e
-- oferecidas ao motor pelos dois jogadores. Semente fixa: a mesma sequência
-- em toda execução.
--
-- Para cada ação estragada:
--   * Game:can_act não pode devolver "erro na validação" (um validador que
--     estoura com uma forma inesperada);
--   * se can_act aceitou, Game:act tem de aceitar também;
--   * se recusou, Game:act recusa do mesmo jeito, sem mudar a partida;
--   * a partida nunca passa para a fase "error".

local Game = require("duelo/core/game")
local Decks = require("duelo/decks/init")
local Jogadas = require("duelo/bot/jogadas")
local Rng = require("duelo/core/rng")
local Serial = require("duelo/core/serial")

local MUTADAS = 3000      -- total de ações estragadas
local POR_PASSO = 6       -- quantas em cada passo da partida
local SEMENTE = 4141

local CAMPOS = { "type", "from", "hand_index", "slot", "target", "targets", "sacrifice", "replace",
  "structure", "creature", "equip", "index", "attackers", "blocks", "indices", "attacker", "blocker",
  "p", "zone", "uid", "lixo" }

local TIPOS = { "pass", "play", "attack", "block", "choose", "activate", "mulligan", "nada" }

local function copia(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = copia(x) end
  return c
end

-- Um valor qualquer. As funções devolvem tabelas novas a cada chamada.
local LIXO = {
  function() return 0 end, function() return -1 end, function() return 1 end, function() return 2 end,
  function() return 5 end, function() return 7 end, function() return 1.5 end, function() return -3.25 end,
  function() return 2 ^ 40 end, function() return 1e308 end, function() return -2 ^ 31 end,
  function() return math.huge end, function() return -math.huge end, function() return 0 / 0 end,
  function() return "" end, function() return "x" end, function() return "1" end, function() return "hand" end,
  function() return "mao" end, function() return "jogador" end, function() return "criatura" end,
  function() return true end, function() return false end,
  function() return {} end, function() return { 1 } end, function() return { 1, 2 } end,
  function() return { {} } end, function() return { "x" } end, function() return { x = { y = {} } } end,
  function() return { p = 1 } end, function() return { p = 1, slot = 1 } end,
  function() return { p = 2, slot = 1 } end, function() return { p = 3, slot = 1 } end,
  function() return { p = 1, slot = 99 } end, function() return { p = 1, slot = 1.5 } end,
  function() return { p = "1", slot = "1" } end, function() return { p = 1, zone = "jogador" } end,
  function() return { p = 2, zone = "jogador" } end, function() return { p = 1, slot = 1, zone = "estrutura" } end,
  function() return { p = 1, slot = 1, zone = {} } end, function() return { p = 1, slot = 1, zone = 3 } end,
  function() return { { p = 1, slot = 1 } } end, function() return { { p = 1, zone = "jogador" }, 4 } end,
  function() return { [2] = { p = 1, slot = 1 } } end, function() return { attacker = 1, blocker = 1 } end,
  function() return { { attacker = 1, blocker = 1 } } end, function() return { { attacker = "a" } } end,
}

local function lixo(rng) return LIXO[rng(#LIXO)]() end

-- As chaves de uma tabela, em ordem fixa (pairs não tem ordem garantida).
local function chaves(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks, Serial.sort_keys)
  return ks
end

-- Estraga a ação no lugar: uma de várias mudanças, na raiz ou numa tabela de dentro.
local function estragar(a, rng)
  local alvo = a
  -- Às vezes desce para uma tabela de dentro (alvo, lista de atacantes...).
  if rng(3) == 1 then
    local dentro = {}
    for _, k in ipairs(chaves(a)) do
      if type(a[k]) == "table" then dentro[#dentro + 1] = a[k] end
    end
    if #dentro > 0 then
      alvo = dentro[rng(#dentro)]
      if rng(2) == 1 then
        for _, k in ipairs(chaves(alvo)) do
          if type(alvo[k]) == "table" then alvo = alvo[k]; break end
        end
      end
    end
  end
  local ks = chaves(alvo)
  local modo = rng(6)
  if modo == 1 and #ks > 0 then
    alvo[ks[rng(#ks)]] = lixo(rng)                      -- troca o valor de um campo
  elseif modo == 2 and #ks > 0 then
    alvo[ks[rng(#ks)]] = nil                            -- tira um campo
  elseif modo == 3 then
    alvo[CAMPOS[rng(#CAMPOS)]] = lixo(rng)              -- campo a mais (ou trocado)
  elseif modo == 4 then
    alvo[#alvo + 1] = lixo(rng)                         -- mais um item na lista
  elseif modo == 5 and #ks > 0 then
    local k = ks[rng(#ks)]                              -- número vizinho, negativo ou fracionário
    if type(alvo[k]) == "number" then
      local d = ({ -1, 1, 0.5, -alvo[k] * 2, 100 })[rng(5)]
      alvo[k] = alvo[k] + d
    else
      alvo[k] = lixo(rng)
    end
  else
    if alvo == a and rng(2) == 1 then a.type = TIPOS[rng(#TIPOS)] else alvo[CAMPOS[rng(#CAMPOS)]] = lixo(rng) end
  end
end

local function texto(a)
  local ok, s = pcall(Serial.serialize, a)
  if ok then return s end
  -- Com NaN ou infinito o serializador recusa: descrição simples.
  local out = {}
  for _, k in ipairs(chaves(a)) do out[#out + 1] = tostring(k) .. "=" .. tostring(a[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

local function quem_age(g)
  return g.pending_choice and g.pending_choice.player or g.active
end

local function nova_partida(seed, invertida)
  local d1, e1 = Decks.build("wilson")
  local d2, e2 = Decks.build("webber")
  local decks, extras = { d1, d2 }, { e1, e2 }
  if invertida then decks, extras = { d2, d1 }, { e2, e1 } end
  local g = Game.new{ decks = decks, extra_decks = extras, seed = seed, mulligan = false }
  assert(g:start())
  return g
end

return {
  { "fuzz: nenhuma ação torta encerra a partida, e o que can_act aceita o act resolve", function(T)
    local rng = Rng.make(SEMENTE)
    local feitas, aceitas, partidas = 0, 0, 0
    local por_tipo = {}
    while feitas < MUTADAS do
      partidas = partidas + 1
      local g = nova_partida(SEMENTE + partidas, partidas % 2 == 0)
      local passos = 0
      while feitas < MUTADAS and g.winner == nil and g.phase == "playing" and g.round <= 40 and passos < 400 do
        passos = passos + 1
        local p = quem_age(g)
        local validas = Jogadas.list(g, p)
        T.ok(#validas > 0, "há jogada válida")
        for _ = 1, POR_PASSO do
          if feitas >= MUTADAS or g.winner ~= nil or g.phase ~= "playing" then break end
          -- A base é uma jogada válida de agora (de quem age).
          local quem = quem_age(g)
          local bases = quem == p and validas or Jogadas.list(g, quem)
          local a = copia(bases[rng(#bases)])
          for _ = 1, rng(3) do estragar(a, rng) end
          -- Quase sempre por quem age; às vezes pelo outro jogador.
          if rng(5) == 1 then quem = Game.other(quem) end
          local onde = "partida " .. partidas .. ", passo " .. passos .. ", lado " .. quem .. ": " .. texto(a)
          feitas = feitas + 1
          por_tipo[tostring(a.type)] = (por_tipo[tostring(a.type)] or 0) + 1
          local eventos, registradas = #g.events, #g.log.actions
          local pode, motivo = g:can_act(quem, a)
          T.ok(not tostring(motivo):find("erro na validação", 1, true),
            "o validador estourou (" .. tostring(motivo) .. ") em " .. onde)
          T.eq(#g.events, eventos, "can_act não emite eventos")
          local ok, err = g:act(quem, a)
          T.ok(g.phase ~= "error", "a partida foi encerrada por erro ("
            .. tostring(g.error and g.error.message) .. ") em " .. onde)
          if pode then
            aceitas = aceitas + 1
            T.ok(ok, "can_act aceitou e act recusou (" .. tostring(err) .. ") em " .. onde)
          else
            T.ok(not ok, "can_act recusou (" .. tostring(motivo) .. ") e act aceitou em " .. onde)
            T.eq(#g.events, eventos, "ação recusada não emite eventos: " .. onde)
            T.eq(#g.log.actions, registradas, "ação recusada não entra no registro: " .. onde)
          end
        end
        -- A partida anda com uma jogada válida sorteada.
        if g.winner == nil and g.phase == "playing" then
          local q = quem_age(g)
          local lista = Jogadas.list(g, q)
          local a = lista[rng(#lista)]
          local ok, err = g:act(q, a)
          T.ok(ok, "jogada válida recusada (" .. tostring(err) .. "): " .. texto(a))
          T.ok(g.phase ~= "error", "erro numa jogada válida: " .. tostring(g.error and g.error.message))
        end
      end
    end
    T.eq(feitas, MUTADAS, "ações estragadas oferecidas ao motor")
    -- O fuzz exercitou os dois lados da invariante e os tipos de ação.
    T.ok(aceitas > 100, "parte das ações estragadas continua válida: " .. aceitas)
    T.ok(feitas - aceitas > 1000, "a maior parte é recusada: " .. (feitas - aceitas))
    for _, tipo in ipairs({ "play", "pass", "attack", "block", "choose", "activate" }) do
      T.ok((por_tipo[tipo] or 0) > 20, "ações do tipo " .. tipo .. ": " .. tostring(por_tipo[tipo]))
    end
  end },

  { "alvo de tipo errado, ou informado em carta sem alvos, é recusado por can_act e não derruba o act", function(T)
    local g = nova_partida(7, false)
    -- Uma criatura sem alvos de entrada na mão de quem tem a vez.
    local p = g.active
    local indice, def
    for i, c in ipairs(g.players[p].hand) do
      local d = g:def_of(c)
      if d.kind == "criatura" and d.play_targets == nil and not d.sacrifice and g:card_cost(p, c) <= g.players[p].mana then
        indice, def = i, d
        break
      end
    end
    if indice == nil then
      -- Sem criatura barata na mão inicial: põe uma no lugar da primeira carta.
      for i, c in ipairs(g.players[p].deck) do
        local d = g:def_of(c)
        if d.kind == "criatura" and d.play_targets == nil and not d.sacrifice and d.cost <= g.players[p].mana then
          g.players[p].hand[1], g.players[p].deck[i] = c, g.players[p].hand[1]
          indice, def = 1, d
          break
        end
      end
    end
    T.ok(indice ~= nil, "há uma criatura sem alvos para jogar")
    local base = { type = "play", from = "hand", hand_index = indice, slot = 5 }
    T.ok(g:can_act(p, base), "a jogada sem alvo vale")
    local tortas = {
      { target = 1 }, { targets = { 1 } }, { targets = "1" }, { target = {} }, { target = "x" },
      { target = true }, { targets = {} }, { targets = { {} } }, { target = { p = 1, zone = "jogador" } },
      { targets = { { p = 1, zone = "jogador" } } }, { target = false }, { targets = 0 },
    }
    for _, extra in ipairs(tortas) do
      local a = copia(base)
      for k, v in pairs(extra) do a[k] = v end
      local pode, motivo = g:can_act(p, a)
      T.eq(pode, false, "can_act recusa " .. texto(a))
      T.ok(not tostring(motivo):find("erro na validação", 1, true), "com um motivo claro: " .. tostring(motivo))
      local ok = g:act(p, a)
      T.eq(ok, false, "act recusa " .. texto(a))
      T.eq(g.phase, "playing", "a partida continua de pé depois de " .. texto(a))
    end
    T.eq(#g.log.actions, 0, "nada entrou no registro")
    T.ok(g:act(p, base), "e a jogada sem alvo entra: " .. tostring(def.id))
  end },
}
