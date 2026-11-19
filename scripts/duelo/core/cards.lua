-- Registro de definições de cartas. Lua 5.1 puro.
--
-- Uma definição descreve a carta (custo, atributos, palavras-chave, efeitos).
-- As cartas de conteúdo ficam em arquivos próprios e se registram com Cards.define.
--
-- Campos comuns:
--   id, name, kind ("criatura" | "feitico" | "estrutura" | "equipamento" | "turf" | "evento"), cost
--   numero                             número permanente da carta (cartas/numeros.lua),
--                                      usado no código do deck
--   campeao = true, nivel = n          marcação de Campeão (kind continua "criatura")
--                                      e o nível dele; só informativos por enquanto
-- Criatura:
--   atk, hp, speed (padrão 1), kw = { agressivo = true, fragil = true, ... },
--   kw.rival = "tipo"                  Rival guarda o nome do tipo (ex.: "porco")
--   kw.guarda = true                   Guarda (Porco guarda): só na defesa, depois
--                                      de bloquear o atacante dela e sobreviver,
--                                      passa a bloquear o próximo atacante à
--                                      direita que nunca teve bloqueador; uma vez
--                                      por combate (ver combate.lua)
--   types = { aranha = true, ... }, sobrevivente (boolean)
--   campeao = true                     Campeão (ex.: Webber); só marca a carta, o
--                                      motor ainda não trata Campeões diferente
--   returns_to_extra = true            como ficha, volta ao baralho extra em vez do
--                                      descarte (Fantasmas criados, Alimentos)
--   no_attack = true / no_block = true não pode atacar / não pode bloquear
--   cannot_be_blocked_by(game, atacante, bloqueador) -> boolean   restrição de
--                                      bloqueio da atacante: true recusa esse
--                                      bloqueador (ex.: Webber e as Aranhas do
--                                      adversário). Vale no bloqueio declarado,
--                                      nos obrigatórios e no salto da Guarda; deve
--                                      depender só das cartas, não do momento
--                                      (o emparelhamento obrigatório fica em cache
--                                      por combate)
--   sacrifice = { count = n, filter = fn(game, c) }  custo de jogar: abater n
--                                      criaturas suas (action.sacrifice = espaços)
--   block_speed                        velocidade ao bloquear (ex.: Tentáculo)
--   speed_fn(game, criatura, role)     velocidade que depende do estado; role =
--                                      "attack" | "block"
--   on_strike(game, criatura, alvo)    Golpear: depois de um golpe com dano > 0
--   on_attack(game, criatura)          Ao atacar: quando a criatura é declarada
--                                      atacante (antes dos bloqueios)
--   on_play(game, criatura, objects, action)  efeito ao entrar em campo; com
--                                      play_targets, os alvos vêm da jogada (objects)
--   play_targets(game, p, action, objects) -> ok, erro   alvos do efeito de
--                                      entrada (criatura ou estrutura), conferidos
--                                      na jogada e de novo na entrada
--   on_any_enter(game, criatura, nova) reage a qualquer criatura que entrar
--   stats(game, criatura) -> atk, hp   atributos que dependem do estado (ex.: Morcego)
--   aura_hp(game, fonte, alvo) -> n    bônus de vida contínuo que a fonte, em campo,
--                                      dá a cada criatura do mesmo dono (ela
--                                      inclusa); somado em Game:hp. Não pode
--                                      chamar Game:hp (laço). Quando a fonte sai,
--                                      a vida cai e o dano marcado pode virar
--                                      letal no próximo estado estável
-- Feitiço:
--   speed ("instantaneo" | "rapido" | "lento")
--   targets(game, p, action, objects) -> ok, erro   confere os alvos; objects traz os
--                                         objetos dos alvos, na jogada e ao resolver
--   on_cast(game, p, action, card, objects)  o efeito; use objects, não o espaço da ação
--   creates_structure = true           cria estrutura: com a zona cheia, a jogada
--                                      traz action.replace (espaço a substituir), que o
--                                      efeito passa como opts.slot de create_token
-- Equipamento (campos de bônus em equipamentos.lua: slot, atk_bonus, hp_bonus,
-- durability, damage_reduction):
--   on_strike(game, portador, alvo, equip)  Golpear do equipamento
--   on_attack(game, portador, equip)   Ao atacar do equipamento (o portador foi
--                                      declarado atacante)
--   activate(game, p, equip, action, objects)  efeito ativado; equip.holder é o
--                                      portador e só existe durante o activate (não
--                                      em can_activate nem em targets). O uso gasta
--                                      1 de durabilidade, salvo activation.no_wear
--   can_activate(game, p, fonte, action) -> ok, motivo   condição extra do efeito
--                                      ativado (estrutura ou equipamento)

local Cards = {}

local registry = {}

function Cards.define(def)
  assert(type(def.id) == "string", "carta sem id")
  local SPEEDS = { instantaneo = true, rapido = true, lento = true }
  if def.activate then
    -- Cada efeito ativado diz o seu tipo: Instantâneo, Rápido ou Lento.
    assert(def.activation and SPEEDS[def.activation.speed],
      "carta " .. def.id .. ": activation.speed precisa ser instantaneo, rapido ou lento")
  end
  if def.kind == "feitico" then
    assert(SPEEDS[def.speed], "carta " .. def.id .. ": feitiço precisa de speed instantaneo, rapido ou lento")
    assert(type(def.on_cast) == "function", "carta " .. def.id .. ": feitiço precisa de on_cast")
  end
  if def.kind == "equipamento" then
    assert(def.slot == "mao" or def.slot == "peito" or def.slot == "cabeca",
      "carta " .. def.id .. ": equipamento precisa de slot mao, peito ou cabeca")
  end
  def.kw = def.kw or {}
  -- Rival guarda o nome do tipo (ex.: rival = "porco"), não true.
  assert(def.kw.rival == nil or type(def.kw.rival) == "string",
    "carta " .. def.id .. ": kw.rival precisa ser o nome de um tipo")
  def.types = def.types or {}
  def.cost = def.cost or 0
  registry[def.id] = def
  return def
end

function Cards.get(id)
  return registry[id]
end

function Cards.remove(id)
  registry[id] = nil
end

-- Usado pelos testes para isolar o registro entre casos.
function Cards.snapshot()
  local copy = {}
  for k, v in pairs(registry) do copy[k] = v end
  return copy
end

function Cards.restore(snap)
  for k in pairs(registry) do registry[k] = nil end
  for k, v in pairs(snap) do registry[k] = v end
end

return Cards
