-- Testes da interface em texto (#64): tela, comandos, partida contra o bot e
-- descrição dos eventos.
local Game = require("duelo/core/game")
local Cards = require("duelo/core/cards")
local Jogadas = require("duelo/bot/jogadas")
local Demo = require("duelo/terminal/deck_demo")
local Tela = require("duelo/terminal/tela")
local Comandos = require("duelo/terminal/comandos")
local Partida = require("duelo/terminal/partida")

-- Partida com o baralho de demonstração, sem as mãos iniciais, para montar o
-- cenário à mão. O jogador 1 começa com a vez.
local function bare(seed)
  local decks = Demo.decks()
  local g = Game.new{ decks = decks, first = 1, mulligan = false, rng = Partida.make_rng(seed or 7) }
  g:start()
  g.players[1].hand, g.players[2].hand = {}, {}
  return g
end

local function put(g, p, id, slot)
  return g:place_creature(p, { id = id, uid = g:next_uid() }, slot)
end

local function give(g, p, id)
  local pl = g.players[p]
  pl.hand[#pl.hand + 1] = { id = id, uid = g:next_uid() }
  return #pl.hand
end

local function contains(s, sub)
  return s:find(sub, 1, true) ~= nil
end

local function assert_contains(T, s, sub)
  T.ok(contains(s, sub), "esperava encontrar \"" .. sub .. "\" em:\n" .. s)
end

local function parse_ok(T, g, p, linha)
  local a, err = Comandos.parse(g, p, linha)
  T.ok(a ~= nil, "comando \"" .. linha .. "\" deu erro: " .. tostring(err))
  return a
end

local function parse_err(T, g, p, linha, trecho)
  local a, err = Comandos.parse(g, p, linha)
  T.eq(a, nil, "comando \"" .. linha .. "\" devia falhar")
  T.ok(contains(err, trecho), "erro de \"" .. linha .. "\" devia conter \"" .. trecho .. "\": " .. tostring(err))
end

return {
  ----------------------------------------------------------------------------
  -- Tela
  ----------------------------------------------------------------------------

  { "render mostra rodada, período, vida, mana, token, vez e fogueira", function(T)
    local g = bare()
    g.players[1].life, g.players[2].life = 17, 12
    g.players[1].mana, g.players[2].mana = 3, 2
    local s = Tela.render(g, 1)
    assert_contains(T, s, "Rodada 1")
    assert_contains(T, s, "Período: manhã")
    assert_contains(T, s, "Fogueira: apagada (dia)")
    assert_contains(T, s, "Eu:  vida 17  mana 3/1")
    assert_contains(T, s, "Ele: vida 12  mana 2/1")
    assert_contains(T, s, "Token de ataque: eu")
    assert_contains(T, s, "Vez: eu")
    -- Visto pelo jogador 2, os lados trocam.
    local s2 = Tela.render(g, 2)
    assert_contains(T, s2, "Eu:  vida 12")
    assert_contains(T, s2, "Token de ataque: ele")
    assert_contains(T, s2, "Vez: ele")
  end },

  { "render mostra a fogueira à noite", function(T)
    local g = bare()
    for _ = 1, 4 do g:advance_vez() end
    T.eq(g:period(), "noite")
    local s = Tela.render(g, 1)
    assert_contains(T, s, "Período: noite")
    assert_contains(T, s, "Fogueira: eu 3 / ele 3")
  end },

  { "render mostra o campo com dano, palavras-chave e equipamentos", function(T)
    local g = bare()
    local lenhador = put(g, 1, "demo_lenhador", 2)
    g:equip(lenhador, { id = "demo_lanca", uid = g:next_uid() })
    local coelho = put(g, 2, "demo_coelho", 5)
    local cao = put(g, 2, "demo_cao", 1)
    cao.damage = 1
    local s = Tela.render(g, 1)
    assert_contains(T, s, "c2  Lenhador              4/4         vel 1  Sobrevivente  {Lanca}")
    assert_contains(T, s, "o5  Coelho                2/1         vel 1  Fragil")
    assert_contains(T, s, "o1  Cao de caca           2/2 (-1)    vel 1  Agressivo")
    assert_contains(T, s, "c1  (vazio)")
    assert_contains(T, s, "o6  (vazio)")
    T.ok(coelho ~= nil)
  end },

  { "render mostra as estruturas dos dois lados", function(T)
    local g = bare()
    g:put_structure(1, { id = "demo_tocha", uid = g:next_uid() })
    g:put_structure(2, { id = "demo_tocha", uid = g:next_uid() })
    local s = Tela.render(g, 1)
    assert_contains(T, s, "e1  Tocha                 ativável (instantaneo)")
    assert_contains(T, s, "e2  (vazio)")
    assert_contains(T, s, "oe1 Tocha")
    T.ok(g:act(1, { type = "activate", structure = 1 }))
    assert_contains(T, Tela.render(g, 1), "e1  Tocha                 ativável (instantaneo, usada)")
  end },

  { "render numera a mão com nome, custo, tipo, velocidade e texto", function(T)
    local g = bare()
    give(g, 1, "demo_lobo"); give(g, 1, "demo_raio"); give(g, 1, "demo_lanca")
    local s = Tela.render(g, 1)
    assert_contains(T, s, "Mão (3, limite 10")
    assert_contains(T, s, "1. Lobo (custo 3, criatura, vel 1) 3/3")
    assert_contains(T, s, "2. Raio (custo 2, feitico, rapido): Causa 3 de dano a uma criatura.")
    assert_contains(T, s, "3. Lanca (custo 2, equipamento, mao) +2 atq: O portador ganha +2 de ataque.")
    -- A mão do oponente não aparece.
    give(g, 2, "demo_urso")
    T.ok(not contains(Tela.render(g, 1), "Urso"))
  end },

  { "render mostra o Inventário e as separadas quando existem", function(T)
    local g = bare()
    local s = Tela.render(g, 1)
    T.ok(not contains(s, "Inventário"))
    g:add_to_inventory(1, { id = "demo_lanca", uid = g:next_uid() })
    g.players[1].separated[1] = { id = "demo_lobo", uid = g:next_uid() }
    s = Tela.render(g, 1)
    assert_contains(T, s, "Inventário (jogar com: inv <n>)")
    assert_contains(T, s, "1. Lanca (custo 2, equipamento, mao)")
    assert_contains(T, s, "Separadas (jogar com: sep <n>)")
    assert_contains(T, s, "1. Lobo (custo 3, criatura, vel 1)")
  end },

  { "render mostra a pilha e o combate com atacantes e bloqueios", function(T)
    local g = bare()
    put(g, 1, "demo_lobo", 1); put(g, 1, "demo_aranha", 3)
    put(g, 2, "demo_urso", 2)
    T.ok(g:act(1, { type = "attack", attackers = { 1, 3 } }))
    T.ok(g:act(1, { type = "pass" }))
    local s = Tela.render(g, 2)
    assert_contains(T, s, "Pilha (do topo): ataque (ele)")
    assert_contains(T, s, "Combate: atacam o1 Lobo, o3 Aranha")
    assert_contains(T, s, "Bloqueios: declare agora")
    T.ok(g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 2 } } }))
    s = Tela.render(g, 2)
    assert_contains(T, s, "Bloqueios: c2 bloqueia o1")
    assert_contains(T, Tela.render(g, 1), "Bloqueios: o2 bloqueia c1")
  end },

  { "render mostra a escolha pendente numerada só para quem escolhe", function(T)
    local g = bare()
    g:set_choice(1, { reason = "teste", options = { "primeira", "segunda" }, allow_none = true,
      resolve = function() end })
    local s = Tela.render(g, 1)
    assert_contains(T, s, "Escolha pendente (teste): escolher <n> ou escolher nada")
    assert_contains(T, s, "1. primeira")
    assert_contains(T, s, "2. segunda")
    assert_contains(T, s, "Vez: eu (escolha)")
    T.ok(not contains(Tela.render(g, 2), "Escolha pendente"))
  end },

  { "render cabe em 80 colunas", function(T)
    local g = bare()
    local lenhador = put(g, 1, "demo_lenhador", 1)
    g:equip(lenhador, { id = "demo_lanca", uid = g:next_uid() })
    g:equip(lenhador, { id = "demo_armadura", uid = g:next_uid() })
    for _, id in ipairs(Demo.IDS) do give(g, 1, id) end
    for line in Tela.render(g, 1):gmatch("[^\n]+") do
      T.ok(Tela.ulen(line) <= 80, "linha com mais de 80 colunas: " .. line)
    end
  end },

  { "render mostra o fim de partida", function(T)
    local g = bare()
    g.players[2].life = 0
    g:check_winner()
    assert_contains(T, Tela.render(g, 1), "FIM DE PARTIDA: você venceu")
    assert_contains(T, Tela.render(g, 2), "FIM DE PARTIDA: você perdeu")
  end },

  ----------------------------------------------------------------------------
  -- Comandos
  ----------------------------------------------------------------------------

  { "jogar: criatura com e sem espaço, substituindo e feitiço com alvo", function(T)
    local g = bare()
    g.players[1].mana = 10
    give(g, 1, "demo_lobo"); give(g, 1, "demo_raio"); give(g, 1, "demo_curativo")
    put(g, 1, "demo_coelho", 1)
    put(g, 2, "demo_urso", 4)
    local a = parse_ok(T, g, 1, "jogar 1")
    T.eq(a.type, "play"); T.eq(a.hand_index, 1); T.eq(a.from, "hand"); T.eq(a.slot, 2, "primeiro espaço livre")
    T.eq(parse_ok(T, g, 1, "jogar 1 em 5").slot, 5)
    T.eq(parse_ok(T, g, 1, "jogar 1 em c6").slot, 6)
    T.eq(parse_ok(T, g, 1, "jogar 1 substituindo c1").slot, 1)
    a = parse_ok(T, g, 1, "jogar 2 em o4")
    T.eq(a.hand_index, 2); T.eq(a.target.p, 2); T.eq(a.target.slot, 4); T.eq(a.target.zone, "criatura")
    a = parse_ok(T, g, 1, "jogar 2 em c1")
    T.eq(a.target.p, 1); T.eq(a.target.slot, 1)
    a = parse_ok(T, g, 1, "jogar 3 em eu")
    T.eq(a.target.p, 1); T.eq(a.target.zone, "jogador")
    a = parse_ok(T, g, 1, "jogar 3 em ele")
    T.eq(a.target.p, 2); T.eq(a.target.zone, "jogador")
    -- O que o parse devolve, o motor aceita.
    T.ok(g:act(1, parse_ok(T, g, 1, "jogar 2 em o4")))
  end },

  { "jogar: erros dizem o que falta", function(T)
    local g = bare()
    give(g, 1, "demo_lobo"); give(g, 1, "demo_raio"); give(g, 1, "demo_lanca")
    parse_err(T, g, 1, "jogar", "falta o número da carta")
    parse_err(T, g, 1, "jogar 9", "não há carta 9")
    parse_err(T, g, 1, "jogar 2", "falta o alvo")
    parse_err(T, g, 1, "jogar 2 em 3", "precisa do lado")
    parse_err(T, g, 1, "jogar 2 em x9", "alvo inválido")
    parse_err(T, g, 1, "jogar 3", "falta a criatura")
    parse_err(T, g, 1, "jogar 3 em o2", "criatura sua")
    parse_err(T, g, 1, "jogar 1 blá", "não entendi")
    for s = 1, 6 do put(g, 1, "demo_coelho", s) end
    parse_err(T, g, 1, "jogar 1", "campo cheio")
    T.eq(parse_ok(T, g, 1, "jogar 1 substituindo c4").slot, 4)
  end },

  { "jogar: estrutura, equipamento, sacrifício, Inventário e separadas", function(T)
    local g = bare()
    Cards.define{ id = "term_ritual", name = "Ritual", kind = "criatura", cost = 1, atk = 4, hp = 4,
      sacrifice = { count = 2 } }
    give(g, 1, "demo_tocha"); give(g, 1, "demo_lanca"); give(g, 1, "term_ritual")
    put(g, 1, "demo_lenhador", 2); put(g, 1, "demo_coelho", 3)
    local a = parse_ok(T, g, 1, "jogar 1")
    T.eq(a.type, "play"); T.eq(a.slot, nil, "estrutura com vaga não precisa de espaço")
    T.eq(parse_ok(T, g, 1, "jogar 1 em e2").slot, 2)
    g:put_structure(1, { id = "demo_tocha", uid = g:next_uid() })
    g:put_structure(1, { id = "demo_tocha", uid = g:next_uid() })
    parse_err(T, g, 1, "jogar 1", "zona de estruturas cheia")
    T.eq(parse_ok(T, g, 1, "jogar 1 substituindo e1").slot, 1)
    a = parse_ok(T, g, 1, "jogar 2 em c2")
    T.eq(a.target, 2, "equipamento mira o espaço da criatura")
    parse_err(T, g, 1, "jogar 3", "falta o sacrifício")
    a = parse_ok(T, g, 1, "jogar 3 sacrificando c2 c3")
    T.eq(a.sacrifice[1], 2); T.eq(a.sacrifice[2], 3); T.eq(a.slot, 1)
    a = parse_ok(T, g, 1, "jogar 3 em 2 sacrificando 2 3")
    T.eq(a.slot, 2)
    g:add_to_inventory(1, { id = "demo_lanca", uid = g:next_uid() })
    a = parse_ok(T, g, 1, "inv 1 em c2")
    T.eq(a.from, "inventory"); T.eq(a.hand_index, 1); T.eq(a.target, 2)
    T.eq(parse_ok(T, g, 1, "jogar inv 1 em c2").from, "inventory")
    parse_err(T, g, 1, "inv 2", "não há carta 2 no Inventário")
    g.players[1].separated[1] = { id = "demo_lobo", uid = g:next_uid() }
    T.eq(parse_ok(T, g, 1, "sep 1").from, "separated")
  end },

  { "atacar: espaços, todos e erros", function(T)
    local g = bare()
    put(g, 1, "demo_lobo", 1); put(g, 1, "demo_aranha", 4)
    local a = parse_ok(T, g, 1, "atacar c1 c4")
    T.eq(a.type, "attack"); T.eq(#a.attackers, 2); T.eq(a.attackers[1], 1); T.eq(a.attackers[2], 4)
    T.eq(parse_ok(T, g, 1, "atacar 4").attackers[1], 4)
    a = parse_ok(T, g, 1, "atacar todos")
    T.eq(#a.attackers, 2)
    parse_err(T, g, 1, "atacar", "falta quem ataca")
    parse_err(T, g, 1, "atacar o1", "use c1..c6")
    parse_err(T, g, 1, "atacar c9", "espaço inválido")
    T.ok(g:act(1, parse_ok(T, g, 1, "atacar todos")))
  end },

  { "bloquear: pares, nada e erros", function(T)
    local g = bare()
    put(g, 1, "demo_lobo", 1); put(g, 1, "demo_aranha", 3)
    put(g, 2, "demo_urso", 2); put(g, 2, "demo_lenhador", 5)
    T.ok(g:act(1, { type = "attack", attackers = { 1, 3 } }))
    T.ok(g:act(1, { type = "pass" }))
    local a = parse_ok(T, g, 2, "bloquear o1=c2 o3=c5")
    T.eq(a.type, "block"); T.eq(#a.blocks, 2)
    T.eq(a.blocks[1].attacker, 1); T.eq(a.blocks[1].blocker, 2)
    T.eq(a.blocks[2].attacker, 3); T.eq(a.blocks[2].blocker, 5)
    T.eq(parse_ok(T, g, 2, "bloquear 1=2").blocks[1].blocker, 2)
    T.eq(#parse_ok(T, g, 2, "bloquear nada").blocks, 0)
    parse_err(T, g, 2, "bloquear", "falta o bloqueio")
    parse_err(T, g, 2, "bloquear o1", "use <atacante>=<bloqueador>")
    parse_err(T, g, 2, "bloquear c1=c2", "atacante inválido")
    parse_err(T, g, 2, "bloquear o1=o2", "bloqueador inválido")
    T.ok(g:act(2, a))
  end },

  { "ativar: estrutura, criatura, equipamento e alvo", function(T)
    local g = bare()
    local a = parse_ok(T, g, 1, "ativar e1")
    T.eq(a.type, "activate"); T.eq(a.structure, 1); T.eq(a.creature, nil)
    T.eq(parse_ok(T, g, 1, "ativar 2").structure, 2)
    a = parse_ok(T, g, 1, "ativar c3")
    T.eq(a.creature, 3); T.eq(a.equip, nil)
    a = parse_ok(T, g, 1, "ativar c3 mao em o2")
    T.eq(a.creature, 3); T.eq(a.equip, "mao"); T.eq(a.target.p, 2); T.eq(a.target.slot, 2)
    a = parse_ok(T, g, 1, "ativar e1 em oe2")
    T.eq(a.target.zone, "estrutura"); T.eq(a.target.p, 2); T.eq(a.target.slot, 2)
    parse_err(T, g, 1, "ativar", "falta o que ativar")
    parse_err(T, g, 1, "ativar oe1", "só se ativa o que é seu")
    parse_err(T, g, 1, "ativar e3", "espaço de estrutura inválido")
    g:put_structure(1, { id = "demo_tocha", uid = g:next_uid() })
    T.ok(g:act(1, parse_ok(T, g, 1, "ativar e1")))
    T.eq(g.players[2].life, 19)
  end },

  { "escolher, passar, jogadas, ajuda, sair e desconhecido", function(T)
    local g = bare()
    local a = parse_ok(T, g, 1, "escolher 2")
    T.eq(a.type, "choose"); T.eq(a.index, 2)
    T.eq(parse_ok(T, g, 1, "escolher nada").index, 0)
    parse_err(T, g, 1, "escolher", "falta a opção")
    parse_err(T, g, 1, "escolher x", "opção inválida")
    T.eq(parse_ok(T, g, 1, "passar").type, "pass")
    T.eq(parse_ok(T, g, 1, "PASSAR").type, "pass", "maiúsculas valem")
    T.eq(parse_ok(T, g, 1, "jogadas").type, "jogadas")
    T.eq(parse_ok(T, g, 1, "ajuda").type, "ajuda")
    T.eq(parse_ok(T, g, 1, "sair").type, "sair")
    parse_err(T, g, 1, "", "digite um comando")
    parse_err(T, g, 1, "voar", "comando desconhecido")
    T.ok(contains(Comandos.help(), "bloquear"))
  end },

  { "j <n> devolve a n-ésima jogada de Jogadas.list", function(T)
    local g = bare()
    give(g, 1, "demo_coelho")
    local lista = Jogadas.list(g, 1)
    T.ok(#lista >= 2)
    T.eq(parse_ok(T, g, 1, "j 1").type, "pass")
    local a = parse_ok(T, g, 1, "j 2")
    T.eq(a.type, lista[2].type); T.eq(a.hand_index, lista[2].hand_index); T.eq(a.slot, lista[2].slot)
    parse_err(T, g, 1, "j 99", "não há jogada 99")
    parse_err(T, g, 1, "jogar 1 em o3", "essa carta não tem alvo")
    parse_err(T, g, 1, "j", "falta o número da jogada")
    parse_err(T, g, 1, "j x", "falta o número da jogada")
  end },

  { "todo comando gerado de uma jogada volta à mesma ação pelo parse", function(T)
    local g = bare()
    g.players[1].mana = 10
    give(g, 1, "demo_lobo"); give(g, 1, "demo_raio"); give(g, 1, "demo_lanca"); give(g, 1, "demo_tocha")
    give(g, 1, "demo_curativo")
    put(g, 1, "demo_lenhador", 1); put(g, 2, "demo_urso", 2)
    g:put_structure(1, { id = "demo_tocha", uid = g:next_uid() })
    local function key(a)
      local parts = {}
      for k, v in pairs(a) do
        if type(v) == "table" then
          local inner = {}
          for k2, v2 in pairs(v) do inner[#inner + 1] = tostring(k2) .. "=" .. tostring(v2) end
          table.sort(inner)
          v = "{" .. table.concat(inner, ",") .. "}"
        end
        parts[#parts + 1] = k .. "=" .. tostring(v)
      end
      table.sort(parts)
      return table.concat(parts, " ")
    end
    local lista = Jogadas.list(g, 1)
    T.ok(#lista > 10)
    for _, a in ipairs(lista) do
      local cmd = Partida.describe_action(g, 1, a):gsub(" %(.-%)", "")
      local b, err = Comandos.parse(g, 1, cmd)
      T.ok(b ~= nil, "comando \"" .. cmd .. "\" deu erro: " .. tostring(err))
      T.eq(key(b), key(a), "comando \"" .. cmd .. "\"")
    end
  end },

  ----------------------------------------------------------------------------
  -- Partida
  ----------------------------------------------------------------------------

  { "Partida.new deixa o bot jogar até a vez do humano", function(T)
    local partida = Partida.new{ decks = Demo.decks(), seed = 3, human = 1 }
    local g = partida.g
    T.eq(g.first, 2, "com esta semente o bot começa")
    T.eq(g.active, 1, "a vez já é do humano")
    local s = partida:tela()
    assert_contains(T, s, "Rodada 1: token de ataque com o bot.")
    assert_contains(T, s, "Vez: eu")
    -- A tela seguinte não repete os eventos já mostrados.
    T.ok(not contains(partida:tela(), "Rodada 1: token"))
  end },

  { "Partida.step aplica o comando, deixa o bot responder e devolve a tela", function(T)
    local partida = Partida.new{ decks = Demo.decks(), seed = 5, human = 1 }
    local g = partida.g
    T.eq(g.active, 1)
    local n = #g.players[1].hand
    local saida, acabou = partida:step("passar")
    T.eq(acabou, false)
    T.ok(g.active == 1 or g.pending_choice ~= nil, "a vez voltou ao humano")
    assert_contains(T, saida, "Rodada")
    assert_contains(T, saida, "Mão (")
    T.ok(#g.players[1].hand >= n - 1)
  end },

  { "Partida.step devolve o erro do comando e do motor sem mudar a partida", function(T)
    local partida = Partida.new{ decks = Demo.decks(), seed = 5, human = 1 }
    local g = partida.g
    local eventos = #g.events
    local saida, acabou = partida:step("voar")
    T.eq(acabou, false)
    assert_contains(T, saida, "Erro: comando desconhecido")
    saida, acabou = partida:step("atacar c1")
    T.eq(acabou, false)
    assert_contains(T, saida, "Erro: ")
    T.eq(#g.events, eventos, "nada aconteceu")
  end },

  { "Partida.step responde a ajuda e jogadas", function(T)
    local partida = Partida.new{ decks = Demo.decks(), seed = 5, human = 1 }
    local saida = partida:step("ajuda")
    assert_contains(T, saida, "Comandos:")
    saida = partida:step("jogadas")
    assert_contains(T, saida, "Jogadas válidas (j <n> executa):")
    assert_contains(T, saida, "1. passar")
  end },

  { "step(\"sair\") encerra a partida", function(T)
    local partida = Partida.new{ decks = Demo.decks(), seed = 5, human = 1 }
    local saida, acabou = partida:step("sair")
    T.eq(acabou, true)
    assert_contains(T, saida, "Partida encerrada")
    saida, acabou = partida:step("passar")
    T.eq(acabou, true)
    assert_contains(T, saida, "já acabou")
  end },

  { "uma sequência de comandos joga até o fim contra o bot com semente fixa", function(T)
    local partida = Partida.new{ decks = Demo.decks(), seed = 11, human = 1 }
    local rng = Partida.make_rng(77)
    local passos, acabou, ultima = 0, false, ""
    while not acabou do
      passos = passos + 1
      T.ok(passos < 1000, "a partida não acaba")
      -- Uma jogada válida qualquer, escrita como comando.
      local lista = Jogadas.list(partida.g, partida.human)
      T.ok(#lista > 0, "o humano sempre tem uma jogada")
      local cmd = Partida.describe_action(partida.g, partida.human, lista[rng(#lista)]):gsub(" %(.-%)", "")
      ultima, acabou = partida:step(cmd)
      T.ok(not contains(ultima, "Erro"), "comando \"" .. cmd .. "\": " .. ultima)
    end
    T.ok(partida.g.winner ~= nil, "a partida tem vencedor")
    T.eq(partida.g.phase, "over")
    assert_contains(T, ultima, "FIM DE PARTIDA")
    T.ok(passos > 5)
  end },

  { "a mesma semente dá a mesma partida", function(T)
    local function jogar(seed)
      local partida = Partida.new{ decks = Demo.decks(), seed = seed, human = 2 }
      local out = {}
      for _ = 1, 8 do
        local s, acabou = partida:step("passar")
        out[#out + 1] = s
        if acabou then break end
      end
      return table.concat(out)
    end
    T.eq(jogar(9), jogar(9))
    T.ok(jogar(9) ~= jogar(10))
  end },

  { "o humano responde a uma escolha e bloqueia pelo comando", function(T)
    local partida = Partida.new{ decks = Demo.decks(), seed = 5, human = 1 }
    local g = partida.g
    g:set_choice(1, { reason = "teste", options = { "a", "b" }, resolve = function() end })
    assert_contains(T, partida:tela(), "Escolha pendente (teste)")
    local saida, acabou = partida:step("escolher 2")
    T.eq(acabou, false)
    T.eq(g.pending_choice, nil)
    T.ok(not contains(saida, "Erro"), saida)
  end },

  ----------------------------------------------------------------------------
  -- Eventos
  ----------------------------------------------------------------------------

  { "describe_events narra golpe, morte e dano ao jogador", function(T)
    local g = bare()
    put(g, 1, "demo_lobo", 1); put(g, 1, "demo_aranha", 2)
    put(g, 2, "demo_coelho", 3)
    local from = #g.events + 1
    T.ok(g:act(1, { type = "attack", attackers = { 1, 2 } }))
    T.ok(g:act(1, { type = "pass" }))
    T.ok(g:act(2, { type = "block", blocks = { { attacker = 1, blocker = 3 } } }))
    T.ok(g:act(2, { type = "pass" }))
    T.ok(g:act(1, { type = "pass" }))
    T.eq(g.players[2].life, 18)
    local texto = table.concat(Partida.describe_events(g, from, 1), "\n")
    assert_contains(T, texto, "Você ataca com Lobo, Aranha.")
    assert_contains(T, texto, "O bot bloqueia: Coelho bloqueia Lobo.")
    assert_contains(T, texto, "Fase rápida: Aranha.")
    assert_contains(T, texto, "Aranha golpeia o bot por 2.")
    assert_contains(T, texto, "O bot sofre 2 de dano (combate); vida 18.")
    assert_contains(T, texto, "Fase normal: Lobo contra Coelho.")
    assert_contains(T, texto, "Lobo golpeia Coelho por 3.")
    assert_contains(T, texto, "Coelho golpeia Lobo por 2.")
    assert_contains(T, texto, "Coelho (do bot) morre por Lobo.")
    -- Do ponto de vista do bot, os papéis trocam.
    local texto2 = table.concat(Partida.describe_events(g, from, 2), "\n")
    assert_contains(T, texto2, "O bot ataca com Lobo, Aranha.")
    assert_contains(T, texto2, "Você bloqueia: Coelho bloqueia Lobo.")
    assert_contains(T, texto2, "Você sofre 2 de dano (combate); vida 18.")
    assert_contains(T, texto2, "Coelho (sua) morre por Lobo.")
  end },

  { "describe_events narra jogadas, estruturas, equipamentos e fim de partida", function(T)
    local g = bare()
    g.players[1].mana = 10
    give(g, 1, "demo_lenhador"); give(g, 1, "demo_lanca"); give(g, 1, "demo_tocha")
    local from = #g.events + 1
    T.ok(g:act(1, { type = "play", hand_index = 1, slot = 2 }))
    T.ok(g:act(2, { type = "pass" }))
    T.ok(g:act(1, { type = "play", hand_index = 1, target = 2 }))
    T.ok(g:act(2, { type = "pass" }))
    T.ok(g:act(1, { type = "play", hand_index = 1 }))
    T.ok(g:act(2, { type = "pass" }))
    T.ok(g:act(1, { type = "activate", structure = 1 }))
    local texto = table.concat(Partida.describe_events(g, from, 1), "\n")
    assert_contains(T, texto, "Você jogou Lenhador (custo 3).")
    assert_contains(T, texto, "Lenhador entra em c2.")
    assert_contains(T, texto, "O bot passou.")
    assert_contains(T, texto, "Lanca equipada em Lenhador (mao).")
    assert_contains(T, texto, "Tocha entra em e1.")
    assert_contains(T, texto, "Você ativou Tocha.")
    assert_contains(T, texto, "O bot sofre 1 de dano (tocha); vida 19.")
    assert_contains(T, texto, "Período: tarde.")
    g.players[2].life = 0
    g:check_winner()
    texto = table.concat(Partida.describe_events(g, #g.events, 1), "\n")
    assert_contains(T, texto, "FIM DE PARTIDA: você venceu!")
    T.eq(Partida.describe_events(g, #g.events, 2)[1], "FIM DE PARTIDA: você perdeu.")
  end },

  { "describe_events não revela a compra do outro jogador", function(T)
    local g = bare()
    local from = #g.events + 1
    g:draw(2, 1)
    T.eq(#Partida.describe_events(g, from, 1), 0)
    T.eq(#Partida.describe_events(g, from, 2), 0, "compra do baralho não gera frase")
  end },

  { "a tela marca as cartas acima do limite de mão", function(T)
    local g = bare()
    local remove = g:add_hand_limit_mod(function() return 1 end)
    while g:hand_count(1) < Game.HAND_LIMIT + 1 do give(g, 1, "demo_coelho") end
    remove()
    local text = Tela.render(g, 1)
    T.ok(text:find("\n! ", 1, true) ~= nil, "uma carta marcada")
    T.ok(text:find("será destruída no fim da rodada", 1, true) ~= nil)
    g:act(1, { type = "play", hand_index = #g.players[1].hand, slot = 1 })
    text = Tela.render(g, 1)
    T.eq(text:find("\n! ", 1, true), nil, "usada, some a marca")
  end },

  { "a destruição do fim da rodada é narrada sem revelar a carta do adversário", function(T)
    local g = bare()
    local remove = g:add_hand_limit_mod(function() return 1 end)
    while g:hand_count(2) < Game.HAND_LIMIT + 1 do give(g, 2, "demo_coelho") end
    remove()
    local from = #g.events
    g:act(1, { type = "pass" }); g:act(2, { type = "pass" })
    local text = table.concat(Partida.describe_events(g, from, 1), "\n")
    T.ok(text:find("Fim da rodada: uma carta acima do limite", 1, true) ~= nil, text)
    T.eq(text:find("Coelho", 1, true), nil, "o nome da carta do bot não aparece")
  end },
}
