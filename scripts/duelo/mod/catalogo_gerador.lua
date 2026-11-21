-- Gera scripts/duelo/mod/catalogo.lua (US #37): o que os clientes precisam
-- saber de cada carta para desenhá-la (nome, tipo, custo, ataque, vida, texto
-- e imagem), sem carregar as cartas nem o motor.
--
-- As definições das cartas (scripts/duelo/cartas) têm funções e pedem o
-- motor; os clientes não as carregam (US #41). O catálogo é só dados, e é
-- público: tudo o que está nele está impresso na carta.
--
-- Para gerar de novo, depois de criar ou mudar uma carta (na raiz do repo):
--   lua tools/gerar_catalogo.lua
-- tests/test_mod_mao.lua falha se o arquivo não bater com as cartas.
--
-- Este módulo NÃO é carregado no jogo: só pelo gerador e pelos testes.
--
-- Imagem de cada carta (IMAGENS abaixo):
--   { tipo = "album", tex = "pigman.tex" }    ícone do Álbum do jogo
--       (images/scrapbook_icons1..3.xml; o atlas certo vem de
--       GetScrapbookIconAtlas, em simutil.lua);
--   { tipo = "avatar", tex = "avatar_wilson.tex" }   retrato do personagem
--       (images/avatars.xml), para os campeões, que não estão no Álbum.

local Gerador = {}

-- id da carta -> o nome do ícone no jogo (o prefab do bicho ou do item).
Gerador.IMAGENS = {
  porco = { tipo = "album", tex = "pigman.tex" },
  porco_guarda = { tipo = "album", tex = "pigguard.tex" },
  sapo = { tipo = "album", tex = "frog.tex" },
  morcego = { tipo = "album", tex = "bat.tex" },
  passaro = { tipo = "album", tex = "robin.tex" },
  borboleta = { tipo = "album", tex = "butterfly.tex" },
  cao_de_caca = { tipo = "album", tex = "hound.tex" },
  wilson = { tipo = "avatar", tex = "avatar_wilson.tex" },
  maquina_de_ciencia = { tipo = "album", tex = "researchlab.tex" },
  machado = { tipo = "album", tex = "axe.tex" },
  lanca = { tipo = "album", tex = "spear.tex" },
  pa = { tipo = "album", tex = "shovel.tex" },
  armadura_de_grama = { tipo = "album", tex = "armorgrass.tex" },
  armadura_de_madeira = { tipo = "album", tex = "armorwood.tex" },
  webber = { tipo = "avatar", tex = "avatar_webber.tex" },
  aranha = { tipo = "album", tex = "spider.tex" },
  aranha_guerreira = { tipo = "album", tex = "spider_warrior.tex" },
  curandeira = { tipo = "album", tex = "spider_healer.tex" },
  dardo = { tipo = "album", tex = "blowdart_pipe.tex" },
  pomada = { tipo = "album", tex = "healingsalve.tex" },
  dardo_do_sono = { tipo = "album", tex = "blowdart_sleep.tex" },
}

-- Os campos de cada entrada, na ordem em que saem no arquivo.
local CAMPOS = { "numero", "nome", "tipo", "custo", "ataque", "vida", "bonus_ataque", "bonus_vida",
  "durabilidade", "campeao", "texto" }

-- A tabela do catálogo, a partir das cartas registradas no motor.
function Gerador.tabela()
  local Cards = require("duelo/core/cards")
  -- Recarrega sempre: o registro de cartas pode ter sido restaurado antes.
  package.loaded["duelo/cartas/init"] = nil
  local ids = require("duelo/cartas/init")
  local out = {}
  for _, id in ipairs(ids) do
    local def = Cards.get(id)
    out[id] = {
      numero = def.numero,
      nome = def.name,
      tipo = def.kind,
      custo = def.cost,
      ataque = def.atk,
      vida = def.hp,
      bonus_ataque = def.atk_bonus,
      bonus_vida = def.hp_bonus,
      durabilidade = def.durability,
      campeao = def.campeao and true or nil,
      texto = def.text,
      imagem = Gerador.IMAGENS[id],
    }
  end
  return out
end

local function literal(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

-- O texto do arquivo scripts/duelo/mod/catalogo.lua, sempre na mesma ordem
-- (pelo número da carta).
function Gerador.texto()
  local tabela = Gerador.tabela()
  local ids = {}
  for id in pairs(tabela) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b)
    local na, nb = tabela[a].numero or 0, tabela[b].numero or 0
    if na ~= nb then return na < nb end
    return a < b
  end)
  local linhas = {
    "-- Catálogo das cartas para os clientes (US #37): só dados, sem o motor.",
    "-- ARQUIVO GERADO por scripts/duelo/mod/catalogo_gerador.lua a partir de",
    "-- scripts/duelo/cartas. Não edite: rode `lua tools/gerar_catalogo.lua`.",
    "",
    "return {",
  }
  for _, id in ipairs(ids) do
    local c = tabela[id]
    linhas[#linhas + 1] = "  " .. id .. " = {"
    for _, campo in ipairs(CAMPOS) do
      if c[campo] ~= nil then linhas[#linhas + 1] = "    " .. campo .. " = " .. literal(c[campo]) .. "," end
    end
    if c.imagem ~= nil then
      linhas[#linhas + 1] = "    imagem = { tipo = " .. literal(c.imagem.tipo) .. ", tex = " .. literal(c.imagem.tex) .. " },"
    end
    linhas[#linhas + 1] = "  },"
  end
  linhas[#linhas + 1] = "}"
  return table.concat(linhas, "\n") .. "\n"
end

return Gerador
