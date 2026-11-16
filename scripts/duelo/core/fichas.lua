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
      if self:add_to_hand(p, card) then return card end
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
      return self:put_structure(p, card, opts.slot, { ficha = true })
    end
    error("ficha de tipo sem lugar em campo: " .. tostring(def.kind))
  end

  -- Tira uma criatura de campo. dest = "discard" | "hand" | "deck" | "destroyed".
  -- Os equipamentos vão para o descarte. Fichas deixam de existir em qualquer destino.
  function Game:remove_creature(c, dest, reason)
    local pl = self.players[c.owner]
    if pl.field[c.slot] ~= c then return end
    pl.field[c.slot] = nil
    self:discard_all_equips(c, reason)
    self:emit{ t = "leave", p = c.owner, slot = c.slot, uid = c.uid, id = c.def.id, dest = dest, reason = reason }
    local card = c.card
    card.durability = nil
    if c.ficha or card.ficha then
      self:vanish(c.owner, card, reason)
    elseif dest == "hand" then
      self:add_to_hand(c.owner, card)
    elseif dest == "deck" then
      pl.deck[#pl.deck + 1] = card
    elseif dest == "destroyed" then
      self:destroy_card(c.owner, card, reason)
    else
      pl.discard[#pl.discard + 1] = card
    end
  end
end
