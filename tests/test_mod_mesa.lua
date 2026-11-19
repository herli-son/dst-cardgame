-- Testes da US #30: mesa de tiles, números e câmera.
--
-- O jogo não roda aqui. A calibração é Lua puro (scripts/duelo/mod/mesa.lua)
-- e é testada com os números medidos no jogo (issue #30): portal no tile
-- (35, 29) e um ponto do carpete central no tile (29, 28), com o eixo x
-- espelhado pelo gerador (x_tile = 38 - col). O eixo z não foi espelhado
-- (flip_y = 1), mas o deslocamento exato das linhas não foi medido: o portal
-- fica na junção das linhas 9|10, e o tile 29 pode ser a linha 9 ou a 10.
-- Por isso cada caso roda com os dois deslocamentos (lin + 19 e lin + 20),
-- e os dois contêm o tile (29, 28) no carpete.
--
-- Mapa falso: o tile (tx, ty) cobre [4 tx, 4 tx + 4) x [4 ty, 4 ty + 4) no
-- mundo; centro em (4 tx + 2, 4 ty + 2). É só um modelo para os testes; no
-- jogo a conversão vem de TheWorld.Map:GetTileCenterPoint.

local RAIZ = "./"

-- Cópia nova da mesa por caso: a calibração fica em Mesa.calibracao.
local function nova_mesa()
  local fn, err = loadfile(RAIZ .. "scripts/duelo/mod/mesa.lua")
  assert(fn, err)
  return fn()
end

local DESLOCAMENTOS = { 19, 20 }

-- Mundo medido: tile do mapa de cada (col, lin) do layout.
local function tile_do_mapa(col, lin, desl)
  return 38 - col, lin + desl
end

local function centro_mundo(tx, ty)
  return tx * 4 + 2, ty * 4 + 2
end

local function tile_no_ponto(x, z)
  return math.floor(x / 4), math.floor(z / 4)
end

-- Grade do mapa falso: [tx][ty] = uso do layout ("criatura", "carpete"...).
local function mapa_falso(Mesa, desl)
  local grade = {}
  for col = 0, Mesa.LARGURA - 1 do
    for lin = 0, Mesa.ALTURA - 1 do
      local tx, ty = tile_do_mapa(col, lin, desl)
      grade[tx] = grade[tx] or {}
      grade[tx][ty] = Mesa.uso_em(col, lin)
    end
  end
  return grade
end

-- Posição do portal no mundo: centro da coluna 3, junção das linhas 9|10.
local function portal_no_mundo(desl)
  local tx, ty = tile_do_mapa(3, 9, desl)
  local x = centro_mundo(tx, ty)
  local z = ty * 4 + 4 -- borda sul da linha 9 = norte da linha 10
  return x, z
end

-- Coleta os tiles de carpete em volta do portal, como calibracao.lua faz.
local function carpete_em_volta(Mesa, desl)
  local grade = mapa_falso(Mesa, desl)
  local px, pz = portal_no_mundo(desl)
  local ptx, pty = tile_no_ponto(px, pz)
  local lista = {}
  for tx = ptx - 20, ptx + 20 do
    for ty = pty - 20, pty + 20 do
      if grade[tx] and grade[tx][ty] == "centro" then
        lista[#lista + 1] = { x = tx, y = ty }
      end
    end
  end
  return lista, px, pz, ptx, pty
end

local function calibrar_medido(Mesa, desl)
  local lista, px, pz = carpete_em_volta(Mesa, desl)
  local ret = assert(Mesa.achar_carpete(lista))
  return Mesa.calibrar({ carpete = ret, centro_mundo = centro_mundo, portal = { x = px, z = pz } }), ret
end

return {
  { "o modelo reproduz o que foi medido: portal (35, 29), carpete com (29, 28)", function(T)
    local Mesa = nova_mesa()
    for _, desl in ipairs(DESLOCAMENTOS) do
      local _, px, pz, ptx, pty = carpete_em_volta(Mesa, desl)
      T.eq(ptx, 35, "portal x")
      T.ok(pty == 29 or pty == 30, "portal y na junção das linhas 9|10")
      local grade = mapa_falso(Mesa, desl)
      T.eq(grade[29][28], "centro", "tile (29, 28) é carpete")
      local _, r = calibrar_medido(Mesa, desl)
      T.ok(r.x_min <= 29 and 29 <= r.x_max and r.y_min <= 28 and 28 <= r.y_max, "retângulo contém (29, 28)")
      T.ok(r.x_max < 35, "carpete com x menor que o portal")
    end
  end },

  { "calibração com os números medidos dá espelhado = true e o portal na coluna 3", function(T)
    local Mesa = nova_mesa()
    for _, desl in ipairs(DESLOCAMENTOS) do
      local calib = calibrar_medido(Mesa, desl)
      T.eq(calib.espelhado, true, "espelhado")
      T.eq(calib.fonte, "carpete", "fonte")
      T.eq(calib.aviso, nil, "sem aviso: o portal está onde o layout diz")
      local px, pz = portal_no_mundo(desl)
      local col, lin = Mesa.tile_do_layout(px, pz, calib)
      T.eq(col, 3, "portal na coluna 3")
      T.ok(lin == 9 or lin == 10, "portal na junção 9|10")
      -- A origem é a junção das colunas e linhas 9|10 do layout.
      local ox, oz = Mesa.centro_abs(calib)
      T.eq(ox, 4 * 29, "origem x entre os tiles 29 e 28 (colunas 9 e 10)")
      T.eq(oz, pz, "origem z na linha do portal")
      -- O centro de cada tile do layout volta para o mesmo tile do mapa.
      for col2 = 0, Mesa.LARGURA - 1 do
        for lin2 = 0, Mesa.ALTURA - 1 do
          local x, z = Mesa.posicao_abs(col2, lin2, calib)
          local tx, ty = tile_no_ponto(x, z)
          local ex, ey = tile_do_mapa(col2, lin2, desl)
          T.eq(tx, ex, "tile x de " .. col2 .. "," .. lin2)
          T.eq(ty, ey, "tile y de " .. col2 .. "," .. lin2)
          local c3, l3 = Mesa.tile_do_layout(x, z, calib)
          T.eq(c3, col2, "ida e volta col")
          T.eq(l3, lin2, "ida e volta lin")
        end
      end
    end
  end },

  { "sem espelhamento o portal fica a oeste e espelhado = false", function(T)
    local Mesa = nova_mesa()
    local lista = {}
    for col = 6, 13 do
      for lin = 8, 11 do lista[#lista + 1] = { x = 100 + col, y = 50 + lin } end
    end
    local r = assert(Mesa.achar_carpete(lista))
    local px = (100 + 3) * 4 + 2
    local pz = (50 + 10) * 4
    local calib = Mesa.calibrar({ carpete = r, centro_mundo = centro_mundo, portal = { x = px, z = pz } })
    T.eq(calib.espelhado, false, "não espelhado")
    T.eq(calib.aviso, nil, "sem aviso")
    T.eq((Mesa.tile_do_layout(px, pz, calib)), 3, "portal na coluna 3")
  end },

  { "achar_carpete recusa carpete incompleto, girado ou vazio", function(T)
    local Mesa = nova_mesa()
    local r, motivo = Mesa.achar_carpete({})
    T.eq(r, nil, "vazio")
    T.eq(type(motivo), "string", "motivo")
    local girado = {}
    for x = 0, 3 do for y = 0, 7 do girado[#girado + 1] = { x = x, y = y } end end
    r, motivo = Mesa.achar_carpete(girado)
    T.eq(r, nil, "girado")
    T.ok(motivo:find("girado"), "motivo diz girado")
    local buraco = {}
    for x = 0, 7 do for y = 0, 3 do
      if not (x == 2 and y == 1) then buraco[#buraco + 1] = { x = x, y = y } end
    end end
    r = Mesa.achar_carpete(buraco)
    T.eq(r, nil, "com buraco")
    local grande = {}
    for x = 0, 8 do for y = 0, 3 do grande[#grande + 1] = { x = x, y = y } end end
    r = Mesa.achar_carpete(grande)
    T.eq(r, nil, "9 x 4")
  end },

  { "calibrar avisa quando o portal não está onde o layout diz", function(T)
    local Mesa = nova_mesa()
    local lista = carpete_em_volta(Mesa, 20)
    local r = assert(Mesa.achar_carpete(lista))
    local calib = Mesa.calibrar({ carpete = r, centro_mundo = centro_mundo, portal = { x = 0, z = 0 } })
    T.eq(type(calib.aviso), "string", "aviso")
    calib = Mesa.calibrar({ carpete = r, centro_mundo = centro_mundo })
    T.eq(type(calib.aviso), "string", "aviso sem portal")
    T.eq(calib.espelhado, false, "sem portal não dá para saber")
  end },

  { "reserva pelo portal dá a mesma origem que o carpete no caso medido", function(T)
    local Mesa = nova_mesa()
    for _, desl in ipairs(DESLOCAMENTOS) do
      local calib = calibrar_medido(Mesa, desl)
      local px, pz = portal_no_mundo(desl)
      local reserva = Mesa.calibrar_pelo_portal(px, pz)
      T.eq(reserva.fonte, "portal", "fonte")
      T.eq(reserva.espelhado, true, "espelhado por padrão (medido)")
      T.eq(type(reserva.aviso), "string", "avisa")
      T.eq(reserva.origem_x, calib.origem_x, "origem x")
      T.eq(reserva.origem_z, calib.origem_z, "origem z")
    end
  end },

  { "16 espaços absolutos sem sobreposição e sobre os tiles certos da mesa", function(T)
    local Mesa = nova_mesa()
    for _, desl in ipairs(DESLOCAMENTOS) do
      local calib = calibrar_medido(Mesa, desl)
      local grade = mapa_falso(Mesa, desl)
      local vistos, total = {}, 0
      local function conferir(x, z, uso, nome)
        T.ok(x ~= nil, nome .. " existe")
        local tx, ty = tile_no_ponto(x, z)
        local cx, cz = centro_mundo(tx, ty)
        T.eq(x, cx, nome .. " no centro do tile (x)")
        T.eq(z, cz, nome .. " no centro do tile (z)")
        T.eq(grade[tx][ty], uso, nome .. " sobre tile de " .. uso)
        local chave = tx .. "," .. ty
        T.ok(not vistos[chave], nome .. " sobrepõe " .. tostring(vistos[chave]))
        vistos[chave] = nome
        total = total + 1
      end
      for p = 1, 2 do
        for n = 1, 6 do
          local x, z = Mesa.espaco_criatura_abs(p, n, calib)
          conferir(x, z, "criatura", "criatura " .. p .. "/" .. n)
        end
        for n = 1, 2 do
          local x, z = Mesa.espaco_estrutura_abs(p, n, calib)
          conferir(x, z, "estrutura", "estrutura " .. p .. "/" .. n)
        end
        T.eq(Mesa.espaco_criatura_abs(p, 7, calib), nil, "não há espaço 7")
        T.eq(Mesa.espaco_estrutura_abs(p, 3, calib), nil, "não há estrutura 3")
      end
      T.eq(total, 16, "16 espaços")
      local ox, oz = Mesa.centro_abs(calib)
      local tx, ty = tile_no_ponto(ox - 1, oz - 1)
      T.eq(grade[tx][ty], "centro", "centro da mesa sobre o carpete")
      -- Cada jogador só tem espaços do seu lado da mesa.
      for n = 1, 6 do
        local _, _, _, lin1 = Mesa.espaco_criatura_abs(1, n, calib)
        local _, _, _, lin2 = Mesa.espaco_criatura_abs(2, n, calib)
        T.eq(lin1, 13, "jogador 1 na linha 13")
        T.eq(lin2, 6, "jogador 2 na linha 6")
      end
    end
  end },

  { "heading: o lado de cada jogador fica embaixo da tela dele", function(T)
    local Mesa = nova_mesa()
    for _, desl in ipairs(DESLOCAMENTOS) do
      local calib = calibrar_medido(Mesa, desl)
      T.eq(Mesa.heading(1, calib), 90, "jogador 1 (sul, z maior)")
      T.eq(Mesa.heading(2, calib), 270, "jogador 2 = jogador 1 + 180")
      T.eq(Mesa.heading(3, calib), 90, "espectador olha como o 1")
      T.eq(Mesa.heading(0, calib), 90, "lado desconhecido olha como o 1")
      -- GetDownVec = (cos h, sin h) aponta do centro para os espaços do jogador.
      local ox, oz = Mesa.centro_abs(calib)
      for p = 1, 2 do
        local h = math.rad(Mesa.heading(p, calib))
        local dx, dz = math.cos(h), math.sin(h)
        for n = 1, 6 do
          local x, z = Mesa.espaco_criatura_abs(p, n, calib)
          T.ok((x - ox) * dx + (z - oz) * dz > 0, "espaço " .. p .. "/" .. n .. " na metade de baixo")
          local x2, z2 = Mesa.espaco_criatura_abs(3 - p, n, calib)
          T.ok((x2 - ox) * dx + (z2 - oz) * dz < 0, "espaço do outro na metade de cima")
        end
      end
    end
  end },

  { "cada jogador conta os espaços da esquerda para a direita da câmera dele", function(T)
    local Mesa = nova_mesa()
    local function confere(calib, rotulo)
      for p = 1, 2 do
        local rx, rz = Mesa.direita(Mesa.heading(p, calib))
        local antes = -math.huge
        for n = 1, 6 do
          local x, z = Mesa.espaco_criatura_abs(p, n, calib)
          local d = x * rx + z * rz
          T.ok(d > antes, rotulo .. ": criatura " .. p .. "/" .. n .. " à direita da anterior")
          antes = d
        end
        local x1, z1 = Mesa.espaco_estrutura_abs(p, 1, calib)
        local x2, z2 = Mesa.espaco_estrutura_abs(p, 2, calib)
        T.ok(x1 * rx + z1 * rz < x2 * rx + z2 * rz, rotulo .. ": estrutura 1 à esquerda da 2")
      end
      -- O espaço n de um fica de frente para o 7 - n do outro.
      for n = 1, 6 do
        local x1 = Mesa.espaco_criatura_abs(1, n, calib)
        local x2 = Mesa.espaco_criatura_abs(2, 7 - n, calib)
        T.eq(x1, x2, rotulo .. ": " .. n .. " de frente para " .. (7 - n))
      end
    end
    for _, desl in ipairs(DESLOCAMENTOS) do
      local calib = calibrar_medido(Mesa, desl)
      confere(calib, "medido")
      -- No caso medido (espelhado) a ordem da câmera é a das listas do layout.
      for p = 1, 2 do
        for n = 1, 6 do
          local _, _, col = Mesa.espaco_criatura_abs(p, n, calib)
          T.eq(col, Mesa.espaco_criatura(p, n).col, "espelhado: coluna do layout " .. p .. "/" .. n)
        end
      end
      -- Sem espelhamento a câmera inverte as colunas, mas a numeração de
      -- quem olha continua da esquerda para a direita.
      local reto = { origem_x = calib.origem_x, origem_z = calib.origem_z, espelhado = false }
      confere(reto, "sem espelhamento")
      local _, _, col = Mesa.espaco_criatura_abs(1, 1, reto)
      T.eq(col, 12, "sem espelhamento o espaço 1 do jogador 1 é a coluna 12")
    end
  end },

  { "a calibração padrão fica em Mesa.calibracao", function(T)
    local Mesa = nova_mesa()
    T.eq(Mesa.calibracao, nil, "nasce sem calibração")
    T.eq(Mesa.espaco_criatura_abs(1, 1), nil, "sem calibração não há posição")
    local calib = calibrar_medido(Mesa, 20)
    Mesa.definir_calibracao(calib)
    T.eq(Mesa.calibracao, calib, "guardada")
    local x, z = Mesa.espaco_criatura_abs(1, 1)
    local x2, z2 = Mesa.espaco_criatura_abs(1, 1, calib)
    T.eq(x, x2, "x igual à explícita")
    T.eq(z, z2, "z igual à explícita")
  end },
}
