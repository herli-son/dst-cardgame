-- Estruturas: zona de 2 espaços, substituição (destrói a antiga), quebra e efeitos
-- ativados. Lua 5.1 puro.
-- Instala os métodos no Game: require("duelo/core/estruturas")(Game)
--
-- Campos da definição de uma estrutura:
--   activation = { once_per_round = bool, speed = "instantaneo" | "rapido" | "lento" }
--   activate(game, p, fonte, action, objects)   efeito ativado; objects são os alvos
--                                               travados; pode abrir uma escolha
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

  -- Tira a estrutura de campo e manda a carta ao destino, sem disparar efeitos.
  local function remove_structure(g, p, slot, reason)
    local pl = g.players[p]
    local st = pl.structures[slot]
    if st == nil then return nil end
    pl.structures[slot] = nil
    -- O efeito "ao quebrar" roda depois de a carta ir ao destino (já zerada): os
    -- marcadores dela ficam guardados na instância para ele consultar.
    st.marks = { used_round = st.card.used_round, used_period = st.card.used_period }
    g:unlink(st)
    g:emit{ t = "break", p = p, slot = slot, uid = st.uid, card_uid = st.card_uid, id = st.def.id, reason = reason }
    if st.ficha then st.card.ficha = true end
    g:to_discard(p, st.card)
    return st
  end

  -- Quebrar: a estrutura sai de campo, vai para o descarte (fichas também, menos
  -- as marcadas com returns_to_extra) e dispara o "ao quebrar".
  -- O estado fica completo antes do efeito "ao quebrar": se ele decidir a partida,
  -- nada fica pela metade.
  function Game:break_structure(p, slot, reason)
    local st = remove_structure(self, p, slot, reason)
    if st and st.def.on_break then self:effect("quebrar", st.def.id, st.def.on_break, self, st) end
  end

  Game.first_free_structure = first_free

  -- Substituir (doc): a estrutura substituída é destruída. Vai para as Destruídas
  -- e não dispara o "ao quebrar".
  local function destroy_structure(g, p, slot, reason)
    local pl = g.players[p]
    local st = pl.structures[slot]
    if st == nil then return end
    pl.structures[slot] = nil
    g:unlink(st)
    g:emit{ t = "structure_destroyed", p = p, slot = slot, uid = st.uid, card_uid = st.card_uid,
      id = st.def.id, reason = reason }
    if st.ficha then st.card.ficha = true end
    g:destroy_card(p, st.card, reason)
  end

  -- Coloca uma estrutura num espaço. Com a zona cheia, a nova substitui a do
  -- espaço indicado, que é destruída; sem espaço indicado, a zona precisa ter vaga.
  function Game:put_structure(p, card, slot, opts)
    opts = opts or {}
    slot = slot or first_free(self, p)
    if slot == nil then return nil, "zona de estruturas cheia: é preciso indicar qual substituir" end
    destroy_structure(self, p, slot, "substituida")
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
    self:run_entry(st, opts.entry)
    return st
  end

  -- Estrutura que entra em jogo por efeito (ficha ou carta buscada). Com vaga, entra
  -- nela (opts.slot só substitui com a zona cheia). Com a zona cheia, o dono escolhe
  -- qual substituir ou nenhuma; sem substituição, a ficha deixa de existir e a carta
  -- vai para o descarte. A vaga é conferida de novo quando a escolha abre.
  -- Retorna a estrutura, ou nil e "pendente".
  function Game:enter_structure(p, card, opts)
    opts = opts or {}
    local free = first_free(self, p)
    local slot = opts.slot
    -- Espaço fora da zona é ignorado.
    if slot ~= nil and (type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > Game.STRUCTURE_SLOTS) then
      slot = nil
    end
    if slot == nil or (self.players[p].structures[slot] ~= nil and free ~= nil) then slot = free end
    if slot then return self:put_structure(p, card, slot, opts) end
    local function drop(g, reason)
      if card.ficha or opts.ficha then g:vanish(p, card, reason) else g:to_discard(p, card) end
    end
    self:set_choice(p, {
      reason = "substituir_estrutura",
      allow_none = true,
      prepare = function(g, spec)
        local vaga = first_free(g, p)
        if vaga then
          g:put_structure(p, card, vaga, opts)
          return false
        end
        spec.options = {}
        for s = 1, Game.STRUCTURE_SLOTS do spec.options[s] = s end
      end,
      resolve = function(g, idx)
        if idx == nil then return drop(g, "nao_substituiu") end
        g:put_structure(p, card, idx, opts)
      end,
    })
    return nil, "pendente"
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
      return g:check_entry_targets(p, def, action)
    end,
    resolve = function(g, p, card, def, action)
      g:put_structure(p, card, action.slot, { entry = { locks = g:lock_targets(action), action = action } })
    end,
  }

  ----------------------------------------------------------------------------
  -- Escolhas pendentes
  ----------------------------------------------------------------------------

  -- Um efeito pode pedir uma escolha ao jogador. Enquanto ela estiver aberta,
  -- só a ação "choose" desse jogador é aceita. Escolhas abertas enquanto outra
  -- está pendente entram numa fila e são feitas na ordem.
  -- spec = { reason, options = {...}, allow_none = bool, resolve = function(g, index_ou_nil) }
  -- spec.prepare(g, spec), se existir, roda quando a escolha abre (e não quando é
  -- pedida): monta as opções com o estado daquele momento. Se devolver false, a
  -- escolha não é mais necessária (prepare já resolveu tudo) e a próxima da fila abre.
  -- Regra única de ordem: uma escolha pedida enquanto outra está aberta, sendo
  -- preparada ou sendo resolvida entra no fim da fila, atrás das que já esperavam.
  -- Roda fn(a, b) com essa marca ligada. A marca volta ao valor anterior mesmo
  -- num erro ou quando a partida é decidida no meio.
  local function while_choosing(g, fn, a, b)
    local prev = g.opening_choice
    g.opening_choice = true
    local res
    local ok, err = xpcall(function() res = fn(a, b) end, Game.capture_error)
    -- A marca volta sempre; num erro de carta a partida termina de qualquer jeito.
    g.opening_choice = prev
    if not ok then error(err, 0) end
    return res
  end

  local function open_choice(g, spec)
    if spec.prepare then
      local ran, keep = false, nil
      g:effect("preparar_escolha", spec.reason, function()
        ran = true
        keep = while_choosing(g, spec.prepare, g, spec)
      end)
      -- Preparo pulado (partida sendo decidida) ou recusado: a escolha não abre.
      if not ran or keep == false then
        return false
      end
    end
    g.pending_choice = spec
    g:emit{ t = "choice", p = spec.player, reason = spec.reason, count = #(spec.options or {}) }
    return true
  end

  function Game:set_choice(p, spec)
    spec.player = p
    if self.pending_choice or self.opening_choice then
      self.choice_queue = self.choice_queue or {}
      table.insert(self.choice_queue, spec)
      return
    end
    if not open_choice(self, spec) then self:next_choice() end
  end

  -- Há escolha aberta ou esperando na fila.
  function Game:choices_waiting()
    return self.pending_choice ~= nil or (self.choice_queue ~= nil and #self.choice_queue > 0)
  end

  -- Abre a próxima escolha da fila, se houver.
  function Game:next_choice()
    local q = self.choice_queue
    while q and #q > 0 do
      local spec = table.remove(q, 1)
      if open_choice(self, spec) then return spec end
    end
  end

  -- O que vem depois de uma escolha: abrir a próxima da fila (que herda a decisão
  -- de passar a vez), retomar a pilha em resolução e as continuações suspensas.
  -- Devolve se a vez deve passar agora.
  local function run_continuations(g)
    local conts = g.choice_continuations
    if conts and #conts > 0 then
      g.choice_continuations = {}
      for _, c in ipairs(conts) do
        local ctx = c.context or {}
        g:effect(ctx.kind or "continuar", ctx.id, c.fn, g)
      end
      return true
    end
    return false
  end

  local function after_choose(g, ch)
    if g.pending_choice == nil then g:next_choice() end
    -- Sem mais escolhas, as mortes causadas pela escolha acontecem antes de
    -- retomar a pilha ou as continuações (próxima fase do combate, rodada nova).
    -- Um "ao morrer" que abrir outra escolha segura a retomada de novo.
    if g.pending_choice == nil then
      g:settle()
      if g.pending_choice == nil then g:next_choice() end
    end
    if g.pending_choice then
      if g.pending_choice.passes_turn == nil then g.pending_choice.passes_turn = ch.passes_turn end
      return false
    end
    if g.resolving then
      -- A pilha retoma; ao fechar, ela mesma passa a vez para quem não a abriu.
      g:resolve_stack()
      if not g:choices_waiting() then run_continuations(g) end
      return false
    end
    if run_continuations(g) then return false end
    return ch.passes_turn == true
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
    -- A resolução de uma escolha é um efeito próprio.
    g:run_card("escolher", ch.reason, while_choosing, g, function(gg, i) gg:as_one_effect(ch.resolve, gg, i) end, g, idx)
    return true, nil, after_choose(g, ch)
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
    -- Contexto da ação inteira (o act zera o contexto a cada jogada); os trechos
    -- de carta lá dentro marcam o próprio contexto com run_card.
    g.context = { kind = "ativar", id = def.id }
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
      local valid, why = g:run_card("ativar", def.id, def.targets, g, p, action, g:target_objects(action))
      if not valid then return false, why or "alvo inválido" end
    end
    if def.can_activate then
      local can, reason = g:run_card("ativar", def.id, def.can_activate, g, p, src, action)
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
      local valid, objects = gg:targets_still_valid(locks)
      if not valid or (def.targets and not def.targets(gg, p, action, objects)) then
        gg:emit{ t = "fizzle", p = p, id = def.id }
        return
      end
      gg:as_one_effect(def.activate, gg, p, src, action, objects)
    end)
  end
end
