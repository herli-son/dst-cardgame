-- Efeitos de início e fim de rodada e de início de período, em ordem. Lua 5.1 puro.
-- Instala os métodos no Game: require("duelo/core/rodada")(Game)
--
-- Campos da definição de uma criatura ou estrutura:
--   on_round_start(game, obj)          no início da rodada (depois da manutenção:
--                                      Fome, mana e compra; antes da manhã)
--   on_round_end(game, obj)            no fim da rodada (dois passes seguidos),
--                                      antes do dano da fogueira e do limite de mão
--   on_period_start(game, obj, period) quando um período começa ("manha",
--                                      "tarde" ou "noite"), depois das regras do
--                                      motor do período (ex.: a fogueira acende)
-- Equipamento: os mesmos ganchos, com o portador, como on_attack e on_strike:
--   on_round_start(game, portador, equip), on_round_end(game, portador, equip),
--   on_period_start(game, portador, equip, period)
--
-- Ordem da passada pelo campo (doc): primeiro o jogador com o token de ataque,
-- depois o outro; para cada um, as criaturas do espaço 1 ao 6 (cada criatura e,
-- logo depois dela, os equipamentos dela na ordem mão, peito, cabeça) e depois
-- as estruturas dos espaços 1 e 2. Os ganchos genéricos da partida (Game:on
-- "round_start", "round_end" e "period", na ordem de registro) rodam depois da
-- passada pelo campo: o campo tem ordem fixa; os ganchos genéricos são efeitos
-- avulsos (feitiços, regras de teste) que ficam por último.
--
-- Cada efeito é uma ação própria para a vitória (Game:effect); com a partida
-- decidida, os que faltam não rodam. Depois de cada efeito o estado estabiliza
-- (Game:settle): quem ficou com dano letal morre antes do efeito seguinte.
--
-- Quem roda: a lista de objetos é fixada no início da passada (pelos uids) e
-- lida objeto a objeto. Quem saiu de campo até a sua vez (morreu, foi devolvido à
-- mão) não roda; quem entrou em campo durante a passada não roda nesta passada
-- (uid novo, fora da lista). Uma criatura que trocou de espaço roda na posição
-- que tinha no início. Os equipamentos são lidos na hora em que o portador roda.
--
-- Escolhas: se um efeito abre uma escolha, a passada para ali e o resto (os
-- objetos seguintes, os ganchos genéricos e o que vem depois do momento: a
-- manhã, o fim da rodada) fica como continuação (Game:after_choices) e retoma
-- quando a escolha for feita.

return function(Game)
  -- Nome do campo da definição e do contexto de erro para cada momento.
  Game.MOMENTS = {
    round_start = { field = "on_round_start", kind = "inicio_rodada" },
    round_end = { field = "on_round_end", kind = "fim_rodada" },
    period = { field = "on_period_start", kind = "inicio_periodo" },
  }

  -- Lista fixa dos objetos em campo, na ordem da passada.
  local function field_plan(g)
    local plan = {}
    local first = g.attacker or 1
    for _, p in ipairs({ first, Game.other(first) }) do
      for s = 1, Game.FIELD_SLOTS do
        local c = g.players[p].field[s]
        if c then plan[#plan + 1] = { zone = "criatura", uid = c.uid } end
      end
      for s = 1, Game.STRUCTURE_SLOTS do
        local st = g.players[p].structures[s]
        if st then plan[#plan + 1] = { zone = "estrutura", uid = st.uid } end
      end
    end
    return plan
  end

  -- Roda o efeito de um objeto do plano, se ele ainda estiver em campo.
  local function run_entry(g, moment, entry, arg)
    local field, kind = moment.field, moment.kind
    if entry.zone == "estrutura" then
      local st = g:find_structure(entry.uid)
      if st and st.def[field] then g:effect(kind, st.def.id, st.def[field], g, st, arg) end
      return
    end
    local c = g:find_creature(entry.uid)
    if c == nil then return end
    if c.def[field] then g:effect(kind, c.def.id, c.def[field], g, c, arg) end
    for _, slot in ipairs(Game.EQUIP_ORDER) do
      -- O portador precisa continuar em campo para os equipamentos dele rodarem.
      if g.winner ~= nil or g:find_creature(entry.uid) ~= c then return end
      local e = c.equips[slot]
      if e and e.def[field] then g:effect(kind, e.def.id, e.def[field], g, c, e, arg) end
    end
  end

  -- Momento da rodada: a passada pelo campo, os ganchos genéricos e, depois de
  -- tudo (inclusive das escolhas abertas no meio), then_fn(game), se houver.
  -- event = "round_start" | "round_end" | "period"; arg é o período, no "period".
  function Game:run_moment(event, arg, then_fn)
    local moment = assert(Game.MOMENTS[event], "momento desconhecido: " .. tostring(event))
    local plan = field_plan(self)
    local i = 0
    local function step(g)
      while i < #plan do
        -- Escolha aberta: o resto da passada espera por ela.
        if g:choices_waiting() then return g:after_choices(step) end
        i = i + 1
        if g.winner == nil then
          run_entry(g, moment, plan[i], arg)
          g:settle()
        end
      end
      if g:choices_waiting() then return g:after_choices(step) end
      if g.winner == nil then g:run_hooks(event, arg) end
      if then_fn then g:after_choices(then_fn) end
    end
    step(self)
  end
end
