-- Jogar cartas e manter criaturas em campo. Lua 5.1 puro.
-- Instala os métodos no Game: require("duelo/core/jogar")(Game)

local Cards = require("duelo/core/cards")

return function(Game)
  Game.FIELD_SLOTS = 6

  -- Como cada tipo de carta é jogado: validate(g, p, card, def, action) -> ok, erro
  -- e resolve(g, p, card, def, action). Os tipos são preenchidos pelas US de cada um.
  Game.play_rules = Game.play_rules or {}

  function Game:next_uid()
    self.uid_counter = (self.uid_counter or 0) + 1
    return self.uid_counter
  end

  function Game:def_of(card)
    return Cards.get(card.id)
  end

  -- Custo atual da carta: um custo fixado por efeito (ex.: Sapo, Inventário) vale
  -- no lugar do impresso, e modificadores somam por cima.
  function Game:card_cost(p, card)
    local def = self:def_of(card)
    local cost = card.cost_override or def.cost
    cost = cost + (card.cost_mod or 0)
    if cost < 0 then cost = 0 end
    return cost
  end

  ----------------------------------------------------------------------------
  -- Campo
  ----------------------------------------------------------------------------

  function Game:creature_at(p, slot)
    return self.players[p].field[slot]
  end

  function Game:free_slots(p)
    local list = {}
    for s = 1, Game.FIELD_SLOTS do
      if self.players[p].field[s] == nil then list[#list + 1] = s end
    end
    return list
  end

  function Game:creatures(p)
    local list = {}
    for s = 1, Game.FIELD_SLOTS do
      local c = self.players[p].field[s]
      if c then list[#list + 1] = c end
    end
    return list
  end

  -- Todas as criaturas em campo, começando pelo jogador com o token de ataque.
  function Game:all_creatures()
    local list = {}
    local first = self.attacker or 1
    for _, p in ipairs({ first, Game.other(first) }) do
      for _, c in ipairs(self:creatures(p)) do list[#list + 1] = c end
    end
    return list
  end

  -- Ataque e vida atuais. Cartas com atributos que dependem do estado (ex.: Morcego)
  -- definem stats(game, criatura). Bônus de equipamentos e efeitos somam por cima.
  function Game:atk(c)
    local base = c.def.atk or 0
    if c.def.stats then base = (c.def.stats(self, c)) end
    local v = base + (c.atk_bonus or 0)
    if v < 0 then v = 0 end
    return v
  end

  function Game:hp(c)
    local base = c.def.hp or 0
    if c.def.stats then local _, h = c.def.stats(self, c); base = h end
    return base + (c.hp_bonus or 0)
  end

  -- Coloca uma criatura em campo. opts.ficha marca criaturas criadas por efeito.
  -- Dispara o efeito de entrada da própria carta e as reações das outras.
  function Game:place_creature(p, card, slot, opts)
    opts = opts or {}
    local def = self:def_of(card)
    local c = {
      uid = card.uid or self:next_uid(),
      card = card,
      def = def,
      owner = p,
      slot = slot,
      damage = 0,
      equips = {},
      entered_round = self.round,
      ficha = opts.ficha or card.ficha or false,
    }
    self.players[p].field[slot] = c
    self:emit{ t = "summon", p = p, slot = slot, uid = c.uid, id = def.id, ficha = c.ficha }
    if def.on_play then def.on_play(self, c) end
    for _, other in ipairs(self:all_creatures()) do
      if other ~= c and other.def.on_any_enter and self.players[other.owner].field[other.slot] == other then
        other.def.on_any_enter(self, other, c)
      end
    end
    return c
  end

  ----------------------------------------------------------------------------
  -- Jogar uma carta da mão
  ----------------------------------------------------------------------------

  -- action = { type = "play", hand_index = n, ... campos de cada tipo ... }
  Game.actions.play = function(g, p, action)
    local pl = g.players[p]
    local card = pl.hand[action.hand_index or -1]
    if card == nil then return false, "carta não está na mão" end
    local def = g:def_of(card)
    if def == nil then return false, "carta desconhecida: " .. tostring(card.id) end
    local rule = Game.play_rules[def.kind]
    if rule == nil then return false, "tipo de carta ainda não suportado: " .. tostring(def.kind) end

    local cost = g:card_cost(p, card)
    if not g:can_pay_mana(p, cost) then return false, "mana insuficiente" end
    local uses_fogueira = not def.no_fogueira
    if uses_fogueira and not g:can_pay_fogueira(p) then return false, "fogueira apagada" end
    local ok, err = rule.validate(g, p, card, def, action)
    if not ok then return false, err end

    table.remove(pl.hand, action.hand_index)
    g:spend_mana(p, cost)
    if uses_fogueira then g:spend_fogueira(p) end
    g:emit{ t = "play", p = p, id = def.id, cost = cost }
    rule.resolve(g, p, card, def, action)
    return true, nil, not def.keeps_turn
  end

  ----------------------------------------------------------------------------
  -- Criaturas
  ----------------------------------------------------------------------------

  Game.play_rules.criatura = {
    -- action.slot: espaço livre de 1 a 6
    validate = function(g, p, card, def, action)
      local s = action.slot
      if type(s) ~= "number" or s < 1 or s > Game.FIELD_SLOTS or s % 1 ~= 0 then
        return false, "espaço inválido"
      end
      if g.players[p].field[s] ~= nil then return false, "espaço ocupado" end
      if def.can_play and not def.can_play(g, p, action) then return false, "condição da carta não atendida" end
      return true
    end,
    resolve = function(g, p, card, def, action)
      g:place_creature(p, card, action.slot)
    end,
  }
end
