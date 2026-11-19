-- Testes da US #31: nada do mundo interfere no duelo.
--
-- O jogo não roda aqui. O que dá para conferir é que os módulos
-- scripts/duelo/mod/relogio.lua e scripts/duelo/mod/protecao.lua compilam e,
-- com um ambiente falso (stubs de AddPlayerPostInit, AddComponentPostInit,
-- AddPrefabPostInit, TheWorld, TheNet, net_tinybyte, TUNING e um clock cujo
-- OnUpdate acumula o dt), fazem as chamadas certas em cada lado. O resto
-- (Charlie, luz, relógio da tela) só se confirma no jogo (docs/mod.md).
--
-- Os arquivos são lidos relativos à raiz do repositório, de onde o runner
-- roda (package.path começa com "scripts/?.lua").

local RAIZ = "./"
local SEG_TIME = 30

local function rodar(arquivo, env)
  local fn, err = loadfile(RAIZ .. arquivo)
  assert(fn, err)
  setfenv(fn, env)
  return fn()
end

-- Os módulos guardam estado em locais do arquivo; cada caso carrega uma
-- cópia nova para não vazar estado de um caso para outro.
local function carregar(nome)
  local fn, err = loadfile(RAIZ .. "scripts/duelo/mod/" .. nome .. ".lua")
  assert(fn, err)
  return fn()
end

-- net_tinybyte falso: registra set/value e os argumentos da declaração. Nasce
-- em 0, como no jogo antes de o valor do servidor chegar.
local function net_tinybyte_falso(registro)
  return function(guid, nome, dirty)
    local nv = { guid = guid, nome = nome, dirty = dirty, valor = 0, sets = 0 }
    function nv:set(v) self.valor = v; self.sets = self.sets + 1 end
    function nv:value() return self.valor end
    registro[#registro + 1] = nv
    return nv
  end
end

-- Ambiente falso do mod para um lado (servidor ou cliente).
local function ambiente(servidor)
  local reg = {
    component_postinits = {}, -- nome -> fn
    prefab_postinits = {}, -- nome -> fn
    player_postinits = {}, -- lista de fn
    netvars = {},
    eventos = {}, -- eventos empurrados em TheWorld
  }
  local GLOBAL = {
    TheWorld = {
      ismastersim = servidor,
      ismastershard = servidor,
      PushEvent = function(self, nome, dados) reg.eventos[#reg.eventos + 1] = { nome = nome, dados = dados } end,
    },
    TheNet = { GetIsServer = function() return servidor end },
    TUNING = { SEG_TIME = SEG_TIME, STARTING_TEMP = 35 },
    net_tinybyte = net_tinybyte_falso(reg.netvars),
    print = function() end,
    require = require,
  }
  local ctx = {
    GLOBAL = GLOBAL,
    AddComponentPostInit = function(nome, fn) reg.component_postinits[nome] = fn end,
    AddPrefabPostInit = function(nome, fn) reg.prefab_postinits[nome] = fn end,
    AddPlayerPostInit = function(fn) reg.player_postinits[#reg.player_postinits + 1] = fn end,
  }
  return ctx, reg, GLOBAL
end

-- Clock falso: o OnUpdate original acumula o dt e conta as chamadas.
local function clock_falso()
  local clock = { acumulado = 0, chamadas = 0 }
  function clock:OnUpdate(dt)
    self.acumulado = self.acumulado + dt
    self.chamadas = self.chamadas + 1
  end
  clock.OnStaticUpdate = clock.OnUpdate
  clock.LongUpdate = clock.OnUpdate
  return clock
end

-- Instala o relógio num lado e simula o jogo: cria o clock (post init do
-- componente) e o forest_network (post init do prefab).
local function relogio_instalado(servidor, travado)
  local ctx, reg = ambiente(servidor)
  local Relogio = carregar("relogio")
  Relogio.instalar({
    GLOBAL = ctx.GLOBAL,
    AddComponentPostInit = ctx.AddComponentPostInit,
    AddPrefabPostInit = ctx.AddPrefabPostInit,
    travado = travado,
  })
  local clock = clock_falso()
  local original = clock.OnUpdate
  reg.component_postinits.clock(clock, { GUID = 1 })
  -- forest_network falso: as tarefas com atraso só rodam quando o teste
  -- simula o primeiro passo depois da carga (rodar_tarefas).
  local rede = { GUID = 7, tarefas = {} }
  function rede:DoTaskInTime(t, fn) self.tarefas[#self.tarefas + 1] = fn end
  reg.rede = rede
  reg.prefab_postinits.forest_network(rede)
  for _, fn in ipairs(rede.tarefas) do fn(rede) end
  if not servidor then
    -- No jogo o cliente recebe o valor do servidor junto com a entidade;
    -- aqui o "sync" é feito à mão (1 = travado, 2 = livre).
    reg.netvars[1].valor = travado and 1 or 2
  end
  return Relogio, clock, original, reg
end

-- Jogador falso com os componentes do servidor ou só os do cliente.
local function jogador_falso(servidor)
  local j = { chamadas = {}, eventos = {}, tarefas = {}, valido = true }
  local function anotar(nome)
    return function(_, ...) j.chamadas[#j.chamadas + 1] = { nome, ... } end
  end
  j.components = {
    playervision = {
      ForceNightVision = anotar("ForceNightVision"),
      ForceNoNightVisionCC = anotar("ForceNoNightVisionCC"),
    },
  }
  if servidor then
    local invencivel = false
    j.components.health = {
      SetInvincible = function(_, v) invencivel = v; j.chamadas[#j.chamadas + 1] = { "SetInvincible", v } end,
      IsInvincible = function() return invencivel end,
    }
    j.components.hunger = { Pause = anotar("Pause") }
    j.components.sanity = { ignore = false }
    j.components.temperature = { SetTemp = anotar("SetTemp") }
  end
  function j:ListenForEvent(nome, fn) self.eventos[nome] = fn end
  function j:DoTaskInTime(t, fn) self.tarefas[#self.tarefas + 1] = fn end
  function j:IsValid() return self.valido end
  function j:HasTag(tag) return tag == "player" end
  return j
end

local function contar(chamadas, nome)
  local n, ultima = 0, nil
  for _, c in ipairs(chamadas) do
    if c[1] == nome then n = n + 1; ultima = c end
  end
  return n, ultima
end

local function evento(reg, nome)
  local achados = {}
  for _, e in ipairs(reg.eventos) do
    if e.nome == nome then achados[#achados + 1] = e.dados end
  end
  return achados
end

return {
  { "relogio.lua e protecao.lua compilam e devolvem módulos", function(T)
    local Relogio = carregar("relogio")
    T.eq(type(Relogio.instalar), "function", "Relogio.instalar")
    T.eq(type(Relogio.avancar), "function", "Relogio.avancar")
    T.eq(type(Relogio.travar), "function", "Relogio.travar")
    T.eq(type(Relogio.liberar), "function", "Relogio.liberar")
    T.eq(Relogio.SEGMENTOS.day + Relogio.SEGMENTOS.dusk + Relogio.SEGMENTOS.night, 16, "16 segmentos")
    T.eq(Relogio.SEGMENTOS.day, 5, "dia 5")
    T.eq(Relogio.SEGMENTOS.dusk, 5, "entardecer 5")
    T.eq(Relogio.SEGMENTOS.night, 6, "noite 6")
    local Protecao = carregar("protecao")
    T.eq(type(Protecao.instalar), "function", "Protecao.instalar")
    T.eq(type(Protecao.aplicar), "function", "Protecao.aplicar")
  end },

  { "modinfo.lua tem a opção relogio com travado/livre e padrão travado", function(T)
    local env = {}
    rodar("modinfo.lua", env)
    local opcao
    for _, o in ipairs(env.configuration_options) do
      if o.name == "relogio" then opcao = o end
    end
    T.ok(opcao, "opção relogio")
    T.eq(opcao.default, "travado", "padrão travado")
    T.eq(type(opcao.label), "string", "label")
    local dados = {}
    for _, o in ipairs(opcao.options) do dados[o.data] = true end
    T.ok(dados.travado and dados.livre, "valores travado e livre")
    T.eq(#opcao.options, 2, "só duas opções")
  end },

  { "modmain.lua instala os três ganchos e expõe DUELO no ambiente global", function(T)
    local ctx, reg, GLOBAL = ambiente(true)
    local configs = {}
    local env = {
      GLOBAL = GLOBAL,
      GetModConfigData = function(nome) configs[#configs + 1] = nome; return "travado" end,
      AddPlayerPostInit = ctx.AddPlayerPostInit,
      AddComponentPostInit = ctx.AddComponentPostInit,
      AddPrefabPostInit = ctx.AddPrefabPostInit,
    }
    rodar("modmain.lua", env)
    T.eq(configs[1], "relogio", "lê a opção relogio")
    T.eq(type(reg.component_postinits.clock), "function", "AddComponentPostInit(clock)")
    T.eq(type(reg.prefab_postinits.forest_network), "function", "AddPrefabPostInit(forest_network)")
    T.eq(#reg.player_postinits, 1, "um AddPlayerPostInit")
    T.eq(type(env.DUELO.Relogio.avancar), "function", "DUELO.Relogio no ambiente do mod")
    T.eq(GLOBAL.DUELO, env.DUELO, "DUELO também no ambiente global (console)")
    T.eq(env.DUELO.Mesa, require("duelo/mod/mesa"), "DUELO.Mesa continua")
  end },

  { "wrapper chama o OnUpdate original com dt 0 quando travado", function(T)
    for _, servidor in ipairs({ true, false }) do
      local Relogio, clock, original = relogio_instalado(servidor, true)
      T.ok(clock.OnUpdate ~= original, "OnUpdate trocado")
      T.eq(clock.OnStaticUpdate, original, "OnStaticUpdate continua o original")
      T.eq(clock.LongUpdate, clock.OnUpdate, "LongUpdate (c_skip) passa pelo wrapper")
      clock:LongUpdate(30)
      T.eq(clock.acumulado, 0, "c_skip não anda com o relógio travado")
      clock.chamadas = 0
      T.eq(Relogio.travado(), true, "nasce travado")
      clock:OnUpdate(0.5)
      clock:OnUpdate(1)
      T.eq(clock.chamadas, 2, "o original continua sendo chamado (eventos saem)")
      T.eq(clock.acumulado, 0, "mas com dt 0")
    end
  end },

  { "wrapper repassa o dt real quando livre", function(T)
    for _, servidor in ipairs({ true, false }) do
      local Relogio, clock = relogio_instalado(servidor, false)
      T.eq(Relogio.travado(), false, "nasce livre")
      clock:OnUpdate(0.5)
      clock:OnUpdate(1)
      T.eq(clock.chamadas, 2, "duas chamadas")
      T.eq(clock.acumulado, 1.5, "dt real acumulado")
    end
  end },

  { "antes da netvar existir vale o estado inicial da opção", function(T)
    local ctx, reg = ambiente(false)
    local Relogio = carregar("relogio")
    Relogio.instalar({ GLOBAL = ctx.GLOBAL, AddComponentPostInit = ctx.AddComponentPostInit,
      AddPrefabPostInit = ctx.AddPrefabPostInit, travado = true })
    local clock = clock_falso()
    reg.component_postinits.clock(clock, {})
    T.eq(#reg.netvars, 0, "ainda sem netvar")
    clock:OnUpdate(2)
    T.eq(clock.acumulado, 0, "travado pela opção")
  end },

  { "avancar(n) chama o original com n * SEG_TIME, só no servidor", function(T)
    local Relogio, clock = relogio_instalado(true, true)
    T.eq(Relogio.avancar(1), true, "avancar devolve true no servidor")
    T.eq(clock.acumulado, SEG_TIME, "um segmento")
    T.eq(Relogio.avancar(2.5), true, "fração de segmento")
    T.eq(clock.acumulado, 3.5 * SEG_TIME, "3,5 segmentos")
    T.eq(Relogio.travado(), true, "continua travado depois do passo")
    clock:OnUpdate(10)
    T.eq(clock.acumulado, 3.5 * SEG_TIME, "e o tempo real não anda")

    local RelogioCliente, clock_cliente = relogio_instalado(false, true)
    T.eq(RelogioCliente.avancar(1), false, "cliente não avança")
    T.eq(clock_cliente.acumulado, 0, "nada andou no cliente")
  end },

  { "durante o passo o wrapper repassa o dt (o clock se chama de novo na troca de período)", function(T)
    -- O clock de verdade chama self:OnUpdate(resto) quando o passo passa do
    -- fim do período; aqui o original falso faz o mesmo uma vez.
    local recursivo = false
    local acumulado = 0
    local function fake(self, dt)
      acumulado = acumulado + dt
      if not recursivo and dt > 0 then
        recursivo = true
        self:OnUpdate(5) -- passa pelo wrapper
      end
    end
    local ctx, reg = ambiente(true)
    local R = carregar("relogio")
    R.instalar({ GLOBAL = ctx.GLOBAL, AddComponentPostInit = ctx.AddComponentPostInit,
      AddPrefabPostInit = ctx.AddPrefabPostInit, travado = true })
    local c = { OnUpdate = fake }
    reg.component_postinits.clock(c, {})
    reg.prefab_postinits.forest_network({ GUID = 1, DoTaskInTime = function() end })
    R.avancar(1)
    T.eq(acumulado, SEG_TIME + 5, "a chamada interna passou com o dt dela")
    -- avancar aninhado (de dentro de um evento do clock) não encerra o de fora.
    acumulado = 0
    local aninhado = false
    local function fake2(self, dt)
      acumulado = acumulado + dt
      if not aninhado and dt > 0 then
        aninhado = true
        R.avancar(1)          -- passo interno
        self:OnUpdate(7)      -- resto do passo de fora, depois do interno
      end
    end
    c = { OnUpdate = fake2 }
    reg.component_postinits.clock(c, {})
    R.avancar(1)
    T.eq(acumulado, 2 * SEG_TIME + 7, "o resto do passo de fora não se perde")
    acumulado, recursivo = 0, false
    c:OnUpdate(3)
    T.eq(acumulado, 0, "fora do passo volta a travar (a interna também vira 0)")
  end },

  { "travar/liberar mexem na netvar no servidor e são recusados no cliente", function(T)
    local Relogio, clock, _, reg = relogio_instalado(true, true)
    T.eq(#reg.netvars, 1, "uma netvar declarada")
    local nv = reg.netvars[1]
    T.eq(nv.guid, 7, "no GUID do forest_network")
    T.eq(type(nv.nome), "string", "nome da netvar")
    T.eq(type(nv.dirty), "string", "evento dirty")
    T.eq(nv.valor, 1, "servidor manda o estado inicial")
    T.eq(nv.sets, 1, "um set no post init")

    T.eq(Relogio.liberar(), true, "liberar")
    T.eq(nv.valor, 2, "netvar livre")
    T.eq(Relogio.travado(), false, "livre")
    clock:OnUpdate(2)
    T.eq(clock.acumulado, 2, "o tempo anda")

    T.eq(Relogio.travar(), true, "travar")
    T.eq(nv.valor, 1, "netvar travado")
    clock:OnUpdate(2)
    T.eq(clock.acumulado, 2, "o tempo parou")

    local RelogioCliente, clock_cliente, _, reg_cliente = relogio_instalado(false, true)
    local nvc = reg_cliente.netvars[1]
    T.eq(nvc.sets, 0, "cliente não escreve na netvar")
    T.eq(RelogioCliente.liberar(), false, "cliente não libera")
    T.eq(RelogioCliente.travar(), false, "cliente não trava")
    -- O cliente obedece ao que chega pela rede.
    nvc.valor = 2
    clock_cliente:OnUpdate(4)
    T.eq(clock_cliente.acumulado, 4, "cliente anda quando a netvar diz livre")
    nvc.valor = 1
    clock_cliente:OnUpdate(4)
    T.eq(clock_cliente.acumulado, 4, "e para quando diz travado")
    -- Antes de o valor chegar (0), vale a opção do mod: o cliente não anda.
    nvc.valor = 0
    clock_cliente:OnUpdate(4)
    T.eq(clock_cliente.acumulado, 4, "valor ainda não chegou: vale a opção (travado)")
  end },

  { "servidor envia 5/5/6 ao seasons e trava as quatro estações; cliente não envia nada", function(T)
    local _, _, _, reg = relogio_instalado(true, true)
    local segs = evento(reg, "ms_setseasonclocksegs")
    T.eq(#segs, 1, "um ms_setseasonclocksegs")
    local primeira
    for _, v in pairs(segs[1]) do primeira = v; break end
    T.ok(primeira, "tabela com pelo menos uma estação (vale para todas)")
    T.eq(primeira.day, 5, "dia 5")
    T.eq(primeira.dusk, 5, "entardecer 5")
    T.eq(primeira.night, 6, "noite 6")
    local nenhum_direto = evento(reg, "ms_setclocksegs")
    T.eq(#nenhum_direto, 0, "não usa ms_setclocksegs direto (o seasons desfaria)")

    local comprimentos = evento(reg, "ms_setseasonlength")
    T.eq(#comprimentos, 4, "quatro estações")
    local vistas = {}
    for _, d in ipairs(comprimentos) do
      T.eq(d.length, 0, "duração 0 para " .. tostring(d.season))
      vistas[d.season] = true
    end
    for _, s in ipairs({ "autumn", "winter", "spring", "summer" }) do
      T.ok(vistas[s], "estação " .. s)
    end

    local _, _, _, reg_cliente = relogio_instalado(false, true)
    T.eq(#reg_cliente.eventos, 0, "cliente não empurra eventos no mundo")
  end },

  { "5/5/6 e estações só vão depois da carga do mundo (o save do seasons apagaria antes)", function(T)
    local ctx, reg = ambiente(true)
    local R = carregar("relogio")
    R.instalar({ GLOBAL = ctx.GLOBAL, AddComponentPostInit = ctx.AddComponentPostInit,
      AddPrefabPostInit = ctx.AddPrefabPostInit, travado = true })
    local rede = { GUID = 3, tarefas = {} }
    function rede:DoTaskInTime(t, fn) self.tarefas[#self.tarefas + 1] = { t = t, fn = fn } end
    reg.prefab_postinits.forest_network(rede)
    T.eq(#evento(reg, "ms_setseasonclocksegs"), 0, "nada no post init (antes do seasons:OnLoad)")
    T.eq(#evento(reg, "ms_setseasonlength"), 0, "nem as durações")
    T.eq(#rede.tarefas, 1, "uma tarefa agendada")
    T.eq(rede.tarefas[1].t, 0, "para o primeiro passo")
    rede.tarefas[1].fn(rede)
    T.eq(#evento(reg, "ms_setseasonclocksegs"), 1, "5/5/6 depois da carga")
    T.eq(#evento(reg, "ms_setseasonlength"), 4, "estações travadas depois da carga")
  end },

  { "PlayerPostInit no servidor liga invencibilidade, visão noturna, fome e sanidade paradas", function(T)
    local ctx, reg = ambiente(true)
    local Protecao = carregar("protecao")
    Protecao.instalar({ GLOBAL = ctx.GLOBAL, AddPlayerPostInit = ctx.AddPlayerPostInit })
    T.eq(#reg.player_postinits, 1, "um post init de jogador")
    local j = jogador_falso(true)
    reg.player_postinits[1](j)

    local n, c = contar(j.chamadas, "SetInvincible")
    T.eq(n, 1, "SetInvincible uma vez")
    T.eq(c[2], true, "SetInvincible(true)")
    n, c = contar(j.chamadas, "ForceNightVision")
    T.eq(n, 1, "ForceNightVision")
    T.eq(c[2], true, "ForceNightVision(true)")
    n, c = contar(j.chamadas, "ForceNoNightVisionCC")
    T.eq(n, 1, "ForceNoNightVisionCC")
    T.eq(c[2], true, "sem filtro verde")
    n = contar(j.chamadas, "Pause")
    T.eq(n, 1, "hunger:Pause()")
    T.eq(j.components.sanity.ignore, true, "sanity.ignore")
    n, c = contar(j.chamadas, "SetTemp")
    T.eq(n, 1, "temperature:SetTemp")
    T.eq(c[2], 35, "temperatura fixa em STARTING_TEMP")
  end },

  { "PlayerPostInit no cliente só força a visão noturna", function(T)
    local ctx, reg = ambiente(false)
    local Protecao = carregar("protecao")
    Protecao.instalar({ GLOBAL = ctx.GLOBAL, AddPlayerPostInit = ctx.AddPlayerPostInit })
    local j = jogador_falso(false)
    -- No cliente não há health/hunger/sanity; mesmo que houvesse, não mexe.
    j.components.health = { SetInvincible = function() error("cliente chamou SetInvincible") end,
      IsInvincible = function() return false end }
    j.components.hunger = { Pause = function() error("cliente chamou Pause") end }
    j.components.sanity = { ignore = false }
    reg.player_postinits[1](j)
    local n = contar(j.chamadas, "ForceNightVision")
    T.eq(n, 1, "ForceNightVision no cliente (a luz é do cliente)")
    n = contar(j.chamadas, "ForceNoNightVisionCC")
    T.eq(n, 1, "ForceNoNightVisionCC no cliente")
    T.eq(contar(j.chamadas, "SetInvincible"), 0, "sem SetInvincible")
    T.eq(contar(j.chamadas, "Pause"), 0, "sem Pause")
    T.eq(j.components.sanity.ignore, false, "sanidade intocada")
    T.eq(next(j.eventos), nil, "cliente não escuta eventos do servidor")
  end },

  { "servidor reaplica a proteção quando o jogo desliga a invencibilidade ou revive", function(T)
    local ctx, reg = ambiente(true)
    local Protecao = carregar("protecao")
    Protecao.instalar({ GLOBAL = ctx.GLOBAL, AddPlayerPostInit = ctx.AddPlayerPostInit })
    local j = jogador_falso(true)
    reg.player_postinits[1](j)
    T.eq(type(j.eventos.invincibletoggle), "function", "escuta invincibletoggle")
    T.eq(type(j.eventos.ms_respawnedfromghost), "function", "escuta ms_respawnedfromghost")

    -- O jogo desliga (DisableLoadingProtection): a proteção volta numa tarefa.
    j.components.health.SetInvincible(nil, false)
    j.eventos.invincibletoggle(j, { invincible = false })
    T.eq(#j.tarefas, 1, "agendou a reaplicação")
    j.tarefas[1]()
    T.eq(j.components.health.IsInvincible(), true, "invencível de novo")
    T.eq(contar(j.chamadas, "Pause"), 2, "fome pausada de novo")

    -- Já invencível: o evento true não agenda nada.
    j.eventos.invincibletoggle(j, { invincible = true })
    T.eq(#j.tarefas, 1, "nada agendado para true")

    -- Reviver: reaplica direto.
    j.eventos.ms_respawnedfromghost(j)
    T.eq(contar(j.chamadas, "Pause"), 3, "fome pausada após reviver")
    T.eq(contar(j.chamadas, "SetTemp"), 3, "temperatura fixa após reviver")
    -- 3 = post init, o desligamento simulado pelo teste e a reaplicação;
    -- o ms_respawnedfromghost não chamou porque já estava invencível.
    T.eq(contar(j.chamadas, "SetInvincible"), 3, "SetInvincible só quando não estava invencível")
  end },

  { "jogador sem componentes (prefab estranho) não quebra o post init", function(T)
    local ctx, reg = ambiente(true)
    local Protecao = carregar("protecao")
    Protecao.instalar({ GLOBAL = ctx.GLOBAL, AddPlayerPostInit = ctx.AddPlayerPostInit })
    local j = jogador_falso(true)
    j.components = {}
    reg.player_postinits[1](j)
    T.eq(#j.chamadas, 0, "nenhuma chamada")
  end },
}
