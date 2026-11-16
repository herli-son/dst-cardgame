-- Registro de definições de cartas. Lua 5.1 puro.
--
-- Uma definição descreve a carta (custo, atributos, palavras-chave, efeitos).
-- As cartas de conteúdo ficam em arquivos próprios e se registram com Cards.define.
--
-- Campos comuns:
--   id, name, kind ("criatura" | "feitico" | "estrutura" | "equipamento" | "turf" | "evento"), cost
-- Criatura:
--   atk, hp, speed (padrão 1), kw = { agressivo = true, fragil = true, ... },
--   types = { aranha = true, ... }, sobrevivente (boolean)
--   on_play(game, criatura)            efeito ao entrar em campo
--   on_any_enter(game, criatura, nova) reage a qualquer criatura que entrar
--   stats(game, criatura) -> atk, hp   atributos que dependem do estado (ex.: Morcego)
-- Feitiço:
--   speed ("instantaneo" | "rapido" | "lento")
--   targets(game, p, action) -> ok, erro   confere os alvos (na jogada e de novo ao resolver)
--   on_cast(game, p, action, card)        o efeito

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

return Cards
