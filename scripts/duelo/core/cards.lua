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

local Cards = {}

local registry = {}

function Cards.define(def)
  assert(type(def.id) == "string", "carta sem id")
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
