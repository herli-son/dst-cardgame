-- Fichas: cartas criadas por efeitos. Lua 5.1 puro.
-- Instala os métodos no Game: require("duelo/core/fichas")(Game)
--
-- Uma ficha é uma cópia do baralho extra do jogador (doc, "Fichas" e "Baralho
-- extra"): criar tira a cópia de lá, e sem cópia disponível a criação não
-- acontece. A ficha usa a mesma definição da carta de mesmo nome, então tem os
-- mesmos atributos. Quando "deixa de existir", volta para o baralho extra.

return function(Game)
  -- Tira do baralho extra uma cópia da carta id, marcada como ficha. nil se não houver.
  function Game:take_from_extra(p, id)
    assert(self:def_of({ id = id }) ~= nil, "ficha desconhecida: " .. tostring(id))
    local extra = self.players[p].extra
    for i = #extra, 1, -1 do
      if extra[i].id == id then
        local card = table.remove(extra, i)
        card.ficha = true
        return card
      end
    end
  end

  -- A ficha volta para o baralho extra do dono, limpa.
  function Game:vanish(p, card, reason)
    self:reset_card(card)
    local extra = self.players[p].extra
    extra[#extra + 1] = card
    self:emit{ t = "vanish", p = p, id = card.id, card_uid = card.uid, reason = reason }
  end

  -- Cria uma ficha para o jogador p.
  -- opts.zone = "hand" para criar na mão; senão vai para o campo conforme o tipo.
  -- opts.slot escolhe o espaço; sem ele, usa o primeiro livre.
  -- Retorna a criatura, a estrutura ou a carta criada. Sem isso, retorna nil e o motivo:
  -- "sem_copia" (o baralho extra não tem cópia), "sem_espaco" (não foi criada) ou
  -- "pendente" (o dono escolhe onde ela entra).
  function Game:create_token(p, id, opts)
    opts = opts or {}
    local def = self:def_of({ id = id })
    assert(def ~= nil, "ficha desconhecida: " .. tostring(id))
    local slot
    if opts.zone ~= "hand" and def.kind == "criatura" then
      slot = opts.slot
      if slot == nil or self.players[p].field[slot] ~= nil then slot = self:free_slots(p)[1] end
      -- Sem espaço, a cópia nem sai do baralho extra.
      if slot == nil then
        self:emit{ t = "no_space", p = p, id = id }
        return nil, "sem_espaco"
      end
    end
    local card = self:take_from_extra(p, id)
    if card == nil then
      self:emit{ t = "no_copy", p = p, id = id }
      return nil, "sem_copia"
    end
    if opts.zone == "hand" then
      if self:add_to_hand(p, card, "ficha") then return card end
      return nil, "sem_espaco"
    end
    if def.kind == "criatura" then
      return self:place_creature(p, card, slot, { ficha = true })
    elseif def.kind == "estrutura" then
      return self:enter_structure(p, card, { slot = opts.slot, ficha = true })
    end
    error("ficha de tipo sem lugar em campo: " .. tostring(def.kind))
  end

  -- Tira uma criatura de campo. dest = "discard" | "hand" | "deck" | "destroyed".
  -- opts.equips = "discard" (padrão) ou "inventory" (ex.: Telelocador).
  -- Fichas deixam de existir em qualquer destino.
  function Game:remove_creature(c, dest, reason, opts)
    opts = opts or {}
    local pl = self.players[c.owner]
    if pl.field[c.slot] ~= c then return end
    -- Os equipamentos saem da criatura primeiro (eventos com ela ainda em campo).
    -- Para o Inventário, eles só vão depois de a criatura chegar ao destino, porque
    -- a criatura devolvida à mão tem prioridade no limite de mão.
    local detached
    if opts.equips == "inventory" then
      detached = self:detach_equips(c, reason)
    else
      self:discard_all_equips(c, reason)
    end
    pl.field[c.slot] = nil
    self:emit{ t = "leave", p = c.owner, slot = c.slot, uid = c.uid, card_uid = c.card_uid,
      id = c.def.id, dest = dest, reason = reason }
    self:send_card(c, dest, reason)
    if detached then self:deposit_equips(c.owner, detached, reason) end
  end

  function Game:send_card(c, dest, reason)
    local pl = self.players[c.owner]
    local card = c.card
    if c.ficha or card.ficha then
      self:vanish(c.owner, card, reason)
      return
    end
    self:reset_card(card)
    if dest == "hand" then
      self:add_to_hand(c.owner, card, "campo")
    elseif dest == "deck" then
      pl.deck[#pl.deck + 1] = card
    elseif dest == "destroyed" then
      self:destroy_card(c.owner, card, reason)
    else
      self:to_discard(c.owner, card)
    end
  end

  -- Abater: a criatura morre, vai para o descarte e dispara os efeitos "ao morrer"
  -- (o dela, on_death, e os ganchos "death" da partida). killer é a criatura que
  -- causou a morte, quando houver (Cão vermelho, Cão de gelo).
  function Game:kill(c, reason, killer)
    self:kill_many({ { c, killer } }, reason)
  end

  -- Abate toda criatura com dano maior ou igual à vida. Repete enquanto houver
  -- mortes, porque um efeito "ao morrer" pode deixar outra criatura com dano
  -- letal; para se a partida for decidida ou se um efeito abrir uma escolha.
  -- killers[c] = criatura que causou o dano letal em c; reason vale para elas.
  -- Se a verificação tiver de esperar uma escolha, quem matou e o motivo ficam
  -- guardados (pending_lethal) e valem quando a verificação rodar.
  function Game:check_lethal(killers, reason)
    local pend = self.pending_lethal or {}
    -- A entrada guarda o dano daquele momento: se o dano mudar depois (cura ou
    -- outra fonte), ela deixa de valer.
    for c, k in pairs(killers or {}) do pend[c] = { killer = k, reason = reason, damage = c.damage } end
    self.pending_lethal = pend
    while self.winner == nil and not self:choices_waiting() do
      local dead = {}
      for _, c in ipairs(self:all_creatures()) do
        if c.damage >= self:hp(c) then
          local info = self.pending_lethal[c]
          if info and info.damage ~= c.damage then info = nil end
          dead[#dead + 1] = { c, info and info.killer, info and info.reason or "dano" }
        end
      end
      self.pending_lethal = {}
      if #dead == 0 then return end
      self:kill_many(dead, "dano")
    end
  end

  -- Estado estável: depois de cada ação, de cada efeito resolvido e de cada troca
  -- de vez, período ou rodada, abate as criaturas com dano letal. Não roda com
  -- escolhas esperando; roda de novo quando a última for feita.
  function Game:settle()
    if self.winner == nil and not self:choices_waiting() then self:check_lethal() end
  end

  -- Mortes simultâneas (ex.: golpes da mesma fase do combate): todas saem de campo
  -- antes de qualquer efeito "ao morrer" disparar. killer pode já estar fora de
  -- campo, inclusive por ter morrido junto; os efeitos devem conferir isso.
  -- list = { { criatura, quem_matou, motivo }, ... }; o motivo de cada item vale
  -- no lugar de reason.
  function Game:kill_many(list, reason)
    local dead, seen = {}, {}
    for _, item in ipairs(list) do
      local c, killer = item[1], item[2]
      if not seen[c] and self.players[c.owner].field[c.slot] == c then
        seen[c] = true
        self:emit{ t = "death", p = c.owner, slot = c.slot, uid = c.uid, card_uid = c.card_uid, id = c.def.id,
          reason = item[3] or reason, killer_uid = killer and killer.uid or nil }
        dead[#dead + 1] = item
      end
    end
    for _, item in ipairs(dead) do self:remove_creature(item[1], "discard", item[3] or reason or "abatida") end
    for _, item in ipairs(dead) do
      -- Partida decidida: os efeitos de morte que faltam não rodam.
      if self.winner ~= nil then return end
      local c, killer = item[1], item[2]
      if c.def.on_death then self:effect("morrer", c.def.id, c.def.on_death, self, c, killer) end
      if self.winner ~= nil then return end
      self:run_hooks("death", c, killer)
    end
  end
end
