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
--   * Bloqueios obrigatórios (doc, "Palavras-chave"), em ordem de prioridade:
--     1. Rival (tipo): o atacante Rival deve ser bloqueado por uma criatura desse
--        tipo, se o defensor tiver;
--     2. Frágil: o atacante Frágil deve ser bloqueado por uma Agressiva, se o
--        defensor tiver;
--     3. Agressivo: o atacante Agressivo sem bloqueio é bloqueado por uma Frágil
--        do defensor que esteja livre (sem bloquear ninguém).
--     O defensor declara os pares e o motor confere; se ele passar sem declarar,
--     o motor completa os obrigatórios pela ordem declarada dos atacantes e pela
--     ordem dos espaços dos bloqueadores. Um bloqueador que o atacante recusa
--     (cannot_be_blocked_by; Webber e Aranhas adversárias) não conta, não é
--     exigido nem atraído.
--
-- Resolução par a par (doc, "Combate" e "Velocidade"): o combate resolve na
-- ordem dos espaços dos atacantes (não na ordem declarada), um par de cada vez.
-- O par é o atacante com o bloqueador dele, ou o atacante sozinho golpeando o
-- jogador. O par do espaço 1 resolve por completo, depois o do espaço 2, e assim
-- por diante.
--   * Dentro do par vale a Velocidade: a fase rápida (velocidade 2 e 3) e a fase
--     normal (velocidade 1 e 3), só entre os dois do par. Em cada fase os golpes
--     acontecem ao mesmo tempo, os efeitos de Golpear disparam, a vitória é
--     verificada e só então as criaturas mortas saem de campo. Quem morre na
--     fase rápida não golpeia na normal; a velocidade 3 golpeia nas duas fases,
--     mas contra o jogador golpeia uma vez só.
--   * As mortes, os "ao morrer", o Golpear e as escolhas de um par acontecem
--     antes de o par seguinte começar. Uma escolha aberta segura o resto do
--     combate (a fase seguinte do par ou os pares seguintes), que volta para a
--     pilha e continua depois dela.
--   * Uma criatura que já saiu de campo quando chega a vez do par dela não
--     golpeia nem é golpeada. Se o atacante saiu, o par é pulado. Se o
--     bloqueador saiu (morto por um "ao morrer" de um par anterior, por
--     exemplo), o atacante não golpeia ninguém: o bloqueio declarado vale.
--   * A partida decidida em qualquer fase para o combate.
--   * Durabilidade (doc, "Equipamentos"): em cada fase, depois dos efeitos de
--     Golpear, a ferramenta na mão de quem golpeou perde 1 e a armadura no peito
--     de quem foi golpeado perde 1, por golpe, mesmo com dano zero
--     (wear_from_strikes).
--   * Guarda (kw.guarda; Porco guarda): só na defesa. Depois de resolver o par
--     dela, se sobreviveu e ainda não saltou neste combate, passa a bloquear o
--     próximo atacante à direita (espaço maior que o do atacante que ela
--     bloqueou) que nunca teve bloqueador e ainda está em campo; não salta para
--     quem perdeu o bloqueador nem para um atacante que a recusa
--     (cannot_be_blocked_by), e nesse caso segue para o próximo elegível. Esse par resolve normalmente quando chegar a vez
--     dele, com o dano que ela já tem e revidando. Uma vez por Guarda por
--     combate. O salto é decidido quando chega a vez de um atacante que nunca
--     teve bloqueador: entre as Guardas já resolvidas e elegíveis, salta a do
--     menor espaço. O salto entra em cb.blocks e sai como evento "block" com
--     auto = "guarda".
--
-- Campos da definição usados aqui (referência completa em cards.lua): no_attack,
-- no_block, cannot_be_blocked_by, speed, block_speed, speed_fn, kw (fragil,
-- agressivo, rival, guarda), types, on_strike e on_attack (criatura e equipamento).

return function(Game)
  ----------------------------------------------------------------------------
  -- Golpes e dano em criaturas
  ----------------------------------------------------------------------------

  -- Redução de dano da criatura: a soma de def.damage_reduction dos equipamentos
  -- dela (ex.: Armadura de madeira). Vale para cada fonte de dano, em separado.
  function Game:damage_reduction(c)
    local total = 0
    for _, e in pairs(c.equips or {}) do total = total + (e.def.damage_reduction or 0) end
    return total
  end

  -- O dano fica marcado na criatura (é permanente). Devolve o dano aplicado
  -- (0 se nenhum). A redução de dano entra aqui: o dano de cada fonte perde a
  -- redução, no mínimo 0; reduzido a zero, nada é marcado e sai o evento
  -- "damage_absorbed" (para a tela mostrar que a armadura absorveu um dano de
  -- feitiço ou efeito; em combate o golpe já saiu como "strike" e ainda gasta a
  -- armadura).
  function Game:damage_creature(c, n, source, reason)
    if Game.check_amount(n) <= 0 then return 0 end
    if self.players[c.owner].field[c.slot] ~= c then return 0 end
    local reduced = math.min(self:damage_reduction(c), n)
    n = n - reduced
    if n <= 0 then
      self:emit{ t = "damage_absorbed", p = c.owner, slot = c.slot, uid = c.uid, amount = reduced,
        source_uid = source and source.uid or nil, reason = reason }
      return 0
    end
    c.damage = c.damage + n
    self:emit{ t = "creature_damage", p = c.owner, slot = c.slot, uid = c.uid, amount = n,
      damage = c.damage, source_uid = source and source.uid or nil, reason = reason,
      reduced = reduced > 0 and reduced or nil }
    if c.damage < self:hp(c) then self:fire_survive_effects(c, n, source) end
    return n
  end

  -- "Sobreviveu a dano": a criatura recebeu dano de uma fonte (dano marcado > 0;
  -- dano reduzido a zero não conta) e, logo depois dele, o dano marcado ainda é
  -- menor que a vida. Dispara na hora, dentro de damage_creature, para cada
  -- fonte de dano, em def.on_survive_damage(game, ouvinte, criatura, amount,
  -- source) de cada criatura em campo do mesmo dono (a própria inclusa), na
  -- ordem dos espaços. Cada um é um efeito próprio para a vitória.
  --
  -- Escolha do momento: na hora, e não no estado estável (settle). Em combate,
  -- os golpes de uma fase são simultâneos e as mortes só saem em check_lethal,
  -- mas quem morre já tem dano >= vida ao receber o golpe, então nunca dispara;
  -- quem sobrevive dispara antes dos efeitos de Golpear e da verificação de
  -- mortes da fase. Consequência aceita: se na mesma fase morre a fonte de uma
  -- aura de vida, a sobrevivente é curada com a vida que tinha no golpe, e só
  -- depois a vida cai. Um ouvinte só roda se estiver em jogo (em campo e com
  -- dano < vida, o mesmo critério de in_play); a sobrevivente é reconferida
  -- antes de cada ouvinte, então se um deles a deixar letal, ou a tirar de
  -- campo, ou decidir a partida, os seguintes não rodam.
  function Game:fire_survive_effects(c, amount, source)
    local pl = self.players[c.owner]
    for _, l in ipairs(self:creatures(c.owner)) do
      if self.winner ~= nil or pl.field[c.slot] ~= c or c.damage >= self:hp(c) then return end
      if l.def.on_survive_damage and pl.field[l.slot] == l and l.damage < self:hp(l) then
        self:effect("sobreviver", l.def.id, l.def.on_survive_damage, self, l, c, amount, source)
      end
    end
  end

  -- Cura tira marcadores de dano; nunca mais do que o dano que a criatura tem.
  -- Devolve o quanto curou (0 se nada), para efeitos como o da Curandeira com o
  -- Webber. source é a carta ou criatura que curou, quando houver.
  function Game:heal_creature(c, n, source, reason)
    if Game.check_amount(n) <= 0 then return 0 end
    if self.players[c.owner].field[c.slot] ~= c then return 0 end
    local amount = math.min(n, c.damage)
    if amount <= 0 then return 0 end
    c.damage = c.damage - amount
    -- Quem causou um dano letal pendente deixa de valer: se o dano voltar ao
    -- mesmo valor por outra fonte, a morte não é dele.
    if self.pending_lethal then self.pending_lethal[c] = nil end
    self:emit{ t = "creature_heal", p = c.owner, slot = c.slot, uid = c.uid, amount = amount,
      damage = c.damage, source_uid = source and source.uid or nil, reason = reason }
    return amount
  end

  -- Um golpe é um evento próprio, mesmo quando o dano é zero (armaduras perdem
  -- durabilidade ao serem golpeadas). O Golpear só dispara quando o dano aplicado
  -- é maior que zero, e quem dispara é a fase (strike_phase), não esta função.
  -- target é uma criatura ou { player = p }. n é o dano (padrão: o ataque atual).
  -- in_phase = true quando o golpe faz parte de uma fase: a vitória é verificada
  -- no fim da fase. O caminho fora de fase (padrões de n e in_phase) fica para
  -- cartas que golpeiam fora do combate; ele verifica a vitória logo depois do
  -- golpe e não dispara Golpear. Devolve o dano aplicado de fato.
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
  -- Validação, sem declarar: devolve ok, erro e as criaturas, na ordem declarada.
  local function validate_attack(g, p, action)
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
    return true, nil, attackers
  end
  Game.validators.attack = validate_attack

  Game.actions.attack = function(g, p, action)
    local ok, err, attackers = validate_attack(g, p, action)
    if not ok then return false, err end
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
    g:fire_attack_effects(attackers)
    return true, nil, false
  end

  -- "Ao atacar": dispara quando o ataque é declarado, na ordem declarada, para
  -- cada atacante: def.on_attack(game, criatura) da criatura e depois
  -- equip.def.on_attack(game, criatura, equip) de cada equipamento dela (ordem
  -- dos espaços). Cada efeito é um efeito próprio para a vitória.
  function Game:fire_attack_effects(attackers)
    for _, c in ipairs(attackers) do
      if self.winner ~= nil then return end
      if c.def.on_attack then self:effect("atacar", c.def.id, c.def.on_attack, self, c) end
      for _, slot in ipairs(Game.EQUIP_ORDER) do
        if self.winner ~= nil then return end
        local e = c.equips[slot]
        if e and e.def.on_attack then self:effect("atacar", e.def.id, e.def.on_attack, self, c, e) end
      end
    end
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

  ----------------------------------------------------------------------------
  -- Bloqueios obrigatórios: Rival, Frágil e Agressivo
  ----------------------------------------------------------------------------

  local function kw(c, k) return c.def.kw[k] end

  -- Restrição de bloqueio da carta atacante (def.cannot_be_blocked_by, ver
  -- cards.lua): d não pode bloquear a. Vale para o bloqueio declarado, para os
  -- obrigatórios (nem atrai nem exige um bloqueador proibido) e para o salto
  -- da Guarda.
  local function can_block(g, a, d)
    local deny = a.def.cannot_be_blocked_by
    return deny == nil or not deny(g, a, d)
  end

  -- Critério único de quem está no combate, usado nos bloqueios obrigatórios e
  -- nos golpes: em campo, do mesmo lado, e sem dano letal esperando uma escolha
  -- para morrer.
  local function in_play(g, c, side)
    return c ~= nil and c.owner == side and g.players[side].field[c.slot] == c
      and c.damage < g:hp(c)
  end

  -- Quem pode bloquear: as criaturas do defensor que bloqueiam.
  local function blockers_of(g, p)
    local list = {}
    for _, d in ipairs(g:creatures(p)) do
      if not d.def.no_block and in_play(g, d, p) then list[#list + 1] = d end
    end
    return list
  end

  local function attackers_of(g, cb)
    local list = {}
    for _, a in ipairs(cb.attackers) do
      if in_play(g, a, cb.attacker) then list[#list + 1] = a end
    end
    return list
  end

  -- Cada nível diz se o atacante a está sujeito a ele e se d o atende.
  local TIERS = {
    { applies = function(a) return kw(a, "rival") ~= nil end,
      fits = function(a, d) return d.def.types[kw(a, "rival")] == true end },
    { applies = function(a) return kw(a, "fragil") == true end,
      fits = function(a, d) return kw(d, "agressivo") == true end },
  }

  -- O nível que vale para o atacante: o primeiro a que ele está sujeito e que o
  -- defensor pode atender com alguma criatura (Rival tem prioridade sobre Frágil).
  local function tier_of(g, a, defenders)
    for i, t in ipairs(TIERS) do
      if t.applies(a) then
        for _, d in ipairs(defenders) do
          if t.fits(a, d) and can_block(g, a, d) then return i end
        end
      end
    end
  end

  -- Pontuação de um conjunto de pares: quantos obrigatórios de cada nível ficam
  -- atendidos. Compara primeiro o nível 1 (Rival), depois o 2 (Frágil).
  local function better(x, y)
    for k = 1, #TIERS do
      if x[k] ~= y[k] then return x[k] > y[k] end
    end
    return false
  end

  -- Melhor emparelhamento dos obrigatórios: atende o máximo de Rivais e, entre
  -- esses, o máximo de Frágeis. Busca completa (no máximo 6 contra 6); no empate
  -- fica o primeiro achado, pela ordem dos atacantes e dos espaços.
  local function best_forced(g, obligated, tiers, defenders)
    local best_score, best_pairs = nil, nil
    local used, cur, score = {}, {}, {}
    for k = 1, #TIERS do score[k] = 0 end
    local function go(i)
      if i > #obligated then
        if best_score == nil or better(score, best_score) then
          best_score, best_pairs = {}, {}
          for k = 1, #TIERS do best_score[k] = score[k] end
          for n, pr in ipairs(cur) do best_pairs[n] = pr end
        end
        return
      end
      local a = obligated[i]
      local k = tiers[a]
      for _, d in ipairs(defenders) do
        if not used[d] and TIERS[k].fits(a, d) and can_block(g, a, d) then
          used[d] = true; cur[#cur + 1] = { a, d }; score[k] = score[k] + 1
          go(i + 1)
          used[d] = nil; cur[#cur] = nil; score[k] = score[k] - 1
        end
      end
      go(i + 1)
    end
    go(1)
    return best_score, best_pairs
  end

  -- O melhor emparelhamento só depende de quem está no combate (atacantes e
  -- bloqueadores em jogo). Fica guardado por combate, fora do estado da partida,
  -- porque a validação de bloqueios (can_act) pode ser chamada milhares de vezes
  -- para o mesmo combate.
  local forced_cache = setmetatable({}, { __mode = "k" })

  local function obligations(g, cb)
    local defenders = blockers_of(g, cb.defender)
    local attackers = attackers_of(g, cb)
    local obligated, tiers = {}, {}
    local key = {}
    for _, a in ipairs(attackers) do
      tiers[a] = tier_of(g, a, defenders)
      if tiers[a] then obligated[#obligated + 1] = a end
      key[#key + 1] = a.uid
    end
    key[#key + 1] = "/"
    for _, d in ipairs(defenders) do key[#key + 1] = d.uid end
    key = table.concat(key, ",")
    local cached = forced_cache[cb]
    if cached == nil or cached.key ~= key then
      local score, pairs = best_forced(g, obligated, tiers, defenders)
      cached = { key = key, score = score, pairs = pairs }
      forced_cache[cb] = cached
    end
    return attackers, defenders, obligated, tiers, cached
  end

  local TIER_MESSAGES = {
    "atacante Rival deve ser bloqueado por uma criatura do tipo dele",
    "atacante Frágil deve ser bloqueado por uma criatura Agressiva",
  }

  -- Confere os pares contra as regras. pairs = { { atacante, bloqueador }, ... }.
  -- Recusa se os pares atendem menos obrigatórios do que seria possível.
  function Game:check_forced_blocks(cb, pairs)
    local attackers, defenders, obligated, tiers, forced = obligations(self, cb)
    local block_of, blocking = {}, {}
    for _, pr in ipairs(pairs) do block_of[pr[1]], blocking[pr[2]] = pr[2], pr[1] end
    local declared = {}
    for k = 1, #TIERS do declared[k] = 0 end
    for _, a in ipairs(obligated) do
      local k = tiers[a]
      -- validate_block já recusou pares proibidos; o can_block aqui só protege
      -- quem chamar este método direto.
      if block_of[a] and TIERS[k].fits(a, block_of[a]) and can_block(self, a, block_of[a]) then
        declared[k] = declared[k] + 1
      end
    end
    local best = forced.score
    for k = 1, #TIERS do
      if declared[k] < best[k] then return false, TIER_MESSAGES[k] end
      if declared[k] > best[k] then break end
    end
    for _, a in ipairs(attackers) do
      if kw(a, "agressivo") and not block_of[a] then
        for _, d in ipairs(defenders) do
          if kw(d, "fragil") and not blocking[d] and can_block(self, a, d) then
            return false, "atacante Agressivo sem bloqueio deve ser bloqueado por uma Frágil livre"
          end
        end
      end
    end
    return true
  end

  -- Completa os pares obrigatórios quando o defensor não declarou: o melhor
  -- emparelhamento de Rival e Frágil, depois as Frágeis livres nos Agressivos.
  local function auto_blocks(g, cb)
    local attackers, defenders, _, _, forced = obligations(g, cb)
    local used, pairs = {}, {}
    local function set(a, d)
      used[d] = true
      cb.blocks[a], cb.blocked[a] = d, true
      pairs[#pairs + 1] = { attacker = a.uid, blocker = d.uid }
    end
    for _, pr in ipairs(forced.pairs) do set(pr[1], pr[2]) end
    for _, a in ipairs(attackers) do
      if kw(a, "agressivo") and not cb.blocked[a] then
        for _, d in ipairs(defenders) do
          if not used[d] and kw(d, "fragil") and can_block(g, a, d) then set(a, d); break end
        end
      end
    end
    if #pairs > 0 then g:emit{ t = "block", p = cb.defender, blocks = pairs, auto = true } end
  end

  -- action = { type = "block", blocks = { { attacker = espaço, blocker = espaço }, ... } }
  -- Uma lista vazia declara que não há bloqueios e não conta como pôr algo na pilha.
  -- Validação, sem declarar: devolve ok, erro e os pares { atacante, bloqueador }.
  local function validate_block(g, p, action)
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
      if not can_block(g, a, d) then return false, "essa criatura não pode bloquear esse atacante" end
      if atk_used[a] then return false, "cada atacante é bloqueado por uma criatura só" end
      if blk_used[d] then return false, "cada criatura bloqueia um atacante só" end
      atk_used[a], blk_used[d] = true, true
      chosen[#chosen + 1] = { a, d }
    end
    local ok, why = g:check_forced_blocks(cb, chosen)
    if not ok then return false, why end
    return true, nil, chosen
  end
  Game.validators.block = validate_block

  Game.actions.block = function(g, p, action)
    local ok, err, chosen = validate_block(g, p, action)
    if not ok then return false, err end
    local cb = g.combat
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
  -- combate. Se o defensor passou sem declarar, os bloqueios obrigatórios são
  -- completados aqui, com quem está em campo agora.
  function Game:finalize_blocks(cb)
    if not cb.blocks_declared then auto_blocks(self, cb) end
  end

  ----------------------------------------------------------------------------
  -- Resolver
  ----------------------------------------------------------------------------

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
    if c.def.speed_fn then v = self:run_card("velocidade", c.def.id, c.def.speed_fn, self, c, role) end
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
  -- bloqueando; dispara a cada golpe com dano > 0. Efeitos: def.on_strike(game, criatura, alvo)
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

  -- Durabilidade (doc, "Equipamentos"): a ferramenta na mão perde 1 a cada golpe
  -- que o portador dá; a armadura no peito perde 1 a cada golpe que o portador
  -- recebe. Conta todo golpe de combate, mesmo com dano zero (um golpe reduzido
  -- a zero pela armadura ainda gasta a armadura). Roda depois dos efeitos de
  -- Golpear, para um equipamento que quebra no golpe (ex.: Pá, durabilidade 1)
  -- ainda disparar o seu Golpear.
  function Game:wear_from_strikes(strikes)
    for _, s in ipairs(strikes) do
      local src, target = s[1], s[2]
      if self.players[src.owner].field[src.slot] == src then self:wear(src, "mao", 1) end
      if not target.player and self.players[target.owner].field[target.slot] == target then
        self:wear(target, "peito", 1)
      end
    end
  end

  -- Uma fase de golpes: todos os golpes de `strikes` ao mesmo tempo (valores lidos
  -- antes de qualquer dano), depois os efeitos de Golpear, depois a durabilidade,
  -- depois a vitória e depois as mortes. strikes = { { src, alvo }, ... }.
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
    self:wear_from_strikes(strikes)
    self:check_lethal(killers, "combate")
  end

  -- Monta os golpes de uma fase do par do atacante a. phase = "rapida"
  -- (velocidade 2 e 3) ou "normal": quem golpeou na rápida só golpeia de novo se
  -- ainda tiver velocidade 3; quem não golpeou golpeia com velocidade 1 ou mais.
  -- Contra o jogador, um golpe só. struck[c] = true para quem já golpeou neste
  -- par. Quem não está no combate (in_play) não golpeia nem é golpeado: sem o
  -- atacante, o par é pulado; sem o bloqueador, o atacante continua bloqueado e
  -- não golpeia ninguém.
  local function pair_strikes(g, cb, a, phase, struck)
    local strikes = {}
    local function strikes_now(c, role)
      local v = g:speed(c, role)
      if phase == "rapida" then return v >= 2 end
      if struck[c] then return v == 3 end
      return v >= 1
    end
    if in_play(g, a, cb.attacker) then
      if cb.blocked[a] then
        local d = cb.blocks[a]
        if in_play(g, d, cb.defender) then
          if strikes_now(a, "attack") then strikes[#strikes + 1] = { a, d } end
          if strikes_now(d, "block") then strikes[#strikes + 1] = { d, a } end
        end
      elseif not struck[a] and strikes_now(a, "attack") then
        strikes[#strikes + 1] = { a, { player = cb.defender } }
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
    -- A ordem dos pares é a dos espaços dos atacantes, fixada aqui.
    local order = {}
    for i, a in ipairs(cb.attackers) do order[i] = a end
    table.sort(order, function(x, y) return x.slot < y.slot end)
    cb.order = order
    self:emit{ t = "combat_start", p = cb.attacker }
    self:run_combat_pairs(cb, 1, 1, {})
  end

  local PHASES = { "rapida", "normal" }

  -- Guarda: quando chega a vez de um atacante que nunca teve bloqueador, uma
  -- Guarda já resolvida (par dela antes deste), viva e que ainda não saltou
  -- passa a bloqueá-lo; com várias elegíveis, a do menor espaço. Uma vez por
  -- Guarda por combate. O salto vale como bloqueio declarado.
  local function guard_jump(g, cb, k)
    local b = cb.order[k]
    if cb.blocked[b] or not in_play(g, b, cb.attacker) then return end
    cb.guarded = cb.guarded or {}
    local best
    for m = 1, k - 1 do
      local a = cb.order[m]
      local d = cb.blocked[a] and cb.blocks[a] or nil
      if d and kw(d, "guarda") and not cb.guarded[d] and in_play(g, d, cb.defender)
        and can_block(g, b, d) and (best == nil or d.slot < best.slot) then
        best = d
      end
    end
    if best == nil then return end
    cb.guarded[best] = true
    cb.blocks[b], cb.blocked[b] = best, true
    g:emit{ t = "block", p = cb.defender, auto = "guarda",
      blocks = { { attacker = b.uid, blocker = best.uid } } }
  end

  -- Roda os pares a partir do par `first`, começando pela fase `first_phase`
  -- (struck é o estado desse par). Depois de cada fase, se uma escolha ficou
  -- aberta (um "ao morrer" ou um Golpear que pede escolha), o resto do combate
  -- volta para a pilha e só roda depois da escolha, com as mortes já resolvidas.
  function Game:run_combat_pairs(cb, first, first_phase, struck)
    local order = cb.order
    for k = first, #order do
      local a = order[k]
      local from = 1
      if k == first then from = first_phase else struck = {} end
      -- O salto da Guarda é decidido agora, com as Guardas dos pares anteriores.
      if from == 1 then guard_jump(self, cb, k) end
      for ph = from, #PHASES do
        local phase = PHASES[ph]
        local strikes = pair_strikes(self, cb, a, phase, struck)
        if #strikes > 0 then
          local d = cb.blocked[a] and cb.blocks[a] or nil
          self:emit{ t = "strike_phase", phase = phase, attacker_uid = a.uid,
            blocker_uid = d and d.uid or nil }
          self:strike_phase(strikes)
        end
        if self.winner ~= nil then return end
        if (ph < #PHASES or k < #order) and self:choices_waiting() then
          self.stack[#self.stack + 1] = { owner = cb.attacker, label = "ataque",
            resolve = function(g) g:run_combat_pairs(cb, k, ph + 1, struck) end }
          return
        end
      end
      -- O par acabou, com as mortes dele já resolvidas (uma escolha aberta na
      -- última fase retoma aqui, com first_phase além das fases).
    end
    self:emit{ t = "combat_end", p = cb.attacker }
  end
end
