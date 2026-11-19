-- Decks do MVP (#20, #21): validade das listas e partidas inteiras com as
-- cartas reais no simulador (bot contra bot e ao acaso).
local Decks = require("duelo/decks/init")
local Simulador = require("duelo/sim/simulador")

local function somar(lista)
  local n = 0
  for _, item in ipairs(lista) do n = n + item[2] end
  return n
end

local tests = {
  { "os decks do MVP têm 40 cartas, até 3 cópias e só cartas registradas", function(T)
    for _, nome in ipairs(Decks.NOMES) do
      local ok, err = Decks.validar(Decks.lista(nome))
      T.ok(ok, nome .. ": " .. tostring(err))
      ok, err = Decks.validar_extra(Decks.lista_extra(nome))
      T.ok(ok, nome .. " extra: " .. tostring(err))
      local deck, extra = Decks.build(nome)
      T.eq(#deck, 40, nome)
      T.eq(#extra, somar(Decks.lista_extra(nome)), nome .. " extra")
    end
  end },

  { "cada deck tem o campeão e o Webber tem uma Aranha no extra por cópia", function(T)
    local function qtd(lista, id)
      for _, item in ipairs(lista) do if item[1] == id then return item[2] end end
      return 0
    end
    T.eq(qtd(Decks.lista("wilson"), "wilson"), 3)
    T.eq(qtd(Decks.lista("webber"), "webber"), 3)
    T.eq(qtd(Decks.lista_extra("webber"), "aranha"), qtd(Decks.lista("webber"), "webber"))
  end },

  { "validar recusa 39 cartas, 4 cópias, cópias fracionadas, id repetido e carta desconhecida", function(T)
    local base = Decks.lista("wilson")
    local function copia() local l = {} for i, it in ipairs(base) do l[i] = { it[1], it[2] } end return l end
    local function recusa(l, trecho)
      local ok, err = Decks.validar(l)
      T.eq(ok, false, trecho)
      T.ok(type(err) == "string" and err:find(trecho, 1, true) ~= nil, tostring(err))
    end
    local l = copia(); l[1][2] = 2
    recusa(l, "39 cartas")
    -- 4 cópias com o total ainda em 40, para a recusa vir só das cópias.
    l = copia(); l[1][2] = 4; l[2][2] = 1
    recusa(l, "cópias")
    l = copia(); l[1][2] = 2.5; l[2][2] = 2.5
    recusa(l, "cópias")
    l = copia(); l[1][1] = "nao_existe"
    recusa(l, "desconhecida")
    l = copia(); l[1][2] = 2; l[#l + 1] = { "wilson", 1 }
    recusa(l, "repetida")
    T.eq((Decks.validar(base)), true)
    T.eq((Decks.validar_extra({ { "aranha", 3 } })), true)
    T.eq((Decks.validar_extra({ { "aranha", 4 } })), false)
  end },
}

-- Partidas inteiras com as cartas reais: cada combinação de decks, bot x bot
-- e ao acaso, com várias sementes; nenhuma pode terminar em erro, travamento
-- ou invariante quebrada.
local combos = { { "wilson", "webber" }, { "webber", "wilson" }, { "wilson", "wilson" }, { "webber", "webber" } }
for _, combo in ipairs(combos) do
  for _, modo in ipairs({ "bot", "random" }) do
    tests[#tests + 1] = { combo[1] .. " x " .. combo[2] .. " (" .. modo .. ") joga sem falhas", function(T)
      local d1, e1 = Decks.build(combo[1])
      local d2, e2 = Decks.build(combo[2])
      for seed = 1, 3 do
        local r = Simulador.run_game{ decks = { d1, d2 }, extra_decks = { e1, e2 }, seed = seed,
          players = { modo, modo }, max_rounds = 40 }
        local ok = r.resultado == "vitoria" or r.resultado == "empate" or r.resultado == "limite_rodadas"
        T.ok(ok, combo[1] .. " x " .. combo[2] .. " " .. modo .. " seed " .. seed .. ": " .. r.resultado
          .. " (" .. tostring(r.motivo) .. ", passo " .. tostring(r.passo) .. ")"
          .. (r.erro and r.erro.traceback and ("\n" .. r.erro.traceback) or ""))
      end
    end }
  end
end

return tests
