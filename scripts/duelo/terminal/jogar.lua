-- Jogar pelo terminal contra o bot. Lua 5.1 puro, sem o Don't Starve Together.
--
-- Uso, a partir da raiz do repositório (ou de qualquer pasta):
--   lua5.1 scripts/duelo/terminal/jogar.lua [semente]
--
-- A semente é um número; a mesma semente dá o mesmo embaralhamento e as mesmas
-- jogadas do bot para as mesmas entradas. Sem semente, usa o relógio.
-- Digite "ajuda" para a lista de comandos e "sair" para encerrar.

-- A pasta scripts/ fica dois níveis acima deste arquivo. O separador pode ser
-- "/" ou "\" (Windows); o Lua aceita "/" nos dois sistemas.
local function pasta_do_script()
  local caminho = arg and arg[0] or ""
  local dir = caminho:match("^(.*)[/\\][^/\\]*$")
  return dir or "."
end

-- Também procura em scripts/ a partir da pasta atual, para quando arg[0] não
-- trouxer o caminho (alguns interpretadores embutidos).
local raiz_scripts = pasta_do_script() .. "/../.."
package.path = raiz_scripts .. "/?.lua;scripts/?.lua;" .. package.path

local Demo = require("duelo/terminal/deck_demo")
local Partida = require("duelo/terminal/partida")
local Comandos = require("duelo/terminal/comandos")

local seed = tonumber(arg and arg[1]) or os.time()

io.write("Duelo no terminal. Semente: " .. seed .. "\n")
io.write(Comandos.help() .. "\n\n")

local partida = Partida.new{ decks = Demo.decks(), seed = seed, human = 1 }
io.write(partida:tela())

while true do
  io.write("> ")
  io.flush()
  local linha = io.read("*l")
  if linha == nil then
    io.write("\nPartida encerrada.\n")
    break
  end
  local saida, acabou = partida:step(linha)
  io.write(saida)
  if acabou then break end
end
