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

function Game:begin_round()
  self.round = self.round + 1
  if self.round == 1 then
    self.attacker = self.first
  else
    self.attacker = other(self.attacker)
  end
  self.active = self.attacker
  self.vez = 1
  self.passes = 0
  self:emit{ t = "round_start", round = self.round, attacker = self.attacker }
end

function Game:end_round()
  self:emit{ t = "round_end", round = self.round }
  if self.winner == nil then
    self:begin_round()
  end
end

function Game:advance_vez()
  self.vez = self.vez + 1
  self.active = other(self.active)
  self:emit{ t = "vez", vez = self.vez, active = self.active }
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
  local ok, err, passes_turn = handler(self, p, action)
  if not ok then return false, err end
  self.passes = 0
  if passes_turn ~= false and self.winner == nil then
    self:advance_vez()
  end
  return true
end

return Game
