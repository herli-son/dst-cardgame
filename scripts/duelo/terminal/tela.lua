-- Tela em texto da partida, para o jogador humano. Lua 5.1 puro.
--
-- Interface:
--   local Tela = require("duelo/terminal/tela")
--   Tela.render(g, p) -> string     a partida inteira vista pelo jogador p
--   Tela.nome(def_ou_carta)         nome de exibição de uma carta
--   Tela.criatura_curta(g, c)       "Nome 3/5" para mensagens
--
-- Texto puro, sem cores, com linhas de no máximo 80 colunas. As larguras são
-- medidas em caracteres (não em bytes), então nomes com acento alinham.
-- Os espaços do campo aparecem como c1..c6 (meus) e o1..o6 (do oponente); as
-- estruturas como e1/e2 e oe1/oe2. São os mesmos nomes que os comandos usam.

local Game = require("duelo/core/game")

local Tela = {}

Tela.LARGURA = 80

----------------------------------------------------------------------------
-- Texto
----------------------------------------------------------------------------

-- Quantidade de caracteres de um texto UTF-8 (bytes de continuação não contam).
local function ulen(s)
  local n = 0
  for i = 1, #s do
    local b = s:byte(i)
    if b < 128 or b >= 192 then n = n + 1 end
  end
  return n
end
Tela.ulen = ulen

-- Corta o texto em n caracteres (sem partir um caractere UTF-8).
local function ucut(s, n)
  if ulen(s) <= n then return s end
  local count, i = 0, 1
  while i <= #s do
    local b = s:byte(i)
    if b < 128 or b >= 192 then
      if count == n then return s:sub(1, i - 1) end
      count = count + 1
    end
    i = i + 1
  end
  return s
end

-- Preenche à direita até n caracteres (ou corta).
local function pad(s, n)
  s = ucut(tostring(s), n)
  return s .. string.rep(" ", n - ulen(s))
end
Tela.pad = pad

local function upper_first(s)
  return s:sub(1, 1):upper() .. s:sub(2)
end

function Tela.nome(x)
  if x == nil then return "?" end
  local def = x.def or x
  return def.name or def.id or "?"
end

local PERIODOS = { manha = "manhã", tarde = "tarde", noite = "noite" }

function Tela.periodo(g)
  if g.phase ~= "playing" and g.phase ~= "over" then return "-" end
  return PERIODOS[g:period()] or tostring(g:period())
end

-- Palavras-chave de uma definição, em texto: "Agressivo, Rival(porco)".
function Tela.palavras(def)
  local list = {}
  local keys = {}
  for k in pairs(def.kw or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = def.kw[k]
    if k == "rival" then
      list[#list + 1] = "Rival(" .. tostring(v) .. ")"
    elseif v then
      list[#list + 1] = upper_first(k)
    end
  end
  if def.sobrevivente then list[#list + 1] = "Sobrevivente" end
  if def.no_attack then list[#list + 1] = "Não ataca" end
  if def.no_block then list[#list + 1] = "Não bloqueia" end
  return table.concat(list, ", ")
end

-- Velocidade impressa de uma carta na mão (criatura) ou tipo do efeito.
local function velocidade_carta(def)
  if def.kind == "criatura" then
    if def.speed_fn then return "vel ?" end
    return "vel " .. tostring(def.speed or 1)
  end
  if def.kind == "feitico" then return def.speed end
  if def.activation then return def.activation.speed end
  if def.kind == "equipamento" then return def.slot end
  return nil
end

----------------------------------------------------------------------------
-- Partes da tela
----------------------------------------------------------------------------

local function quem(g, p, j)
  if j == nil then return "-" end
  if j == p then return "eu" end
  return "ele"
end

local function fogueira_texto(g, p)
  if not g:is_night_lit() then
    local pend = (g.fogueira_pending or {})[p] or 0
    if pend > 0 then return "apagada (dia, +" .. pend .. " guardado)" end
    return "apagada (dia)"
  end
  local o = Game.other(p)
  return "eu " .. tostring(g.fogueira[p]) .. " / ele " .. tostring(g.fogueira[o])
end

function Tela.cabecalho(g, p)
  local o = Game.other(p)
  local me, him = g.players[p], g.players[o]
  local lines = {}
  lines[#lines + 1] = string.rep("=", Tela.LARGURA)
  lines[#lines + 1] = "Rodada " .. tostring(g.round) .. "   Período: " .. Tela.periodo(g)
    .. "   Fogueira: " .. fogueira_texto(g, p)
  lines[#lines + 1] = pad("Eu:  vida " .. me.life .. "  mana " .. me.mana .. "/" .. me.max_mana, 40)
    .. "Ele: vida " .. him.life .. "  mana " .. him.mana .. "/" .. him.max_mana
  local vez = quem(g, p, g.active)
  if g.pending_choice then vez = quem(g, p, g.pending_choice.player) .. " (escolha)" end
  if g.winner ~= nil then vez = "-" end
  lines[#lines + 1] = pad("Token de ataque: " .. quem(g, p, g.attacker), 40) .. "Vez: " .. vez
  if g.winner ~= nil then
    local fim = "empate"
    if g.winner == p then fim = "você venceu" elseif g.winner ~= 0 then fim = "você perdeu" end
    lines[#lines + 1] = "FIM DE PARTIDA: " .. fim
  elseif g.phase == "error" then
    lines[#lines + 1] = "PARTIDA ENCERRADA POR ERRO: " .. tostring(g.error and g.error.message)
  end
  return lines
end

-- Nome do espaço de uma criatura, visto por p: c3 (minha) ou o3 (dele).
function Tela.espaco(p, c)
  if c.owner == p then return "c" .. c.slot end
  return "o" .. c.slot
end

function Tela.pilha(g, p)
  local lines = {}
  if g:stack_open() then
    local itens = {}
    for i = #g.stack, 1, -1 do
      local e = g.stack[i]
      local def = g:def_of({ id = e.label })
      local label = def and Tela.nome(def) or tostring(e.label)
      itens[#itens + 1] = label .. " (" .. quem(g, p, e.owner) .. ")"
    end
    lines[#lines + 1] = ucut("Pilha (do topo): " .. table.concat(itens, ", "), Tela.LARGURA)
  end
  local cb = g.combat
  if cb then
    local atk = {}
    for _, a in ipairs(cb.attackers) do
      if g.players[a.owner].field[a.slot] == a then
        atk[#atk + 1] = Tela.espaco(p, a) .. " " .. Tela.nome(a)
      end
    end
    lines[#lines + 1] = ucut("Combate: atacam " .. table.concat(atk, ", "), Tela.LARGURA)
    local blocks = {}
    for _, a in ipairs(cb.attackers) do
      local d = cb.blocks[a]
      if d then blocks[#blocks + 1] = Tela.espaco(p, d) .. " bloqueia " .. Tela.espaco(p, a) end
    end
    if cb.blocks_declared then
      if #blocks == 0 then
        lines[#lines + 1] = "  Bloqueios: nenhum"
      else
        lines[#lines + 1] = ucut("  Bloqueios: " .. table.concat(blocks, ", "), Tela.LARGURA)
      end
    elseif g:can_declare_blocks(p) then
      lines[#lines + 1] = "  Bloqueios: declare agora (bloquear o1=c1 ... ou bloquear nada)"
    else
      lines[#lines + 1] = "  Bloqueios: ainda não declarados"
    end
  end
  return lines
end

-- Uma criatura em campo: "c1 Nome               3/5 (-2) vel 1  Agressivo  {Lanca}"
local function linha_criatura(g, p, prefixo, c)
  if c == nil then return pad(prefixo, 4) .. "(vazio)" end
  local atk, hp = g:atk(c), g:hp(c)
  local stats = atk .. "/" .. hp
  if c.damage > 0 then stats = stats .. " (-" .. c.damage .. ")" end
  local vel = "vel " .. g:speed(c, "attack")
  local extras = {}
  local kw = Tela.palavras(c.def)
  if kw ~= "" then extras[#extras + 1] = kw end
  local eq = {}
  for _, s in ipairs(Game.EQUIP_ORDER) do
    local e = c.equips[s]
    if e then
      local d = e.durability and (" " .. e.durability) or ""
      -- Equipamento com efeito ativado: "*" ativável, "!" pronto (ex.: Pá que
      -- golpeou nesta rodada), "x" já usado nesta rodada.
      local marca = ""
      if e.def.activation then
        if e.pronta == g.round then marca = "!"
        elseif e.def.activation.once_per_round and e.card and e.card.used_round == g.round then marca = "x"
        else marca = "*" end
      end
      eq[#eq + 1] = Tela.nome(e) .. d .. marca
    end
  end
  if #eq > 0 then extras[#extras + 1] = "{" .. table.concat(eq, ", ") .. "}" end
  if c.ficha then extras[#extras + 1] = "(ficha)" end
  local line = pad(prefixo, 4) .. pad(Tela.nome(c), 22) .. pad(stats, 12) .. pad(vel, 7)
    .. table.concat(extras, "  ")
  return (ucut(line, Tela.LARGURA):gsub("%s+$", ""))
end

local function linha_estrutura(g, prefixo, st)
  if st == nil then return pad(prefixo, 4) .. "(vazio)" end
  local extras = {}
  if st.def.activation then
    local marca = ""
    if st.def.activation.once_per_round and st.card.used_round == g.round then marca = ", usada" end
    extras[#extras + 1] = "ativável (" .. st.def.activation.speed .. marca .. ")"
  end
  if st.ficha then extras[#extras + 1] = "(ficha)" end
  return (ucut(pad(prefixo, 4) .. pad(Tela.nome(st), 22) .. table.concat(extras, "  "), Tela.LARGURA):gsub("%s+$", ""))
end

function Tela.campo(g, p)
  local o = Game.other(p)
  local lines = {}
  lines[#lines + 1] = string.rep("-", Tela.LARGURA)
  lines[#lines + 1] = "Oponente"
  for s = 1, Game.STRUCTURE_SLOTS do
    lines[#lines + 1] = linha_estrutura(g, "oe" .. s, g.players[o].structures[s])
  end
  for s = 1, Game.FIELD_SLOTS do
    lines[#lines + 1] = linha_criatura(g, p, "o" .. s, g.players[o].field[s])
  end
  lines[#lines + 1] = string.rep("-", Tela.LARGURA)
  lines[#lines + 1] = "Eu"
  for s = 1, Game.FIELD_SLOTS do
    lines[#lines + 1] = linha_criatura(g, p, "c" .. s, g.players[p].field[s])
  end
  for s = 1, Game.STRUCTURE_SLOTS do
    lines[#lines + 1] = linha_estrutura(g, "e" .. s, g.players[p].structures[s])
  end
  return lines
end

-- Uma carta na mão: "3. Nome (custo 2, criatura, vel 1) 3/2 Agressivo: texto"
local function linha_carta(g, p, i, card)
  local def = g:def_of(card)
  if def == nil then return i .. ". " .. tostring(card.id) .. " (carta desconhecida)" end
  local partes = { "custo " .. g:card_cost(p, card), def.kind }
  local vel = velocidade_carta(def)
  if vel then partes[#partes + 1] = vel end
  local line = i .. ". " .. Tela.nome(def) .. " (" .. table.concat(partes, ", ") .. ")"
  if def.kind == "criatura" then
    line = line .. " " .. tostring(def.atk or 0) .. "/" .. tostring(def.hp or 0)
    local kw = Tela.palavras(def)
    if kw ~= "" then line = line .. " " .. kw end
  elseif def.kind == "equipamento" then
    local b = {}
    if def.atk_bonus then b[#b + 1] = "+" .. def.atk_bonus .. " atq" end
    if def.hp_bonus then b[#b + 1] = "+" .. def.hp_bonus .. " vida" end
    if def.durability then b[#b + 1] = "dur " .. def.durability end
    if #b > 0 then line = line .. " " .. table.concat(b, ", ") end
  end
  if def.text then line = line .. ": " .. def.text end
  -- Dois espaços de recuo na tela.
  return ucut(line, Tela.LARGURA - 2)
end

function Tela.mao(g, p)
  local pl = g.players[p]
  local lines = {}
  lines[#lines + 1] = string.rep("-", Tela.LARGURA)
  -- Cartas que passam do limite: serão destruídas no fim da rodada se não forem usadas.
  local risk = {}
  for _, e in ipairs(g:hand_overflow(p)) do risk[e.card] = true end
  local function mark(card) return risk[card] and "! " or "  " end
  lines[#lines + 1] = "Mão (" .. #pl.hand .. ", limite " .. g:hand_limit(p) .. ", baralho " .. #pl.deck .. ")"
  if #pl.hand == 0 then lines[#lines + 1] = "  (vazia)" end
  for i, card in ipairs(pl.hand) do lines[#lines + 1] = mark(card) .. linha_carta(g, p, i, card) end
  if #pl.inventory > 0 then
    lines[#lines + 1] = "Inventário (jogar com: inv <n>)"
    for i, card in ipairs(pl.inventory) do lines[#lines + 1] = mark(card) .. linha_carta(g, p, i, card) end
  end
  if #pl.separated > 0 then
    lines[#lines + 1] = "Separadas (jogar com: sep <n>)"
    for i, card in ipairs(pl.separated) do lines[#lines + 1] = mark(card) .. linha_carta(g, p, i, card) end
  end
  if next(risk) then
    lines[#lines + 1] = "! = acima do limite: será destruída no fim da rodada se não for usada"
  end
  return lines
end

-- Texto de uma opção de escolha: cartas e objetos pelo nome, o resto como está.
function Tela.opcao(opt)
  if type(opt) == "table" then
    if opt.def or opt.name or opt.id then return Tela.nome(opt) end
    if opt.player then return "jogador " .. tostring(opt.player) end
    return "opção"
  end
  return tostring(opt)
end

function Tela.escolha(g, p)
  local ch = g.pending_choice
  if ch == nil or ch.player ~= p then return {} end
  local lines = {}
  lines[#lines + 1] = string.rep("-", Tela.LARGURA)
  lines[#lines + 1] = "Escolha pendente (" .. tostring(ch.reason) .. "): escolher <n>"
    .. (ch.allow_none and " ou escolher nada" or "")
  for i, opt in ipairs(ch.options or {}) do
    lines[#lines + 1] = ucut("  " .. i .. ". " .. Tela.opcao(opt), Tela.LARGURA)
  end
  return lines
end

local function append(dst, src)
  for _, l in ipairs(src) do dst[#dst + 1] = l end
end

function Tela.render(g, p)
  local lines = {}
  append(lines, Tela.cabecalho(g, p))
  append(lines, Tela.pilha(g, p))
  append(lines, Tela.campo(g, p))
  append(lines, Tela.mao(g, p))
  append(lines, Tela.escolha(g, p))
  lines[#lines + 1] = string.rep("=", Tela.LARGURA)
  return table.concat(lines, "\n") .. "\n"
end

return Tela
