-- Estruturas: zona de 2 espaços, substituição, quebra e efeitos ativados. Lua 5.1 puro.
-- Instala os métodos no Game: require("duelo/core/estruturas")(Game)
--
-- Campos da definição de uma estrutura:
--   activation = { once_per_round = bool, passes_turn = bool }   (passes_turn é obrigatório)
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
    self:emit{ t = "break", p = p, slot = slot, uid = st.uid, id = st.def.id, reason = reason }
    if st.def.on_break then st.def.on_break(self, st) end
    if not st.ficha then pl.discard[#pl.discard + 1] = st.card end
  end

  -- Coloca uma estrutura num espaço. Com a zona cheia, a nova substitui a do
  -- espaço indicado, que é quebrada.
  function Game:put_structure(p, card, slot, opts)
    opts = opts or {}
    slot = slot or first_free(self, p) or 1
    if self.players[p].structures[slot] then self:break_structure(p, slot, "substituida") end
    local def = self:def_of(card)
    local st = {
      uid = card.uid or self:next_uid(),
      card = card,
      def = def,
      owner = p,
      slot = slot,
      ficha = opts.ficha or card.ficha or false,
      used_round = nil,
    }
    self.players[p].structures[slot] = st
    self:emit{ t = "structure", p = p, slot = slot, uid = st.uid, id = def.id }
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
  -- só a ação "choose" desse jogador é aceita.
  -- spec = { reason, options = {...}, allow_none = bool, resolve = function(g, index_ou_nil) }
  function Game:set_choice(p, spec)
    spec.player = p
    self.pending_choice = spec
    self:emit{ t = "choice", p = p, reason = spec.reason, count = #(spec.options or {}) }
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
    return true, nil, ch.passes_turn == true
  end

  ----------------------------------------------------------------------------
  -- Efeitos ativados de estruturas
  ----------------------------------------------------------------------------

  -- action = { type = "activate", structure = slot, ... }
  Game.actions.activate = function(g, p, action)
    local st = g:structure_at(p, action.structure or -1)
    if st == nil then return false, "não há estrutura nesse espaço" end
    local def = st.def
    if def.activate == nil then return false, "essa estrutura não tem efeito ativado" end
    local spec = def.activation or {}
    if spec.once_per_round and st.used_round == g.round then return false, "já ativada nesta rodada" end
    st.used_round = g.round
    g:emit{ t = "activate", p = p, slot = st.slot, id = def.id }
    def.activate(g, p, st, action)
    local passes = spec.passes_turn
    if g.pending_choice then
      -- A vez só passa depois da escolha, se o efeito gastar a vez.
      g.pending_choice.passes_turn = passes
      return true, nil, false
    end
    return true, nil, passes
  end
end
