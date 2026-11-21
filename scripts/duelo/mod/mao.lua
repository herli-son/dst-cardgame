-- A mão do jogador na tela (US #37): o que o painel de cartas mostra.
--
-- A mão não usa o inventário do jogo: é um painel do mod, na parte de baixo
-- da tela, com as cartas em leque (widgets/duelo_mao.lua). Este módulo decide
-- o conteúdo e a posição de cada carta a partir da visão local da partida
-- (duelo/mod/partida_cliente) e do catálogo de cartas (duelo/mod/catalogo);
-- o widget só desenha. Lua puro, testado sem o jogo (tests/test_mod_mao.lua).
--
-- Segredo da mão: a visão de cada cliente só traz a própria mão (US #41). O
-- painel mostra exatamente essa lista; do adversário o cliente só sabe a
-- quantidade de cartas, e nada dela é desenhado aqui.
--
-- Limite de mão: 10 cartas, mais o que a Mochila der (o limite vem na visão,
-- `limite_mao`). O leque não tem limite próprio: com mais cartas, elas ficam
-- mais juntas, sempre dentro de Mao.LEQUE.largura.
--
-- Modelo (Mao.modelo()):
--   { visivel = bool,          há partida em curso e este cliente joga nela
--     limite = n, total = n,   limite de mão e quantas cartas há
--     cartas = { {
--       indice = n,            posição na mão (o hand_index da ação "play")
--       uid = n, id = texto,
--       nome, tipo, texto,     do catálogo (id fora do catálogo: nome = id)
--       custo = n,             custo de agora, da visão (com descontos)
--       tipo_nome = texto,     "Criatura", "Campeão · Sobrevivente"...
--       esquerda, direita = { valor, rotulo } | false   os dois valores da
--                              carta: ataque e vida; no equipamento, bônus e
--                              durabilidade de agora
--       atributos = texto,     os mesmos valores numa linha ("4 / 5")
--       imagem = { tipo, tex } | false,       ícone (reserva da figura)
--       figura = { banco, build, anim } | false,   o boneco animado
--       pagavel = bool,        a mana de agora paga o custo
--       x, y, rot              posição no leque (Mao.leque)
--     }, ... } }
--
-- Interface:
--   Mao.instalar{ cliente = Cliente, catalogo = tabela, log = fn } -> Mao
--   Mao.modelo() -> modelo
--   Mao.leque(n) -> { { x, y, rot }, ... }
--   Mao.ligar_widget(w)      w:Atualizar(modelo) a cada mudança (nil desliga)
--   Mao.atualizar()

local Mao = {}

-- O leque, em unidades da tela do jogo (a raiz de baixo tem 1280 de largura).
--   largura: espaço máximo entre o centro da primeira e o da última carta;
--   passo: distância entre cartas vizinhas quando cabem todas;
--   giro: graus de inclinação por carta a partir do meio (até giro_max);
--   queda: quanto as cartas das pontas descem, na ponta do leque cheio.
Mao.LEQUE = { largura = 760, passo = 96, giro = 2.5, giro_max = 14, queda = 26 }

local estado = {
  cliente = nil,
  catalogo = nil,
  log = nil,
  widget = nil,
}

local function log(msg)
  if estado.log then estado.log("[duelo] mão: " .. tostring(msg)) end
end

-- Posição de cada uma das n cartas: x a partir do centro, y para baixo nas
-- pontas (um arco) e a inclinação em graus (positiva: para a direita).
function Mao.leque(n)
  local L = Mao.LEQUE
  local out = {}
  if type(n) ~= "number" or n < 1 then return out end
  n = math.floor(n)
  local passo = L.passo
  if n > 1 and passo * (n - 1) > L.largura then passo = L.largura / (n - 1) end
  local meio = (n + 1) / 2
  -- A ponta do leque cheio (largura inteira) é a referência da queda.
  local ponta = L.largura / 2
  for i = 1, n do
    local d = i - meio
    local x = d * passo
    local rot = d * L.giro
    if rot > L.giro_max then rot = L.giro_max elseif rot < -L.giro_max then rot = -L.giro_max end
    local t = ponta > 0 and (x / ponta) or 0
    out[i] = { x = x, y = -L.queda * t * t, rot = rot }
  end
  return out
end

local function numero(v)
  return type(v) == "number" and v == v and v or nil
end

-- A linha de atributos de uma carta, pelo tipo.
local function atributos(c, na_visao)
  if c == nil then return false end
  local partes = {}
  if c.tipo == "criatura" then
    if numero(c.ataque) and numero(c.vida) then partes[#partes + 1] = c.ataque .. " / " .. c.vida end
  elseif c.tipo == "equipamento" then
    if numero(c.bonus_ataque) and c.bonus_ataque ~= 0 then partes[#partes + 1] = "+" .. c.bonus_ataque .. " ataque" end
    if numero(c.bonus_vida) and c.bonus_vida ~= 0 then partes[#partes + 1] = "+" .. c.bonus_vida .. " vida" end
    -- A durabilidade de agora (um equipamento que volta para a mão já gasto).
    local dur = numero(na_visao.durabilidade) or numero(c.durabilidade)
    if dur then partes[#partes + 1] = "dur. " .. dur end
  end
  if #partes == 0 then return false end
  return table.concat(partes, " · ")
end

local NOMES_DOS_TIPOS = { criatura = "Criatura", equipamento = "Equipamento", feitico = "Feitiço", estrutura = "Estrutura" }

-- A linha de tipo: "Campeão · Sobrevivente", "Criatura", "Equipamento"...
local function nome_do_tipo(c)
  if c == nil then return false end
  local partes = {}
  if c.campeao then partes[#partes + 1] = "Campeão" end
  if c.sobrevivente then partes[#partes + 1] = "Sobrevivente" end
  if #partes == 0 then partes[1] = NOMES_DOS_TIPOS[c.tipo] end
  if #partes == 0 then return false end
  return table.concat(partes, " · ")
end

-- Os dois valores da linha de baixo da carta: { valor = texto, rotulo = texto }
-- à esquerda e à direita, ou false. Criatura: ataque e vida. Equipamento: o
-- bônus (de ataque ou de vida) e a durabilidade de agora.
local function valores(c, na_visao)
  if c == nil then return false, false end
  if c.tipo == "criatura" then
    if numero(c.ataque) and numero(c.vida) then
      return { valor = tostring(c.ataque), rotulo = "ataque" }, { valor = tostring(c.vida), rotulo = "vida" }
    end
  elseif c.tipo == "equipamento" then
    local esq = false
    if numero(c.bonus_ataque) and c.bonus_ataque ~= 0 then
      esq = { valor = "+" .. c.bonus_ataque, rotulo = "ataque" }
    elseif numero(c.bonus_vida) and c.bonus_vida ~= 0 then
      esq = { valor = "+" .. c.bonus_vida, rotulo = "vida" }
    end
    local dur = numero(na_visao.durabilidade) or numero(c.durabilidade)
    return esq, dur and { valor = tostring(dur), rotulo = "dur." } or false
  end
  return false, false
end

function Mao.modelo()
  local vazio = { visivel = false, limite = 0, total = 0, cartas = {} }
  local C = estado.cliente
  if C == nil then return vazio end
  local v, lado = C.visao(), C.lado()
  if v == nil or (lado ~= 1 and lado ~= 2) then return vazio end
  local eu = type(v.jogadores) == "table" and v.jogadores[lado] or nil
  if type(eu) ~= "table" or type(eu.mao) ~= "table" then return vazio end
  -- Com a partida acabada (ou interrompida por erro), a mão sai da tela.
  if v.vencedor ~= false or v.erro then return vazio end
  local catalogo = estado.catalogo or {}
  local mana = numero(eu.mana) or 0
  local posicoes = Mao.leque(#eu.mao)
  local cartas = {}
  for i, na_visao in ipairs(eu.mao) do
    if type(na_visao) ~= "table" then na_visao = {} end
    local c = catalogo[na_visao.id]
    local custo = numero(na_visao.custo) or (c and numero(c.custo)) or 0
    local tipo = c and c.tipo or false
    local esquerda, direita = valores(c, na_visao)
    cartas[i] = {
      indice = i,
      uid = na_visao.card_uid,
      id = na_visao.id,
      nome = c and c.nome or tostring(na_visao.id),
      tipo = tipo,
      tipo_nome = nome_do_tipo(c),
      esquerda = esquerda, direita = direita,
      texto = c and c.texto or false,
      custo = custo,
      atributos = atributos(c, na_visao),
      imagem = c and c.imagem or false,
      figura = c and c.figura or false,
      pagavel = custo <= mana,
      x = posicoes[i].x, y = posicoes[i].y, rot = posicoes[i].rot,
    }
  end
  return { visivel = true, limite = numero(eu.limite_mao) or 0, total = #cartas, cartas = cartas }
end

function Mao.atualizar()
  local w = estado.widget
  if w == nil then return end
  -- A tela do jogo foi desfeita e o widget morreu com ela: desliga.
  if type(w.inst) == "table" and w.inst.IsValid ~= nil and not w.inst:IsValid() then
    estado.widget = nil
    return
  end
  local ok, modelo = pcall(Mao.modelo)
  if not ok then
    log("erro ao montar a mão: " .. tostring(modelo))
    return
  end
  local err
  ok, err = pcall(function() w:Atualizar(modelo) end)
  if not ok then
    -- O widget morreu (a tela do jogo foi desfeita): desliga até o próximo.
    estado.widget = nil
    log("o painel da mão não pôde ser atualizado (desligado): " .. tostring(err))
  end
end

function Mao.ligar_widget(w)
  estado.widget = w
  Mao.atualizar()
end

-- Liga o módulo.
--   ctx.cliente: duelo/mod/partida_cliente.lua já instalado;
--   ctx.catalogo: duelo/mod/catalogo.lua;
--   ctx.log: função de log (opcional).
function Mao.instalar(ctx)
  estado.cliente = ctx.cliente
  estado.catalogo = ctx.catalogo
  estado.log = ctx.log
  estado.widget = nil
  local C = ctx.cliente
  -- A fotografia e cada lote mudam a mão (comprar, jogar, mana, custo).
  C.quando_estado(Mao.atualizar)
  if C.quando_lote then C.quando_lote(Mao.atualizar) end
  return Mao
end

return Mao
