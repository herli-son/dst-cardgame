-- Criaturas neutras do MVP (#22): cartas comuns aos dois baralhos. Lua 5.1 puro.
-- Carregar o módulo registra as cartas no motor (Cards.define) e devolve a
-- lista dos ids registrados, na ordem do documento.
--
-- Os campos usados aqui estão descritos no cabeçalho de cards.lua.

local Cards = require("duelo/core/cards")

local ids = {}

local function define(def)
  Cards.define(def)
  ids[#ids + 1] = def.id
  return def
end

----------------------------------------------------------------------------
-- Porcos
----------------------------------------------------------------------------

define{
  id = "porco", name = "Porco", kind = "criatura", cost = 4,
  atk = 4, hp = 5,
  types = { porco = true },
  text = "Porco. Sem efeito.",
}

-- A Guarda (o salto para o próximo atacante sem bloqueador) é regra do motor:
-- ver combate.lua. A carta só carrega a palavra-chave.
define{
  id = "porco_guarda", name = "Porco guarda", kind = "criatura", cost = 5,
  atk = 2, hp = 7,
  types = { porco = true },
  kw = { guarda = true },
  text = "Porco. Guarda: ao bloquear e sobreviver, passa a bloquear também o "
    .. "próximo atacante à direita que ficou sem bloqueador, uma vez por combate.",
}

----------------------------------------------------------------------------
-- Sapo
----------------------------------------------------------------------------

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

define{
  id = "sapo", name = "Sapo", kind = "criatura", cost = 1,
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

----------------------------------------------------------------------------
-- Morcego
----------------------------------------------------------------------------

-- Ataque e vida por período (Game:period(): "manha" | "tarde" | "noite").
local MORCEGO = { manha = { 0, 1 }, tarde = { 1, 1 }, noite = { 2, 1 } }

define{
  id = "morcego", name = "Morcego", kind = "criatura", cost = 1,
  atk = 0, hp = 1, speed = 2,
  kw = { agressivo = true },
  stats = function(game, c)
    local s = MORCEGO[game:period()] or MORCEGO.manha
    return s[1], s[2]
  end,
  text = "Agressivo. Velocidade 2. De manhã é 0/1, à tarde 1/1 e à noite 2/1.",
}

----------------------------------------------------------------------------
-- Pássaro e Borboleta
----------------------------------------------------------------------------

define{
  id = "passaro", name = "Pássaro", kind = "criatura", cost = 1,
  atk = 0, hp = 1,
  kw = { fragil = true },
  -- Reage à entrada de qualquer criatura Agressiva, de qualquer jogador, jogada
  -- ou criada. O abate dispara o "ao morrer" normalmente; a compra vem depois.
  on_any_enter = function(game, passaro, nova)
    if not nova.def.kw.agressivo then return end
    game:kill(passaro, "passaro")
    game:draw(passaro.owner, 1)
  end,
  text = "Frágil. Quando uma criatura Agressiva entra em jogo, abata o Pássaro "
    .. "e o dono dele compra 1 carta.",
}

define{
  id = "borboleta", name = "Borboleta", kind = "criatura", cost = 1,
  atk = 0, hp = 1,
  kw = { fragil = true },
  on_death = function(game, c)
    game:heal_player(c.owner, 2, "borboleta")
  end,
  text = "Frágil. Ao morrer, o dono recupera 2 de vida.",
}

----------------------------------------------------------------------------
-- Cão de caça
----------------------------------------------------------------------------

-- As variantes por estação ficam para a US #45.
define{
  id = "cao_de_caca", name = "Cão de caça", kind = "criatura", cost = 2,
  atk = 2, hp = 2,
  kw = { agressivo = true },
  text = "Agressivo.",
}

return ids
