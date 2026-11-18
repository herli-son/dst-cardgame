-- Registro de definições de cartas. Lua 5.1 puro.
--
-- Uma definição descreve a carta (custo, atributos, palavras-chave, efeitos).
-- As cartas de conteúdo ficam em arquivos próprios e se registram com Cards.define.
--
-- Campos comuns:
--   id, name, kind ("criatura" | "feitico" | "estrutura" | "equipamento" | "turf" | "evento"), cost
-- Criatura:
--   atk, hp, speed (padrão 1), kw = { agressivo = true, fragil = true, ... },
--   kw.rival = "tipo"                  Rival guarda o nome do tipo (ex.: "porco")
--   types = { aranha = true, ... }, sobrevivente (boolean)
--   returns_to_extra = true            como ficha, volta ao baralho extra em vez do
--                                      descarte (Fantasmas criados, Alimentos)
--   no_attack = true / no_block = true não pode atacar / não pode bloquear
--   block_speed                        velocidade ao bloquear (ex.: Tentáculo)
--   speed_fn(game, criatura, role)     velocidade que depende do estado; role =
--                                      "attack" | "block"
--   on_strike(game, criatura, alvo)    Golpear: depois de um golpe com dano > 0
--   on_play(game, criatura, objects, action)  efeito ao entrar em campo; com
--                                      play_targets, os alvos vêm da jogada (objects)
--   play_targets(game, p, action, objects) -> ok, erro   alvos do efeito de
--                                      entrada (criatura ou estrutura), conferidos
--                                      na jogada e de novo na entrada
--   on_any_enter(game, criatura, nova) reage a qualquer criatura que entrar
--   stats(game, criatura) -> atk, hp   atributos que dependem do estado (ex.: Morcego)
-- Feitiço:
--   speed ("instantaneo" | "rapido" | "lento")
--   targets(game, p, action, objects) -> ok, erro   confere os alvos; objects traz os
--                                         objetos dos alvos, na jogada e ao resolver
--   on_cast(game, p, action, card, objects)  o efeito; use objects, não o espaço da ação
--   creates_structure = true           cria estrutura: com a zona cheia, a jogada
--                                      traz action.replace (espaço a substituir), que o
--                                      efeito passa como opts.slot de create_token
-- Equipamento:
--   on_strike(game, portador, alvo, equip)  Golpear do equipamento

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
