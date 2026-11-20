-- O que cada jogador pode ver da partida (US #41). Lua 5.1 puro.
--
-- O motor (duelo/core/game) guarda tudo: as duas mãos, os dois baralhos e
-- todos os eventos. Ele só existe no servidor. Antes de qualquer coisa sair
-- para um cliente, ela passa por aqui, que tira o que aquele lado não pode
-- saber. Este arquivo não dá require em nada: recebe a partida `g` pronta
-- (no servidor) e só lê os campos e chama os métodos dela; no cliente, só as
-- funções de diferença (Visao.aplicar) são usadas.
--
-- Lados: 1 e 2 são os jogadores; 3 (ou qualquer outro valor) é espectador e
-- recebe só o que é público.
--
-- Interface:
--   Visao.evento_para(ev, lado [, avisar]) -> cópia | nil
--       o evento como aquele lado pode recebê-lo: uma cópia (nunca a tabela
--       do motor), com os campos secretos tirados, ou nil se o lado não deve
--       receber nada. `avisar(texto)` é chamado quando um evento de tipo
--       desconhecido é reduzido (uma vez por tipo e por carga do módulo).
--   Visao.estado_para(g, lado) -> fotografia
--       o estado visível para aquele lado, só com números, strings, booleans
--       e tabelas (serializável por duelo/core/serial).
--   Visao.diferenca(antes, depois) -> lista de mudanças
--   Visao.aplicar(estado, mudancas) -> estado
--       a diferença entre duas fotografias e o caminho de volta: aplicar as
--       mudanças em `antes` dá uma tabela igual a `depois`. É assim que o
--       cliente acompanha a partida sem ter o motor: o servidor manda a
--       fotografia uma vez e, a cada jogada, os eventos e as mudanças.
--   Visao.copiar(v) -> cópia simples (sem funções)
--
-- Regra de segurança dos eventos: lista de permissão por tipo (Visao.TIPOS).
--   "publico"  todos recebem a cópia inteira.
--   "mao"      o dono (ev.p) recebe inteira; os outros recebem só
--              { t, p, source, oculto = true }: sabem que a carta foi para a
--              mão e de onde veio, não qual carta (nem `id` nem `card_uid`:
--              os uids nascem na ordem da lista do baralho, então o uid
--              também diria qual é a carta).
--   "dono"     só o dono recebe; os outros não recebem nada.
-- Além disso, todo evento com `private = true` é tratado no mínimo como
-- "dono" (ou "mao", se for esse o tipo dele), qualquer que seja a lista.
-- Tipo fora da lista (carta nova que emite um evento que este arquivo ainda
-- não conhece): o dono (ev.p) recebe inteiro; os outros recebem só
-- { t, p, desconhecido = true }, sem nenhum outro campo, e o aviso sai no
-- log. Assim uma carta nova nunca vaza a mão por esquecimento; o preço é o
-- adversário ver menos até o tipo entrar na lista.
--
-- Tipos de evento do motor (emit{ t = ... } em duelo/core/*.lua e nas cartas):
--   partida e rodada: start, mulligan_start, mulligan (só a quantidade
--     trocada), round_start, round_end, period, vez, pass, game_over,
--     engine_error;
--   jogadores: mana, fogueira, player_damage, player_heal;
--   cartas: to_hand ("mao"), play, reveal, inventory, destroyed, vanish,
--     look ("dono": as cartas do topo do baralho vistas pela Máquina de
--     Ciência);
--   campo: summon, structure, equip, unequip, activate, death, leave, break,
--     structure_destroyed, unlink, link_limit, no_space, no_copy, fizzle,
--     creature_damage, damage_absorbed, creature_heal;
--   pilha e combate: instant, stack_push, stack_resolve, stack_closed, ready,
--     attack, block, combat_start, combat_end, strike_phase, strike;
--   escolhas: choice (jogador, motivo e quantidade de opções; as opções só
--     vão na fotografia de quem escolhe).
-- Todos são "publico", menos to_hand e look. O que torna uma carta pública é
-- ela sair da mão ou do baralho para a mesa, o descarte, as destruídas, o
-- Inventário (só recebe equipamentos que estavam em campo) ou ser mostrada
-- (reveal).

local Visao = {}

Visao.ESPECTADOR = 3

local PUBLICOS = {
  "start", "mulligan_start", "mulligan", "round_start", "round_end", "period", "vez", "pass",
  "game_over", "engine_error",
  "mana", "fogueira", "player_damage", "player_heal",
  "play", "reveal", "inventory", "destroyed", "vanish",
  "summon", "structure", "equip", "unequip", "activate", "death", "leave", "break",
  "structure_destroyed", "unlink", "link_limit", "no_space", "no_copy", "fizzle",
  "creature_damage", "damage_absorbed", "creature_heal",
  "instant", "stack_push", "stack_resolve", "stack_closed", "ready",
  "attack", "block", "combat_start", "combat_end", "strike_phase", "strike",
  "choice",
}

Visao.TIPOS = { to_hand = "mao", look = "dono" }
for _, t in ipairs(PUBLICOS) do Visao.TIPOS[t] = "publico" end

-- Cópia simples: números, strings, booleans e tabelas; funções e afins ficam
-- de fora, e uma tabela que se contém vira nil naquele ponto.
local function copiar(v, vistos)
  local tv = type(v)
  if tv == "number" or tv == "string" or tv == "boolean" then return v end
  if tv ~= "table" then return nil end
  vistos = vistos or {}
  if vistos[v] then return nil end
  vistos[v] = true
  local c = {}
  for k, x in pairs(v) do
    local tk = type(k)
    if tk == "string" or (tk == "number" and k % 1 == 0) then c[k] = copiar(x, vistos) end
  end
  vistos[v] = nil
  return c
end
Visao.copiar = copiar

----------------------------------------------------------------------------
-- Eventos
----------------------------------------------------------------------------

local avisados = {}

function Visao.evento_para(ev, lado, avisar)
  if type(ev) ~= "table" then return nil end
  local regra = Visao.TIPOS[ev.t]
  local dono = ev.p ~= nil and ev.p == lado and (lado == 1 or lado == 2)
  if regra == "publico" and not ev.private then return copiar(ev) end
  if dono then return copiar(ev) end
  if regra == "mao" then
    return { t = ev.t, p = ev.p, source = ev.source, oculto = true }
  end
  if regra ~= nil then return nil end -- "dono", ou público marcado como privado
  if ev.private then return nil end
  -- Tipo desconhecido: nada além do tipo e do jogador.
  local t = type(ev.t) == "string" and ev.t or "?"
  if not avisados[t] then
    avisados[t] = true
    if avisar then
      avisar("evento de tipo desconhecido \"" .. t .. "\": os outros lados recebem só o tipo "
        .. "(acrescente-o a Visao.TIPOS em duelo/mod/visao.lua)")
    end
  end
  return { t = t, p = (ev.p == 1 or ev.p == 2) and ev.p or nil, desconhecido = true }
end

----------------------------------------------------------------------------
-- Fotografia do estado
----------------------------------------------------------------------------

local EQUIPS = { "mao", "peito", "cabeca" }
local ZONA_CAMPO, ZONA_ESTRUTURAS = 6, 2

-- Chama um método da partida que pode rodar código de carta (ataque, vida,
-- velocidade, custo). Um erro ali não pode derrubar o envio: vale o reserva.
-- O contexto do motor (qual carta roda) volta ao que era.
local function seguro(g, reserva, metodo, ...)
  local fn = g[metodo]
  if type(fn) ~= "function" then return reserva end
  local antes = g.context
  local ok, a = pcall(fn, g, ...)
  g.context = antes
  if ok and a ~= nil then return a end
  return reserva
end

local function carta(c)
  return { id = c.id, card_uid = c.uid }
end

local function lista_cartas(lista)
  local out = {}
  for i, c in ipairs(lista or {}) do out[i] = carta(c) end
  return out
end

-- Cartas que o dono pode jogar (mão, Inventário, separadas): com o custo de agora.
local function lista_jogaveis(g, p, lista)
  local out = {}
  for i, c in ipairs(lista or {}) do
    local x = carta(c)
    x.custo = seguro(g, false, "card_cost", p, c)
    if c.durability ~= nil then x.durabilidade = c.durability end
    out[i] = x
  end
  return out
end

local function equipamento(g, e)
  local x = { uid = e.uid, card_uid = e.card_uid, id = e.def and e.def.id or (e.card and e.card.id) }
  if e.durability ~= nil then x.durabilidade = e.durability end
  if e.card and e.card.used_round == g.round then x.usado = true end
  if e.pronta == g.round then x.pronto = true end
  return x
end

local function criatura(g, c)
  local def = c.def or {}
  local x = {
    uid = c.uid, card_uid = c.card_uid, id = def.id,
    atk = seguro(g, def.atk or 0, "atk", c),
    hp = seguro(g, def.hp or 0, "hp", c),
    dano = c.damage or 0,
    vel = seguro(g, def.speed or 1, "speed", c, "attack"),
    ficha = c.ficha and true or false,
    entrou = c.entered_round,
    equips = {},
  }
  for _, s in ipairs(EQUIPS) do
    local e = c.equips and c.equips[s]
    if e then x.equips[s] = equipamento(g, e) end
  end
  return x
end

local function estrutura(g, st)
  local x = { uid = st.uid, card_uid = st.card_uid, id = st.def and st.def.id, ficha = st.ficha and true or false }
  if st.card and st.card.used_round == g.round then x.usada = true end
  return x
end

local function espacos(lista, n, fn, g)
  local out = {}
  for i = 1, n do
    local o = lista and lista[i]
    if o then out[i] = fn(g, o) else out[i] = false end
  end
  return out
end

-- Uma opção de escolha, para quem escolhe: carta, objeto em campo, jogador
-- ou valor simples (o número de um espaço, por exemplo).
local function opcao(opt)
  local t = type(opt)
  if t == "number" or t == "string" or t == "boolean" then return { valor = opt } end
  if t ~= "table" then return {} end
  if opt.def ~= nil then
    return { objeto = opt.uid, id = opt.def.id, card_uid = opt.card_uid, p = opt.owner, slot = opt.slot }
  end
  if opt.id ~= nil then return { carta = opt.id, card_uid = opt.uid } end
  if opt.player ~= nil then return { jogador = opt.player } end
  return {}
end

local function escolha(g, lado)
  local ch = g.pending_choice
  if ch == nil then return false end
  local x = { p = ch.player, motivo = ch.reason, n = #(ch.options or {}), nenhuma = ch.allow_none and true or false }
  -- As opções podem ser cartas do baralho ou da mão de quem escolhe.
  if ch.player == lado and (lado == 1 or lado == 2) then
    x.opcoes = {}
    for i, opt in ipairs(ch.options or {}) do x.opcoes[i] = opcao(opt) end
  end
  return x
end

local function pilha(g)
  local out = {}
  for i, e in ipairs(g.stack or {}) do
    out[i] = { p = e.owner, rotulo = type(e.label) == "string" and e.label or false }
  end
  return out
end

local function combate(g)
  local cb = g.combat
  if cb == nil then return false end
  local x = { atacante = cb.attacker, defensor = cb.defender, declarados = cb.blocks_declared and true or false,
    atacantes = {}, bloqueios = {} }
  for i, a in ipairs(cb.attackers or {}) do
    x.atacantes[i] = a.uid
    local d = cb.blocks and cb.blocks[a]
    if d then x.bloqueios[#x.bloqueios + 1] = { atacante = a.uid, bloqueador = d.uid } end
  end
  return x
end

local function jogador(g, p, lado)
  local pl = g.players[p]
  local x = {
    vida = pl.life, mana = pl.mana, mana_max = pl.max_mana, fome = pl.fome,
    troca_feita = pl.mulligan_done and true or false,
    -- Do adversário só se sabe quantas cartas há na mão e no baralho.
    mao_n = #pl.hand, baralho_n = #pl.deck, extra_n = #pl.extra,
    limite_mao = seguro(g, false, "hand_limit", p),
    -- Públicos: o Inventário só recebe equipamentos que estavam em campo e as
    -- separadas são reveladas.
    inventario = lista_jogaveis(g, p, pl.inventory),
    separadas = lista_jogaveis(g, p, pl.separated),
    descarte = lista_cartas(pl.discard),
    destruidas = lista_cartas(pl.destroyed),
    campo = espacos(pl.field, ZONA_CAMPO, criatura, g),
    estruturas = espacos(pl.structures, ZONA_ESTRUTURAS, estrutura, g),
  }
  if p == lado then x.mao = lista_jogaveis(g, p, pl.hand) end
  return x
end

function Visao.estado_para(g, lado)
  local noite = g.fogueira ~= nil and g.fogueira[1] ~= nil
  local x = {
    fase = g.phase, rodada = g.round, vez = g.vez, periodo = g.current_period or false,
    ativo = g.active or false, atacante = g.attacker or false, primeiro = g.first or false,
    vencedor = g.winner == nil and false or g.winner,
    fogueira = noite and { g.fogueira[1], g.fogueira[2] } or false,
    fogueira_guardada = { (g.fogueira_pending or {})[1] or 0, (g.fogueira_pending or {})[2] or 0 },
    jogadores = { jogador(g, 1, lado), jogador(g, 2, lado) },
    pilha = pilha(g),
    combate = combate(g),
    escolha = escolha(g, lado),
    erro = g.error and tostring(g.error.message) or false,
  }
  return x
end

----------------------------------------------------------------------------
-- Diferença entre fotografias
----------------------------------------------------------------------------

-- Uma mudança é { c = { chave, chave, ... }, v = valor }: o valor novo no
-- caminho `c` a partir da raiz; sem `v`, a chave some. Tabelas dos dois lados
-- são comparadas por dentro; o resto é trocado inteiro.
local function diferenca(a, b, caminho, out)
  for k, vb in pairs(b) do
    local va = a[k]
    if type(va) == "table" and type(vb) == "table" then
      caminho[#caminho + 1] = k
      diferenca(va, vb, caminho, out)
      caminho[#caminho] = nil
    elseif va ~= vb then
      local c = {}
      for i, x in ipairs(caminho) do c[i] = x end
      c[#c + 1] = k
      out[#out + 1] = { c = c, v = copiar(vb) }
    end
  end
  for k in pairs(a) do
    if b[k] == nil then
      local c = {}
      for i, x in ipairs(caminho) do c[i] = x end
      c[#c + 1] = k
      out[#out + 1] = { c = c }
    end
  end
  return out
end

function Visao.diferenca(antes, depois)
  return diferenca(antes or {}, depois or {}, {}, {})
end

-- Aplica as mudanças na própria tabela. Mudança malformada (caminho que não
-- existe) é erro: quem chama pede a fotografia de novo.
function Visao.aplicar(estado, mudancas)
  for _, m in ipairs(mudancas or {}) do
    local c = m.c
    if type(c) ~= "table" or #c == 0 then error("mudança sem caminho", 0) end
    local t = estado
    for i = 1, #c - 1 do
      t = t[c[i]]
      if type(t) ~= "table" then error("mudança num caminho que não existe", 0) end
    end
    t[c[#c]] = m.v
  end
  return estado
end

return Visao
