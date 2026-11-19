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
--     seguem coerentes. Livre, repassa o `dt` real. `OnStaticUpdate` e
--     `LongUpdate` do clock continuam apontando para o original (o
--     construtor copia `self.OnUpdate` para eles antes do post init).
--   * O estado "travado" fica numa variável de rede (`net_bool`, netvars.lua)
--     declarada no `forest_network` (prefabs/world_network.lua cria o
--     `clock` e o `seasons` nessa entidade; prefabs/forest_network.lua é a
--     versão da floresta) por `AddPrefabPostInit("forest_network", ...)`.
--     O servidor é o dono (`set`); os clientes só leem (`value`). Como o
--     clock também roda nos clientes, os dois lados precisam do wrapper
--     (modinfo.lua: all_clients_require_mod = true).
--   * No mesmo post init o servidor manda ao mundo a divisão 5/5/6 por
--     `ms_setseasonclocksegs` (components/seasons.lua, OnSetSeasonClockSegs:
--     uma única entrada vale para todas as estações; o `seasons` reenvia a
--     divisão ao clock a cada dia novo por PushSeasonClockSegs, então um
--     `ms_setclocksegs` direto seria desfeito) e trava as quatro estações
--     com `ms_setseasonlength` e `length = 0` (components/seasons.lua,
--     OnSetSeasonLength; é o que worldsettings_overrides.lua faz para as
--     opções autumn/winter/spring/summer = "noseason").
--   * `Relogio.avancar(segmentos)` (só servidor) chama o `OnUpdate` original
--     com `dt = segmentos * TUNING.SEG_TIME` (tuning.lua: SEG_TIME = 30 s).
--     Durante o passo o wrapper repassa qualquer `dt`, porque o próprio
--     clock se chama de novo (`self:OnUpdate(-restante)`) quando o passo
--     atravessa a troca de período. A troca de segmento faz o servidor
--     sincronizar os clientes pelas netvars do clock.
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
local estado = {
  GLOBAL = nil, -- ambiente global do jogo (TheWorld, TUNING, net_bool)
  travado_inicial = true, -- vale até a netvar existir
  netvar = nil, -- net_bool no forest_network
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

-- O relógio está travado neste lado? Antes de a netvar existir, vale o
-- estado inicial da opção do mod.
function Relogio.travado()
  if estado.netvar ~= nil then
    return estado.netvar:value() == true
  end
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
end

-- Post init do forest_network: declara a netvar nos dois lados e, no
-- servidor, define o estado inicial e configura o `seasons`.
local function post_init_rede(inst)
  local G = estado.GLOBAL
  estado.netvar = G.net_bool(inst.GUID, NETVAR, NETVAR_DIRTY)
  if not servidor() then return end

  estado.netvar:set(estado.travado_inicial == true)

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
  estado.em_passo = true
  local ok, err = pcall(estado.original, estado.clock, dt)
  estado.em_passo = false
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
    estado.netvar:set(travado)
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
