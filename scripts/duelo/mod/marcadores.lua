-- Números e zonas da mesa (US #30; posições e rótulos do layout do bug
-- #147).
--
-- Cada espaço com dono tem um marcador com o que ele é, na cor do jogador:
-- os espaços de criatura ("J1 3"), as estruturas ("J2 E1"), os decks
-- ("J1 Deck", "J1 Extra"), o descarte ("Descarte") e as destruídas
-- ("Destruídas"). Onde cada rótulo fica:
--   * espaço de criatura e estrutura (2 tiles): no tile da carta (o de
--     trás), que é onde ficam as informações da carta; o tile da frente é
--     da criatura viva ou da estrutura em pé.
--   * decks, descarte, destruídas e eventos (blocos de 2 tiles): na junção
--     dos 2 tiles.
--   * "Descarte" e "Destruídas" não levam "J1"/"J2": ficam na coluna dos
--     eventos, a 2 tiles do deck da ponta, e o texto mais curto não encosta
--     no rótulo dele; o dono vem da cor do texto, do contorno e do lado da
--     mesa.
--   * combate: com 6 pares, um rótulo por par ficaria embaixo das criaturas
--     que duelam ali, então os quadrados não têm rótulo (o dono de cada um
--     vem do contorno) e há um "Combate" só, em cor neutra, na coluna de
--     paralelepípedos da borda da mesa ao lado da primeira coluna de
--     espaços, entre as duas fileiras (Mesa.ROTULO_COMBATE).
--   * "Eventos", em cor neutra, entre a pilha e o evento em vigor.
-- O contorno de cada tile, na cor do dono, é desenhado por
-- duelo/mod/contornos.lua. São 26 marcadores: 12 criaturas, 4 estruturas,
-- 4 decks, 2 descartes, 2 destruídas, "Combate" e "Eventos".
-- O marcador é o prefab do mod `duelo_marcador`
-- (scripts/prefabs/duelo_marcador.lua, registrado por PrefabFiles no
-- modmain): uma entidade de rede sem física, sem arte e sem clique, só com
-- um Label.
--
-- Por que um prefab de rede com netvars: o texto do Label é local (o motor
-- não o replica), então o servidor manda o que cada marcador é por três
-- `net_tinybyte` (netvars.lua: 3 bits, 0..7) — tipo (1 criatura,
-- 2 estrutura, 3 combate, 4 deck, 5 eventos, 6 descarte, 7 destruídas: os 7
-- tipos cabem, mas o tinybyte fica cheio; um oitavo tipo pede
-- `net_smallbyte`, 0..63, nos dois lados), jogador (0 = nenhum, a cor
-- neutra; 1; 2) e número (0..6; nos decks, 1 = principal e 2 = extra) — e
-- cada lado monta o texto quando o evento "dirty" chega (netvars.lua: o
-- "dirty" dispara no
-- servidor e nos clientes; no host o próprio servidor desenha). Num cliente
-- o rótulo também é montado uma vez numa tarefa de 0 s, para o caso de os
-- valores chegarem junto com a entidade. A posição vem do Transform, que já
-- é replicado. Assim, quando a partida (US #33, #37) precisar mudar um
-- marcador (destacar, esconder), basta o servidor mudar as netvars.
-- A alternativa de cada cliente criar entidades locais a partir da
-- calibração evitaria o prefab, mas deixaria o servidor sem como mexer neles.
--
-- Chamadas do jogo e onde se confirmam:
--   * `inst.entity:AddLabel()` e `Label:SetFont`, `SetFontSize`,
--     `SetWorldOffset`, `SetUIOffset`, `SetColour`, `SetText`, `Enable`:
--     prefabs/dummytarget.lua, prefabs/sounddebugicon.lua,
--     components/healthbar.lua. O Label é desenhado na tela (tamanho em
--     pixels, sempre de pé), então fica legível com qualquer heading.
--   * Fonte `TALKINGFONT` (fonts.lua; tem contorno, lê-se sobre qualquer
--     chão), com `DEFAULTFONT` de reserva.
--   * `SpawnPrefab`, `Transform:SetPosition`, `inst:Remove()`,
--     `inst:IsValid()`: entityscript.lua / mainfunctions.lua.
--   * `inst.persists = false` (mainfunctions.lua, SaveGame: só entra no save
--     quem tem `persists`; entityscript.lua o liga por padrão): o
--     marcador não é salvo; o servidor o recria a cada carga na calibração,
--     então não há duplicata ao recarregar.
--
-- Este arquivo é Lua puro: tudo do jogo chega por `ctx` em `instalar` (e
-- pelo `G` que o prefab passa a `preparar`), para os testes
-- (tests/test_mod_mesa.lua) rodarem com um ambiente falso.

local Marcadores = {}

Marcadores.PREFAB = "duelo_marcador"
-- Tipos de marcador (netvar de 3 bits: 0 = ainda não definido, 1..7).
Marcadores.TIPO = { criatura = 1, estrutura = 2, combate = 3, deck = 4, evento = 5, descarte = 6, destruidas = 7 }
-- Rótulo das zonas sem dono, das zonas de cada jogador que não têm número e
-- de cada deck (pelo número do marcador).
Marcadores.TEXTO_ZONA = { [3] = "Combate", [5] = "Eventos" }
Marcadores.TEXTO_DO_JOGADOR = { [6] = "Descarte", [7] = "Destruídas" }
Marcadores.DECK = { principal = 1, extra = 2 }
Marcadores.TEXTO_DECK = { [1] = "Deck", [2] = "Extra" }

-- Cores dos rótulos (r, g, b em 0..1): azul para o jogador 1, vermelho para
-- o 2 e amarelo claro para o que não tem dono (jogador 0).
Marcadores.CORES = {
  [1] = { 0.45, 0.75, 1 },
  [2] = { 1, 0.5, 0.45 },
  neutro = { 1, 0.9, 0.6 },
}

Marcadores.TAMANHO = { espaco = 28, zona = 36 }

local DIRTY = "duelo_marcador.dirty"

local estado = {
  GLOBAL = nil,
  Mesa = nil,
  marcadores = {}, -- servidor: os marcadores criados
}

local function servidor()
  local w = estado.GLOBAL and estado.GLOBAL.TheWorld or nil
  return w ~= nil and w.ismastersim == true
end

-- Texto do marcador, ou nil se o marcador ainda não foi definido.
function Marcadores.texto(tipo, jogador, numero)
  if Marcadores.TEXTO_ZONA[tipo] ~= nil then return Marcadores.TEXTO_ZONA[tipo] end
  if jogador ~= 1 and jogador ~= 2 then return nil end
  if Marcadores.TEXTO_DO_JOGADOR[tipo] ~= nil then return Marcadores.TEXTO_DO_JOGADOR[tipo] end
  if numero == nil or numero < 1 then return nil end
  if tipo == Marcadores.TIPO.criatura then
    return "J" .. jogador .. " " .. numero
  elseif tipo == Marcadores.TIPO.estrutura then
    return "J" .. jogador .. " E" .. numero
  elseif tipo == Marcadores.TIPO.deck and Marcadores.TEXTO_DECK[numero] ~= nil then
    return "J" .. jogador .. " " .. Marcadores.TEXTO_DECK[numero]
  end
  return nil
end

-- Cor do rótulo: a do dono; neutra nas zonas sem dono e sem jogador (0).
function Marcadores.cor(tipo, jogador)
  local c = Marcadores.TEXTO_ZONA[tipo] == nil and Marcadores.CORES[jogador] or Marcadores.CORES.neutro
  return c[1], c[2], c[3]
end

-- Lê as netvars e atualiza o Label (servidor com tela e clientes).
function Marcadores.atualizar_rotulo(inst)
  local tipo = inst.duelo_tipo:value()
  local jogador = inst.duelo_jogador:value()
  local numero = inst.duelo_numero:value()
  local texto = Marcadores.texto(tipo, jogador, numero)
  local label = inst.Label
  if texto == nil then
    label:Enable(false)
    return nil
  end
  label:SetText(texto)
  label:SetColour(Marcadores.cor(tipo, jogador))
  label:SetFontSize(Marcadores.TEXTO_ZONA[tipo] ~= nil and Marcadores.TAMANHO.zona or Marcadores.TAMANHO.espaco)
  label:Enable(true)
  return texto
end

-- Chamado pelo prefab nos dois lados, antes de SetPristine: declara as
-- netvars (iguais no servidor e nos clientes, netvars.lua), arruma o Label e,
-- fora do servidor dedicado, escuta o "dirty".
--   G: ambiente global do jogo (o prefab passa _G).
function Marcadores.preparar(inst, G)
  inst.duelo_tipo = G.net_tinybyte(inst.GUID, "duelo_marcador.tipo", DIRTY)
  inst.duelo_jogador = G.net_tinybyte(inst.GUID, "duelo_marcador.jogador", DIRTY)
  inst.duelo_numero = G.net_tinybyte(inst.GUID, "duelo_marcador.numero", DIRTY)

  local label = inst.Label
  label:SetFont(G.TALKINGFONT or G.DEFAULTFONT)
  label:SetFontSize(Marcadores.TAMANHO.espaco)
  label:SetWorldOffset(0, 0.5, 0)
  label:SetUIOffset(0, 0, 0)
  label:SetColour(1, 1, 1)
  label:SetText("")
  label:Enable(false)

  if not G.TheNet:IsDedicated() then
    inst:ListenForEvent(DIRTY, Marcadores.atualizar_rotulo)
    if not G.TheWorld.ismastersim then
      inst:DoTaskInTime(0, Marcadores.atualizar_rotulo)
    end
  end
end

-- Servidor: diz o que o marcador é (as netvars levam aos clientes).
function Marcadores.definir(inst, tipo, jogador, numero)
  inst.duelo_tipo:set(tipo)
  inst.duelo_jogador:set(jogador or 0)
  inst.duelo_numero:set(numero or 0)
end

local function criar_um(x, z, tipo, jogador, numero)
  local inst = estado.GLOBAL.SpawnPrefab(Marcadores.PREFAB)
  if inst == nil then return nil end
  inst.Transform:SetPosition(x, 0, z)
  Marcadores.definir(inst, tipo, jogador, numero)
  estado.marcadores[#estado.marcadores + 1] = inst
  return inst
end

-- Servidor: remove os marcadores antigos e cria os 26 nas posições da
-- calibração (ver o cabeçalho): 12 criaturas e 4 estruturas, no tile da
-- carta; 4 decks, 2 descartes, 2 destruídas e "Eventos", na junção dos 2
-- tiles; "Combate" na borda, entre as duas fileiras. Devolve a lista.
function Marcadores.criar(calib)
  if not servidor() then return nil end
  local Mesa = estado.Mesa
  Marcadores.remover()
  local T = Marcadores.TIPO
  for p = 1, 2 do
    for n = 1, 6 do
      local carta = Mesa.espaco_criatura_abs(p, n, calib).carta
      criar_um(carta.x, carta.z, T.criatura, p, n)
    end
    for n = 1, 2 do
      local carta = Mesa.espaco_estrutura_abs(p, n, calib).carta
      criar_um(carta.x, carta.z, T.estrutura, p, n)
    end
    for _, qual in ipairs(Mesa.DECKS) do
      local centro = Mesa.espaco_deck_abs(p, qual, calib).centro
      criar_um(centro.x, centro.z, T.deck, p, Marcadores.DECK[qual])
    end
    local descarte = Mesa.espaco_descarte_abs(p, calib).centro
    criar_um(descarte.x, descarte.z, T.descarte, p, 0)
    local destruidas = Mesa.espaco_destruidas_abs(p, calib).centro
    criar_um(destruidas.x, destruidas.z, T.destruidas, p, 0)
  end
  local cx, cz = Mesa.rotulo_combate_abs(calib)
  criar_um(cx, cz, T.combate, 0, 0)
  local evento = Mesa.espaco_evento_abs(calib).centro
  criar_um(evento.x, evento.z, T.evento, 0, 0)
  return estado.marcadores
end

-- Servidor: remove os marcadores criados.
function Marcadores.remover()
  for _, inst in ipairs(estado.marcadores) do
    if inst:IsValid() then inst:Remove() end
  end
  estado.marcadores = {}
end

function Marcadores.lista()
  return estado.marcadores
end

-- Liga o módulo no ambiente do mod.
--   ctx.GLOBAL: ambiente global do jogo;
--   ctx.Mesa: duelo/mod/mesa;
--   ctx.Calibracao: duelo/mod/calibracao (já instalado).
-- No servidor, cria os marcadores a cada calibração.
function Marcadores.instalar(ctx)
  estado.GLOBAL = ctx.GLOBAL
  estado.Mesa = ctx.Mesa
  estado.marcadores = {}
  ctx.Calibracao.quando_calibrar(function(calib)
    if servidor() then Marcadores.criar(calib) end
  end)
  return Marcadores
end

return Marcadores
