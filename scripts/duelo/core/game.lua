-- Motor de regras do duelo. Lua 5.1 puro, sem dependências do Don't Starve Together.
--
-- A partida é um objeto Game. Os jogadores só agem por Game:act(p, action);
-- tudo o que acontece fica registrado em Game.events, que a camada do mod
-- usa para mostrar animações e atualizar a interface.
--
-- Identificadores nos eventos: card_uid identifica a carta durante toda a partida;
-- uid identifica um objeto em campo (criatura, estrutura ou equipamento) e muda a
-- cada entrada. Eventos de objeto em campo trazem os dois; eventos de zona trazem
-- card_uid. Eventos com private = true só podem ser mostrados ao jogador p.

local Game = {}
Game.__index = Game

Game.START_LIFE = 20
-- Recuperar vida nunca passa deste valor.
Game.MAX_LIFE = 20
Game.START_HAND = 4
Game.MAX_MANA = 10
Game.HAND_LIMIT = 10
Game.DRAW_PER_ROUND = 1

-- Ações registradas por tipo. Cada handler recebe (game, player, action) e
-- devolve: ok (boolean), erro (string | nil), passa_a_vez (boolean).
Game.actions = {}

-- Validação de cada ação, sem resolver: validators[tipo](game, player, action)
-- devolve ok, erro e, para o handler, o que a validação já apurou. Cada handler
-- começa chamando a sua; Game:can_act chama só ela.
Game.validators = {}

-- Regras do próprio motor chamadas quando o período muda: hook(game, periodo).
-- Efeitos de cartas não entram aqui: usam Game:on(...), que vale só para a partida.
Game.period_hooks = {}

-- Ganchos por partida, para efeitos de cartas. Eventos:
--   "period" (g, periodo), "round_start" (g), "round_end" (g), "death" (g, criatura)
local HOOK_EVENTS = { period = true, round_start = true, round_end = true, death = true }

-- id: a carta dona do gancho, para o registro de erro.
function Game:on(event, fn, id)
  assert(HOOK_EVENTS[event], "evento de gancho desconhecido: " .. tostring(event))
  local list = self.hooks[event]
  list[#list + 1] = { fn = fn, id = id }
  return fn
end

function Game:off(event, fn)
  local list = self.hooks[event]
  for i = #list, 1, -1 do
    if list[i].fn == fn then table.remove(list, i) end
  end
end

local function has_hook(list, entry)
  for _, e in ipairs(list) do if e == entry then return true end end
  return false
end

function Game:run_hooks(event, ...)
  -- Percorre uma cópia, porque um gancho pode adicionar ou remover outros. Um
  -- gancho removido durante a passada não roda mais, e um registrado durante a
  -- passada (mesmo que seja a mesma função de novo) só roda na próxima.
  local live = self.hooks[event]
  local list = {}
  for i, entry in ipairs(live) do list[i] = entry end
  for _, entry in ipairs(list) do
    if has_hook(live, entry) then
      self:effect("gancho:" .. event, entry.id, entry.fn, self, ...)
    end
  end
end

local function other(p)
  return p == 1 and 2 or 1
end
Game.other = other

local function pack(...)
  return { n = select("#", ...), ... }
end

-- Sinal interno: a partida foi decidida por um efeito aninhado, e o resto do
-- efeito de fora não acontece. É capturado pelo efeito mais externo.
local DECIDED = {}

-- Erro capturado: guarda o valor original e o traceback do ponto onde ele
-- nasceu, uma vez só; quem relança uma captura pronta não a embrulha de novo.
local CAPTURED = {}
local function capture(e)
  if e == DECIDED then return e end
  if type(e) == "table" and getmetatable(e) == CAPTURED then return e end
  return setmetatable({ value = e, traceback = debug.traceback("", 2) }, CAPTURED)
end
Game.capture_error = capture

-- Roda código de carta marcando qual carta ou efeito está rodando, para o
-- registro de erro apontar a carta certa. O contexto anterior volta no fim e
-- também quando a partida é decidida no meio; num erro, fica o contexto mais
-- interno, o que de fato falhou.
function Game:run_card(kind, id, fn, ...)
  local prev = self.context
  self.context = { kind = kind, id = id }
  local args = pack(...)
  local r
  local ok, err = xpcall(function() r = pack(fn(unpack(args, 1, args.n))) end, capture)
  if not ok then
    if err == DECIDED then self.context = prev end
    error(err, 0)
  end
  self.context = prev
  return unpack(r, 1, r.n)
end

-- rng(n) deve devolver um inteiro entre 1 e n. O padrão usa math.random.
local function default_rng(n)
  return math.random(n)
end

local function new_player(deck, extra)
  return {
    life = Game.START_LIFE,
    deck = deck or {}, -- o topo do baralho é o último elemento
    extra = extra or {}, -- baralho extra: evoluções, invocações e cartas criadas por efeitos
    hand = {},
    discard = {},
    destroyed = {},   -- cartas destruídas: saem de jogo e não voltam (diferente do descarte)
    field = {},       -- 6 espaços de criatura
    structures = {},  -- 2 espaços de estrutura
    inventory = {},
    separated = {},   -- cartas separadas: reveladas, com marcadores, contam como mão
    mana = 0,
    max_mana = 0,
    fome = 0,         -- marcador de Fome: dano da próxima rodada com baralho vazio
    mulligan_done = false,
  }
end

-- Cópia profunda: a partida nunca altera as tabelas de quem a criou.
local function deep_copy(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = deep_copy(x) end
  return c
end

-- Copia o baralho recebido e dá a cada carta um identificador próprio desta partida.
local function copy_deck(g, deck)
  local copy = {}
  for i, card in ipairs(deck or {}) do
    local c = deep_copy(card)
    c.uid = g:next_uid()
    copy[i] = c
  end
  return copy
end

function Game.new(opts)
  opts = opts or {}
  local g = setmetatable({}, Game)
  g.rng = opts.rng or default_rng
  g.uid_counter = 0
  g.hooks = { period = {}, round_start = {}, round_end = {}, death = {} }
  -- Modificadores do limite de mão; use Game:add_hand_limit_mod.
  g.hand_limit_mods = {}
  g.players = {
    new_player(copy_deck(g, opts.decks and opts.decks[1]), copy_deck(g, opts.extra_decks and opts.extra_decks[1])),
    new_player(copy_deck(g, opts.decks and opts.decks[2]), copy_deck(g, opts.extra_decks and opts.extra_decks[2])),
  }
  g.first = opts.first or g.rng(2)
  g.use_mulligan = opts.mulligan ~= false
  g.phase = "setup" -- "setup" | "mulligan" | "playing" | "over" | "error"
  g.round = 0
  g.attacker = nil -- jogador com o token de ataque nesta rodada
  g.active = nil   -- jogador que tem a vez
  g.vez = 0        -- número da vez dentro da rodada
  g.passes = 0     -- passes seguidos
  g.winner = nil
  g.fogueira = { nil, nil }
  g.fogueira_pending = { 0, 0 }
  g.events = {}
  return g
end

function Game:emit(ev)
  self.events[#self.events + 1] = ev
end

function Game:shuffle_deck(p)
  local deck = self.players[p].deck
  for i = #deck, 2, -1 do
    local j = self.rng(i)
    deck[i], deck[j] = deck[j], deck[i]
  end
end

-- Modificador do limite de mão: fn(game, p) -> número a somar (ex.: Mochila).
-- Devolve uma função que remove o modificador (ex.: ao desequipar).
-- Cada chamada cria um registro próprio: duas Mochilas com a mesma função são dois
-- modificadores, e remover um não tira o outro.
-- id: a carta dona do modificador, para o registro de erro.
function Game:add_hand_limit_mod(fn, id)
  local mods = self.hand_limit_mods
  local entry = { fn = fn, id = id }
  mods[#mods + 1] = entry
  return function()
    for i = #mods, 1, -1 do
      if mods[i] == entry then
        table.remove(mods, i)
        return
      end
    end
  end
end

-- Limite de mão do jogador, com os modificadores ativos.
function Game:hand_limit(p)
  local n = Game.HAND_LIMIT
  for _, entry in ipairs(self.hand_limit_mods) do
    n = n + (self:run_card("limite_mao", entry.id, entry.fn, self, p) or 0)
  end
  return n
end

-- Tudo o que conta para o limite de mão: mão, Inventário e cartas separadas.
function Game:hand_count(p)
  local pl = self.players[p]
  return #pl.hand + #pl.inventory + #pl.separated
end

-- Destruir é diferente de descartar: a carta vai para a zona de destruídas e
-- não pode ser recuperada por efeitos que buscam no descarte.
function Game:destroy_card(p, card, reason)
  self:reset_card(card)
  local pl = self.players[p]
  pl.destroyed[#pl.destroyed + 1] = card
  self:emit{ t = "destroyed", p = p, card_uid = card.uid, id = card.id, reason = reason }
end

-- Limpa os marcadores que só valem numa zona (custo fixado, durabilidade, usos).
function Game:reset_card(card)
  card.cost_override = nil
  card.cost_mod = nil
  card.durability = nil
  card.used_round = nil
  card.used_period = nil
  card.arrived = nil
end

-- Coloca uma carta na mão respeitando o limite; acima dele, a carta é destruída.
-- source diz de onde ela veio ("baralho", "ficha", "campo"...). O evento traz o id
-- da carta e é privado: a camada do mod só repassa id e card_uid ao dono.
function Game:add_to_hand(p, card, source)
  -- Uma ficha só entra na mão ao ser criada; movida para a mão de outro lugar
  -- (descarte, campo), ela volta ao baralho extra.
  if card.ficha and source ~= "ficha" then return self:vanish(p, card, source) end
  if self:hand_count(p) >= self:hand_limit(p) then
    self:destroy_card(p, card, "limite_de_mao")
    return false
  end
  local pl = self.players[p]
  pl.hand[#pl.hand + 1] = card
  self:mark_arrival(card)
  self:emit{ t = "to_hand", p = p, card_uid = card.uid, id = card.id, source = source or "baralho", private = true }
  return true
end

-- Ordem de chegada às zonas que contam como mão (mão, Inventário, separadas),
-- para o fim da rodada destruir primeiro o que entrou por último.
function Game:mark_arrival(card)
  self.arrival_counter = (self.arrival_counter or 0) + 1
  card.arrived = self.arrival_counter
end

-- Cartas que passam do limite de mão, da que entrou por último para a mais
-- antiga (doc, "Limite de mão"): o limite pode baixar com cartas a mais (ex.: a
-- Mochila sai de campo). Elas ficam até o fim da rodada, e é esta a lista que o
-- jogo mostra como "serão destruídas se não forem usadas".
function Game:hand_overflow(p)
  local excess = self:hand_count(p) - self:hand_limit(p)
  if excess <= 0 then return {} end
  local pl = self.players[p]
  local all = {}
  for _, zone in ipairs({ "hand", "inventory", "separated" }) do
    for i, card in ipairs(pl[zone]) do
      all[#all + 1] = { card = card, zone = zone, index = i, order = card.arrived or 0 }
    end
  end
  table.sort(all, function(a, b)
    if a.order ~= b.order then return a.order > b.order end
    if a.zone ~= b.zone then return a.zone > b.zone end
    return a.index > b.index
  end)
  local list = {}
  for i = 1, excess do list[i] = all[i] end
  return list
end

-- Fim da rodada: destrói o que passa do limite, da mais recente para a mais
-- antiga, nessa ordem (a carta é achada pela identidade na hora de tirar).
function Game:enforce_hand_limit(p)
  local list = self:hand_overflow(p)
  for _, e in ipairs(list) do
    local zone = self.players[p][e.zone]
    for i = #zone, 1, -1 do
      if zone[i] == e.card then table.remove(zone, i); break end
    end
    self:destroy_card(p, e.card, "limite_de_mao_fim_rodada")
  end
  return #list
end

function Game:draw(p, n)
  local pl = self.players[p]
  for _ = 1, n or 1 do
    local card = table.remove(pl.deck)
    if card == nil then return end
    self:add_to_hand(p, card, "baralho")
  end
end

local function start_impl(self)
  for p = 1, 2 do
    self:shuffle_deck(p)
    self:draw(p, Game.START_HAND)
  end
  self:emit{ t = "start", first = self.first }
  if self.use_mulligan then
    self.phase = "mulligan"
    self:emit{ t = "mulligan_start" }
  else
    self.phase = "playing"
    self:begin_round()
  end
  return true
end

-- Troca inicial: cada jogador escolhe quais cartas da mão inicial devolver
-- (lista de índices, pode ser vazia). As devolvidas voltam ao baralho, que é
-- embaralhado, e o jogador compra a mesma quantidade. Uma vez por jogador.
local function mulligan_impl(self, p, indices)
  if p ~= 1 and p ~= 2 then return false, "jogador inválido" end
  if self.phase ~= "mulligan" then return false, "fora da fase de troca" end
  local pl = self.players[p]
  if pl.mulligan_done then return false, "troca já feita" end
  local chosen, back = {}, {}
  for _, i in ipairs(indices or {}) do
    if pl.hand[i] == nil or chosen[i] then return false, "índice inválido" end
    chosen[i] = true
  end
  local keep = {}
  for i, card in ipairs(pl.hand) do
    if chosen[i] then back[#back + 1] = card else keep[#keep + 1] = card end
  end
  pl.hand = keep
  for _, card in ipairs(back) do pl.deck[#pl.deck + 1] = card end
  self:shuffle_deck(p)
  self:draw(p, #back)
  pl.mulligan_done = true
  self:emit{ t = "mulligan", p = p, count = #back }
  if self.players[1].mulligan_done and self.players[2].mulligan_done then
    self.phase = "playing"
    self:begin_round()
  end
  return true
end

-- Início da rodada para cada jogador: Fome (se o baralho estiver vazio), mana e compra.
function Game:round_upkeep(p)
  local pl = self.players[p]
  if #pl.deck == 0 then
    pl.fome = pl.fome + 1
    pl.life = pl.life - pl.fome
    self:emit{ t = "player_damage", p = p, amount = pl.fome, source = "fome", life = pl.life }
  end
  pl.max_mana = math.min(Game.MAX_MANA, self.round)
  pl.mana = pl.max_mana
  self:emit{ t = "mana", p = p, mana = pl.mana, max = pl.max_mana }
  self:draw(p, Game.DRAW_PER_ROUND)
end

function Game:can_pay_mana(p, cost)
  return self.players[p].mana >= (cost or 0)
end

function Game:spend_mana(p, cost)
  local pl = self.players[p]
  pl.mana = pl.mana - (cost or 0)
  self:emit{ t = "mana", p = p, mana = pl.mana, max = pl.max_mana }
end

-- Período pela vez: vezes 1 e 2 de manhã, 3 e 4 à tarde, da 5 em diante à noite.
-- O combate acontece dentro de uma única vez, então o período não avança no meio dele.
function Game.period_of(vez)
  if vez <= 2 then return "manha" elseif vez <= 4 then return "tarde" end
  return "noite"
end

function Game:period()
  return Game.period_of(self.vez)
end

function Game:update_period()
  local per = self:period()
  if per ~= self.current_period then
    self.current_period = per
    self:emit{ t = "period", period = per, round = self.round }
    -- A vida pode mudar com o período (atributos que dependem dele): o estado
    -- estabiliza antes dos ganchos do novo período.
    self:settle()
    -- Se uma morte abrir uma escolha, os ganchos do período esperam por ela.
    self:after_choices(function(g)
      for _, hook in ipairs(Game.period_hooks) do g:effect("regra", per, hook, g, per) end
      g:run_hooks("period", per)
    end)
  end
end

----------------------------------------------------------------------------
-- Fogueira
----------------------------------------------------------------------------

Game.FOGUEIRA_START = 3
Game.FOGUEIRA_DAMAGE = 2

-- Ações que continuam permitidas com a fogueira em zero: passar, atacar e ativar efeitos.
-- Bloquear faz parte de responder a um ataque e escolher completa um efeito já pago.
-- "play" passa por aqui e a jogada confere a carta: só as que não gastam fogueira
-- (Turfs, Gosma) podem ser jogadas com o contador em zero.
Game.allowed_at_zero_fogueira = { pass = true, attack = true, activate = true, choose = true, block = true, play = true }

-- Acende quando a noite começa, com o valor inicial mais os bônus guardados na rodada.
function Game:light_fogueira()
  for p = 1, 2 do
    self.fogueira[p] = Game.FOGUEIRA_START + self.fogueira_pending[p]
    self.fogueira_pending[p] = 0
    self:emit{ t = "fogueira", p = p, value = self.fogueira[p], reason = "acendeu" }
  end
end

table.insert(Game.period_hooks, function(g, per)
  if per == "noite" then g:light_fogueira() end
end)

function Game:is_night_lit()
  return self.fogueira[1] ~= nil
end

-- Bônus de fogueira (ex.: Machado). De dia, fica guardado para quando a noite começar;
-- à noite, soma na hora.
function Game:fogueira_bonus(p, n)
  if self:is_night_lit() then
    self.fogueira[p] = self.fogueira[p] + n
    self:emit{ t = "fogueira", p = p, value = self.fogueira[p], reason = "bonus" }
  else
    self.fogueira_pending[p] = self.fogueira_pending[p] + n
  end
end

-- Carta jogada à noite gasta 1. De dia, não custa nada.
function Game:can_pay_fogueira(p)
  if not self:is_night_lit() then return true end
  return self.fogueira[p] > 0
end

function Game:spend_fogueira(p)
  if not self:is_night_lit() then return end
  self.fogueira[p] = self.fogueira[p] - 1
  self:emit{ t = "fogueira", p = p, value = self.fogueira[p], reason = "carta" }
end

----------------------------------------------------------------------------
-- Vida dos jogadores
----------------------------------------------------------------------------

-- Um efeito é uma ação só (doc, "Vitória e empate"): todo dano que ele causa aos
-- jogadores conta junto, e a vitória é verificada no fim dele. Se o mesmo efeito
-- deixar os dois jogadores com zero ou menos, é empate. Efeitos diferentes contam
-- separadamente: um efeito que começa quando algum jogador já está com zero ou
-- menos (a partida está decidida) não acontece. Efeitos aninhados (a morte
-- causada por um feitiço) são efeitos próprios e decidem no fim deles.

-- Enquanto um efeito roda, um jogador com zero ou menos de vida (ainda que por um
-- instante) faz os efeitos aninhados que começarem nesse intervalo não
-- acontecerem: a partida está sendo decidida por este efeito.
function Game:as_one_effect(fn, ...)
  if self.winner ~= nil then return end
  if self.players[1].life <= 0 or self.players[2].life <= 0 then return end
  local args = { n = select("#", ...), ... }
  self.effect_depth = (self.effect_depth or 0) + 1
  local ok, err = xpcall(function() fn(unpack(args, 1, args.n)) end, capture)
  self.effect_depth = self.effect_depth - 1
  -- Erro de carta: a partida termina com estado de erro, sem vencedor.
  if not ok and err ~= DECIDED then error(err, 0) end
  if ok then self:check_winner() end
  -- Partida decidida: o efeito de fora, se houver, para aqui.
  if self.winner ~= nil and self.effect_depth > 0 then error(DECIDED, 0) end
end

-- Efeito de carta: marca o contexto (qual carta roda, para o registro de erro) e
-- trata o efeito como uma ação própria para a vitória.
function Game:effect(kind, id, fn, ...)
  return self:run_card(kind, id, Game.as_one_effect, self, fn, ...)
end

function Game:check_winner()
  if self.winner ~= nil then return end
  local dead1 = self.players[1].life <= 0
  local dead2 = self.players[2].life <= 0
  if dead1 and dead2 then
    self.winner = 0 -- empate
  elseif dead1 then
    self.winner = 2
  elseif dead2 then
    self.winner = 1
  end
  if self.winner ~= nil then
    self.phase = "over"
    self:emit{ t = "game_over", winner = self.winner }
  end
end

-- source: motivo do dano ("combate", "fogueira", ...). opts.from: a criatura que
-- causou o dano, quando houver (para efeitos que interceptam dano de criatura,
-- como o Porco guarda). opts.no_check adia a verificação de vitória, para danos
-- simultâneos poderem terminar em empate.
-- Devolve o dano aplicado (0 se nenhum).
function Game:damage_player(p, n, source, opts)
  if Game.check_amount(n) <= 0 then return 0 end
  opts = opts or {}
  local pl = self.players[p]
  pl.life = pl.life - n
  self:emit{ t = "player_damage", p = p, amount = n, source = source, life = pl.life,
    from_uid = opts.from and opts.from.uid or nil }
  -- Dentro de um efeito, a vitória é verificada no fim dele.
  if not opts.no_check and (self.effect_depth or 0) == 0 then self:check_winner() end
  return n
end

-- Quantidade de dano ou de cura: número inteiro. Outro valor é erro da carta que
-- pediu (vira o estado de erro da partida, em vez de corromper vida ou dano).
-- Nível 3: a posição do erro é a de quem chamou damage_* ou heal_*; vindo do
-- combate, é Game:strike, e a carta aparece no traceback e no contexto do erro.
function Game.check_amount(n)
  if type(n) ~= "number" or n ~= n or n % 1 ~= 0 then
    error("quantidade inválida: " .. tostring(n), 3)
  end
  return n
end

-- Recupera vida do jogador, até Game.MAX_LIFE. Devolve o quanto recuperou (0 se
-- nada). Com a partida decidida, não recupera. Dentro de um efeito, recuperar
-- depois de um dano letal do mesmo efeito salva o jogador: a vitória é
-- verificada no fim do efeito.
function Game:heal_player(p, n, source)
  if Game.check_amount(n) <= 0 or self.winner ~= nil then return 0 end
  local pl = self.players[p]
  local amount = math.min(n, Game.MAX_LIFE - pl.life)
  if amount <= 0 then return 0 end
  pl.life = pl.life + amount
  self:emit{ t = "player_heal", p = p, amount = amount, source = source, life = pl.life }
  return amount
end

----------------------------------------------------------------------------
-- Rodada
----------------------------------------------------------------------------

function Game:begin_round()
  self.round = self.round + 1
  self.fogueira = { nil, nil }
  self.fogueira_pending = { 0, 0 }
  self.fogueira_no_damage = false -- ex.: Lua cheia
  if self.round == 1 then
    self.attacker = self.first
  else
    self.attacker = other(self.attacker)
  end
  self.active = self.attacker
  self.vez = 1
  self.passes = 0
  self.current_period = nil
  self:emit{ t = "round_start", round = self.round, attacker = self.attacker }
  for p = 1, 2 do self:round_upkeep(p) end
  self:check_winner()
  if self.winner ~= nil then return end
  self:run_hooks("round_start")
  -- Um gancho de início de rodada pode abrir escolhas; a manhã só começa depois.
  self:after_choices(function(g) g:update_period() end)
end

function Game:end_round()
  self:run_hooks("round_end")
  -- Um gancho de fim de rodada pode abrir escolhas; a rodada só termina depois.
  self:after_choices(function(g) g:finish_round() end)
end

function Game:finish_round()
  -- Terminar a rodada à noite com a fogueira em zero causa dano. As duas
  -- verificações acontecem antes de decidir o vencedor, para um empate ser possível.
  if self:is_night_lit() and not self.fogueira_no_damage then
    for p = 1, 2 do
      if self.fogueira[p] <= 0 then
        local pl = self.players[p]
        pl.life = pl.life - Game.FOGUEIRA_DAMAGE
        self:emit{ t = "player_damage", p = p, amount = Game.FOGUEIRA_DAMAGE, source = "fogueira", life = pl.life }
      end
    end
    self:check_winner()
  end
  self:emit{ t = "round_end", round = self.round }
  if self.winner == nil then
    -- A rodada nova começa com o estado estável: se uma morte do fim da rodada
    -- abrir uma escolha, a rodada nova só começa depois dela. O limite de mão
    -- vale sobre esse estado estável, logo antes da rodada nova.
    self:settle()
    self:after_choices(function(g)
      if g.winner ~= nil then return end
      for p = 1, 2 do g:enforce_hand_limit(p) end
      g:begin_round()
    end)
  end
end

-- Roda fn agora se não houver escolha aberta; senão, quando a última for feita.
-- opts.keeps_turn_flow = true: a continuação faz parte da jogada e não cuida da
-- vez (ex.: a criatura que entra depois do sacrifício); a vez segue a decisão da
-- jogada que abriu a escolha. Sem isso, a continuação cuida da vez (ex.: a
-- rodada que avança).
function Game:after_choices(fn, opts)
  if not self:choices_waiting() then return fn(self) end
  self.choice_continuations = self.choice_continuations or {}
  -- Guarda quem pediu, para o registro de erro apontar a mesma carta quando a
  -- continuação rodar depois.
  table.insert(self.choice_continuations, { fn = fn, context = self.context,
    keeps_turn_flow = opts and opts.keeps_turn_flow or false })
end

function Game:advance_vez()
  self.vez = self.vez + 1
  self.active = other(self.active)
  self:emit{ t = "vez", vez = self.vez, active = self.active }
  self:update_period()
end

-- Verificações comuns a toda jogada, antes do handler: fase, vez, escolha
-- pendente, fogueira apagada e pilha aberta. Não muda nada.
local function check_action(self, p, action)
  if self.winner ~= nil then return false, "partida encerrada" end
  if self.phase ~= "playing" then return false, "a partida ainda não começou" end
  if type(action) ~= "table" or action.type == nil then return false, "ação inválida" end
  -- Uma escolha aberta só aceita a ação "choose" de quem escolhe, mesmo fora da vez.
  if self.pending_choice then
    if action.type ~= "choose" then return false, "há uma escolha pendente" end
    if p ~= self.pending_choice.player then return false, "a escolha é do outro jogador" end
  elseif p ~= self.active then
    return false, "não é a sua vez"
  end
  if action.type == "pass" then return true end
  if Game.actions[action.type] == nil then return false, "ação desconhecida: " .. tostring(action.type) end
  if self:is_night_lit() and self.fogueira[p] <= 0 and not Game.allowed_at_zero_fogueira[action.type] then
    return false, "fogueira apagada: só é possível passar, atacar ou ativar efeitos"
  end
  if self:stack_open() and not Game.allowed_with_stack[action.type] then
    return false, "com a pilha aberta, só Rápidos e Instantâneos"
  end
  return true
end

-- Jogada sem proteção; use Game:act.
local function act_impl(self, p, action)
  self.context = nil
  local ok, err = check_action(self, p, action)
  if not ok then return false, err end

  if action.type == "pass" and self:stack_open() then
    self:stack_pass(p)
    return true
  end

  if action.type == "pass" then
    self.passes = self.passes + 1
    self:emit{ t = "pass", p = p }
    if self.passes >= 2 then
      self:end_round()
    else
      self:advance_vez()
    end
    return true
  end

  local handler = Game.actions[action.type]
  local passes_turn
  ok, err, passes_turn = handler(self, p, action)
  -- O contexto da ação termina com o handler; o que vem depois (vez, período)
  -- é do motor, não da carta.
  self.context = nil
  if not ok then return false, err end
  -- Escolher completa um efeito que já aconteceu; não é uma jogada nova e não
  -- interrompe dois passes seguidos.
  if action.type ~= "choose" then self.passes = 0 end
  -- Um efeito que abriu uma escolha segura a vez até ela ser feita.
  if self.pending_choice and self.pending_choice.passes_turn == nil then
    self.pending_choice.passes_turn = passes_turn ~= false
    return true
  end
  if passes_turn ~= false and self.winner == nil and not self:stack_open() then
    self:advance_vez()
  end
  return true
end

-- Ações aceitas com a pilha aberta; cada uma confere o tipo do efeito.
Game.allowed_with_stack = { play = true, activate = true, choose = true, block = true }

----------------------------------------------------------------------------
-- Entradas protegidas
----------------------------------------------------------------------------

-- Erro no código de uma carta é bug da carta. Em vez de tentar recuperar a
-- partida, o motor a encerra com estado de erro: guarda a mensagem, o traceback
-- e o contexto (qual carta ou efeito rodava) e não aceita mais nenhuma ação.

-- Somente start, mulligan e act são a interface pública do motor. As outras
-- funções (create_token, kill, set_choice...) são usadas pelas cartas, sempre
-- dentro de uma dessas entradas protegidas.

local function error_message(err)
  if type(err) == "string" then return err end
  -- Erro em tabela: usa err.message, se houver; nunca o endereço da tabela, para
  -- o log de eventos continuar igual entre execuções.
  if type(err) == "table" and type(err.message) == "string" then return err.message end
  return "erro do tipo " .. type(err)
end

-- Diz se a jogada seria aceita agora, sem fazê-la: roda só as verificações de
-- Game:act e a validação do handler, sem resolver nada, emitir eventos ou mudar
-- o estado. Devolve ok, erro, como Game:act. Um erro de carta durante a
-- validação não encerra a partida: a jogada é dada como inválida.
function Game:can_act(p, action)
  if self.phase == "error" then return false, "partida encerrada por erro" end
  local ok, err = check_action(self, p, action)
  if not ok then return false, err end
  if action.type == "pass" then return true end
  local validate = Game.validators[action.type]
  if validate == nil then return false, "ação sem validação: " .. tostring(action.type) end
  -- A validação marca o contexto da jogada; aqui ele volta ao que era.
  local prev = self.context
  local results
  local ran, captured = xpcall(function() results = pack(validate(self, p, action)) end, capture)
  self.context = prev
  if not ran then return false, "erro na validação: " .. error_message(captured.value) end
  if not results[1] then return false, results[2] end
  return true
end

function Game:fail(captured)
  -- self.error é preenchido antes de qualquer coisa que possa falhar.
  self.phase = "error"
  self.effect_depth = 0
  self.error = {
    value = captured.value,
    message = error_message(captured.value),
    traceback = captured.traceback,
    context = self.context,
  }
  pcall(self.emit, self, { t = "engine_error", context = self.context, message = self.error.message })
end

function Game:guarded(fn, ...)
  if self.phase == "error" then return false, "partida encerrada por erro" end
  local args = pack(...)
  local results
  local ok, captured = xpcall(function() results = pack(fn(self, unpack(args, 1, args.n))) end, capture)
  if not ok then
    self:fail(captured)
    return false, "erro no motor: partida encerrada"
  end
  return unpack(results, 1, results.n)
end

-- Depois de cada entrada, o motor chega a um estado estável (Game:settle).
local function settled_call(self, core, ...)
  local r = pack(core(self, ...))
  self:settle()
  return unpack(r, 1, r.n)
end

function Game:start()
  return self:guarded(settled_call, start_impl)
end

function Game:mulligan(p, indices)
  return self:guarded(settled_call, mulligan_impl, p, indices)
end

-- Ponto único de entrada das jogadas.
function Game:act(p, action)
  return self:guarded(settled_call, act_impl, p, action)
end

require("duelo/core/pilha")(Game)
require("duelo/core/jogar")(Game)
require("duelo/core/estruturas")(Game)
require("duelo/core/equipamentos")(Game)
require("duelo/core/fichas")(Game)
require("duelo/core/combate")(Game)

return Game
