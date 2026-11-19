-- sapo: criatura neutra do MVP (#22). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

-- Equipamentos da criatura, na ordem fixa dos espaços (Game.EQUIP_ORDER).
local function equips_of(game, c)
  local list = {}
  for _, s in ipairs(game.EQUIP_ORDER) do
    local e = c.equips[s]
    if e then list[#list + 1] = e end
  end
  return list
end

-- Tira o equipamento e da criatura alvo e manda para o Inventário do dono dela,
-- como o motor faz ao trocar um equipamento (deposit_equips: a durabilidade fica
-- na carta; ficha deixa de existir; Inventário cheio destrói). O custo fixado
-- em 1 vale enquanto a carta estiver no Inventário: o motor o limpa ao jogar a
-- carta (jogar.lua) e ao mudar de zona (reset_card).
local function roubar(game, alvo, e)
  local slot
  for s, x in pairs(alvo.equips) do
    if x == e then slot = s end
  end
  if slot == nil then return end
  alvo.equips[slot] = nil
  game:emit{ t = "unequip", p = alvo.owner, slot = alvo.slot, holder_uid = alvo.uid, equip_slot = slot,
    uid = e.uid, card_uid = e.card_uid, id = e.def.id, reason = "sapo" }
  e.card.cost_override = 1
  game:deposit_equips(alvo.owner, { e }, "sapo")
end

return Cards.define{
  id = "sapo", name = "Sapo", kind = "criatura", cost = 1, numero = 3,
  atk = 1, hp = 2,
  kw = { agressivo = true },
  -- Golpear uma criatura com equipamentos: com um só, ele vai direto; com mais,
  -- o dono do Sapo escolhe qual (reason "sapo"). As opções são montadas quando a
  -- escolha abre, com os equipamentos que a criatura tiver nesse momento.
  on_strike = function(game, sapo, alvo)
    if alvo.player then return end
    local list = equips_of(game, alvo)
    if #list == 0 then return end
    if #list == 1 then return roubar(game, alvo, list[1]) end
    local spec = { reason = "sapo" }
    spec.prepare = function(g, sp)
      if g:find_creature(alvo.uid) ~= alvo then return false end
      local now = equips_of(g, alvo)
      if #now == 0 then return false end
      if #now == 1 then
        roubar(g, alvo, now[1])
        return false
      end
      sp.options = now
    end
    spec.resolve = function(g, idx)
      roubar(g, alvo, spec.options[idx])
    end
    game:set_choice(sapo.owner, spec)
  end,
  text = "Agressivo. Golpear: escolha um equipamento da criatura golpeada; ele vai "
    .. "para o Inventário do dono dela e custa 1 enquanto estiver lá.",
}
