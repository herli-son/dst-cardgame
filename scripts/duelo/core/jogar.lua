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
    if c.def.stats then
      local a = c.def.stats(self, c)
      if a ~= nil then base = a end
    end
    local v = base + (c.atk_bonus or 0) + (self.equip_bonus and self:equip_bonus(c, "atk_bonus") or 0)
    if v < 0 then v = 0 end
    return v
  end

  function Game:hp(c)
    local base = c.def.hp or 0
    if c.def.stats then
      local _, h = c.def.stats(self, c)
      if h ~= nil then base = h end
    end
    return base + (c.hp_bonus or 0) + (self.equip_bonus and self:equip_bonus(c, "hp_bonus") or 0)
  end

  -- Coloca uma criatura em campo. opts.ficha marca criaturas criadas por efeito.
  -- Dispara o efeito de entrada da própria carta e as reações das outras.
  function Game:place_creature(p, card, slot, opts)
    opts = opts or {}
    local def = self:def_of(card)
    -- Cada entrada em campo é uma instância nova, com uid próprio: uma carta que
    -- sai e volta não é mais o mesmo alvo.
    local c = {
      uid = self:next_uid(),
      card_uid = card.uid,
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
    self:emit{ t = "summon", p = p, slot = slot, uid = c.uid, card_uid = c.card_uid, id = def.id, ficha = c.ficha }
    if def.on_play then def.on_play(self, c) end
    for _, other in ipairs(self:all_creatures()) do
      if other ~= c and other.def.on_any_enter and self.players[other.owner].field[other.slot] == other then
        other.def.on_any_enter(self, other, c)
      end
    end
    return c
  end

  function Game:find_creature(uid)
    for p = 1, 2 do
      for s = 1, Game.FIELD_SLOTS do
        local c = self.players[p].field[s]
        if c and c.uid == uid then return c end
      end
    end
  end

  ----------------------------------------------------------------------------
  -- Alvos
  ----------------------------------------------------------------------------

  -- Alvos são escritos como { p = jogador, slot = espaço, zone = "criatura" | "estrutura" }
  -- (zone padrão: "criatura"), ou { p = jogador, zone = "jogador" } para mirar o
  -- próprio jogador, em action.target ou na lista action.targets.
  -- O formato é conferido antes de qualquer gasto. Na jogada, o motor trava o uid de
  -- cada alvo; ao resolver, o alvo só vale se aquele mesmo objeto continuar em campo.
  local ZONE_SLOTS = { criatura = "FIELD_SLOTS", estrutura = "STRUCTURE_SLOTS" }

  local function each_target(action, fn)
    if action.target ~= nil then fn(action.target) end
    if action.targets ~= nil then
      if type(action.targets) ~= "table" then return fn(action.targets) end
      for _, t in ipairs(action.targets) do fn(t) end
    end
  end

  local function object_at(g, t)
    local zone = t.zone or "criatura"
    if zone == "jogador" then return g.players[t.p] end
    if zone == "estrutura" then return g:structure_at(t.p, t.slot) end
    return g:creature_at(t.p, t.slot)
  end

  function Game:check_targets(action)
    local err
    each_target(action, function(t)
      if err then return end
      if type(t) ~= "table" then err = "alvo inválido"; return end
      local zone = t.zone or "criatura"
      if zone == "jogador" then
        if t.p ~= 1 and t.p ~= 2 then err = "jogador do alvo inválido" end
        return
      end
      local max = ZONE_SLOTS[zone] and Game[ZONE_SLOTS[zone]]
      if max == nil then err = "zona de alvo inválida"; return end
      if t.p ~= 1 and t.p ~= 2 then err = "jogador do alvo inválido"; return end
      if type(t.slot) ~= "number" or t.slot % 1 ~= 0 or t.slot < 1 or t.slot > max then
        err = "espaço do alvo inválido"
        return
      end
      -- O alvo precisa existir na jogada; "alvo perdido" vale só para o que sai depois.
      if object_at(self, t) == nil then err = "não há alvo nesse espaço" end
    end)
    if err then return false, err end
    return true
  end

  -- Devolve as travas { {zone, uid}, ... } dos alvos; ficam com o efeito na pilha,
  -- não na ação enviada pelo jogador.
  function Game:lock_targets(action)
    local locks = {}
    each_target(action, function(t)
      local zone = t.zone or "criatura"
      if zone == "jogador" then
        -- Jogadores não saem de jogo: o alvo sempre vale.
        locks[#locks + 1] = { zone = zone, p = t.p }
      else
        local o = object_at(self, t)
        locks[#locks + 1] = { zone = zone, uid = o and o.uid or nil }
      end
    end)
    return locks
  end

  function Game:find_structure(uid)
    for p = 1, 2 do
      for s = 1, Game.STRUCTURE_SLOTS do
        local st = self.players[p].structures[s]
        if st and st.uid == uid then return st end
      end
    end
  end

  -- Cada alvo travado precisa continuar em campo, onde quer que esteja agora.
  -- A busca é pelo uid, não pelo espaço, porque haverá cartas que trocam criaturas
  -- de posição e o alvo deve continuar o mesmo. Devolve ok e a lista de objetos
  -- (criatura, estrutura ou jogador), na ordem dos alvos. Os efeitos recebem essa
  -- lista e devem usá-la, não o espaço escrito na ação.
  function Game:targets_still_valid(locks)
    local objects = {}
    for i, l in ipairs(locks) do
      if l.zone == "jogador" then
        objects[i] = { player = l.p }
      else
        if l.uid == nil then return false end
        local found
        if l.zone == "estrutura" then found = self:find_structure(l.uid) else found = self:find_creature(l.uid) end
        if found == nil then return false end
        objects[i] = found
      end
    end
    return true, objects
  end

  ----------------------------------------------------------------------------
  -- Jogar uma carta da mão
  ----------------------------------------------------------------------------

  -- Zonas de onde se joga: todas contam como mão.
  Game.PLAYABLE_ZONES = { hand = "hand", inventory = "inventory", separated = "separated" }

  -- action = { type = "play", hand_index = n, from = "hand" | "inventory" | "separated", ... }
  Game.actions.play = function(g, p, action)
    local pl = g.players[p]
    local zone_name = Game.PLAYABLE_ZONES[action.from or "hand"]
    if zone_name == nil then return false, "origem inválida" end
    local zone = pl[zone_name]
    local card = zone[action.hand_index or -1]
    if card == nil then return false, "carta não está na mão" end
    local def = g:def_of(card)
    if def == nil then return false, "carta desconhecida: " .. tostring(card.id) end
    local rule = Game.play_rules[def.kind]
    if rule == nil then return false, "tipo de carta ainda não suportado: " .. tostring(def.kind) end
    if g:stack_open() and not (rule.allowed_in_stack and rule.allowed_in_stack(g, def)) then
      return false, "com a pilha aberta, só Rápidos e Instantâneos"
    end

    local cost = g:card_cost(p, card)
    if not g:can_pay_mana(p, cost) then return false, "mana insuficiente" end
    local uses_fogueira = not def.no_fogueira
    if uses_fogueira and not g:can_pay_fogueira(p) then return false, "fogueira apagada" end
    local ok, err = rule.validate(g, p, card, def, action)
    if not ok then return false, err end

    table.remove(zone, action.hand_index)
    -- Custo fixado ou alterado por zona (Sapo, Inventário) não acompanha a carta.
    card.cost_override, card.cost_mod = nil, nil
    g:spend_mana(p, cost)
    if uses_fogueira then g:spend_fogueira(p) end
    g:emit{ t = "play", p = p, card_uid = card.uid, id = def.id, cost = cost }
    local passes = rule.resolve(g, p, card, def, action)
    if passes == nil then passes = not def.keeps_turn end
    return true, nil, passes
  end

  ----------------------------------------------------------------------------
  -- Feitiços
  ----------------------------------------------------------------------------

  -- Manda a carta usada para o descarte; fichas deixam de existir.
  function Game:to_discard(p, card)
    if card.ficha then return self:vanish(p, card, "descarte") end
    self:reset_card(card)
    local d = self.players[p].discard
    d[#d + 1] = card
  end

  Game.play_rules.feitico = {
    allowed_in_stack = function(g, def) return def.speed ~= "lento" end,
    -- Os alvos ficam na própria ação (action.target, action.targets...) e a carta os confere.
    validate = function(g, p, card, def, action)
      local ok, err = g:can_use_speed(def.speed)
      if not ok then return false, err end
      ok, err = g:check_targets(action)
      if not ok then return false, err end
      if def.targets then
        local valid, why = def.targets(g, p, action)
        if not valid then return false, why or "alvo inválido" end
      end
      return true
    end,
    resolve = function(g, p, card, def, action)
      local locks = g:lock_targets(action)
      return g:use_speed(p, def.speed, def.id, function(gg)
        -- Alvo perdido: se o alvo saiu de campo até a resolução, o feitiço não acontece.
        local valid, objects = gg:targets_still_valid(locks)
        if valid and def.targets then valid = def.targets(gg, p, action, objects) end
        if valid then
          def.on_cast(gg, p, action, card, objects)
        else
          gg:emit{ t = "fizzle", p = p, id = def.id }
        end
        gg:to_discard(p, card)
      end)
    end,
  }

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
