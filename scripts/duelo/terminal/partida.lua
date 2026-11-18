-- Partida humano contra bot, sem terminal: recebe linhas e devolve texto.
-- Lua 5.1 puro.
--
-- Interface:
--   local Partida = require("duelo/terminal/partida")
--   local partida = Partida.new{ decks = {d1, d2}, extra_decks = {e1, e2},
--                                seed = n, human = 1 }
--   partida:tela() -> string            a tela atual (depois de o bot jogar)
--   partida:step(linha) -> texto, acabou
--       processa uma linha do humano: interpreta o comando, aplica no motor,
--       deixa o bot jogar até a vez voltar ao humano (ou a partida acabar) e
--       devolve o texto a mostrar: os eventos desde a última tela, uma frase
--       por linha, e a tela nova. Com erro de comando ou do motor, devolve só
--       a mensagem de erro. acabou = true quando a partida terminou ou o
--       humano pediu para sair.
--   Partida.describe_events(g, from_index, p) -> lista de frases
--       traduz g.events[from_index..] para o jogador p
--
-- A semente alimenta um gerador próprio (Park e Miller), então a mesma semente
-- dá a mesma partida, com as mesmas jogadas do bot para as mesmas entradas.

local Game = require("duelo/core/game")
local Bot = require("duelo/bot/bot")
local Jogadas = require("duelo/bot/jogadas")
local Tela = require("duelo/terminal/tela")
local Comandos = require("duelo/terminal/comandos")

local Partida = {}
Partida.__index = Partida

-- Gerador determinístico (Park e Miller), só com inteiros exatos em doubles.
function Partida.make_rng(seed)
  local s = math.floor(tonumber(seed) or 1) % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function(n)
    s = (s * 48271) % 2147483647
    return (s % n) + 1
  end
end

-- Limite de jogadas seguidas do bot numa mesma chamada, contra laços sem fim.
Partida.BOT_STEP_LIMIT = 500

function Partida.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Partida)
  self.human = opts.human or 1
  self.bot_player = Game.other(self.human)
  self.seed = opts.seed or 1
  local rng = Partida.make_rng(self.seed)
  self.g = Game.new{
    decks = opts.decks, extra_decks = opts.extra_decks,
    first = opts.first, mulligan = false, rng = rng,
  }
  self.bot = Bot.new{ rng = Partida.make_rng(self.seed + 1) }
  self.last_event = 0
  self.over = false
  self.mensagens = {}
  self.g:start()
  self:run_bot()
  return self
end

----------------------------------------------------------------------------
-- Eventos em frases
----------------------------------------------------------------------------

-- Nomes dos objetos pelo uid, lidos dos eventos de entrada em campo.
local function build_names(g)
  local names = {}
  for _, ev in ipairs(g.events) do
    if ev.uid and ev.id and (ev.t == "summon" or ev.t == "structure" or ev.t == "equip") then
      local def = g:def_of({ id = ev.id })
      names[ev.uid] = def and (def.name or def.id) or ev.id
    end
  end
  return names
end

local function nome_id(g, id)
  if id == nil then return "?" end
  local def = g:def_of({ id = id })
  return def and (def.name or def.id) or tostring(id)
end

local PERIODOS = { manha = "manhã", tarde = "tarde", noite = "noite" }

local FONTES = { combate = "combate", fome = "Fome", fogueira = "fogueira apagada" }

-- Traduz os eventos a partir de from_index para o jogador p. Eventos privados do
-- outro jogador não aparecem.
function Partida.describe_events(g, from_index, p)
  local names = build_names(g)
  local function nome(uid) return names[uid] or "?" end
  local function quem(j, maiusc)
    local s = (j == p) and "você" or "o bot"
    if maiusc then s = s:sub(1, 1):upper() .. s:sub(2) end
    return s
  end
  -- Forma possessiva: "sua" / "do bot".
  local function de_quem(j) return (j == p) and "sua" or "do bot" end
  local function rotulo(label)
    if label == nil then return "?" end
    local def = g:def_of({ id = label })
    return def and (def.name or def.id) or tostring(label)
  end
  local out = {}
  local function add(s) out[#out + 1] = s end
  for i = from_index or 1, #g.events do
    local ev = g.events[i]
    local t = ev.t
    if ev.private and ev.p ~= p then
      -- nada: evento privado do outro jogador
    elseif t == "round_start" then
      add("Rodada " .. ev.round .. ": token de ataque com " .. quem(ev.attacker) .. ".")
    elseif t == "period" then
      add("Período: " .. (PERIODOS[ev.period] or ev.period) .. ".")
    elseif t == "fogueira" then
      if ev.reason == "acendeu" then
        add("Fogueira " .. de_quem(ev.p) .. " acesa com " .. ev.value .. ".")
      elseif ev.reason == "bonus" then
        add("Fogueira " .. de_quem(ev.p) .. " sobe para " .. ev.value .. ".")
      end
    elseif t == "play" then
      add(quem(ev.p, true) .. " jogou " .. nome_id(g, ev.id)
        .. " (custo " .. ev.cost .. ").")
    elseif t == "summon" then
      local lado = (ev.p == p) and "c" or "o"
      add(nome_id(g, ev.id) .. " entra em " .. lado .. ev.slot .. (ev.ficha and " (ficha)." or "."))
    elseif t == "structure" then
      local lado = (ev.p == p) and "e" or "oe"
      add(nome_id(g, ev.id) .. " entra em " .. lado .. ev.slot .. ".")
    elseif t == "equip" then
      add(nome_id(g, ev.id) .. " equipada em " .. nome(ev.holder_uid) .. " (" .. ev.equip_slot .. ").")
    elseif t == "unequip" then
      add(nome_id(g, ev.id) .. " sai de " .. nome(ev.holder_uid) .. " (" .. tostring(ev.reason) .. ").")
    elseif t == "activate" then
      add(quem(ev.p, true) .. " ativou " .. nome_id(g, ev.id) .. ".")
    elseif t == "instant" then
      -- coberto por play ou activate
    elseif t == "stack_push" then
      add("Na pilha: " .. rotulo(ev.label) .. " (" .. quem(ev.p) .. ").")
    elseif t == "stack_resolve" then
      add("Resolve: " .. rotulo(ev.label) .. ".")
    elseif t == "ready" then
      add(quem(Game.other(ev.active), true) .. " está pronto; a vez é " .. de_quem(ev.active) .. ".")
    elseif t == "pass" then
      if ev.p ~= p then add("O bot passou.") end
    elseif t == "attack" then
      local list = {}
      for _, uid in ipairs(ev.attackers) do list[#list + 1] = nome(uid) end
      add(quem(ev.p, true) .. " ataca com " .. table.concat(list, ", ") .. ".")
    elseif t == "block" then
      if #ev.blocks == 0 then
        add(quem(ev.p, true) .. " não bloqueia.")
      else
        local list = {}
        for _, b in ipairs(ev.blocks) do list[#list + 1] = nome(b.blocker) .. " bloqueia " .. nome(b.attacker) end
        add(quem(ev.p, true) .. " bloqueia" .. (ev.auto and " (obrigatório)" or "")
          .. ": " .. table.concat(list, "; ") .. ".")
      end
    elseif t == "strike_phase" then
      -- Cada par (atacante e bloqueador, ou atacante sozinho) tem as suas fases.
      local par = ev.attacker_uid and (" " .. nome(ev.attacker_uid)
        .. (ev.blocker_uid and (" contra " .. nome(ev.blocker_uid)) or "") .. ".") or ""
      add((ev.phase == "rapida" and "Fase rápida:" or "Fase normal:") .. par)
    elseif t == "strike" then
      if ev.target_player then
        add("  " .. nome(ev.uid) .. " golpeia " .. quem(ev.target_player) .. " por " .. ev.amount .. ".")
      else
        add("  " .. nome(ev.uid) .. " golpeia " .. nome(ev.target_uid) .. " por " .. ev.amount .. ".")
      end
    elseif t == "creature_damage" then
      if ev.reason ~= "combate" then
        add(nome(ev.uid) .. " sofre " .. ev.amount .. " de dano (" .. tostring(ev.reason) .. ").")
      end
    elseif t == "creature_heal" then
      add(nome(ev.uid) .. " recupera " .. ev.amount .. " de vida.")
    elseif t == "player_damage" then
      local fonte = FONTES[ev.source] or tostring(ev.source)
      add(quem(ev.p, true) .. " sofre " .. ev.amount .. " de dano ("
        .. fonte .. "); vida " .. ev.life .. ".")
    elseif t == "player_heal" then
      add(quem(ev.p, true) .. " recupera " .. ev.amount .. " de vida; vida " .. ev.life .. ".")
    elseif t == "death" then
      local por = ev.killer_uid and (" por " .. nome(ev.killer_uid)) or ""
      local dono = (ev.p == p) and "sua" or "do bot"
      add(nome(ev.uid) .. " (" .. dono .. ") morre" .. por .. ".")
    elseif t == "leave" then
      if ev.dest == "hand" then add(nome(ev.uid) .. " volta para a mão.")
      elseif ev.dest == "deck" then add(nome(ev.uid) .. " volta para o baralho.")
      elseif ev.dest == "destroyed" then add(nome(ev.uid) .. " é destruída (" .. tostring(ev.reason) .. ").") end
    elseif t == "break" then
      add(nome(ev.uid) .. " é quebrada.")
    elseif t == "structure_destroyed" then
      add(nome(ev.uid) .. " é destruída (" .. tostring(ev.reason) .. ").")
    elseif t == "destroyed" then
      -- A carta do adversário não é nomeada: a mão dele é privada.
      local carta = (ev.p == p) and nome_id(g, ev.id) or "uma carta"
      if ev.reason == "limite_de_mao" then
        add("Mão cheia: " .. quem(ev.p) .. " perde " .. carta .. " (destruída).")
      elseif ev.reason == "limite_de_mao_fim_rodada" then
        add("Fim da rodada: " .. carta .. " acima do limite de " .. quem(ev.p) .. " é destruída.")
      end
    elseif t == "fizzle" then
      add(nome_id(g, ev.id) .. " não acontece: alvo perdido.")
    elseif t == "no_space" then
      add(nome_id(g, ev.id) .. " não entra: sem espaço.")
    elseif t == "to_hand" then
      if ev.source ~= "baralho" then add(nome_id(g, ev.id) .. " vai para a sua mão.") end
    elseif t == "inventory" then
      if ev.p == p then add(nome_id(g, ev.id) .. " vai para o seu Inventário.") end
    elseif t == "choice" then
      add("Escolha pendente " .. de_quem(ev.p) .. " (" .. tostring(ev.reason) .. ").")
    elseif t == "round_end" then
      add("Fim da rodada " .. ev.round .. ".")
    elseif t == "game_over" then
      if ev.winner == 0 then add("FIM DE PARTIDA: empate.")
      elseif ev.winner == p then add("FIM DE PARTIDA: você venceu!")
      else add("FIM DE PARTIDA: você perdeu.") end
    elseif t == "engine_error" then
      add("ERRO NO MOTOR: " .. tostring(ev.message) .. ".")
    end
  end
  return out
end

----------------------------------------------------------------------------
-- Andamento
----------------------------------------------------------------------------

function Partida:acabou()
  local g = self.g
  return self.over or g.winner ~= nil or g.phase ~= "playing"
end

-- De quem é a vez agora: quem tem a escolha pendente, senão quem tem a vez.
function Partida:vez_de()
  local g = self.g
  if g.pending_choice then return g.pending_choice.player end
  return g.active
end

-- O bot joga até a vez voltar ao humano ou a partida acabar.
function Partida:run_bot()
  local g = self.g
  local passos = 0
  while not self:acabou() and self:vez_de() == self.bot_player do
    passos = passos + 1
    if passos > Partida.BOT_STEP_LIMIT then
      self.mensagens[#self.mensagens + 1] = "O bot parou: limite de jogadas seguidas."
      self.over = true
      return
    end
    local ok, err = self.bot:act(g, self.bot_player)
    if not ok then
      self.mensagens[#self.mensagens + 1] = "O bot não conseguiu jogar: " .. tostring(err)
      self.over = true
      return
    end
  end
end

-- Eventos desde a última tela, em frases, e marca a posição.
function Partida:novidades()
  local lines = Partida.describe_events(self.g, self.last_event + 1, self.human)
  self.last_event = #self.g.events
  for _, m in ipairs(self.mensagens) do lines[#lines + 1] = m end
  self.mensagens = {}
  return lines
end

function Partida:tela()
  local lines = self:novidades()
  local texto = ""
  if #lines > 0 then texto = table.concat(lines, "\n") .. "\n\n" end
  return texto .. Tela.render(self.g, self.human)
end

function Partida:lista_jogadas()
  local lista = Jogadas.list(self.g, self.human)
  if #lista == 0 then return "Nenhuma jogada válida agora.\n" end
  local lines = { "Jogadas válidas (j <n> executa):" }
  for i, a in ipairs(lista) do lines[#lines + 1] = "  " .. i .. ". " .. Partida.describe_action(self.g, self.human, a) end
  return table.concat(lines, "\n") .. "\n"
end

-- Uma ação do motor em texto curto, no vocabulário dos comandos.
function Partida.describe_action(g, p, a)
  local function alvo(t)
    if t == nil then return "" end
    if type(t) ~= "table" then return " em c" .. tostring(t) end
    if t.zone == "jogador" then return " em " .. ((t.p == p) and "eu" or "ele") end
    local meu = t.p == p
    if t.zone == "estrutura" then return " em " .. (meu and "e" or "oe") .. t.slot end
    return " em " .. (meu and "c" or "o") .. t.slot
  end
  if a.type == "pass" then return "passar" end
  if a.type == "play" then
    local zona = { hand = "jogar ", inventory = "inv ", separated = "sep " }
    local card = g.players[p][a.from or "hand"][a.hand_index]
    local s = zona[a.from or "hand"] .. a.hand_index .. " (" .. Tela.nome(g:def_of(card) or card) .. ")"
    if a.slot then s = s .. " em " .. a.slot end
    if a.sacrifice then
      local list = {}
      for i, x in ipairs(a.sacrifice) do list[i] = "c" .. x end
      s = s .. " sacrificando " .. table.concat(list, " ")
    end
    if a.replace then s = s .. " substituindo e" .. a.replace end
    return s .. alvo(a.target)
  end
  if a.type == "attack" then
    local list = {}
    for i, x in ipairs(a.attackers) do list[i] = "c" .. x end
    return "atacar " .. table.concat(list, " ")
  end
  if a.type == "block" then
    if #a.blocks == 0 then return "bloquear nada" end
    local list = {}
    for i, b in ipairs(a.blocks) do list[i] = "o" .. b.attacker .. "=c" .. b.blocker end
    return "bloquear " .. table.concat(list, " ")
  end
  if a.type == "activate" then
    local s
    if a.structure then s = "ativar e" .. a.structure
    else s = "ativar c" .. a.creature .. (a.equip and (" " .. a.equip) or "") end
    return s .. alvo(a.target)
  end
  if a.type == "choose" then
    if a.index == 0 or a.index == nil then return "escolher nada" end
    return "escolher " .. a.index
  end
  return tostring(a.type)
end

-- Processa uma linha do humano. Devolve o texto a mostrar e se a partida acabou.
function Partida:step(linha)
  if self:acabou() then return "A partida já acabou.\n", true end
  local g = self.g
  local action, err = Comandos.parse(g, self.human, linha)
  if action == nil then return "Erro: " .. err .. "\n", false end
  if action.type == "sair" then
    self.over = true
    return "Partida encerrada.\n", true
  end
  if action.type == "ajuda" then return Comandos.help() .. "\n", false end
  if action.type == "jogadas" then return self:lista_jogadas(), false end
  local ok, why = g:act(self.human, action)
  if not ok then
    local texto = "Erro: " .. tostring(why) .. "\n"
    if g.phase == "error" then
      texto = texto .. (g.error and (tostring(g.error.message) .. "\n" .. tostring(g.error.traceback) .. "\n") or "")
      self.over = true
      return texto, true
    end
    return texto, false
  end
  self:run_bot()
  return self:tela(), self:acabou()
end

return Partida
