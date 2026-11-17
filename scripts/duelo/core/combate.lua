-- Combate: declarar ataque, bloquear e resolver os golpes. Lua 5.1 puro.
-- Instala os métodos no Game: require("duelo/core/combate")(Game)
--
-- Regras (doc, "Combate e pilha", "Bloqueios" e "Quem ataca"):
--   * Só quem tem o token ataca, uma vez por rodada, e só com a pilha vazia: o
--     ataque abre a pilha, como um Lento, e o combate resolve por último.
--   * Criaturas que entraram nesta rodada podem atacar.
--   * O defensor declara todos os bloqueios só na primeira resposta ao ataque,
--     uma criatura para cada atacante. Declarar ao menos um bloqueio conta como
--     pôr algo na pilha: o "pass" seguinte é pronto e a vez volta para o atacante.
--   * Atacante sem bloqueio causa ao jogador dano igual ao seu ataque. Se o
--     bloqueador sair de campo antes, o atacante continua bloqueado e não causa
--     dano. O dano que sobra num bloqueio não passa para o jogador.
--   * Uma criatura que sai do lado em que estava (morre, volta para a mão ou muda
--     de dono) sai do combate.
--
-- Resolução em duas fases, pela Velocidade: a fase rápida (velocidade 2 e 3) e a
-- fase normal (velocidade 1 e 3). Em cada fase, todos os golpes acontecem ao mesmo
-- tempo (dano nas criaturas e no jogador), os efeitos de Golpear disparam, a
-- vitória é verificada e só então as criaturas mortas saem de campo, juntas.
--
-- Campos da definição de uma criatura usados aqui:
--   no_attack = true   não pode atacar (ex.: Tentáculo)
--   no_block = true    não pode bloquear

return function(Game)
  ----------------------------------------------------------------------------
  -- Golpes e dano em criaturas
  ----------------------------------------------------------------------------

  -- O dano fica marcado na criatura (é permanente). Devolve o dano aplicado
  -- (0 se nenhum); redução de dano entra aqui.
  function Game:damage_creature(c, n, source, reason)
    if n <= 0 then return 0 end
    if self.players[c.owner].field[c.slot] ~= c then return 0 end
    c.damage = c.damage + n
    self:emit{ t = "creature_damage", p = c.owner, slot = c.slot, uid = c.uid, amount = n,
      damage = c.damage, source_uid = source and source.uid or nil, reason = reason }
    return n
  end

  -- Um golpe é um evento próprio, mesmo quando o dano é zero (armaduras perdem
  -- durabilidade ao serem golpeadas; Golpear dispara a cada golpe).
  -- target é uma criatura ou { player = p }. n é o dano (padrão: o ataque atual).
  -- in_phase = true quando o golpe faz parte de uma fase: a vitória é verificada
  -- no fim da fase; fora dela, logo depois do golpe. Devolve o dano aplicado de
  -- fato (o Golpear só dispara se ele for maior que zero).
  function Game:strike(src, target, n, in_phase)
    n = n or self:atk(src)
    if target.player then
      self:emit{ t = "strike", p = src.owner, uid = src.uid, target_player = target.player, amount = n }
      return self:damage_player(target.player, n, "combate", { from = src, no_check = in_phase }) or 0
    end
    self:emit{ t = "strike", p = src.owner, uid = src.uid, target_uid = target.uid, amount = n }
    return self:damage_creature(target, n, src, "combate") or 0
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
    if not is_sequence(slots) or #slots == 0 then return false, "escolha quem ataca" end
    local seen, attackers = {}, {}
    for _, s in ipairs(slots) do
      if not valid_slot(s) then return false, "espaço inválido" end
      local c = g:creature_at(p, s)
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
      -- Passagens de vez já feitas na pilha: a primeira resposta do defensor é a
      -- próxima passagem.
      handover_at = g.handover_count or 0,
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
  function Game:can_declare_blocks(p)
    local cb = self.combat
    return cb ~= nil and p == cb.defender and self.active == p
      and not cb.blocks_declared and (self.handover_count or 0) - cb.handover_at == 1
  end

  local function in_combat(cb, a)
    for _, x in ipairs(cb.attackers) do if x == a then return true end end
    return false
  end

  -- action = { type = "block", blocks = { { attacker = espaço, blocker = espaço }, ... } }
  -- Uma lista vazia declara que não há bloqueios e não conta como pôr algo na pilha.
  Game.actions.block = function(g, p, action)
    local cb = g.combat
    if not g:can_declare_blocks(p) then
      return false, "bloqueios só na primeira resposta do defensor ao ataque"
    end
    if not is_sequence(action.blocks) then return false, "bloqueios inválidos" end
    local atk_used, blk_used, chosen = {}, {}, {}
    for _, b in ipairs(action.blocks) do
      if type(b) ~= "table" or not valid_slot(b.attacker) or not valid_slot(b.blocker) then
        return false, "bloqueio inválido"
      end
      local a = g:creature_at(cb.attacker, b.attacker)
      local d = g:creature_at(p, b.blocker)
      if a == nil or not in_combat(cb, a) then return false, "essa criatura não está atacando" end
      if d == nil then return false, "não há criatura sua nesse espaço" end
      if d.def.no_block then return false, "essa criatura não bloqueia" end
      if atk_used[a] then return false, "cada atacante é bloqueado por uma criatura só" end
      if blk_used[d] then return false, "cada criatura bloqueia um atacante só" end
      atk_used[a], blk_used[d] = true, true
      chosen[#chosen + 1] = { a, d }
    end
    for _, pr in ipairs(chosen) do
      cb.blocks[pr[1]] = pr[2]
      cb.blocked[pr[1]] = true
    end
    cb.blocks_declared = true
    -- Bloquear é a resposta ao ataque: conta como pôr algo na pilha.
    if #chosen > 0 then g.stack_added = true end
    local list = {}
    for _, pr in ipairs(chosen) do list[#list + 1] = { attacker = pr[1].uid, blocker = pr[2].uid } end
    g:emit{ t = "block", p = p, blocks = list }
    return true, nil, false
  end

  -- Ponto único onde os bloqueios ficam definitivos, chamado ao resolver o
  -- combate (inclusive quando o defensor passou sem bloquear). Frágil e
  -- Agressivo (US #18) entram aqui.
  function Game:finalize_blocks(cb)
  end

  ----------------------------------------------------------------------------
  -- Resolver
  ----------------------------------------------------------------------------

  -- A criatura continua no combate se ainda está em campo, do mesmo lado.
  local function still_in(g, c, side)
    return c ~= nil and c.owner == side and g.players[side].field[c.slot] == c
  end

  -- Velocidade (doc, "Velocidade"): 0 não golpeia; 1 golpeia normalmente; 2 golpeia
  -- antes das de velocidade 1; 3 golpeia antes e de novo junto com as de velocidade
  -- 1, atacando ou bloqueando, mas contra o jogador golpeia uma vez só.
  -- role = "attack" | "block".
  -- Base: def.speed_fn(game, c, role), se existir (ex.: Abelha com 3 Abelhas);
  -- senão def.block_speed bloqueando (ex.: Tentáculo) ou def.speed (padrão 1).
  -- Depois os modificadores da criatura (Game:add_speed_mod), na ordem: primeiro
  -- os relativos (delta), depois os fixos (set; o último vale). Resultado de 0 a 3.
  function Game:speed(c, role)
    local v
    if c.def.speed_fn then v = c.def.speed_fn(self, c, role) end
    if v == nil and role == "block" then v = c.def.block_speed end
    if v == nil then v = c.def.speed or 1 end
    local set
    for _, m in ipairs(c.speed_mods or {}) do
      if m.until_round == nil or self.round <= m.until_round then
        if m.delta then v = v + m.delta end
        if m.set ~= nil then set = m.set end
      end
    end
    if set ~= nil then v = set end
    if v < 0 then v = 0 elseif v > 3 then v = 3 end
    return v
  end

  -- mod = { delta = n } ou { set = n }, com until_round opcional (vale até o fim
  -- dessa rodada; ex.: Dardo do sono, round + 1; Flauta de Pã, round).
  function Game:add_speed_mod(c, mod)
    c.speed_mods = c.speed_mods or {}
    c.speed_mods[#c.speed_mods + 1] = mod
    return mod
  end

  -- Golpear (doc, palavras-chave): a criatura causou dano em combate, atacando ou
  -- bloqueando; dispara a cada golpe. Efeitos: def.on_strike(game, criatura, alvo)
  -- da criatura e dos equipamentos dela (equip.def.on_strike(game, criatura, alvo, equip)).
  -- alvo é a criatura golpeada ou { player = p }.
  function Game:fire_strike_effects(c, target)
    -- Cada efeito de Golpear (o da criatura e o de cada equipamento) é um efeito
    -- próprio para a vitória.
    if c.def.on_strike then self:effect("golpear", c.def.id, c.def.on_strike, self, c, target) end
    for _, slot in ipairs(Game.EQUIP_ORDER) do
      if self.winner ~= nil then return end
      local e = c.equips[slot]
      if e and e.def.on_strike then self:effect("golpear", e.def.id, e.def.on_strike, self, c, target, e) end
    end
  end

  -- Uma fase de golpes: todos os golpes de `strikes` ao mesmo tempo (valores lidos
  -- antes de qualquer dano), depois os efeitos de Golpear, depois a vitória e
  -- depois as mortes. strikes = { { src, alvo }, ... }.
  function Game:strike_phase(strikes)
    local amounts = {}
    for i, s in ipairs(strikes) do amounts[i] = self:atk(s[1]) end
    local killers, hits = {}, {}
    for i, s in ipairs(strikes) do
      local n = self:strike(s[1], s[2], amounts[i], true)
      if not s[2].player then killers[s[2]] = s[1] end
      if n > 0 then hits[#hits + 1] = s end
    end
    -- O dano dos golpes da fase é simultâneo, e a vitória por ele é verificada
    -- antes dos efeitos. Cada efeito de Golpear conta separadamente: se um decidir
    -- a partida, os seguintes não acontecem.
    self:check_winner()
    for _, s in ipairs(hits) do
      if self.winner ~= nil then return end
      self:fire_strike_effects(s[1], s[2])
    end
    if self.winner ~= nil then return end
    self:check_lethal(killers, "combate")
  end

  -- Monta os golpes de uma fase. phase = "rapida" (velocidade 2 e 3) ou
  -- "normal": quem golpeou na rápida só golpeia de novo se ainda tiver velocidade
  -- 3; quem não golpeou golpeia com velocidade 1 ou mais. Quem já golpeou o jogador
  -- não golpeia de novo. Criatura com dano letal (esperando uma escolha para
  -- morrer) não golpeia.
  local function phase_strikes(g, cb, phase, struck, struck_player)
    local strikes = {}
    -- Criatura com dano letal (esperando uma escolha para morrer) já está fora
    -- do combate: não golpeia nem é golpeada.
    local function alive(c) return c.damage < g:hp(c) end
    local function strikes_now(c, role)
      local v = g:speed(c, role)
      if phase == "rapida" then return v >= 2 end
      if struck[c] then return v == 3 end
      return v >= 1
    end
    for _, a in ipairs(cb.attackers) do
      if still_in(g, a, cb.attacker) then
        if cb.blocked[a] then
          local d = cb.blocks[a]
          if still_in(g, d, cb.defender) and alive(a) and alive(d) then
            if strikes_now(a, "attack") then strikes[#strikes + 1] = { a, d } end
            if strikes_now(d, "block") then strikes[#strikes + 1] = { d, a } end
          end
        elseif not struck_player[a] and alive(a) and strikes_now(a, "attack") then
          struck_player[a] = true
          strikes[#strikes + 1] = { a, { player = cb.defender } }
        end
      end
    end
    for _, s in ipairs(strikes) do struck[s[1]] = true end
    return strikes
  end

  function Game:resolve_combat()
    local cb = self.combat
    if cb == nil then return end
    self.combat = nil
    self:finalize_blocks(cb)
    self:emit{ t = "combat_start", p = cb.attacker }
    local struck, struck_player = {}, {}
    for _, phase in ipairs({ "rapida", "normal" }) do
      local strikes = phase_strikes(self, cb, phase, struck, struck_player)
      if #strikes > 0 then
        self:emit{ t = "strike_phase", phase = phase }
        self:strike_phase(strikes)
      end
      if self.winner ~= nil then return end
    end
    self:emit{ t = "combat_end", p = cb.attacker }
  end
end
