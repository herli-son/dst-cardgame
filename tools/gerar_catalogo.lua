-- Gera scripts/duelo/mod/catalogo.lua a partir das cartas (US #37).
-- Rodar na raiz do repositório: lua tools/gerar_catalogo.lua
package.path = "scripts/?.lua;" .. package.path
local texto = require("duelo/mod/catalogo_gerador").texto()
local f = assert(io.open("scripts/duelo/mod/catalogo.lua", "w"))
f:write(texto)
f:close()
print("scripts/duelo/mod/catalogo.lua gerado (" .. #texto .. " bytes)")
