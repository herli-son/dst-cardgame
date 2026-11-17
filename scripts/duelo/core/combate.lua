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
--   * Uma criatura que sai do lado em que estava (morre, volta para a mão ou muda
--     de dono) sai do combate.
--
-- Resolução em fases: em cada fase, todos os golpes acontecem ao mesmo tempo
-- (dano nas criaturas e no jogador), a vitória é verificada e só então as
-- criaturas mortas saem de campo, juntas. Hoje há uma fase só; a Velocidade
-- (US #16) divide os golpes em fases.
--
-- Campos da definição de uma criatura usados aqui:
--   no_attack = true   não pode atacar (ex.: Tentáculo)
--   no_block = true    não pode bloquear

return function(Game)
  ----------------------------------------------------------------------------
  -- Golpes e dano em criaturas
  ----------------------------------------------------------------------------

  -- O dano fica marcado na criatura (é permanente).
  function Game:damage_creature(c, n, source, reason)
    if n <= 0 then return end
    if self.players[c.owner].field[c.slot] ~= c then return end
    c.damage = c.damage + n
    self:emit{ t = "creature_damage", p = c.owner, slot = c.slot, uid = c.uid, amount = n,
      damage = c.damage, source_uid = source and source.uid or nil, reason = reason }
  end

  -- Um golpe é um evento próprio, mesmo quando o dano é zero (armaduras perdem
  -- durabilidade ao serem golpeadas; Golpear dispara a cada golpe).
  -- target é uma criatura ou { player = p }. n é o dano (padrão: o ataque atual).
  -- in_phase = true quando o golpe faz parte de uma fase: a vitória é verificada
  -- no fim da fase; fora dela, logo depois do golpe.
  function Game:strike(src, target, n, in_phase)
    n = n or self:atk(src)
    if target.player then
      self:emit{ t = "strike", p = src.owner, uid = src.uid, target_player = target.player, amount = n }
      self:damage_player(target.player, n, "combate", { from = src, no_check = in_phase })
    else
      self:emit{ t = "strike", p = src.owner, uid = src.uid, target_uid = target.uid, amount = n }
      self:damage_creature(target, n, src, "combate")
    end
    return n
  end

  ----------------------------------------------------------------------------
  -- Entrada
  ----------------------------------------------------------------------------

  -- Lista em sequência exata: só chaves 1..n, sem buracos nem chaves extras.
  local function is_sequence(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do
      if t[i] == nil then return false end
    end
    return true
  end

  local function valid_slot(s)
    return type(s) == "number" and s % 1 == 0 and s >= 1 and s <= Game.FIELD_SLOTS
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
    g.attacked_round = g.round
    g.combat = {
      attacker = p,
      defender = Game.other(p),
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

  -- A criatura continua no combate se ainda está em campo, do mesmo lado.
  local function still_in(g, c, side)
    return c ~= nil and c.owner == side and g.players[side].field[c.slot] == c
  end

  -- Uma fase de golpes: todos os golpes de `strikes` ao mesmo tempo, depois a
  -- vitória e depois as mortes. strikes = { { src, alvo }, ... }.
  function Game:strike_phase(strikes)
    -- Simultâneo: os valores de todos os golpes são lidos antes de qualquer dano.
    local amounts = {}
    for i, s in ipairs(strikes) do amounts[i] = self:atk(s[1]) end
    local killers = {}
    for i, s in ipairs(strikes) do
      self:strike(s[1], s[2], amounts[i], true)
      if not s[2].player then killers[s[2]] = s[1] end
    end
    self:check_winner()
    if self.winner ~= nil then return end
    self:check_lethal(killers, "combate")
  end

  function Game:resolve_combat()
    local cb = self.combat
    if cb == nil then return end
    self.combat = nil
    self:emit{ t = "combat_start", p = cb.attacker }
    local strikes = {}
    for _, a in ipairs(cb.attackers) do
      if still_in(self, a, cb.attacker) then
        if cb.blocked[a] then
          local d = cb.blocks[a]
          if still_in(self, d, cb.defender) then
            strikes[#strikes + 1] = { a, d }
            strikes[#strikes + 1] = { d, a }
          end
        else
          strikes[#strikes + 1] = { a, { player = cb.defender } }
        end
      end
    end
    self:strike_phase(strikes)
    if self.winner == nil then self:emit{ t = "combat_end", p = cb.attacker } end
  end
end
