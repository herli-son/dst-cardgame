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
      local a = self:run_card("atributos", c.def.id, c.def.stats, self, c)
      if a ~= nil then base = a end
    end
    local v = base + (c.atk_bonus or 0) + (self.equip_bonus and self:equip_bonus(c, "atk_bonus") or 0)
    if v < 0 then v = 0 end
    return v
  end

  -- Vida: base (ou stats), bônus da própria criatura, dos equipamentos e das
  -- auras (aura_hp) das criaturas em campo do mesmo dono, a própria inclusa.
  -- A vida máxima é sempre recalculada: quando a fonte de uma aura sai de
  -- campo, uma criatura cujo dano marcado passa a ser letal morre no próximo
  -- estado estável (check_lethal repete enquanto houver mortes, e settle roda
  -- depois de cada ação, efeito e troca de vez), sem tratamento especial aqui.
  function Game:hp(c)
    local base = c.def.hp or 0
    if c.def.stats then
      local _, h = self:run_card("atributos", c.def.id, c.def.stats, self, c)
      if h ~= nil then base = h end
    end
    return base + (c.hp_bonus or 0) + (self.equip_bonus and self:equip_bonus(c, "hp_bonus") or 0)
      + self:aura_hp_bonus(c)
  end

  -- Soma de def.aura_hp(game, fonte, alvo) de cada criatura em campo do dono de c
  -- (c inclusa). A aura não pode chamar Game:hp (laço); use só os atributos
  -- impressos, os tipos e o dono.
  --
  -- Game:hp roda em caminhos quentes (in_play no bot, check_lethal em todo
  -- settle), por isso percorre o campo direto, sem alocar a lista de creatures().
  function Game:aura_hp_bonus(c)
    local total = 0
    local field = self.players[c.owner].field
    for s = 1, Game.FIELD_SLOTS do
      local f = field[s]
      if f and f.def.aura_hp then
        local n = self:run_card("aura", f.def.id, f.def.aura_hp, self, f, c)
        total = total + (n or 0)
      end
    end
    return total
  end

  -- Efeito de entrada com alvos escolhidos na jogada (def.play_targets; doc,
  -- "Momento das escolhas"): opts.entry = { locks, action } vem da jogada; se um
  -- alvo saiu de campo até a entrada, o efeito não acontece (alvo perdido). Sem
  -- entry (a carta entrou por efeito), on_play recebe objects nil e escolhe na hora.
  function Game:run_entry(src, entry)
    local def = src.def
    if def.on_play == nil then return end
    if entry and def.play_targets then
      local valid, objects = self:targets_still_valid(entry.locks)
      if valid then valid = def.play_targets(self, src.owner, entry.action, objects) end
      if not valid then
        self:emit{ t = "fizzle", p = src.owner, id = def.id }
        return
      end
      return self:effect("entrar", def.id, def.on_play, self, src, objects, entry.action)
    end
    self:effect("entrar", def.id, def.on_play, self, src)
  end

  -- Os alvos de entrada são conferidos na jogada, como os de um feitiço.
  function Game:check_entry_targets(p, def, action)
    if def.play_targets == nil then return self:check_no_targets(action) end
    local ok, err = self:check_targets(action)
    if not ok then return false, err end
    local valid, why = def.play_targets(self, p, action, self:target_objects(action))
    if not valid then return false, why or "alvo inválido" end
    return true
  end

  -- Coloca uma criatura em campo. opts.ficha marca criaturas criadas por efeito;
  -- opts.entry traz os alvos de entrada escolhidos na jogada (ver run_entry).
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
      link = opts.link, -- estrutura de origem (ver Game:linked_to)
    }
    self.players[p].field[slot] = c
    self:emit{ t = "summon", p = p, slot = slot, uid = c.uid, card_uid = c.card_uid, id = def.id, ficha = c.ficha }
    self:run_entry(c, opts.entry)
    for _, other in ipairs(self:all_creatures()) do
      if other ~= c and other.def.on_any_enter and self.players[other.owner].field[other.slot] == other then
        self:effect("reagir", other.def.id, other.def.on_any_enter, self, other, c)
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
  --
  -- Invariante: toda ação que a validação aceita (Game:can_act) resolve sem erro
  -- por causa da forma da ação. Por isso a validação de TODA jogada ou ativação
  -- passa por check_targets (carta ou efeito que mira) ou por check_no_targets
  -- (carta ou efeito sem alvos): um action.target ou action.targets de tipo
  -- errado, ou informado onde não há alvos, é recusado ali, e lock_targets e
  -- target_objects só veem alvos já conferidos. (A exceção é o equipamento, em
  -- que action.target é o número do espaço da criatura: ver play_rules.equipamento.)
  local ZONE_SLOTS = { criatura = "FIELD_SLOTS", estrutura = "STRUCTURE_SLOTS" }

  -- Lista em sequência exata: só chaves 1..n, sem buracos nem chaves extras.
  local function is_list(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do
      if t[i] == nil then return false end
    end
    return true
  end

  -- Forma de action.target e action.targets, sem olhar o campo: target é uma
  -- tabela; targets, uma lista de tabelas.
  local function check_target_shape(action)
    if action.target ~= nil and type(action.target) ~= "table" then
      return false, "alvo inválido: use { p = jogador, slot = espaço, zone = ... }"
    end
    if action.targets ~= nil then
      if not is_list(action.targets) then return false, "lista de alvos inválida" end
      for _, t in ipairs(action.targets) do
        if type(t) ~= "table" then return false, "alvo inválido: use { p = jogador, slot = espaço, zone = ... }" end
      end
    end
    return true
  end

  -- Só chega aqui o que a validação aceitou; mesmo assim, o que não for tabela
  -- é pulado em vez de dar erro.
  local function each_target(action, fn)
    if type(action.target) == "table" then fn(action.target) end
    if type(action.targets) == "table" then
      for _, t in ipairs(action.targets) do
        if type(t) == "table" then fn(t) end
      end
    end
  end

  local function object_at(g, t)
    local zone = t.zone or "criatura"
    if zone == "jogador" then return { player = t.p } end
    if zone == "estrutura" then return g:structure_at(t.p, t.slot) end
    return g:creature_at(t.p, t.slot)
  end

  function Game:check_targets(action)
    local ok, shape_err = check_target_shape(action)
    if not ok then return false, shape_err end
    local err
    each_target(action, function(t)
      if err then return end
      local zone = t.zone
      if zone == nil then zone = "criatura" end
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

  -- Para carta ou efeito sem alvos: informar um alvo é recusado, em vez de
  -- ignorado (a resolução não tem o que fazer com ele).
  function Game:check_no_targets(action, what)
    if action.target ~= nil or action.targets ~= nil then
      return false, (what or "essa carta") .. " não tem alvos"
    end
    return true
  end

  -- Objetos atuais dos alvos (criatura, estrutura ou { player = p }), na ordem dos
  -- alvos. Usado na jogada; ao resolver, a lista vem de targets_still_valid.
  function Game:target_objects(action)
    local objects = {}
    each_target(action, function(t) objects[#objects + 1] = object_at(self, t) end)
    return objects
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
  -- Validação da jogada, sem gastar nada. Devolve ok, erro e o que apurou:
  -- { zone, card, def, rule, cost, uses_fogueira }.
  local function validate_play(g, p, action)
    local pl = g.players[p]
    local zone_name = Game.PLAYABLE_ZONES[action.from or "hand"]
    if zone_name == nil then return false, "origem inválida" end
    local zone = pl[zone_name]
    local card = zone[action.hand_index or -1]
    if card == nil then return false, "carta não está na mão" end
    local def = g:def_of(card)
    if def == nil then return false, "carta desconhecida: " .. tostring(card.id) end
    -- Contexto da ação inteira (o act zera o contexto a cada jogada); os trechos
    -- de carta lá dentro marcam o próprio contexto com run_card.
    g.context = { kind = "jogar", id = def.id }
    local rule = Game.play_rules[def.kind]
    if rule == nil then return false, "tipo de carta ainda não suportado: " .. tostring(def.kind) end
    if g:stack_open() and not (rule.allowed_in_stack and rule.allowed_in_stack(g, def)) then
      return false, "com a pilha aberta, só Rápidos e Instantâneos"
    end

    local cost = g:card_cost(p, card)
    if not g:can_pay_mana(p, cost) then return false, "mana insuficiente" end
    local uses_fogueira = not def.no_fogueira
    if uses_fogueira and not g:can_pay_fogueira(p) then return false, "fogueira apagada" end
    local ok, err = g:run_card("jogar", def.id, rule.validate, g, p, card, def, action)
    if not ok then return false, err end
    return true, nil, { zone = zone, card = card, def = def, rule = rule, cost = cost, uses_fogueira = uses_fogueira }
  end
  Game.validators.play = validate_play

  Game.actions.play = function(g, p, action)
    local ok, err, v = validate_play(g, p, action)
    if not ok then return false, err end
    local zone, card, def, rule, cost, uses_fogueira = v.zone, v.card, v.def, v.rule, v.cost, v.uses_fogueira

    table.remove(zone, action.hand_index)
    -- Custo fixado ou alterado por zona (Sapo, Inventário) não acompanha a carta.
    card.cost_override, card.cost_mod = nil, nil
    g:spend_mana(p, cost)
    if uses_fogueira then g:spend_fogueira(p) end
    g:emit{ t = "play", p = p, card_uid = card.uid, id = def.id, cost = cost }
    local passes = g:run_card("jogar", def.id, rule.resolve, g, p, card, def, action)
    if passes == nil then passes = not def.keeps_turn end
    return true, nil, passes
  end

  ----------------------------------------------------------------------------
  -- Feitiços
  ----------------------------------------------------------------------------

  -- Manda a carta para o descarte. Ficha marcada com returns_to_extra volta para o
  -- baralho extra.
  function Game:to_discard(p, card)
    if card.ficha and self:def_of(card).returns_to_extra then return self:vanish(p, card, "descarte") end
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
      if def.targets == nil then ok, err = g:check_no_targets(action) else ok, err = g:check_targets(action) end
      if not ok then return false, err end
      -- Feitiço que cria estrutura (def.creates_structure): com a zona cheia, a
      -- substituída é escolhida na jogada (action.replace). Se abrir vaga até a
      -- resolução, a nova entra na vaga (enter_structure com opts.slot).
      if def.creates_structure and Game.first_free_structure(g, p) == nil then
        local r = action.replace
        if type(r) ~= "number" or r % 1 ~= 0 or r < 1 or r > Game.STRUCTURE_SLOTS then
          return false, "zona cheia: escolha qual estrutura substituir"
        end
      end
      if def.targets then
        local valid, why = def.targets(g, p, action, g:target_objects(action))
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
          gg:as_one_effect(def.on_cast, gg, p, action, card, objects)
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

  -- Sacrifício como custo de jogar (def.sacrifice = { count = n, filter = fn(g, c) }):
  -- action.sacrifice traz os espaços das criaturas suas sacrificadas. Devolve a lista
  -- de criaturas, ou nil e o erro.
  local function sacrifice_list(g, p, def, action)
    local spec = def.sacrifice
    local slots = action.sacrifice
    if type(slots) ~= "table" or #slots ~= spec.count then
      return nil, "escolha " .. spec.count .. " criatura(s) para sacrificar"
    end
    local list, seen = {}, {}
    for i, s in ipairs(slots) do
      local c = type(s) == "number" and g:creature_at(p, s) or nil
      if c == nil or seen[c] then return nil, "sacrifício inválido" end
      if spec.filter and not spec.filter(g, c) then return nil, "essa criatura não pode ser sacrificada" end
      seen[c] = true
      list[i] = c
    end
    return list
  end

  Game.play_rules.criatura = {
    -- action.slot: espaço livre de 1 a 6. Com o campo cheio, o espaço da criatura
    -- sua que será substituída (doc, "Substituir"): ela é destruída, sem "ao morrer",
    -- e os equipamentos vão para o Inventário. Com sacrifício, o sacrifício é pago
    -- na jogada (abate normal) e libera o espaço: action.slot pode ser o de uma
    -- sacrificada, e não há substituição.
    validate = function(g, p, card, def, action)
      local s = action.slot
      if type(s) ~= "number" or s < 1 or s > Game.FIELD_SLOTS or s % 1 ~= 0 then
        return false, "espaço inválido"
      end
      if def.sacrifice then
        local list, err = sacrifice_list(g, p, def, action)
        if list == nil then return false, err end
        local occupant = g.players[p].field[s]
        local freed = false
        for _, c in ipairs(list) do if c == occupant then freed = true end end
        if occupant ~= nil and not freed then return false, "espaço ocupado" end
      elseif g.players[p].field[s] ~= nil and #g:free_slots(p) > 0 then
        return false, "espaço ocupado: substituir só com o campo cheio"
      end
      if def.can_play and not def.can_play(g, p, action) then return false, "condição da carta não atendida" end
      return g:check_entry_targets(p, def, action)
    end,
    resolve = function(g, p, card, def, action)
      -- Os alvos são travados antes da substituição: se o alvo era a substituída,
      -- ele é perdido.
      local entry = { locks = g:lock_targets(action), action = action }
      if def.sacrifice then
        local list = {}
        for i, c in ipairs(sacrifice_list(g, p, def, action)) do list[i] = { c, nil, "sacrificio" } end
        g:kill_many(list, "sacrificio")
        -- A nova entra depois de os efeitos de morte terminarem: se um deles
        -- decidir a partida, ela não entra; se abrir escolha, entra depois dela.
        -- Um "ao morrer" pode ter ocupado o espaço liberado: a nova vai para o
        -- primeiro livre; sem nenhum, não entra e vai para o descarte.
        g:after_choices(function(gg)
          if gg.winner ~= nil then return end
          local slot = action.slot
          if gg.players[p].field[slot] ~= nil then slot = gg:free_slots(p)[1] end
          if slot == nil then
            gg:emit{ t = "no_space", p = p, id = def.id }
            gg:to_discard(p, card)
          else
            gg:place_creature(p, card, slot, { entry = entry })
          end
        end, { keeps_turn_flow = true })
        return
      end
      local old = g.players[p].field[action.slot]
      if old then g:remove_creature(old, "destroyed", "substituida", { equips = "inventory" }) end
      g:place_creature(p, card, action.slot, { entry = entry })
    end,
  }
end
