-- Gerador de jogadas válidas para o bot. Lua 5.1 puro.
--
-- Interface:
--   local Jogadas = require("duelo/bot/jogadas")
--   Jogadas.list(g, p) -> lista de ações (tabelas aceitas por g:act(p, action))
--
-- Enumera candidatos a partir do estado da partida e deixa passar só os que
-- Game:can_act aceita. Não muda g: só lê o estado e chama can_act, que também
-- não muda nada. A lista é determinística (mesma ordem para o mesmo estado).
--
-- Candidatos gerados:
--   * "choose": cada opção da escolha pendente de p, e "nenhuma" (index 0) se
--     a escolha permitir; com escolha pendente, nada mais é gerado;
--   * "pass": sempre que p tem a vez;
--   * "play": cada carta da mão, do Inventário e das separadas, com cada espaço
--     possível (livres; com o campo ou a zona cheia, cada espaço a substituir),
--     cada combinação de sacrifício quando a carta pede, e, para cartas que
--     miram (def.targets ou def.play_targets), cada alvo único entre criaturas,
--     estruturas e jogadores em action.target (listas em action.targets não são
--     geradas); equipamentos miram cada criatura sua;
--   * "attack": cada criatura sozinha e todas juntas;
--   * "block": nenhum bloqueio e cada emparelhamento possível entre atacantes e
--     bloqueadores (até 64 emparelhamentos; acima disso, só nenhum, cada par
--     sozinho e o emparelhamento pela ordem dos espaços);
--   * "activate": cada estrutura sua, cada criatura sua e cada equipamento dela
--     com def.activate, com os mesmos alvos das cartas que miram.

local Game = require("duelo/core/game")

local Jogadas = {}

-- Cópia rasa de uma ação, para variar um campo sem mexer nas outras.
local function with(action, k, v)
  local c = {}
  for key, val in pairs(action) do c[key] = val end
  c[k] = v
  return c
end

-- Todos os alvos únicos possíveis: criaturas e estruturas em campo e os dois jogadores.
local function all_targets(g)
  local list = {}
  for p = 1, 2 do
    for s = 1, Game.FIELD_SLOTS do
      if g:creature_at(p, s) then list[#list + 1] = { p = p, slot = s, zone = "criatura" } end
    end
  end
  for p = 1, 2 do
    for s = 1, Game.STRUCTURE_SLOTS do
      if g:structure_at(p, s) then list[#list + 1] = { p = p, slot = s, zone = "estrutura" } end
    end
  end
  for p = 1, 2 do list[#list + 1] = { p = p, zone = "jogador" } end
  return list
end

-- Variações de alvo de uma ação: sem alvo e com cada alvo possível.
local function with_targets(g, base, needs_target)
  if not needs_target then return { base } end
  local out = { base }
  for _, t in ipairs(all_targets(g)) do out[#out + 1] = with(base, "target", t) end
  return out
end

-- Combinações de k elementos da lista, na ordem.
local function combinations(list, k)
  local out = {}
  local cur = {}
  local function go(start)
    if #cur == k then
      local c = {}
      for i, v in ipairs(cur) do c[i] = v end
      out[#out + 1] = c
      return
    end
    for i = start, #list do
      cur[#cur + 1] = list[i]
      go(i + 1)
      cur[#cur] = nil
    end
  end
  go(1)
  return out
end

local function own_creature_slots(g, p)
  local slots = {}
  for _, c in ipairs(g:creatures(p)) do slots[#slots + 1] = c.slot end
  return slots
end

-- Candidatos de jogar uma carta da zona `from`, índice i.
local function play_candidates(g, p, from, i, card, out)
  local def = g:def_of(card)
  local base = { type = "play", from = from, hand_index = i }
  if def == nil then out[#out + 1] = base; return end
  local needs_target = def.targets ~= nil or def.play_targets ~= nil

  if def.kind == "criatura" then
    local free = g:free_slots(p)
    local bases = {}
    if def.sacrifice then
      local mine = own_creature_slots(g, p)
      for _, combo in ipairs(combinations(mine, def.sacrifice.count)) do
        -- O espaço pode ser um livre ou o de uma sacrificada.
        local slots = {}
        for _, s in ipairs(free) do slots[#slots + 1] = s end
        for _, s in ipairs(combo) do slots[#slots + 1] = s end
        for _, s in ipairs(slots) do
          bases[#bases + 1] = with(with(base, "sacrifice", combo), "slot", s)
        end
      end
    else
      local slots = free
      if #slots == 0 then
        slots = {}
        for s = 1, Game.FIELD_SLOTS do slots[s] = s end
      end
      for _, s in ipairs(slots) do bases[#bases + 1] = with(base, "slot", s) end
    end
    for _, b in ipairs(bases) do
      for _, a in ipairs(with_targets(g, b, needs_target)) do out[#out + 1] = a end
    end
    return
  end

  if def.kind == "estrutura" then
    local bases = {}
    if Game.first_free_structure(g, p) ~= nil then
      bases[1] = base
    else
      for s = 1, Game.STRUCTURE_SLOTS do bases[#bases + 1] = with(base, "slot", s) end
    end
    for _, b in ipairs(bases) do
      for _, a in ipairs(with_targets(g, b, needs_target)) do out[#out + 1] = a end
    end
    return
  end

  if def.kind == "equipamento" then
    for _, s in ipairs(own_creature_slots(g, p)) do out[#out + 1] = with(base, "target", s) end
    return
  end

  if def.kind == "feitico" then
    local bases = { base }
    if def.creates_structure and Game.first_free_structure(g, p) == nil then
      bases = {}
      for s = 1, Game.STRUCTURE_SLOTS do bases[#bases + 1] = with(base, "replace", s) end
    end
    for _, b in ipairs(bases) do
      for _, a in ipairs(with_targets(g, b, needs_target)) do out[#out + 1] = a end
    end
    return
  end

  -- Tipo sem regra de jogada conhecida: can_act decide.
  out[#out + 1] = base
end

local function attack_candidates(g, p, out)
  if g.attacker ~= p or g.attacked_round == g.round or g:stack_open() then return end
  local slots = {}
  for _, c in ipairs(g:creatures(p)) do
    if not c.def.no_attack then slots[#slots + 1] = c.slot end
  end
  for _, s in ipairs(slots) do out[#out + 1] = { type = "attack", attackers = { s } } end
  if #slots > 1 then out[#out + 1] = { type = "attack", attackers = slots } end
end

-- 6 atacantes contra 6 bloqueadores dão 2119 emparelhamentos: cabe inteiro.
local BLOCK_LIMIT = 4096

-- Emparelhamentos: cada atacante bloqueado por no máximo um bloqueador, cada
-- bloqueador em no máximo um atacante. Devolve nil se passar do limite.
local function all_matchings(attackers, blockers)
  local out = {}
  local used, cur = {}, {}
  local overflow = false
  local function go(i)
    if overflow then return end
    if i > #attackers then
      if #out >= BLOCK_LIMIT then overflow = true; return end
      local blocks = {}
      for n, pr in ipairs(cur) do blocks[n] = { attacker = pr[1], blocker = pr[2] } end
      out[#out + 1] = blocks
      return
    end
    go(i + 1)
    for _, b in ipairs(blockers) do
      if not used[b] then
        used[b] = true; cur[#cur + 1] = { attackers[i], b }
        go(i + 1)
        used[b] = nil; cur[#cur] = nil
      end
    end
  end
  go(1)
  if overflow then return nil end
  return out
end

local function block_candidates(g, p, out)
  if not g:can_declare_blocks(p) then return end
  local cb = g.combat
  local attackers, blockers = {}, {}
  for _, a in ipairs(cb.attackers) do
    if g.players[cb.attacker].field[a.slot] == a then attackers[#attackers + 1] = a.slot end
  end
  for _, d in ipairs(g:creatures(p)) do
    if not d.def.no_block then blockers[#blockers + 1] = d.slot end
  end
  local sets = all_matchings(attackers, blockers) or { {} }
  for _, blocks in ipairs(sets) do out[#out + 1] = { type = "block", blocks = blocks } end
end

local function activate_candidates(g, p, out)
  local function add(base, def)
    for _, a in ipairs(with_targets(g, base, def.targets ~= nil)) do out[#out + 1] = a end
  end
  for s = 1, Game.STRUCTURE_SLOTS do
    local st = g:structure_at(p, s)
    if st and st.def.activate then add({ type = "activate", structure = s }, st.def) end
  end
  for _, c in ipairs(g:creatures(p)) do
    if c.def.activate then add({ type = "activate", creature = c.slot }, c.def) end
    for _, k in ipairs(Game.EQUIP_ORDER) do
      local e = c.equips[k]
      if e and e.def.activate then add({ type = "activate", creature = c.slot, equip = k }, e.def) end
    end
  end
end

-- Lista as jogadas válidas de p no estado atual de g, sem mudar g.
function Jogadas.list(g, p)
  local out = {}
  if g.phase ~= "playing" or g.winner ~= nil then return out end
  local candidates = {}
  local ch = g.pending_choice
  if ch then
    if ch.player ~= p then return out end
    for i = 1, #(ch.options or {}) do candidates[#candidates + 1] = { type = "choose", index = i } end
    if ch.allow_none then candidates[#candidates + 1] = { type = "choose", index = 0 } end
  elseif g.active == p then
    candidates[#candidates + 1] = { type = "pass" }
    local pl = g.players[p]
    for _, from in ipairs({ "hand", "inventory", "separated" }) do
      for i, card in ipairs(pl[from]) do play_candidates(g, p, from, i, card, candidates) end
    end
    attack_candidates(g, p, candidates)
    block_candidates(g, p, candidates)
    activate_candidates(g, p, candidates)
  else
    return out
  end
  for _, a in ipairs(candidates) do
    if g:can_act(p, a) then out[#out + 1] = a end
  end
  return out
end

return Jogadas
