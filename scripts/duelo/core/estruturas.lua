-- Estruturas: zona de 2 espaços, substituição, quebra e efeitos ativados. Lua 5.1 puro.
-- Instala os métodos no Game: require("duelo/core/estruturas")(Game)
--
-- Campos da definição de uma estrutura:
--   activation = { once_per_round = bool, speed = "instantaneo" | "rapido" | "lento" }
--   activate(game, p, estrutura, action)   efeito ativado; pode abrir uma escolha
--   on_break(game, estrutura)              ao ser quebrada

return function(Game)
  Game.STRUCTURE_SLOTS = 2

  function Game:structure_at(p, slot)
    return self.players[p].structures[slot]
  end

  function Game:has_structure(p, id)
    for s = 1, Game.STRUCTURE_SLOTS do
      local st = self.players[p].structures[s]
      if st and st.def.id == id then return true end
    end
    return false
  end

  local function first_free(g, p)
    for s = 1, Game.STRUCTURE_SLOTS do
      if g.players[p].structures[s] == nil then return s end
    end
  end

  -- Quebrar: a estrutura sai de campo e vai para o descarte; fichas deixam de existir.
  function Game:break_structure(p, slot, reason)
    local pl = self.players[p]
    local st = pl.structures[slot]
    if st == nil then return end
    pl.structures[slot] = nil
    self:emit{ t = "break", p = p, slot = slot, uid = st.uid, card_uid = st.card_uid, id = st.def.id, reason = reason }
    if st.def.on_break then st.def.on_break(self, st) end
    if st.ficha then
      self:vanish(p, st.card, reason)
    else
      self:to_discard(p, st.card)
    end
  end

  Game.first_free_structure = first_free

  -- Coloca uma estrutura num espaço. Com a zona cheia, a nova substitui a do
  -- espaço indicado, que é quebrada; sem espaço indicado, a zona precisa ter vaga.
  function Game:put_structure(p, card, slot, opts)
    opts = opts or {}
    slot = slot or first_free(self, p)
    if slot == nil then return nil, "zona de estruturas cheia: é preciso indicar qual substituir" end
    if self.players[p].structures[slot] then self:break_structure(p, slot, "substituida") end
    local def = self:def_of(card)
    local st = {
      uid = self:next_uid(),
      card_uid = card.uid,
      card = card,
      def = def,
      owner = p,
      slot = slot,
      ficha = opts.ficha or card.ficha or false,
    }
    self.players[p].structures[slot] = st
    self:emit{ t = "structure", p = p, slot = slot, uid = st.uid, card_uid = st.card_uid, id = def.id }
    if def.on_play then def.on_play(self, st) end
    return st
  end

  Game.play_rules.estrutura = {
    -- action.slot (opcional): espaço 1 ou 2. Obrigatório quando a zona está cheia,
    -- para o dono escolher qual estrutura será substituída.
    validate = function(g, p, card, def, action)
      local s = action.slot
      if s ~= nil and (type(s) ~= "number" or s < 1 or s > Game.STRUCTURE_SLOTS or s % 1 ~= 0) then
        return false, "espaço de estrutura inválido"
      end
      if s == nil and first_free(g, p) == nil then
        return false, "zona cheia: escolha qual estrutura substituir"
      end
      -- Só se substitui com a zona cheia.
      if s ~= nil and g.players[p].structures[s] ~= nil and first_free(g, p) ~= nil then
        return false, "há espaço livre: substituir só com a zona cheia"
      end
      return true
    end,
    resolve = function(g, p, card, def, action)
      g:put_structure(p, card, action.slot)
    end,
  }

  ----------------------------------------------------------------------------
  -- Escolhas pendentes
  ----------------------------------------------------------------------------

  -- Um efeito pode pedir uma escolha ao jogador. Enquanto ela estiver aberta,
  -- só a ação "choose" desse jogador é aceita. Escolhas abertas enquanto outra
  -- está pendente entram numa fila e são feitas na ordem.
  -- spec = { reason, options = {...}, allow_none = bool, resolve = function(g, index_ou_nil) }
  function Game:set_choice(p, spec)
    spec.player = p
    if self.pending_choice then
      self.choice_queue = self.choice_queue or {}
      table.insert(self.choice_queue, spec)
      return
    end
    self.pending_choice = spec
    self:emit{ t = "choice", p = p, reason = spec.reason, count = #(spec.options or {}) }
  end

  -- Abre a próxima escolha da fila, se houver.
  local function next_choice(g)
    local q = g.choice_queue
    if q and #q > 0 then
      local spec = table.remove(q, 1)
      g.pending_choice = spec
      g:emit{ t = "choice", p = spec.player, reason = spec.reason, count = #(spec.options or {}) }
      return spec
    end
  end

  -- action = { type = "choose", index = n } ; index nil ou 0 = nenhuma (se permitido)
  Game.actions.choose = function(g, p, action)
    local ch = g.pending_choice
    if ch == nil then return false, "nenhuma escolha pendente" end
    if ch.player ~= p then return false, "a escolha é do outro jogador" end
    local idx = action.index
    if idx == 0 then idx = nil end
    if idx == nil and not ch.allow_none then return false, "é preciso escolher uma opção" end
    if idx ~= nil and (ch.options == nil or ch.options[idx] == nil) then return false, "opção inválida" end
    g.pending_choice = nil
    ch.resolve(g, idx)
    if g.pending_choice == nil then next_choice(g) end
    if g.pending_choice then
      -- Ainda há escolhas: a vez (se for passar) espera a última.
      if g.pending_choice.passes_turn == nil then g.pending_choice.passes_turn = ch.passes_turn end
      return true, nil, false
    end
    -- Escolha aberta durante a resolução da pilha: continua resolvendo.
    if g.resolving then
      g:resolve_stack()
      return true, nil, false
    end
    -- Continuações suspensas (fim ou início de rodada) retomam aqui.
    local conts = g.choice_continuations
    if conts and #conts > 0 then
      g.choice_continuations = {}
      for _, fn in ipairs(conts) do fn(g) end
      return true, nil, false
    end
    return true, nil, ch.passes_turn == true
  end

  ----------------------------------------------------------------------------
  -- Efeitos ativados de estruturas
  ----------------------------------------------------------------------------

  -- De onde vem o efeito: uma estrutura (action.structure = espaço) ou um equipamento
  -- (action.creature = espaço da criatura, action.equip = "mao" | "peito" | "cabeca").
  local function source_of(g, p, action)
    if action.structure then
      local st = g:structure_at(p, action.structure)
      if st == nil then return nil, "não há estrutura nesse espaço" end
      return st
    end
    if action.creature then
      local c = g:creature_at(p, action.creature)
      if c == nil then return nil, "não há criatura nesse espaço" end
      -- Sem action.equip, o efeito é da própria criatura.
      if action.equip == nil then return c end
      local e = c.equips[action.equip]
      if e == nil then return nil, "não há equipamento nesse espaço" end
      e.holder = c
      return e
    end
    return nil, "escolha a carta que vai ativar"
  end

  -- action = { type = "activate", structure = slot } ou { creature = slot, equip = "mao" }, mais os alvos
  Game.actions.activate = function(g, p, action)
    local src, err = source_of(g, p, action)
    if src == nil then return false, err end
    local def = src.def
    if def.activate == nil then return false, "essa carta não tem efeito ativado" end
    local spec = def.activation
    local ok, why = g:can_use_speed(spec.speed)
    if not ok then return false, why end
    ok, why = g:check_targets(action)
    if not ok then return false, why end
    -- Os usos ficam na carta, não na instância: reequipar não zera o limite.
    -- Passar pelo descarte zera (reset_card), porque a carta volta como nova.
    local card = src.card
    if spec.once_per_round and card.used_round == g.round then return false, "já ativada nesta rodada" end
    local period_key = g.round .. ":" .. tostring(g:period())
    if spec.once_per_period and card.used_period == period_key then return false, "já ativada neste período" end
    if def.targets then
      local valid, why = def.targets(g, p, action)
      if not valid then return false, why or "alvo inválido" end
    end
    if def.can_activate then
      local can, reason = def.can_activate(g, p, src, action)
      if not can then return false, reason or "condição do efeito não atendida" end
    end
    card.used_round = g.round
    card.used_period = period_key
    g:emit{ t = "activate", p = p, uid = src.uid, card_uid = src.card_uid, id = def.id, speed = spec.speed }
    -- Equipamentos com efeito de uso perdem 1 de durabilidade ao usar o efeito.
    if src.holder and src.durability then g:wear(src.holder, def.slot, 1) end
    local locks = g:lock_targets(action)
    return true, nil, g:use_speed(p, spec.speed, def.id, function(gg)
      -- Alvo perdido: se o alvo saiu de campo até a resolução, o efeito não acontece.
      if not gg:targets_still_valid(locks) or (def.targets and not def.targets(gg, p, action)) then
        gg:emit{ t = "fizzle", p = p, id = def.id }
        return
      end
      def.activate(gg, p, src, action)
    end)
  end
end
