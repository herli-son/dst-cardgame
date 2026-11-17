-- Combate: declarar ataque, bloquear e resolver os golpes. Lua 5.1 puro.
-- Instala os métodos no Game: require("duelo/core/combate")(Game)
--
-- Regras (doc, "Combate e pilha", "Bloqueios" e "Quem ataca"):
--   * Só quem tem o token ataca, uma vez por rodada, e só com a pilha vazia: o
--     ataque abre a pilha, como um Lento, e o combate resolve por último.
--   * Criaturas que entraram nesta rodada podem atacar.
--   * O defensor declara todos os bloqueios só na primeira resposta ao ataque,
--     uma criatura para cada atacante. Declarar bloqueios conta como pôr algo na
--     pilha: o "pass" seguinte é pronto e a vez volta para o atacante.
--   * Atacante sem bloqueio causa ao jogador dano igual ao seu ataque. Se o
--     bloqueador sair de campo antes, o atacante continua bloqueado e não causa
--     dano. O dano que sobra num bloqueio não passa para o jogador.
--
-- Campos da definição de uma criatura usados aqui:
--   no_attack = true   não pode atacar (ex.: Tentáculo)
--   no_block = true    não pode bloquear

return function(Game)
  ----------------------------------------------------------------------------
  -- Dano em criaturas
  ----------------------------------------------------------------------------

  -- O dano fica marcado na criatura (é permanente) e ela morre quando o dano
  -- chega à vida. source é a criatura que causou o dano, quando houver.
  function Game:damage_creature(c, n, source, reason)
    if n <= 0 then return end
    if self.players[c.owner].field[c.slot] ~= c then return end
    c.damage = c.damage + n
    self:emit{ t = "creature_damage", p = c.owner, slot = c.slot, uid = c.uid, amount = n,
      damage = c.damage, source_uid = source and source.uid or nil, reason = reason }
  end

  -- Abate as criaturas cujo dano chegou à vida. Roda depois de golpes
  -- simultâneos, para todos os golpes da mesma fase acontecerem antes das mortes.
  function Game:check_deaths(killers)
    killers = killers or {}
    for _, c in ipairs(self:all_creatures()) do
      if c.damage >= self:hp(c) then self:kill(c, "dano", killers[c]) end
    end
  end

  ----------------------------------------------------------------------------
  -- Declarar ataque
  ----------------------------------------------------------------------------

  -- action = { type = "attack", attackers = { espaço, ... } }
  Game.actions.attack = function(g, p, action)
    if g.attacker ~= p then return false, "só quem tem o token ataca" end
    if g.attacked_round == g.round then return false, "já houve ataque nesta rodada" end
    if g:stack_open() then return false, "atacar só com a pilha vazia" end
    local slots = action.attackers
    if type(slots) ~= "table" or #slots == 0 then return false, "escolha quem ataca" end
    local seen, attackers = {}, {}
    for _, s in ipairs(slots) do
      local c = type(s) == "number" and g:creature_at(p, s) or nil
      if c == nil then return false, "não há criatura sua nesse espaço" end
      if seen[c] then return false, "a mesma criatura não ataca duas vezes" end
      if c.def.no_attack then return false, "essa criatura não ataca" end
      seen[c] = true
      attackers[#attackers + 1] = c
    end
    local defender = Game.other(p)
    g.attacked_round = g.round
    g.combat = {
      attacker = p,
      defender = defender,
      attackers = attackers,  -- criaturas, na ordem declarada
      blocks = {},            -- blocks[atacante] = bloqueador
      blocked = {},           -- blocked[atacante] = true se foi bloqueado
      blocks_declared = false,
      defender_windows = 0,   -- quantas vezes o defensor recebeu a vez neste ataque
    }
    local uids = {}
    for i, c in ipairs(attackers) do uids[i] = c.uid end
    g:emit{ t = "attack", p = p, attackers = uids }
    g:push_stack(p, { label = "ataque", resolve = function(gg) gg:resolve_combat() end })
    return true, nil, false
  end

  ----------------------------------------------------------------------------
  -- Bloquear
  ----------------------------------------------------------------------------

  -- A janela de bloqueio é a primeira vez que o defensor recebe a vez no ataque.
  local base_hand_over = Game.hand_over
  function Game:hand_over()
    base_hand_over(self)
    local cb = self.combat
    if cb and self.active == cb.defender then cb.defender_windows = cb.defender_windows + 1 end
  end

  function Game:can_declare_blocks(p)
    local cb = self.combat
    return cb ~= nil and p == cb.defender and self.active == p
      and not cb.blocks_declared and cb.defender_windows == 1
  end

  -- action = { type = "block", blocks = { { attacker = espaço, blocker = espaço }, ... } }
  -- Uma lista vazia declara que não há bloqueios.
  Game.actions.block = function(g, p, action)
    local cb = g.combat
    if not g:can_declare_blocks(p) then
      return false, "bloqueios só na primeira resposta do defensor ao ataque"
    end
    if type(action.blocks) ~= "table" then return false, "bloqueios inválidos" end
    local atk_used, blk_used, pairs_ok = {}, {}, {}
    for _, b in ipairs(action.blocks) do
      if type(b) ~= "table" then return false, "bloqueio inválido" end
      local a = type(b.attacker) == "number" and g:creature_at(cb.attacker, b.attacker) or nil
      local d = type(b.blocker) == "number" and g:creature_at(p, b.blocker) or nil
      if a == nil then return false, "não há atacante nesse espaço" end
      local attacking = false
      for _, x in ipairs(cb.attackers) do if x == a then attacking = true end end
      if not attacking then return false, "essa criatura não está atacando" end
      if d == nil then return false, "não há criatura sua nesse espaço" end
      if d.def.no_block then return false, "essa criatura não bloqueia" end
      if atk_used[a] then return false, "cada atacante é bloqueado por uma criatura só" end
      if blk_used[d] then return false, "cada criatura bloqueia um atacante só" end
      atk_used[a], blk_used[d] = true, true
      pairs_ok[#pairs_ok + 1] = { a, d }
    end
    for _, pr in ipairs(pairs_ok) do
      cb.blocks[pr[1]] = pr[2]
      cb.blocked[pr[1]] = true
    end
    cb.blocks_declared = true
    -- Bloquear é a resposta ao ataque: conta como pôr algo na pilha.
    g.stack_added = true
    local list = {}
    for _, pr in ipairs(pairs_ok) do list[#list + 1] = { attacker = pr[1].uid, blocker = pr[2].uid } end
    g:emit{ t = "block", p = p, blocks = list }
    return true, nil, false
  end

  ----------------------------------------------------------------------------
  -- Resolver
  ----------------------------------------------------------------------------

  local function on_field(g, c)
    return c ~= nil and g.players[c.owner].field[c.slot] == c
  end

  -- Todos golpeiam ao mesmo tempo; as mortes acontecem depois de todos os golpes.
  function Game:resolve_combat()
    local cb = self.combat
    if cb == nil then return end
    self.combat = nil
    self:emit{ t = "combat_start", p = cb.attacker }
    local killers = {}
    local to_player = 0
    for _, a in ipairs(cb.attackers) do
      if on_field(self, a) then
        local d = cb.blocks[a]
        if cb.blocked[a] then
          if on_field(self, d) then
            local da, dd = self:atk(a), self:atk(d)
            self:damage_creature(d, da, a, "combate")
            if d.damage >= self:hp(d) then killers[d] = a end
            self:damage_creature(a, dd, d, "combate")
            if a.damage >= self:hp(a) then killers[a] = d end
          end
        else
          to_player = to_player + self:atk(a)
        end
      end
    end
    self:check_deaths(killers)
    if to_player > 0 then self:damage_player(cb.defender, to_player, "combate") end
    self:emit{ t = "combat_end", p = cb.attacker }
  end
end
