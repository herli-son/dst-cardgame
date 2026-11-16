-- Motor de regras do duelo. Lua 5.1 puro, sem dependências do Don't Starve Together.
--
-- A partida é um objeto Game. Os jogadores só agem por Game:act(p, action);
-- tudo o que acontece fica registrado em Game.events, que a camada do mod
-- usa para mostrar animações e atualizar a interface.

local Game = {}
Game.__index = Game

Game.START_LIFE = 20
Game.START_HAND = 4

-- Ações registradas por tipo. Cada handler recebe (game, player, action) e
-- devolve: ok (boolean), erro (string | nil), passa_a_vez (boolean).
Game.actions = {}

-- Funções chamadas quando o período muda: hook(game, periodo).
Game.period_hooks = {}

local function other(p)
  return p == 1 and 2 or 1
end
Game.other = other

-- rng(n) deve devolver um inteiro entre 1 e n. O padrão usa math.random.
local function default_rng(n)
  return math.random(n)
end

local function new_player(deck)
  return {
    life = Game.START_LIFE,
    deck = deck or {}, -- o topo do baralho é o último elemento
    hand = {},
    discard = {},
    field = {},       -- 6 espaços de criatura
    structures = {},  -- 2 espaços de estrutura
    inventory = {},
  }
end

function Game.new(opts)
  opts = opts or {}
  local g = setmetatable({}, Game)
  g.rng = opts.rng or default_rng
  g.players = { new_player(opts.decks and opts.decks[1]), new_player(opts.decks and opts.decks[2]) }
  g.first = opts.first or g.rng(2)
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

function Game:draw(p, n)
  local pl = self.players[p]
  for _ = 1, n or 1 do
    local card = table.remove(pl.deck)
    if card == nil then return end
    pl.hand[#pl.hand + 1] = card
    self:emit{ t = "draw", p = p }
  end
end

function Game:start()
  for p = 1, 2 do
    self:shuffle_deck(p)
    self:draw(p, Game.START_HAND)
  end
  self:emit{ t = "start", first = self.first }
  self:begin_round()
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
    for _, hook in ipairs(Game.period_hooks) do hook(self, per) end
  end
end

----------------------------------------------------------------------------
-- Fogueira
----------------------------------------------------------------------------

Game.FOGUEIRA_START = 3
Game.FOGUEIRA_DAMAGE = 2

-- Ações que continuam permitidas com a fogueira em zero: passar, atacar e ativar efeitos.
Game.allowed_at_zero_fogueira = { pass = true, attack = true, activate = true }

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
  if self.winner ~= nil then self:emit{ t = "game_over", winner = self.winner } end
end

function Game:damage_player(p, n, source)
  if n <= 0 then return end
  local pl = self.players[p]
  pl.life = pl.life - n
  self:emit{ t = "player_damage", p = p, amount = n, source = source, life = pl.life }
  self:check_winner()
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
  self:update_period()
end

function Game:end_round()
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
    self:begin_round()
  end
end

function Game:advance_vez()
  self.vez = self.vez + 1
  self.active = other(self.active)
  self:emit{ t = "vez", vez = self.vez, active = self.active }
  self:update_period()
end

-- Ponto único de entrada das jogadas.
function Game:act(p, action)
  if self.winner ~= nil then return false, "partida encerrada" end
  if p ~= self.active then return false, "não é a sua vez" end
  if type(action) ~= "table" or action.type == nil then return false, "ação inválida" end

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
  if handler == nil then return false, "ação desconhecida: " .. tostring(action.type) end
  if self:is_night_lit() and self.fogueira[p] <= 0 and not Game.allowed_at_zero_fogueira[action.type] then
    return false, "fogueira apagada: só é possível passar, atacar ou ativar efeitos"
  end
  local ok, err, passes_turn = handler(self, p, action)
  if not ok then return false, err end
  self.passes = 0
  if passes_turn ~= false and self.winner == nil then
    self:advance_vez()
  end
  return true
end

return Game
