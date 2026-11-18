-- Simulador de partidas (#26): joga partidas inteiras com jogadas válidas, ao
-- acaso ou pelo bot, e confere as invariantes do estado a cada jogada, para
-- achar travamentos, erros do motor e estados impossíveis. Lua 5.1 puro.
--
-- Interface:
--   local Simulador = require("duelo/sim/simulador")
--   Simulador.run_game{
--     decks = { d1, d2 }, extra_decks = { e1, e2 },  como em Game.new
--     seed = n,                  semente de tudo o que é sorteado (padrão 1)
--     players = { "random" | "bot", "random" | "bot" },  padrão random x random
--     max_rounds = 60,           parar quando g.round passar disso
--     max_steps = 20000,         parar quando o número de jogadas passar disso
--     invariants = true,         conferir as invariantes depois de cada jogada
--     first = 1 | 2 | nil,       quem começa (nil: sorteado pela semente)
--     mulligan = false,          com true, a troca inicial é feita (ao acaso
--                                para "random", sem trocar para "bot")
--     log = false,               com true, o relatório traz a lista de jogadas
--   } -> relatório, g
--
--   O relatório traz:
--     resultado   "vitoria" | "empate" | "limite_rodadas" | "erro" |
--                 "travamento" | "invariante"
--     vencedor    1 | 2 (só em "vitoria")
--     rodadas     g.round ao parar
--     jogadas     número de jogadas aceitas
--     seed, players
--   e, nas falhas (erro, travamento, invariante):
--     passo       número da jogada em que falhou
--     motivo      texto curto
--     erro        g.error do motor (message, traceback, context), em "erro"
--     invariante  a mensagem da invariante violada, em "invariante"
--     ultima      { p, action } da última jogada tentada
--
--   Simulador.run_many{ n = 100, seed_base = 0, alternar = false, ... }
--     roda n partidas com seeds seed_base + i (i de 1 a n) e os outros campos
--     de run_game; com alternar = true, as partidas ímpares trocam os baralhos
--     (e os jogadores) de lado, para as vitórias por baralho não se confundirem
--     com as vitórias por lado. Devolve o agregado:
--       n, por_resultado = { vitoria = n, ... }, vitorias_por_lado = { n, n },
--       empates, vitorias_por_deck = { n, n }, rodadas = { media, max },
--       jogadas = { media, max }, falhas = { { seed, resultado, motivo }, ... },
--       tempo (segundos de relógio da CPU)
--   Simulador.format_report(agg) -> texto curto
--   Simulador.make_rng(seed) -> rng(n) determinístico, como o Game espera

local Game = require("duelo/core/game")
local Jogadas = require("duelo/bot/jogadas")
local Bot = require("duelo/bot/bot")
local Invariantes = require("duelo/sim/invariantes")

local Simulador = {}

-- Gerador determinístico (Park e Miller), só com inteiros exatos em doubles.
function Simulador.make_rng(seed)
  local s = seed % 2147483647
  if s == 0 then s = 1 end
  return function(n)
    s = (s * 48271) % 2147483647
    return (s % n) + 1
  end
end

----------------------------------------------------------------------------
-- Jogadores
----------------------------------------------------------------------------

-- Um jogador é { choose = fn(g, p, jogadas) -> ação ou nil, mulligan = fn(g, p) -> índices }.
local function random_player(rng)
  return {
    choose = function(g, p, jogadas)
      if #jogadas == 0 then return nil end
      return jogadas[rng(#jogadas)]
    end,
    mulligan = function(g, p)
      local idx = {}
      for i = 1, #g.players[p].hand do
        if rng(2) == 1 then idx[#idx + 1] = i end
      end
      return idx
    end,
  }
end

local function bot_player(rng)
  local bot = Bot.new{ rng = rng }
  return {
    choose = function(g, p, jogadas)
      -- Um erro de carta na avaliação não derruba a partida: o bot passa, como
      -- em Bot:act.
      local ok, a = pcall(bot.choose, bot, g, p, jogadas)
      if ok then return a end
      for _, j in ipairs(jogadas) do if j.type == "pass" then return j end end
      return nil
    end,
    mulligan = function() return {} end,
  }
end

local function make_player(kind, rng)
  if kind == "bot" then return bot_player(rng) end
  if kind == "random" or kind == nil then return random_player(rng) end
  error("tipo de jogador desconhecido: " .. tostring(kind))
end

-- Quem deve agir: quem tem uma escolha pendente, senão o ativo.
local function whose_turn(g)
  return g.pending_choice and g.pending_choice.player or g.active
end

----------------------------------------------------------------------------
-- Uma partida
----------------------------------------------------------------------------

local function describe_action(a)
  if a == nil then return "nil" end
  local parts = { tostring(a.type) }
  local keys = {}
  for k in pairs(a) do if k ~= "type" then keys[#keys + 1] = tostring(k) end end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = a[k]
    if type(v) == "table" then
      local items = {}
      for _, x in ipairs(v) do
        if type(x) == "table" then
          local inner = {}
          for kk, vv in pairs(x) do inner[#inner + 1] = tostring(kk) .. "=" .. tostring(vv) end
          table.sort(inner)
          items[#items + 1] = "{" .. table.concat(inner, ",") .. "}"
        else
          items[#items + 1] = tostring(x)
        end
      end
      if #items == 0 then
        local inner = {}
        for kk, vv in pairs(v) do inner[#inner + 1] = tostring(kk) .. "=" .. tostring(vv) end
        table.sort(inner)
        v = "{" .. table.concat(inner, ",") .. "}"
      else
        v = "{" .. table.concat(items, ",") .. "}"
      end
    end
    parts[#parts + 1] = k .. "=" .. tostring(v)
  end
  return table.concat(parts, " ")
end
Simulador.describe_action = describe_action

function Simulador.run_game(opts)
  opts = opts or {}
  local seed = opts.seed or 1
  local max_rounds = opts.max_rounds or 60
  local max_steps = opts.max_steps or 20000
  local check = opts.invariants ~= false
  local kinds = opts.players or { "random", "random" }

  local g = Game.new{
    decks = opts.decks, extra_decks = opts.extra_decks,
    rng = Simulador.make_rng(seed), first = opts.first, mulligan = opts.mulligan == true,
  }
  local players = { make_player(kinds[1], Simulador.make_rng(seed + 1)), make_player(kinds[2], Simulador.make_rng(seed + 2)) }

  local report = { seed = seed, players = { kinds[1] or "random", kinds[2] or "random" }, jogadas = 0, rodadas = 0 }
  if opts.log then report.log = {} end
  local card_total = Invariantes.count_cards(g)

  local function finish(resultado, extra)
    report.resultado = resultado
    report.rodadas = g.round
    if extra then for k, v in pairs(extra) do report[k] = v end end
    if resultado == "vitoria" then report.vencedor = g.winner end
    return report, g
  end

  local function fail(resultado, step, motivo, extra)
    extra = extra or {}
    extra.passo = step
    extra.motivo = motivo
    if g.phase == "error" and g.error then extra.erro = g.error end
    return finish(resultado, extra)
  end

  local function verify(step)
    if not check then return nil end
    local ok, msg = Invariantes.check(g, { card_total = card_total })
    if ok then return nil end
    return fail("invariante", step, "invariante violada: " .. msg, { invariante = msg })
  end

  -- Início e troca inicial.
  local ok, err = g:start()
  if not ok then return fail("erro", 0, "start recusado: " .. tostring(err)) end
  if g.phase == "mulligan" then
    for p = 1, 2 do
      local idx = players[p].mulligan(g, p)
      ok, err = g:mulligan(p, idx)
      if not ok then return fail("erro", 0, "mulligan recusado: " .. tostring(err)) end
    end
  end
  if g.phase == "error" then return fail("erro", 0, "erro do motor no início") end
  local r = verify(0)
  if r then return r end

  local step = 0
  while true do
    if g.winner ~= nil then
      if g.winner == 0 then return finish("empate") end
      return finish("vitoria")
    end
    if g.phase == "error" then return fail("erro", step, "erro do motor: " .. tostring(g.error and g.error.message)) end
    if g.phase ~= "playing" then return fail("travamento", step, "fase inesperada: " .. tostring(g.phase)) end
    if g.round > max_rounds then return finish("limite_rodadas") end
    if step >= max_steps then return fail("travamento", step, "passou de " .. max_steps .. " jogadas sem terminar") end

    local p = whose_turn(g)
    if p ~= 1 and p ~= 2 then return fail("travamento", step, "ninguém para agir (active = " .. tostring(g.active) .. ")") end
    local jogadas = Jogadas.list(g, p)
    if #jogadas == 0 then
      return fail("travamento", step, "nenhuma jogada válida para o jogador " .. p .. " (rodada " .. g.round .. ")")
    end
    local a = players[p].choose(g, p, jogadas)
    if a == nil then return fail("travamento", step, "o jogador " .. p .. " não escolheu nenhuma jogada") end
    step = step + 1
    if report.log then report.log[#report.log + 1] = { p = p, action = a } end
    report.ultima = { p = p, action = a }
    ok, err = g:act(p, a)
    if not ok then
      if g.phase == "error" then
        return fail("erro", step, "erro do motor: " .. tostring(g.error and g.error.message))
      end
      return fail("travamento", step, "jogada listada recusada (" .. describe_action(a) .. "): " .. tostring(err))
    end
    report.jogadas = step
    if g.phase == "error" then
      return fail("erro", step, "erro do motor: " .. tostring(g.error and g.error.message))
    end
    r = verify(step)
    if r then return r end
  end
end

----------------------------------------------------------------------------
-- Muitas partidas
----------------------------------------------------------------------------

local RESULTS = { "vitoria", "empate", "limite_rodadas", "erro", "travamento", "invariante" }
Simulador.RESULTS = RESULTS

local FAILURES = { erro = true, travamento = true, invariante = true }

function Simulador.run_many(opts)
  opts = opts or {}
  local n = opts.n or 100
  local base = opts.seed_base or 0
  local agg = {
    n = n, por_resultado = {}, vitorias_por_lado = { 0, 0 }, empates = 0,
    vitorias_por_deck = { 0, 0 }, rodadas = { media = 0, max = 0 }, jogadas = { media = 0, max = 0 },
    falhas = {}, players = opts.players or { "random", "random" }, alternar = opts.alternar == true,
  }
  for _, r in ipairs(RESULTS) do agg.por_resultado[r] = 0 end
  local sum_rounds, sum_steps = 0, 0
  local t0 = os.clock()
  for i = 1, n do
    local game_opts = {}
    for k, v in pairs(opts) do game_opts[k] = v end
    game_opts.seed = base + i
    -- Partidas ímpares com os lados trocados: o baralho 1 joga do lado 2.
    local swapped = agg.alternar and i % 2 == 1
    if swapped then
      local decks, extras, kinds = opts.decks, opts.extra_decks, opts.players
      if decks then game_opts.decks = { decks[2], decks[1] } end
      if extras then game_opts.extra_decks = { extras[2], extras[1] } end
      if kinds then game_opts.players = { kinds[2], kinds[1] } end
    end
    local rep = Simulador.run_game(game_opts)
    agg.por_resultado[rep.resultado] = (agg.por_resultado[rep.resultado] or 0) + 1
    if rep.resultado == "vitoria" then
      agg.vitorias_por_lado[rep.vencedor] = agg.vitorias_por_lado[rep.vencedor] + 1
      local deck = rep.vencedor
      if swapped then deck = Game.other(deck) end
      agg.vitorias_por_deck[deck] = agg.vitorias_por_deck[deck] + 1
    elseif rep.resultado == "empate" then
      agg.empates = agg.empates + 1
    end
    sum_rounds = sum_rounds + rep.rodadas
    sum_steps = sum_steps + rep.jogadas
    if rep.rodadas > agg.rodadas.max then agg.rodadas.max = rep.rodadas end
    if rep.jogadas > agg.jogadas.max then agg.jogadas.max = rep.jogadas end
    if FAILURES[rep.resultado] then
      agg.falhas[#agg.falhas + 1] = {
        seed = rep.seed, resultado = rep.resultado, motivo = rep.motivo, passo = rep.passo,
        players = rep.players, erro = rep.erro, invariante = rep.invariante, ultima = rep.ultima,
      }
    end
  end
  if n > 0 then
    agg.rodadas.media = sum_rounds / n
    agg.jogadas.media = sum_steps / n
  end
  agg.tempo = os.clock() - t0
  return agg
end

function Simulador.format_report(agg)
  local lines = {}
  local function add(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
  add("%d partidas (%s x %s%s) em %.1fs", agg.n, tostring(agg.players[1]), tostring(agg.players[2]),
    agg.alternar and ", lados alternados" or "", agg.tempo or 0)
  local parts = {}
  for _, r in ipairs(RESULTS) do
    if (agg.por_resultado[r] or 0) > 0 then parts[#parts + 1] = r .. " " .. agg.por_resultado[r] end
  end
  add("resultados: %s", table.concat(parts, ", "))
  add("vitorias por lado: 1 = %d, 2 = %d; por baralho: 1 = %d, 2 = %d; empates: %d",
    agg.vitorias_por_lado[1], agg.vitorias_por_lado[2], agg.vitorias_por_deck[1], agg.vitorias_por_deck[2], agg.empates)
  add("rodadas: media %.1f, max %d; jogadas: media %.1f, max %d",
    agg.rodadas.media, agg.rodadas.max, agg.jogadas.media, agg.jogadas.max)
  if #agg.falhas == 0 then
    add("falhas: nenhuma")
  else
    add("falhas: %d", #agg.falhas)
    for i, f in ipairs(agg.falhas) do
      if i > 20 then add("  ... e mais %d", #agg.falhas - 20); break end
      add("  seed %d (%s, passo %s): %s", f.seed, f.resultado, tostring(f.passo), tostring(f.motivo))
      if f.ultima then add("    ultima jogada: jogador %d, %s", f.ultima.p, describe_action(f.ultima.action)) end
      if f.erro and f.erro.traceback then add("    %s", (tostring(f.erro.traceback):gsub("\n", "\n    "))) end
    end
  end
  return table.concat(lines, "\n")
end

return Simulador
