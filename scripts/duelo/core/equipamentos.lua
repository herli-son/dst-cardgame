-- Equipamentos presos a Sobreviventes. Lua 5.1 puro.
-- Instala os métodos no Game: require("duelo/core/equipamentos")(Game)
--
-- Campos da definição de um equipamento:
--   slot = "mao" | "peito" | "cabeca"
--   atk_bonus, hp_bonus   bônus enquanto equipado
--   durability            durabilidade inicial (nil = sem durabilidade)
--   on_equip(game, criatura, equipamento)

return function(Game)
  Game.EQUIP_SLOTS = { mao = true, peito = true, cabeca = true }
  -- Ordem fixa dos espaços, para descarte e eventos sempre na mesma sequência.
  Game.EQUIP_ORDER = { "mao", "peito", "cabeca" }

  -- Só Sobreviventes usam equipamentos, salvo cartas que digam o contrário.
  function Game:can_equip(c)
    return c.def.sobrevivente == true or c.can_equip == true
  end

  -- Guarda uma carta no Inventário; acima do limite de mão, ela é destruída.
  function Game:add_to_inventory(p, card)
    if self:hand_count(p) >= self:hand_limit(p) then
      self:destroy_card(p, card, "limite_de_mao")
      return false
    end
    local inv = self.players[p].inventory
    inv[#inv + 1] = card
    self:emit{ t = "inventory", p = p, card_uid = card.uid, id = card.id }
    return true
  end

  -- Prende um equipamento à criatura. Se o espaço estiver ocupado, o antigo vai
  -- para o Inventário do dono com os marcadores (a durabilidade fica na carta).
  function Game:equip(c, card)
    local def = self:def_of(card)
    local old = c.equips[def.slot]
    if old then
      c.equips[def.slot] = nil
      -- Mesma regra da saída de campo: a ficha volta ao baralho extra.
      self:deposit_equips(c.owner, { old }, "troca")
    end
    local e = {
      uid = self:next_uid(),
      card_uid = card.uid,
      card = card,
      def = def,
      durability = card.durability or def.durability,
    }
    c.equips[def.slot] = e
    self:emit{ t = "equip", p = c.owner, slot = c.slot, holder_uid = c.uid, equip_slot = def.slot,
      uid = e.uid, card_uid = e.card_uid, id = def.id }
    if def.on_equip then self:effect("equipar", def.id, def.on_equip, self, c, e) end
    return e
  end

  -- Tira o equipamento de um espaço e manda para o descarte (fichas deixam de existir).
  function Game:discard_equip(c, equip_slot, reason)
    local e = c.equips[equip_slot]
    if e == nil then return end
    c.equips[equip_slot] = nil
    self:emit{ t = "unequip", p = c.owner, slot = c.slot, holder_uid = c.uid, equip_slot = equip_slot,
      uid = e.uid, card_uid = e.card_uid, id = e.def.id, reason = reason }
    self:to_discard(c.owner, e.card)
  end

  function Game:discard_all_equips(c, reason)
    for _, s in ipairs(Game.EQUIP_ORDER) do self:discard_equip(c, s, reason) end
  end

  -- Manda todos os equipamentos para o Inventário do dono, com os marcadores
  -- (ex.: Telelocador). Fichas deixam de existir.
  function Game:return_all_equips(c, reason)
    self:deposit_equips(c.owner, self:detach_equips(c, reason), reason)
  end

  -- Solta os equipamentos da criatura (com os eventos, enquanto ela ainda está em
  -- campo) e devolve a lista, para irem ao Inventário depois.
  function Game:detach_equips(c, reason)
    local list = {}
    for _, s in ipairs(Game.EQUIP_ORDER) do
      local e = c.equips[s]
      if e then
        c.equips[s] = nil
        self:emit{ t = "unequip", p = c.owner, slot = c.slot, holder_uid = c.uid, equip_slot = s,
          uid = e.uid, card_uid = e.card_uid, id = e.def.id, reason = reason }
        list[#list + 1] = e
      end
    end
    return list
  end

  function Game:deposit_equips(p, list, reason)
    for _, e in ipairs(list) do
      if e.card.ficha then
        self:vanish(p, e.card, reason)
      else
        e.card.durability = e.durability
        self:add_to_inventory(p, e.card)
      end
    end
  end

  -- Gasta durabilidade; em zero, o equipamento vai para o descarte.
  function Game:wear(c, equip_slot, n)
    local e = c.equips[equip_slot]
    if e == nil or e.durability == nil then return end
    e.durability = e.durability - (n or 1)
    if e.durability <= 0 then self:discard_equip(c, equip_slot, "durabilidade") end
  end

  function Game:equip_bonus(c, field)
    local total = 0
    for _, e in pairs(c.equips) do total = total + (e.def[field] or 0) end
    return total
  end

  Game.play_rules.equipamento = {
    -- action.target = espaço de uma criatura sua que possa usar equipamentos
    validate = function(g, p, card, def, action)
      if not Game.EQUIP_SLOTS[def.slot] then return false, "equipamento sem espaço definido" end
      local c = g:creature_at(p, action.target or -1)
      if c == nil then return false, "escolha uma criatura sua" end
      if not g:can_equip(c) then return false, "só Sobreviventes usam equipamentos" end
      return true
    end,
    resolve = function(g, p, card, def, action)
      g:equip(g:creature_at(p, action.target), card)
    end,
  }
end
