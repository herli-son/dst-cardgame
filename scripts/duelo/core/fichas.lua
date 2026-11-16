-- Fichas: cartas criadas por efeitos, fora do baralho. Lua 5.1 puro.
-- Instala os métodos no Game: require("duelo/core/fichas")(Game)
--
-- Uma ficha usa a mesma definição da carta de mesmo nome, então tem os mesmos
-- atributos. Quando sai de jogo, ou iria para o descarte, o baralho ou as
-- destruídas, deixa de existir.

return function(Game)
  function Game:make_token(id)
    assert(self:def_of({ id = id }) ~= nil, "ficha desconhecida: " .. tostring(id))
    return { id = id, uid = self:next_uid(), ficha = true }
  end

  function Game:vanish(p, card, reason)
    self:emit{ t = "vanish", p = p, id = card.id, uid = card.uid, reason = reason }
  end

  -- Cria uma ficha para o jogador p.
  -- opts.zone = "hand" para criar na mão; senão vai para o campo conforme o tipo.
  -- opts.slot escolhe o espaço; sem ele, usa o primeiro livre.
  -- Retorna a criatura, a estrutura ou a carta criada, ou nil se não houver espaço.
  function Game:create_token(p, id, opts)
    opts = opts or {}
    local card = self:make_token(id)
    local def = self:def_of(card)
    if opts.zone == "hand" then
      if self:add_to_hand(p, card, "ficha") then return card end
      return nil
    end
    if def.kind == "criatura" then
      local slot = opts.slot
      if slot == nil or self.players[p].field[slot] ~= nil then slot = self:free_slots(p)[1] end
      if slot == nil then
        self:emit{ t = "no_space", p = p, id = id }
        return nil
      end
      return self:place_creature(p, card, slot, { ficha = true })
    elseif def.kind == "estrutura" then
      local slot = opts.slot or self.first_free_structure(self, p)
      if slot == nil then
        -- Zona cheia: o dono escolhe qual estrutura a ficha substitui.
        self:set_choice(p, { reason = "substituir_estrutura", options = { 1, 2 },
          resolve = function(g, idx) g:put_structure(p, card, idx, { ficha = true }) end })
        return nil
      end
      return self:put_structure(p, card, slot, { ficha = true })
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
    pl.field[c.slot] = nil
    if opts.equips == "inventory" then
      self:return_all_equips(c, reason)
    else
      self:discard_all_equips(c, reason)
    end
    self:emit{ t = "leave", p = c.owner, slot = c.slot, uid = c.uid, id = c.def.id, dest = dest, reason = reason }
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
  -- (o dela, on_death, e os ganchos "death" da partida).
  function Game:kill(c, reason)
    local pl = self.players[c.owner]
    if pl.field[c.slot] ~= c then return end
    self:emit{ t = "death", p = c.owner, slot = c.slot, uid = c.uid, id = c.def.id, reason = reason }
    self:remove_creature(c, "discard", reason or "abatida")
    if c.def.on_death then c.def.on_death(self, c) end
    self:run_hooks("death", c)
  end
end
