-- maquina_de_ciencia: estrutura do deck do Wilson (#20). Lua 5.1 puro.
-- Carregar o arquivo registra a carta no motor e devolve a definição.
-- Os campos usados aqui estão descritos nos cabeçalhos de cards.lua e estruturas.lua.

local Cards = require("duelo/core/cards")

local OLHAR = 5

-- As OLHAR cartas do topo do baralho (o topo é o fim da lista), sem tirá-las.
local function topo(game, p)
  local deck = game.players[p].deck
  local list = {}
  for i = #deck, math.max(1, #deck - OLHAR + 1), -1 do list[#list + 1] = deck[i] end
  return list
end

local function tirar_do_baralho(game, p, card)
  local deck = game.players[p].deck
  for i = #deck, 1, -1 do
    if deck[i] == card then return table.remove(deck, i) end
  end
end

return Cards.define{
  id = "maquina_de_ciencia", name = "Máquina de Ciência", kind = "estrutura", cost = 4, numero = 11,
  -- Ativar (Instantâneo), 1 vez por rodada, sem custo e sem gastar a vez: olhe as
  -- 5 cartas do topo do seu baralho; você pode comprar 1 equipamento entre elas
  -- (def.kind == "equipamento"); as outras voltam ao baralho, que é embaralhado.
  -- As cartas olhadas ficam no baralho enquanto a escolha está aberta; a
  -- escolhida sai dele ao resolver. Sem equipamento entre elas, não há escolha:
  -- o baralho só é embaralhado. O evento "look" (privado) mostra ao dono o que
  -- ele viu. Com menos de 5 cartas, olha as que houver.
  activation = { speed = "instantaneo", once_per_round = true },
  activate = function(game, p, st)
    local spec = { reason = "maquina_de_ciencia", allow_none = true }
    spec.prepare = function(g, sp)
      local vistas = topo(g, p)
      local ids = {}
      for i, card in ipairs(vistas) do ids[i] = { card_uid = card.uid, id = card.id } end
      g:emit{ t = "look", p = p, id = st.def.id, uid = st.uid, cards = ids, private = true }
      sp.options = {}
      for _, card in ipairs(vistas) do
        local def = g:def_of(card)
        if def and def.kind == "equipamento" then sp.options[#sp.options + 1] = card end
      end
      if #sp.options == 0 then
        g:shuffle_deck(p)
        return false
      end
    end
    spec.resolve = function(g, idx)
      if idx ~= nil then
        local card = tirar_do_baralho(g, p, spec.options[idx])
        if card then g:add_to_hand(p, card, "maquina") end
      end
      g:shuffle_deck(p)
    end
    game:set_choice(p, spec)
  end,
  text = "Ativar (Instantâneo), uma vez por rodada: olhe as 5 cartas do topo do seu "
    .. "baralho. Você pode comprar 1 equipamento entre elas. Embaralhe as outras de "
    .. "volta no baralho.",
}
