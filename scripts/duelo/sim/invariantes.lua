-- Invariantes do estado da partida, para o simulador (#26). Lua 5.1 puro.
--
-- Interface:
--   local Invariantes = require("duelo/sim/invariantes")
--   Invariantes.check(g, opts) -> ok, mensagem
--     opts.card_total: total de cartas esperado nas zonas dos dois jogadores
--     (ver Invariantes.count_cards); sem ele, a conservação não é conferida.
--   Invariantes.count_cards(g) -> número de cartas em todas as zonas
--
-- Cada verificação é uma regra que o motor garante depois de cada entrada
-- protegida (Game:act, Game:start, Game:mulligan), e o comentário diz onde o
-- motor a garante. Só lê o estado; nunca o altera. A primeira violação achada
-- vira a mensagem devolvida.

local Game = require("duelo/core/game")

local Invariantes = {}

local function is_int(v)
  return type(v) == "number" and v == v and v % 1 == 0
end

-- Lista em sequência exata: só chaves 1..n (as zonas de cartas usam
-- table.insert, table.remove e d[#d + 1], que só funcionam assim).
local function is_sequence(t)
  if type(t) ~= "table" then return false end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

-- Zonas de cartas de cada jogador, na ordem em que são percorridas.
local CARD_ZONES = { "hand", "deck", "discard", "destroyed", "inventory", "separated", "extra" }

-- Percorre cada carta em cada zona dos dois jogadores: fn(p, zona, carta).
-- As cartas em campo (criatura, estrutura, equipamento) contam como zonas
-- "campo", "estruturas" e "equipamentos".
local function each_card(g, fn)
  for p = 1, 2 do
    local pl = g.players[p]
    for _, zone in ipairs(CARD_ZONES) do
      for _, card in ipairs(pl[zone]) do fn(p, zone, card) end
    end
    for s = 1, Game.FIELD_SLOTS do
      local c = pl.field[s]
      if c then
        fn(p, "campo", c.card)
        for _, k in ipairs(Game.EQUIP_ORDER) do
          local e = c.equips[k]
          if e then fn(p, "equipamentos", e.card) end
        end
      end
    end
    for s = 1, Game.STRUCTURE_SLOTS do
      local st = pl.structures[s]
      if st then fn(p, "estruturas", st.card) end
    end
  end
end

function Invariantes.count_cards(g)
  local n = 0
  each_card(g, function() n = n + 1 end)
  return n
end

-- Cada verificação devolve nil quando passa, ou a mensagem da violação.
local checks = {}

-- Fase e vencedor: Game:check_winner põe winner e phase = "over" juntos; depois
-- de Game:fail a fase é "error". Enquanto "playing", não há vencedor.
checks[#checks + 1] = function(g)
  local PHASES = { setup = true, mulligan = true, playing = true, over = true, error = true }
  if not PHASES[g.phase] then return "fase desconhecida: " .. tostring(g.phase) end
  if g.phase == "over" and g.winner == nil then return "fase over sem vencedor" end
  if g.winner ~= nil and g.phase ~= "over" and g.phase ~= "error" then
    return "vencedor " .. tostring(g.winner) .. " com fase " .. tostring(g.phase)
  end
  if g.winner ~= nil and g.winner ~= 0 and g.winner ~= 1 and g.winner ~= 2 then
    return "vencedor inválido: " .. tostring(g.winner)
  end
end

-- Vez e rodada: Game:begin_round põe active = attacker (1 ou 2), vez = 1,
-- passes = 0 e round >= 1; Game:advance_vez e Game:hand_over só alternam
-- active entre 1 e 2. Dois passes seguidos encerram a rodada na hora (act_impl),
-- então com a partida em andamento passes é 0 ou 1; a exceção é um gancho de
-- fim de rodada que abre uma escolha (Game:end_round espera por ela com
-- after_choices), quando passes fica em 2 até a escolha ser feita.
checks[#checks + 1] = function(g)
  if g.phase ~= "playing" then return end
  if g.active ~= 1 and g.active ~= 2 then return "active inválido: " .. tostring(g.active) end
  if g.attacker ~= 1 and g.attacker ~= 2 then return "attacker inválido: " .. tostring(g.attacker) end
  if not is_int(g.round) or g.round < 1 then return "rodada inválida: " .. tostring(g.round) end
  if not is_int(g.vez) or g.vez < 1 then return "vez inválida: " .. tostring(g.vez) end
  if not is_int(g.passes) or g.passes < 0 then return "passes inválido: " .. tostring(g.passes) end
  if g.passes > 1 and not g:choices_waiting() then
    return "passes em " .. g.passes .. " sem escolha esperando"
  end
end

-- Vida: Game.check_amount só deixa dano e cura inteiros, e Game:heal_player
-- nunca passa de Game.MAX_LIFE. Um jogador com zero ou menos de vida decide a
-- partida no fim do efeito ou da entrada que o deixou assim (Game:as_one_effect,
-- Game:damage_player fora de efeito, Game:strike_phase, Game:finish_round,
-- Game:begin_round), então em andamento os dois têm vida positiva.
checks[#checks + 1] = function(g)
  for p = 1, 2 do
    local life = g.players[p].life
    if not is_int(life) then return "vida do jogador " .. p .. " não é inteira: " .. tostring(life) end
    if life > Game.MAX_LIFE then return "vida do jogador " .. p .. " acima do máximo: " .. life end
    if g.phase == "playing" and g.winner == nil and life <= 0 then
      return "jogador " .. p .. " com vida " .. life .. " e partida em andamento"
    end
  end
end

-- Mana: Game:round_upkeep põe max_mana = min(MAX_MANA, round) e mana = max_mana;
-- Game:spend_mana só gasta o que Game:can_pay_mana confirmou. Fome: Game:round_upkeep
-- só soma 1 por rodada.
checks[#checks + 1] = function(g)
  for p = 1, 2 do
    local pl = g.players[p]
    if not is_int(pl.mana) or not is_int(pl.max_mana) then
      return "mana do jogador " .. p .. " não é inteira: " .. tostring(pl.mana) .. "/" .. tostring(pl.max_mana)
    end
    if pl.max_mana < 0 or pl.max_mana > Game.MAX_MANA then
      return "mana máxima do jogador " .. p .. " fora da faixa: " .. pl.max_mana
    end
    if pl.mana < 0 or pl.mana > pl.max_mana then
      return "mana do jogador " .. p .. " fora da faixa: " .. pl.mana .. "/" .. pl.max_mana
    end
    if not is_int(pl.fome) or pl.fome < 0 then return "fome do jogador " .. p .. " inválida: " .. tostring(pl.fome) end
  end
end

-- Zonas de cartas: sequências sem buracos, cada carta com uid numérico e
-- definição conhecida. O limite de mão não entra aqui: Game:add_to_hand destrói
-- o que passaria dele na entrada, mas um modificador de limite removido (ex.:
-- Mochila desequipada) deixa a mão acima do limite até o fim da rodada, quando
-- Game:enforce_hand_limit destrói o excesso.
checks[#checks + 1] = function(g)
  for p = 1, 2 do
    local pl = g.players[p]
    for _, zone in ipairs(CARD_ZONES) do
      if not is_sequence(pl[zone]) then return "zona " .. zone .. " do jogador " .. p .. " com buracos" end
      for i, card in ipairs(pl[zone]) do
        if type(card) ~= "table" or not is_int(card.uid) then
          return "carta " .. i .. " da zona " .. zone .. " do jogador " .. p .. " sem uid"
        end
        if g:def_of(card) == nil then
          return "carta desconhecida na zona " .. zone .. " do jogador " .. p .. ": " .. tostring(card.id)
        end
      end
    end
  end
end

-- Cartas fora de campo estão limpas: Game:to_discard, Game:destroy_card e
-- Game:vanish chamam Game:reset_card (custo fixado, durabilidade e usos saem).
checks[#checks + 1] = function(g)
  local CLEAN = { discard = true, destroyed = true, extra = true }
  local FIELDS = { "cost_override", "cost_mod", "durability", "used_round", "used_period" }
  for p = 1, 2 do
    local pl = g.players[p]
    for zone in pairs(CLEAN) do
      for _, card in ipairs(pl[zone]) do
        for _, f in ipairs(FIELDS) do
          if card[f] ~= nil then
            return "carta " .. tostring(card.id) .. " na zona " .. zone .. " do jogador " .. p .. " com " .. f .. " = " .. tostring(card[f])
          end
        end
      end
    end
  end
end

-- Criaturas em campo: Game:place_creature cria a instância com owner = p,
-- slot = s, damage = 0, equips = {} e def = def_of(card), e field[s] é a
-- própria instância; nada depois muda owner ou slot. Dano só sobe por
-- Game:damage_creature (inteiro positivo) e só desce por Game:heal_creature (até
-- zero). Dano letal (damage >= hp) é abatido por Game:settle depois de cada
-- entrada, a não ser com uma escolha esperando (Game:check_lethal para nela).
-- O vínculo com uma estrutura (c.link) é desfeito quando ela sai de campo
-- (Game:unlink). Só criaturas vão para field (play_rules.criatura e
-- Game:create_token conferem o tipo).
checks[#checks + 1] = function(g)
  local settled = g.phase == "playing" and g.winner == nil and not g:choices_waiting()
  for p = 1, 2 do
    local pl = g.players[p]
    for k in pairs(pl.field) do
      if not is_int(k) or k < 1 or k > Game.FIELD_SLOTS then
        return "campo do jogador " .. p .. " com chave fora dos espaços: " .. tostring(k)
      end
    end
    for s = 1, Game.FIELD_SLOTS do
      local c = pl.field[s]
      if c ~= nil then
        local where = "criatura do jogador " .. p .. " no espaço " .. s
        if type(c) ~= "table" or type(c.card) ~= "table" or c.def == nil then return where .. " malformada" end
        if c.owner ~= p then return where .. " com owner " .. tostring(c.owner) end
        if c.slot ~= s then return where .. " com slot " .. tostring(c.slot) end
        if c.def ~= g:def_of(c.card) then return where .. " com def diferente da carta" end
        if c.def.kind ~= "criatura" then return where .. " não é criatura: " .. tostring(c.def.kind) end
        if c.card_uid ~= c.card.uid then return where .. " com card_uid diferente da carta" end
        if not is_int(c.uid) then return where .. " sem uid" end
        if not is_int(c.damage) or c.damage < 0 then return where .. " com dano inválido: " .. tostring(c.damage) end
        if settled and c.damage >= g:hp(c) then
          return where .. " com dano letal (" .. c.damage .. "/" .. g:hp(c) .. ") e estado estável"
        end
        if not is_int(c.entered_round) or c.entered_round > g.round then
          return where .. " entrou na rodada " .. tostring(c.entered_round) .. ", atual " .. tostring(g.round)
        end
        if c.link ~= nil and g:find_structure(c.link.uid) ~= c.link then
          return where .. " ligada a uma estrutura fora de campo"
        end
        if type(c.equips) ~= "table" then return where .. " sem tabela de equipamentos" end
        for k, e in pairs(c.equips) do
          if not Game.EQUIP_SLOTS[k] then return where .. " com equipamento em espaço inválido: " .. tostring(k) end
          if type(e) ~= "table" or type(e.card) ~= "table" or e.def == nil then return where .. " com equipamento malformado" end
          if e.def ~= g:def_of(e.card) then return where .. ": equipamento com def diferente da carta" end
          if e.def.kind ~= "equipamento" then return where .. ": " .. tostring(e.def.id) .. " não é equipamento" end
          if e.def.slot ~= k then return where .. ": equipamento " .. e.def.id .. " no espaço " .. k .. ", slot " .. tostring(e.def.slot) end
          if e.card_uid ~= e.card.uid then return where .. ": equipamento com card_uid diferente da carta" end
          -- Game:wear descarta o equipamento quando a durabilidade chega a zero.
          if e.durability ~= nil and (not is_int(e.durability) or e.durability < 1) then
            return where .. ": equipamento " .. e.def.id .. " com durabilidade " .. tostring(e.durability)
          end
        end
      end
    end
  end
end

-- Estruturas em campo: Game:put_structure cria a instância com owner, slot e
-- def = def_of(card), e structures[slot] é a própria instância; só estruturas
-- entram ali (play_rules.estrutura e Game:create_token conferem o tipo).
checks[#checks + 1] = function(g)
  for p = 1, 2 do
    local pl = g.players[p]
    for k in pairs(pl.structures) do
      if not is_int(k) or k < 1 or k > Game.STRUCTURE_SLOTS then
        return "estruturas do jogador " .. p .. " com chave fora dos espaços: " .. tostring(k)
      end
    end
    for s = 1, Game.STRUCTURE_SLOTS do
      local st = pl.structures[s]
      if st ~= nil then
        local where = "estrutura do jogador " .. p .. " no espaço " .. s
        if type(st) ~= "table" or type(st.card) ~= "table" or st.def == nil then return where .. " malformada" end
        if st.owner ~= p then return where .. " com owner " .. tostring(st.owner) end
        if st.slot ~= s then return where .. " com slot " .. tostring(st.slot) end
        if st.def ~= g:def_of(st.card) then return where .. " com def diferente da carta" end
        if st.def.kind ~= "estrutura" then return where .. " não é estrutura: " .. tostring(st.def.kind) end
        if st.card_uid ~= st.card.uid then return where .. " com card_uid diferente da carta" end
        if not is_int(st.uid) then return where .. " sem uid" end
      end
    end
  end
end

-- Cartas em trânsito: fora de qualquer zona, guardadas num closure até o
-- motor terminar de movê-las. Cada uma delas segura no máximo uma carta:
--   * cada entrada da pilha (um feitiço Rápido ou Lento sai da mão em
--     play_rules.feitico.resolve e só vai ao descarte ao resolver; ataque e
--     efeitos ativados não seguram carta);
--   * cada escolha aberta ou na fila (Game:enter_structure com a zona cheia
--     segura a carta até o dono escolher);
--   * cada continuação de escolha (a criatura com sacrifício entra depois das
--     escolhas dos "ao morrer", em play_rules.criatura.resolve).
local function in_transit(g)
  local n = g.stack and #g.stack or 0
  if g.pending_choice then n = n + 1 end
  n = n + (g.choice_queue and #g.choice_queue or 0)
  n = n + (g.choice_continuations and #g.choice_continuations or 0)
  return n
end

-- Identidade: cada uid vem de Game:next_uid, um contador que só cresce, para
-- cartas e para instâncias em campo. Uma carta está numa zona só de cada vez
-- (mover é sempre tirar de uma e pôr em outra), então nenhum uid aparece duas
-- vezes, e nenhum passa do contador. Com opts.card_total, o total de cartas é
-- conservado: o motor nunca cria nem some com uma carta, só a muda de zona
-- (fichas saem do baralho extra e voltam para ele); o que falta nas zonas só
-- pode ser o que está em trânsito (in_transit). Com a partida decidida, a
-- conservação não vale mais: Game:close_stack zera a pilha com os feitiços
-- dentro, e as continuações de escolha (criatura com sacrifício) não rodam.
checks[#checks + 1] = function(g, opts)
  local seen = {}
  local total = 0
  local bad
  local function see(uid, what)
    if bad then return end
    if not is_int(uid) then bad = what .. " sem uid"; return end
    if uid > g.uid_counter then bad = what .. " com uid " .. uid .. " acima do contador " .. g.uid_counter; return end
    if seen[uid] then bad = what .. " com uid " .. uid .. " repetido (já visto em " .. seen[uid] .. ")"; return end
    seen[uid] = what
  end
  each_card(g, function(p, zone, card)
    total = total + 1
    see(card.uid, "carta " .. tostring(card.id) .. " na zona " .. zone .. " do jogador " .. p)
  end)
  if bad then return bad end
  for p = 1, 2 do
    local pl = g.players[p]
    for s = 1, Game.FIELD_SLOTS do
      local c = pl.field[s]
      if c then
        see(c.uid, "criatura " .. tostring(c.def.id) .. " do jogador " .. p .. " no espaço " .. s)
        for _, k in ipairs(Game.EQUIP_ORDER) do
          if c.equips[k] then see(c.equips[k].uid, "equipamento " .. tostring(c.equips[k].def.id) .. " do jogador " .. p) end
        end
      end
    end
    for s = 1, Game.STRUCTURE_SLOTS do
      local st = pl.structures[s]
      if st then see(st.uid, "estrutura " .. tostring(st.def.id) .. " do jogador " .. p .. " no espaço " .. s) end
    end
  end
  if bad then return bad end
  if opts and opts.card_total ~= nil then
    local expected = opts.card_total
    -- Cartas nunca aparecem do nada, em nenhuma fase.
    if total > expected then return "total de cartas subiu: " .. total .. ", esperado " .. expected end
    -- Com a partida decidida, o motor zera a pilha e descarta as continuações,
    -- e as cartas que estavam ali se perdem: o déficit só vale em andamento.
    if g.winner == nil then
      local transit = in_transit(g)
      if total + transit < expected then
        return "total de cartas caiu: " .. total .. " nas zonas e no máximo " .. transit .. " em trânsito, esperado " .. expected
      end
    end
  end
end

-- Escolha pendente: Game:set_choice marca o jogador; validate_choose só aceita
-- um índice de options ou, com allow_none, nenhum. Uma escolha sem opção
-- possível travaria a partida. Jogador da escolha é 1 ou 2. Só vale com a
-- partida em andamento: com a partida decidida, uma escolha da fila ainda pode
-- abrir (after_choose chama next_choice) e fica lá, sem efeito.
-- Sem escolha aberta, nada fica esperando: Game:next_choice esvazia a fila
-- (after_choose e set_choice) e run_continuations roda as continuações assim
-- que a última escolha é feita; algo na fila sem escolha aberta seria um
-- travamento silencioso.
checks[#checks + 1] = function(g)
  -- Com a partida decidida, uma escolha cujo preparo decidiu a partida aborta o
  -- laço de next_choice e o resto da fila fica lá sem efeito: só vale em andamento.
  if g.phase == "error" or g.winner ~= nil then return end
  local ch = g.pending_choice
  if ch == nil then
    if g.choice_queue and #g.choice_queue > 0 then
      return "fila com " .. #g.choice_queue .. " escolha(s) sem escolha aberta"
    end
    if g.choice_continuations and #g.choice_continuations > 0 then
      return #g.choice_continuations .. " continuação(ões) de escolha sem escolha aberta"
    end
    return
  end
  if g.phase ~= "playing" then return end
  if ch.player ~= 1 and ch.player ~= 2 then return "escolha pendente sem jogador válido: " .. tostring(ch.player) end
  if ch.options ~= nil and type(ch.options) ~= "table" then return "escolha pendente com options inválido" end
  if type(ch.resolve) ~= "function" then return "escolha pendente sem resolve" end
  if (ch.options == nil or #ch.options == 0) and not ch.allow_none then
    return "escolha pendente (" .. tostring(ch.reason) .. ") sem opção possível"
  end
end

-- Pilha e combate: Game.actions.attack põe o combate na pilha; Game:resolve_combat
-- e Game:close_stack limpam g.combat, então combate só existe com a pilha
-- aberta, e o atacante do combate é quem tem o token (validate_attack), na
-- rodada em que o ataque foi declarado. Com a pilha aberta, stack_opener é quem
-- a abriu (Game:push_stack).
checks[#checks + 1] = function(g)
  if g:stack_open() then
    if g.stack_opener ~= 1 and g.stack_opener ~= 2 then return "pilha aberta sem quem a abriu: " .. tostring(g.stack_opener) end
    for i, entry in ipairs(g.stack) do
      if type(entry) ~= "table" or type(entry.resolve) ~= "function" then return "entrada " .. i .. " da pilha sem resolve" end
      if entry.owner ~= 1 and entry.owner ~= 2 then return "entrada " .. i .. " da pilha sem dono" end
    end
  end
  local cb = g.combat
  if cb == nil then return end
  if not g:stack_open() then return "combate aberto com a pilha vazia" end
  if cb.attacker ~= g.attacker then return "combate de quem não tem o token: " .. tostring(cb.attacker) end
  if cb.defender ~= Game.other(cb.attacker) then return "defensor do combate inválido: " .. tostring(cb.defender) end
  if g.attacked_round ~= g.round then return "combate aberto de outra rodada: " .. tostring(g.attacked_round) end
  if type(cb.attackers) ~= "table" or #cb.attackers == 0 then return "combate sem atacantes" end
end

-- Fogueira: Game:light_fogueira acende as duas quando a noite começa (gancho do
-- período, que espera as escolhas abertas) e Game:begin_round apaga as duas; só
-- Game:spend_fogueira gasta, e só com o contador acima de zero
-- (Game:can_pay_fogueira), então acesa ela nunca fica negativa.
checks[#checks + 1] = function(g)
  if g.phase ~= "playing" then return end
  local lit1, lit2 = g.fogueira[1] ~= nil, g.fogueira[2] ~= nil
  if lit1 ~= lit2 then return "fogueira acesa para um jogador só" end
  if lit1 then
    if g:period() ~= "noite" then return "fogueira acesa de dia (" .. tostring(g:period()) .. ")" end
    for p = 1, 2 do
      if not is_int(g.fogueira[p]) or g.fogueira[p] < 0 then
        return "fogueira do jogador " .. p .. " inválida: " .. tostring(g.fogueira[p])
      end
    end
  elseif g:period() == "noite" and g.winner == nil and not g:choices_waiting() then
    return "noite sem fogueira acesa e sem escolha esperando"
  end
end

-- Roda todas as verificações; a primeira violação vira a mensagem.
function Invariantes.check(g, opts)
  for i, fn in ipairs(checks) do
    local ok, msg = pcall(fn, g, opts)
    if not ok then return false, "erro ao verificar a invariante " .. i .. ": " .. tostring(msg) end
    if msg ~= nil then return false, msg end
  end
  return true
end

return Invariantes
