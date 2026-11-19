-- Decks do jogo: listas de ids e quantidades. Lua 5.1 puro.
--
-- Regras de montagem (doc, "Deck"): 40 cartas no baralho principal, até 3
-- cópias da mesma carta. O baralho extra guarda as cópias que efeitos criam
-- (fichas); hoje ele é listado à mão em cada deck, e a derivação automática a
-- partir do principal fica para a US #125.
--
-- Interface:
--   local Decks = require("duelo/decks/init")
--   Decks.NOMES                     -> { "wilson", "webber" }
--   Decks.lista(nome)               -> { { id, quantidade }, ... } (principal)
--   Decks.lista_extra(nome)         -> idem, baralho extra
--   Decks.build(nome)               -> baralho, extra (listas de { id = ... },
--                                      como Game.new espera); registra as cartas
--   Decks.carregar_cartas()         registra todas as cartas do jogo no motor
--   Decks.validar(lista) -> ok, erro  40 cartas, até 3 cópias inteiras, sem id
--                                      repetido, ids registrados (carrega as cartas)
--   Decks.validar_extra(lista) -> ok, erro  idem sem exigir o total

local Cards = require("duelo/core/cards")

local Decks = {}

Decks.NOMES = { "wilson", "webber" }
Decks.TAMANHO = 40
Decks.COPIAS = 3

-- Relê o arquivo do deck a cada chamada: ele é só dados, e assim ninguém
-- recebe uma lista já mutada por outro chamador.
local function carregar(nome)
  package.loaded["duelo/decks/" .. nome] = nil
  return require("duelo/decks/" .. nome)
end

function Decks.carregar_cartas()
  package.loaded["duelo/cartas/init"] = nil
  require("duelo/cartas/init")
end

function Decks.lista(nome) return carregar(nome).principal end
function Decks.lista_extra(nome) return carregar(nome).extra end

local function expandir(lista)
  local d = {}
  for _, item in ipairs(lista) do
    for _ = 1, item[2] do d[#d + 1] = { id = item[1] } end
  end
  return d
end

function Decks.build(nome)
  Decks.carregar_cartas()
  local deck = carregar(nome)
  return expandir(deck.principal), expandir(deck.extra)
end

local function conferir(lista)
  Decks.carregar_cartas()
  local total, vistos = 0, {}
  for _, item in ipairs(lista) do
    local id, n = item[1], item[2]
    if Cards.get(id) == nil then return nil, "carta desconhecida: " .. tostring(id) end
    if vistos[id] then return nil, "carta repetida na lista: " .. id end
    vistos[id] = true
    if type(n) ~= "number" or n % 1 ~= 0 or n < 1 or n > Decks.COPIAS then
      return nil, id .. ": " .. tostring(n) .. " cópias (máximo " .. Decks.COPIAS .. ", inteiro)"
    end
    total = total + n
  end
  return total
end

function Decks.validar(lista)
  local total, err = conferir(lista)
  if total == nil then return false, err end
  if total ~= Decks.TAMANHO then
    return false, "o deck tem " .. total .. " cartas (precisa de " .. Decks.TAMANHO .. ")"
  end
  return true
end

function Decks.validar_extra(lista)
  local total, err = conferir(lista)
  if total == nil then return false, err end
  return true
end

return Decks
