-- Relógio do mundo controlado pela partida (US #31).
--
-- O relógio do DST (components/clock.lua) anda sozinho a cada atualização,
-- no servidor e em cada cliente. No duelo o tempo só passa quando a partida
-- avança (meio período por vez jogada, docs/investigacao-scripts-dst.md,
-- "Interceptação do relógio"). Este módulo é a abordagem (b) da investigação:
--
--   * `AddComponentPostInit("clock", ...)` (modutil.lua; entityscript.lua
--     chama os post inits logo depois do construtor do componente) troca o
--     `OnUpdate` do relógio por um wrapper. Com o relógio travado, o wrapper
--     chama o original com `dt = 0`: nada anda, mas `clocktick` e os eventos
--     de mudança continuam saindo, então worldstate, luz e o relógio da tela
--     seguem coerentes. Livre, repassa o `dt` real. `LongUpdate` (usado por
--     `c_skip` e pelos eventos `ms_setphase`/`ms_nextphase`, estes com 0)
--     passa pelo mesmo wrapper: travado, `c_skip` não anda o tempo; use
--     `DUELO.Relogio.avancar`. `OnStaticUpdate` continua no original: o jogo
--     só o chama com `dt = 0` (update.lua, jogo pausado).
--   * O estado "travado" fica numa variável de rede (`net_tinybyte`,
--     netvars.lua: 0 = ainda não chegou do servidor, 1 = travado, 2 = livre)
--     declarada no `forest_network` (prefabs/world_network.lua cria o
--     `clock` e o `seasons` nessa entidade; prefabs/forest_network.lua é a
--     versão da floresta) por `AddPrefabPostInit("forest_network", ...)`.
--     O servidor é o dono (`set`); os clientes só leem (`value`). Enquanto
--     o cliente lê 0 (o valor do servidor ainda não chegou), vale o estado
--     inicial da opção do mod, para o relógio do cliente não andar sozinho
--     nos primeiros frames. Como o clock também roda nos clientes, os dois
--     lados precisam do wrapper (modinfo.lua: all_clients_require_mod = true).
--   * No mesmo post init o servidor manda ao mundo a divisão 5/5/6 por
--     `ms_setseasonclocksegs` (components/seasons.lua, OnSetSeasonClockSegs:
--     uma única entrada vale para todas as estações; o `seasons` guarda a
--     divisão em `_segs`, salva e reenvia ao clock a cada dia novo por
--     PushSeasonClockSegs, então um `ms_setclocksegs` direto seria desfeito)
--     e trava as quatro estações com `ms_setseasonlength` e `length = 0`
--     (components/seasons.lua, OnSetSeasonLength; é o que
--     worldsettings_overrides.lua faz para "noseason"). Não é redundante: o
--     nível deixa o outono em "verylongseason", porque a tela de criação do
--     mundo exige uma estação com duração; aqui o outono também trava.
--   * `Relogio.avancar(segmentos)` (só servidor) chama o `OnUpdate` original
--     com `dt = segmentos * TUNING.SEG_TIME` (tuning.lua: SEG_TIME = 30 s).
--     Durante o passo o wrapper repassa qualquer `dt`, porque o próprio
--     clock se chama de novo (`self:OnUpdate(-restante)`) quando o passo
--     atravessa a troca de período. O clock só sincroniza os clientes na
--     troca de segmento (dentro de um segmento usa `set_local`), então um
--     passo que não atravessa um segmento só aparece no cliente no próximo
--     passo que atravessar; os passos da partida (2,5 ou 3 segmentos)
--     sempre atravessam.
--
-- Enquanto não existe partida (a US #37 liga o motor), o relógio nasce no
-- estado da opção "relogio" do mod (modinfo.lua), e os comandos de console
-- `DUELO.Relogio.avancar(n)`, `DUELO.Relogio.travar()` e
-- `DUELO.Relogio.liberar()` servem para o teste manual (docs/mod.md).
--
-- Este arquivo é Lua puro: tudo do jogo chega por `ctx` em `instalar`, para
-- os testes (tests/test_mod_protecao.lua) rodarem com um ambiente falso.

local Relogio = {}

-- Divisão do dia do duelo: 16 segmentos (NUM_SEGS em components/clock.lua),
-- o mais perto de três partes iguais.
Relogio.SEGMENTOS = { day = 5, dusk = 5, night = 6 }
Relogio.ESTACOES = { "autumn", "winter", "spring", "summer" }

local NETVAR = "duelo.relogio_travado"
local NETVAR_DIRTY = "duelo.relogio_travadodirty"

-- Estado deste lado (servidor ou cliente). Um mundo por processo.
local DESCONHECIDO, TRAVADO, LIVRE = 0, 1, 2

local estado = {
  GLOBAL = nil, -- ambiente global do jogo (TheWorld, TUNING, net_tinybyte)
  travado_inicial = true, -- vale até a netvar existir
  netvar = nil, -- net_tinybyte no forest_network
  clock = nil, -- componente clock deste lado
  original = nil, -- OnUpdate original do clock
  em_passo = false, -- true enquanto `avancar` roda
}

local function mundo()
  return estado.GLOBAL and estado.GLOBAL.TheWorld or nil
end

local function servidor()
  local w = mundo()
  return w ~= nil and w.ismastersim == true
end

local function avisar(msg)
  local p = estado.GLOBAL and estado.GLOBAL.print or print
  p("[duelo] " .. msg)
end

-- O relógio está travado neste lado? Antes de a netvar existir ou de o valor
-- do servidor chegar, vale o estado inicial da opção do mod.
function Relogio.travado()
  local v = estado.netvar ~= nil and estado.netvar:value() or DESCONHECIDO
  if v == TRAVADO then return true end
  if v == LIVRE then return false end
  return estado.travado_inicial == true
end

-- Wrapper do OnUpdate do clock (os dois lados).
local function on_update(clock, dt)
  if estado.em_passo or not Relogio.travado() then
    return estado.original(clock, dt)
  end
  return estado.original(clock, 0)
end

local function post_init_clock(clock)
  estado.clock = clock
  estado.original = clock.OnUpdate
  clock.OnUpdate = on_update
  clock.LongUpdate = on_update
end

-- Post init do forest_network: declara a netvar nos dois lados e, no
-- servidor, define o estado inicial e configura o `seasons`.
local function post_init_rede(inst)
  local G = estado.GLOBAL
  estado.netvar = G.net_tinybyte(inst.GUID, NETVAR, NETVAR_DIRTY)
  if not servidor() then return end

  estado.netvar:set(estado.travado_inicial == true and TRAVADO or LIVRE)

  local w = mundo()
  -- Uma única entrada: OnSetSeasonClockSegs usa a primeira como padrão
  -- para todas as estações.
  w:PushEvent("ms_setseasonclocksegs", { autumn = Relogio.SEGMENTOS })
  for _, estacao in ipairs(Relogio.ESTACOES) do
    w:PushEvent("ms_setseasonlength", { season = estacao, length = 0 })
  end
end

-- Liga o módulo no ambiente do mod.
--   ctx.GLOBAL: ambiente global do jogo;
--   ctx.AddComponentPostInit, ctx.AddPrefabPostInit: de modutil.lua;
--   ctx.travado: estado inicial (opção "relogio" do modinfo.lua).
function Relogio.instalar(ctx)
  estado.GLOBAL = ctx.GLOBAL
  estado.travado_inicial = ctx.travado ~= false
  estado.netvar, estado.clock, estado.original, estado.em_passo = nil, nil, nil, false
  ctx.AddComponentPostInit("clock", post_init_clock)
  ctx.AddPrefabPostInit("forest_network", post_init_rede)
  return Relogio
end

-- Servidor: anda `segmentos` segmentos (pode ser fração) de uma vez.
function Relogio.avancar(segmentos)
  if not servidor() then
    avisar("Relogio.avancar só funciona no servidor")
    return false
  end
  if estado.clock == nil or estado.original == nil then
    avisar("o relógio ainda não foi interceptado")
    return false
  end
  segmentos = tonumber(segmentos) or 1
  local dt = segmentos * estado.GLOBAL.TUNING.SEG_TIME
  -- Guarda o valor anterior: um avancar chamado de dentro de um evento do
  -- clock, no meio de outro, não pode encerrar o passo de fora.
  local antes = estado.em_passo
  estado.em_passo = true
  local ok, err = pcall(estado.original, estado.clock, dt)
  estado.em_passo = antes
  if not ok then error(err, 0) end
  return true
end

local function definir(travado)
  if not servidor() then
    avisar("só o servidor trava ou libera o relógio")
    return false
  end
  estado.travado_inicial = travado
  if estado.netvar ~= nil then
    estado.netvar:set(travado and TRAVADO or LIVRE)
  end
  return true
end

-- Servidor: para o relógio (os clientes leem pela netvar).
function Relogio.travar()
  return definir(true)
end

-- Servidor: deixa o relógio correr como no jogo normal.
function Relogio.liberar()
  return definir(false)
end

return Relogio
