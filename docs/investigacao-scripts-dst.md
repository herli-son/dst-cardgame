# Investigação dos scripts do DST

Verificação, no código do próprio jogo, dos pontos que o design do mod tratava como "a verificar".
Fonte: `scripts.zip` da instalação local do Don't Starve Together (`data/databundles`), lido em 16/11/2026.
Os scripts da Klei não são copiados para este repositório; abaixo ficam só as referências de arquivo e o que cada uma confirma.

User Story: #28 · Feature: #27

## Resultado

| Ponto | Situação | Onde está no jogo | O que significa para o mod |
|---|---|---|---|
| Visão noturna protege do Charlie | Confirmado | `components/grue.lua` | O componente `grue` ganha imunidade `nightvision` quando o jogador tem visão noturna. |
| Visão noturna sem tela verde | Confirmado | `components/playervision.lua` (`ForceNightVision`, `ForceNoNightVisionCC`) | Dá para forçar a visão noturna e desligar o filtro verde. A noite do duelo continua com cara de noite. |
| Mudar o período do mundo | Confirmado | `components/clock.lua` (eventos `ms_setphase`, `ms_nextphase`) | O servidor muda para dia, entardecer ou noite quando a partida avança. |
| Travar o relógio | Desenhado | `components/clock.lua` (`OnUpdate`), `modutil.lua` (`AddComponentPostInit`) | O relógio avança sozinho a cada atualização, no servidor e nos clientes. O mod troca o `OnUpdate` do `clock` nos dois lados e só deixa o tempo andar quando a partida avança (ver "Interceptação do relógio"). |
| Períodos 5/5/6 sem a estação desfazer | Confirmado | `components/seasons.lua` (`ms_setseasonclocksegs`, `PushSeasonClockSegs`), `components/clock.lua` (`ms_setclocksegs`) | O componente `seasons` reenvia os segmentos ao relógio a cada dia novo. Para os 5/5/6 ficarem, o mod informa a divisão ao `seasons`, não só ao `clock`. |
| Mapa próprio só com a arena | Confirmado | `map/levels/lavaarena.lua`, `map/levels/quagmire.lua`, `modutil.lua` (`AddLevel`) | A Forja e a Garganta já usam níveis próprios; mods podem registrar um nível com `AddLevel`. |
| Mapa com uma única sala | Confirmado | `map/tasks/lavaarena.lua`, `map/tasksets/lavaarena.lua`, `map/startlocations.lua`, `map/layouts.lua` (`LavaArenaLayout`), `map/static_layouts/events/lava_arena.lua` | A Forja é uma tarefa com a sala `Blank` e um "static layout" no centro. O mod repete a receita com a própria mesa (ver "Mapa customizado"). |
| Tiles no chão da mesa | Confirmado | `components/map.lua` (`Map:SetTile`), `tiledefs.lua`, `tilemanager.lua`, `modutil.lua` (`AddTile`), `constants.lua` (`WORLD_TILES`, `TILE_SCALE`) | Os tiles entram pelo layout na geração ou por `SetTile` em jogo; um tile novo com textura própria entra por `AddTile` (ver "Tiles e câmera"). |
| Câmera presa à mesa | Confirmado | `cameras/followcamera.lua` (`SetTarget`, `SetDistance`, `SetHeadingTarget`, `Snap`) | A câmera segue um alvo; o mod aponta para o centro da mesa e fixa distância e direção. |
| Desligar chefes, invasões e eventos | Confirmado | `map/customize.lua` (`WORLDSETTINGS_GROUP`, `WORLDGEN_GROUP`), `worldsettings_overrides.lua` | Tudo entra em `overrides` do nível; `AddLevel` separa o que é geração do que é configuração de mundo. |
| Imagens do Álbum para as cartas | Confirmado | `simutil.lua` (`GetScrapbookIconAtlas`) | Os ícones do Álbum ficam em `images/scrapbook_icons1.xml` a `scrapbook_icons3.xml`. |
| Mão escondida no inventário | Confirmado | `components/inventory_replica.lua` (`SetClassifiedTarget`) | Os dados do inventário só são enviados ao próprio dono. |
| Comunicação jogador e servidor | Confirmado | `modutil.lua` (`AddModRPCHandler`, `AddClientModRPCHandler`, `AddShardModRPCHandler`), `networkclientrpc.lua`, `netvars.lua` | O mod tem canais próprios para enviar ações (RPC) e estado replicado (netvars); ver "Rede e inventário". |
| Cartas como itens do inventário | Confirmado | `components/inventoryitem.lua` (`atlasname`, `imagename`, `islockedinslot`), `components/inventoryitem_replica.lua`, `widgets/itemtile.lua`, `widgets/inventorybar.lua`, `simutil.lua` (`RegisterInventoryItemAtlas`) | A imagem da carta vem do atlas e nome configurados no prefab; a barra se atualiza sozinha por `itemget`/`itemlose`. |
| Criatura sem IA própria | Confirmado | `entityscript.lua` (`StopBrain`, `SetBrain`) | Dá para desligar o comportamento automático de cada criatura. |
| Animação por comando | Confirmado | `stategraph.lua` (`GoToState`), `stategraphs/SGspider.lua`, `modutil.lua` (`AddStategraphState`, `AddStategraphPostInit`) | O mod leva a criatura a um estado do stategraph dela ou toca a animação direto no `AnimState` e espera `animover` (ver "Animações por comando"). |
| Jogadores protegidos no duelo | Confirmado | `components/health.lua` (`SetInvincible`), `components/hunger.lua` (`Pause`), `components/sanity.lua` (`ignore`) | Invulnerabilidade, fome pausada e sanidade ignorada durante a partida. |
| Mover criatura até o alvo | Confirmado | `components/locomotor.lua` | O movimento existe; a ida e a volta ao tile serão comandadas pelo mod. |
| Reduzir criaturas grandes | A testar no jogo | `prefabs/deerclops.lua`, `prefabs/bearger.lua` (`Transform:SetScale`, `DynamicShadow:SetSize`, `Follower:FollowSymbol`), `components/scaler.lua` | O próprio jogo escala os Chefes com `SetScale` (Deerclops usa 1,65). Sombra, física e efeitos presos não acompanham sozinhos (ver "Escala dos Chefes"). |

## Decisões

### Relógio da partida

Usa o relógio natural do jogo (`components/clock.lua`), sem relógio próprio.

- **Duração dos períodos:** o jogo exige que dia, entardecer e noite somem 16 segmentos (`NUM_SEGS = 16`), então não dá para dividir em três partes iguais. Usamos o mais próximo: **5, 5 e 6** segmentos.
- **Avanço por jogada:** de manhã e à tarde, cada vez jogada consome **50% do período**. Duas vezes completam o período, como nas regras (vezes 1 e 2 de manhã, 3 e 4 à tarde).
- **Noite:** ao chegar, o relógio fica **travado em 50% da noite** até o fim da rodada.
- **Entre as jogadas o relógio não anda.** Como ele avança sozinho com o tempo real, o mod intercepta a atualização do relógio e só o move quando a partida avança.

### Interceptação do relógio

Como o relógio funciona (`components/clock.lua`):

- O estado fica em variáveis de rede do `world_network` (`_segs`, `_phase`, `_cycles`, `_totaltimeinphase`, `_remainingtimeinphase`). O componente existe no servidor **e** nos clientes (`prefabs/world_network.lua` adiciona `clock` e `seasons` para todos; `prefabs/forest_network.lua` é a versão da floresta).
- `OnUpdate(dt)` desconta `dt` de `_remainingtimeinphase`. Dentro de um segmento, servidor e cliente andam por conta própria (`set_local`); na troca de segmento o servidor força a sincronia (`set`), e o cliente espera no fim do segmento até receber. Quando o tempo do período acaba, só o servidor principal troca o período e, ao voltar para o dia, soma um ciclo e dispara `ms_cyclecomplete`.
- No fim de todo `OnUpdate` saem os eventos que o resto do jogo escuta: `clocksegschanged`, `cycleschanged`, `phasechanged`, `moonphasechanged2` e, sempre, `clocktick`. `OnStaticUpdate` e `LongUpdate` são o mesmo `OnUpdate` (com `dt = 0` no estático).
- Eventos que o servidor aceita: `ms_setclocksegs` (troca a divisão e recalcula o período pelo horário atual), `ms_setphase` (vai para o começo de um período), `ms_nextphase` (zera o tempo restante), `ms_nextcycle`, `ms_setmoonphase`, `ms_lockmoonphase`. **Não existe evento de pausa.**
- Constantes (`tuning.lua`): `SEG_TIME = 30` s, 16 segmentos (480 s por dia), padrão 10/4/2.

Quem depende do relógio:

- `components/worldstate.lua` escuta `clocktick` e `phasechanged` e preenche `TheWorld.state` (`phase`, `isday`, `isdusk`, `isnight`, `time`, `timeinphase`, `cycles`). Quase todo o resto lê daí por `WatchWorldState`, por exemplo `components/birdspawner.lua` (`isnight`).
- `components/ambientlighting.lua`, `components/colourcube.lua`, `components/weather.lua`, `components/wildfires.lua`, `components/oceancolor.lua`, `components/worldtemperature.lua`: escutam `phasechanged` ou `clocktick` para luz, cor e temperatura.
- `widgets/uiclock.lua` escuta `clocktick` para desenhar o relógio da tela.
- `components/grue.lua` (Charlie) não olha o relógio: reage a `enterlight`/`exitlight` e a `nightvision` do jogador, então basta a escuridão existir para ele agir.
- `components/seasons.lua` escuta `ms_cyclecomplete` e, a cada dia novo (e em `ms_setseason`, `ms_setseasonlength`, `ms_setseasonclocksegs`, `ms_setseasonsegmodifier`), chama `PushSeasonClockSegs`, que envia `ms_setclocksegs` com os segmentos da estação. **Um `ms_setclocksegs` enviado só pelo mod seria desfeito no dia seguinte.**

Abordagens avaliadas:

- (a) `ms_setclocksegs` com 5/5/6 e "pausar" pelo mesmo evento: **descartada**. O evento só redistribui os segmentos; não há como parar o tempo por ele, e o `seasons` o sobrescreve a cada ciclo.
- (c) `TheWorld:PushEvent("ms_setphase")` a cada jogada: **insuficiente**. Serve para pular de período, mas sempre começa o período do zero (não dá o passo de 50%) e o tempo continua correndo depois.
- (b) trocar o `OnUpdate` do componente `clock`: **recomendada**. `AddComponentPostInit("clock", fn)` roda logo depois do construtor do componente (`entityscript.lua`, `AddComponent`), no servidor e nos clientes que tiverem o mod. O mod guarda o `OnUpdate` original e o substitui por uma versão que, com a partida travada, chama o original com `dt = 0` (nada anda, mas `clocktick` e os eventos de mudança continuam saindo, então `worldstate`, luz e o relógio da tela seguem coerentes). Quando a partida avança, só o servidor chama o original com o `dt` do passo (metade do período, isto é, `segmentos × SEG_TIME / 2`); a troca de segmento faz o servidor sincronizar os clientes pelas variáveis de rede.

Decisão: **abordagem (b)**, com estes cuidados:

- Aplicar nos dois lados (`all_clients_require_mod`): se só o servidor parar, o cliente continua andando sozinho até o fim do segmento atual (até 30 s de luz "errada") e depois trava esperando a sincronia.
- Definir 5/5/6 por `ms_setseasonclocksegs` (tabela com os segmentos por estação, ou uma única entrada que vale para todas) em vez de `ms_setclocksegs`, para o `seasons` passar a reenviar a divisão certa. [provável] Enviar num `AddPrefabPostInit("forest_network")`, que roda depois de `clock` e `seasons` serem criados.
- Travar a estação com `ms_setseasonlength` (as opções `autumn`/`winter`/... = `noseason` de `worldsettings_overrides.lua` usam esse evento), para a virada de dia não mudar a estação.
- `LongUpdate` e `OnStaticUpdate` continuam apontando para o original; `LongUpdate` é chamado por `ms_setphase`/`ms_nextphase` e no carregamento (`world_network.lua`, `PostInit`, com `dt = 0`). Se o mod quiser usar `ms_setphase` para abrir um período, isso continua funcionando.
- Ao fechar a rodada (noite em 50% → manhã), o passo faz o relógio somar um ciclo e disparar `ms_cyclecomplete`; é esperado e inofensivo com a estação travada.

### Câmera

- **Rotação desligada, zoom liberado:** o mod bloqueia só `RotLeft` e `RotRight` (`components/playercontroller.lua`), em vez de usar `TheCamera:SetControllable(false)`, que desligaria o zoom junto.
- **Ângulo da câmera ajustável:** o jogador troca o ângulo por um botão na tela e por uma tecla de atalho, alternando entre predefinições (por exemplo: padrão do jogo, aérea e vista de cima). Cada predefinição muda campos da câmera (`zoomstep`, `distancetarget`, `mindist`, `maxdist`, `mindistpitch`, `maxdistpitch` em `cameras/followcamera.lua`). O nosso mod tem as próprias predefinições, sem depender de outro mod instalado.
- **Referência:** o mod "[DST]Aerial View" (Oficina, id 694531911), que troca entre vista aérea, vista de cima e padrão com uma tecla, ajustando esses mesmos campos. As predefinições do nosso mod partem dos ângulos dele. Serve de referência de abordagem; o código dele não é copiado.
- **Cada jogador vê a mesa do seu lado:** a câmera é de cada cliente, então o mod define a direção com `TheCamera:SetHeadingTarget` (`cameras/followcamera.lua`). Um jogador fica com a direção oposta à do outro (diferença de 180°), e cada um vê o próprio campo na parte de baixo da tela.

## Animações por comando

Como o jogo toca animações (lido em `stategraph.lua`, `stategraphs/SGspider.lua` e `stategraphs/commonstates.lua`):

- Cada criatura tem um stategraph (`inst.sg`, criado por `EntityScript:SetStateGraph` em `entityscript.lua`). Cada `State` tem `onenter` (onde fica o `AnimState:PlayAnimation`/`PushAnimation`), `timeline` (`TimeEvent` em quadros: sons, o golpe) e `events` (`EventHandler`). O estado termina quando chega `animover` (fim da animação) ou `animqueueover` (fim da fila de `PushAnimation`), e o handler chama `inst.sg:GoToState(...)`.
- `inst.sg:GoToState(nome, params)` (`stategraph.lua`) força um estado por fora. `inst.sg:HasState(nome)` diz se ele existe.
- Estados que interessam, na aranha (`SGspider.lua`): `idle` (anima `idle` em laço), `attack` (anima `atk`; no quadro 25 chama `combat:DoAttack`; volta para `idle` em `animover`), `hit` (anima `hit`; volta para `idle`), `death` (anima `death`; vai para `corpse`). Os estados `idle`, `attack`, `hit` e `death` existem com esses nomes também em `SGpig.lua`, `SGhound.lua`, `SGdeerclops.lua` e `SGbearger.lua`, e `commonstates.lua` (`AddCombatStates`, `AddHitState`, `AddDeathState`, `AddIdle`) gera os mesmos nomes para quem usa os estados genéricos.
- Os eventos que levam a esses estados vêm de fora: `doattack` e `locomote` vêm do cérebro e do `locomotor`; `attacked` vem de `components/combat.lua` (`GetAttacked`); `death` vem de `components/health.lua`.

Como desligar a IA sem quebrar a animação:

- `inst:StopBrain(motivo)` (`entityscript.lua`) para só o cérebro; o stategraph continua rodando, então `idle` segue animando, `attacked` ainda leva para `hit` e `locomote` ainda anda. É isso que o mod quer: cérebro parado, stategraph vivo.
- `inst:ClearStateGraph()` e `inst.sg:Stop()` existem, mas param tudo (inclusive o `idle` em laço). Não usar.

Riscos e escolhas para o mod:

- **Entrar em `attack` dá dano de verdade.** O `timeline` chama `combat:DoAttack(alvo)`; com alvo `nil`, `DoAttack` usa `combat.target` (`components/combat.lua`). Opções: (1) tocar só a animação com `inst.AnimState:PlayAnimation("atk")` e escutar `animover` na própria entidade (`inst:ListenForEvent("animover", ...)`, padrão usado em `components/frostybreather.lua` e `components/disappears.lua`), mantendo o stategraph em `idle`; (2) registrar um estado próprio com `AddStategraphState(nomeDoSG, State{...})` que toca `atk` sem `DoAttack` e volta para `idle`, e entrar nele com `GoToState`. A opção (2) é mais limpa porque os `TimeEvent` de som continuam e o stategraph sabe que a criatura está ocupada; a opção (1) pode ser atropelada pelo próprio `idle` (que chama `PlayAnimation` ao entrar). [provável] A (2) é a recomendada; conferir no jogo que o `onenter` do `idle` não é chamado no meio.
- **`hit` é seguro**: só anima e volta para `idle`. Pode ser chamado direto com `GoToState("hit")`.
- **`death` remove a criatura** (vai para `corpse`, solta loot em `CommonStates.AddDeathState`). Para a morte das cartas, o mod toca `death` como animação (`PlayAnimation("death")`) e remove a entidade depois do `animover`, sem passar por `health:Kill`, já que as criaturas ficam invulneráveis.
- Nomes de animação variam por criatura (`atk`, `attack`, `hit`, `death`, `idle`, `idle_loop`); o mod lê o estado do stategraph de cada criatura em vez de fixar o nome da animação. `AnimState:GetCurrentAnimationNumFrames` e `FRAMES` (`constants.lua`) servem para cronometrar.

## Escala dos Chefes

O que os scripts confirmam:

- `Transform:SetScale(s, s, s)` é o jeito oficial: `prefabs/deerclops.lua` aplica 1,65 no próprio prefab, e `components/scaler.lua` (usado em criaturas que crescem) só faz isso e guarda o valor no save. Como a escala é definida no construtor do prefab, o mod a troca num `AddPrefabPostInit` da criatura, que roda no servidor e nos clientes.
- Entidades filhas (`entity:SetParent`) herdam a escala do pai: `prefabs/abigail.lua` divide a própria escala por `target.Transform:GetScale()` ao se prender a um alvo justamente para compensar isso. [provável] Efeitos presos por `SetParent` encolhem junto com o Chefe.

Riscos concretos (continua "a testar no jogo"):

- **Sombra**: `DynamicShadow:SetSize(6, 3.5)` é fixo em `deerclops.lua` e `bearger.lua`, independente da escala. Se não acompanhar, o mod ajusta a sombra junto com a escala.
- **Física e alcance**: `MakeGiantCharacterPhysics(inst, 1000, .5)` e `combat:SetRange(TUNING.DEERCLOPS_ATTACK_RANGE)` não dependem da escala. Um Chefe menor continua empurrando e "alcançando" como grande; para o mod isso só importa no posicionamento da criatura no tile (raio de colisão) e na distância de parada do `locomotor`.
- **Efeitos presos por símbolo**: `Follower:FollowSymbol(guid, símbolo, ...)` (`deerclops.lua`, Deerclops mutado: `swap_gestalt_flame`, `swap_fire_*`; `bearger.lua`: `flameL`, `flameR`) segue a posição do símbolo; não está claro no Lua se o efeito herda a escala. Em `deerclops.lua` o efeito é também filho (`SetParent`) do Chefe, o que [provável] faz a escala acompanhar; nos casos só com `FollowSymbol` precisa de teste.
- **Efeitos soltos no chão**: os golpes dos Chefes criam prefabs independentes (`deerclops_icespike_fx`, `groundpounder` em `components/groundpounder.lua`, que tem o próprio `fxscale`). Não encolhem com a criatura; como o mod não usa os golpes reais, isso só aparece se alguma animação disparar esses efeitos pela `timeline` do stategraph.

## Mapa customizado (para a US #29)

Como um nível é montado (lido em `map/levels.lua`, `map/levels/lavaarena.lua`, `map/locations.lua`, `map/tasksets/lavaarena.lua`, `map/tasks/lavaarena.lua`, `map/rooms.lua`, `map/startlocations.lua`, `map/layouts.lua`, `map/storygen.lua`, `map/forest_map.lua`):

- **Nível** (`AddLevel(LEVELTYPE.SURVIVAL, { id, name, desc, location, version, overrides, required_prefabs })`): `AddModLevel` em `map/levels.lua` divide `overrides` em duas listas usando `map/customize.lua`: o que é configuração de mundo vira um "settings preset" e o resto vira o nível de geração. O `id` não pode começar com `CUSTOM_`. O nível aparece na tela de criação de mundo como predefinição e pode ser escolhido num servidor dedicado por `worldgenoverride.lua` (`saveindex.lua` lê esse arquivo).
- **Location** é o prefab do mundo (`location = "lavaarena" -- this is actually the prefab name`). A Forja e a Garganta têm prefab de mundo próprio (`prefabs/lavaarena.lua`, `prefabs/quagmire.lua`); a floresta é `forest` e exige `multiplayer_portal` no mapa (`required_prefabs` em `map/locations.lua`; `forest_map.lua` aborta a geração sem um ponto de início). [provável] Para o mod, o mais simples é manter `location = "forest"` (fica com `clock`, `seasons`, luz e clima prontos) e desligar o resto por `overrides`; um prefab de mundo próprio (`MakeWorld` em `prefabs/world.lua` + `MakeWorldNetwork`) é a alternativa se a floresta trouxer coisa demais.
- **Task set → task → sala → layout**: `AddTaskSet(nome, { location, tasks = {...}, valid_start_tasks = {...} })`; `AddTask(nome, { room_choices = { Blank = 1 }, background_room = "Blank", room_bg = WORLD_TILES.IMPASSABLE, locks = {}, keys_given = {} })`; a sala `Blank` (`map/rooms.lua`) é vazia e intransitável. `AddStartLocation(nome, { location, start_setpeice = "NomeDoLayout", start_node = "Blank" })` coloca o layout no nó de início (`storygen.lua`, `start_setpeice` → `countstaticlayouts`). As salas também aceitam `contents.countstaticlayouts = { NomeDoLayout = 1 }` (`map/rooms/forest/DLCrooms.lua`, arena da Libélula). O `modworldgenmain.lua` do mod registra tudo isso (`mods.lua` carrega esse arquivo na geração), e as chaves `task_set` e `start_location` dos `overrides` apontam para os nomes registrados.
- **Static layout**: arquivo Lua exportado do Tiled (`map/static_layouts/events/lava_arena.lua`: camada `BG_TILES` com o chão e camadas de objetos com os prefabs). `StaticLayout.Get(caminho, { start_mask, fill_mask, layout_position = LAYOUT_POSITION.CENTER, disable_transform })` em `map/static_layout.lua` converte; a ordem dos tiles do Tiled está em `GROUND_TYPES` do mesmo arquivo (inclui `CHECKER`, `CARPET`, `MOSAIC_*`, `LAVAARENA_FLOOR`). Os layouts são achados por nome em `map/object_layout.lua` (`LayoutForDefinition`) na tabela `Layouts` de `map/layouts.lua`. [provável] O mod registra o seu inserindo na tabela devolvida por `require("map/layouts").Layouts` no `modworldgenmain.lua`, que é o que mods de mapa fazem; não há função `AddLayout` em `modutil.lua`.
- Chaves de geração da location que a Forja usa e servem de modelo (`map/locations.lua`): `world_size = "small"`, `layout_mode = "RestrictNodesByKey"`, `roads = "never"`, `wormhole_prefab = nil`, `keep_disconnected_tiles = true`, `no_joining_islands = true`. `has_ocean` controla o oceano na floresta.

Chaves de `overrides` relevantes (nomes em `map/customize.lua`; efeitos em `worldsettings_overrides.lua`):

- **Geração** (`WORLDGEN_GROUP`): `task_set`, `start_location`, `world_size` (`small`...`huge`), `branching`, `loop`, `roads`, `touchstone`, `boons`, `prefabswaps_start`, `season_start` (`default`, `winter`, `spring`, `summer`), e os grupos de recursos, animais e monstros do mapa (`spiders`, `houndmound`, `merm`, `tentacles`, `walrus`, `pigs`, `beefalo`, `rabbits`, `trees`, `grass`, `berrybush`, ...), todos com `never`/`rare`/`default`/`often`/`always` (`frequency_descriptions`). A Forja zera `boons`, `touchstone`, `traps`, `poi`, `protected`.
- **Chefes e invasões** (`WORLDSETTINGS_GROUP`): `deerclops`, `bearger`, `goosemoose`, `dragonfly`, `antliontribute`, `crabking`, `beequeen`, `toadstool`, `malbatross`, `klaus`, `spiderqueen`, `eyeofterror`, `daywalker`, `sharkboi`, `liefs`, `deciduousmonster`, `hounds`, `summerhounds`, `winterhounds`, `wormattacks`, `pirateraids`, `lureplants`, `hound_mounds`, `nightmarecreatures`, `shadowcreatures`, `brightmarecreatures`, `hunt`, `alternatehunt`, `krampus`. `deerclops = "never"` vira `TUNING.SPAWN_DEERCLOPS = false`; `hounds` vai para `hounded_setdifficulty`.
- **Clima e mundo**: `weather`, `lightning`, `frograin`, `wildfires`, `petrification` (`none` zera `PETRIFICATION_CYCLE`), `meteorshowers`, `earthquakes`, `rifts_enabled`, `rifts_frequency`, `lunarhail_frequency`, `acidrain_enabled`, `wanderingtrader_enabled`, `atriumgate`, `regrowth` e os `*_regrowth`.
- **Estações e dia**: `autumn`, `winter`, `spring`, `summer` (`noseason`, `veryshortseason`...`verylongseason`; `noseason` = `ms_setseasonlength` com 0), `day` (`onlyday`, `onlydusk`, `onlynight`, `default`, `longday`, `longdusk`, `longnight`, `noday`, `nodusk`, `nonight` → `ms_setseasonsegmodifier`; não dá 5/5/6, por isso o relógio usa `ms_setseasonclocksegs` direto).
- **Eventos**: `specialevent` (`none`/`default`/...) e os eventos individuais `crow_carnival`, `hallowed_nights`, `winters_feast`, `year_of_the_*`.
- **Sobreviventes**: `spawnmode`, `ghostenabled`, `ghostsanitydrain`, `portalresurection`, `resettime`, `healthpenalty`, `lessdamagetaken`, `temperaturedamage`, `hunger`, `darkness` (`nonlethal` → `TUNING.NONLETHAL_DARKNESS`; **não** usar, o Charlie faz parte do duelo), `extrastartingitems`, `seasonalstartingitems`, `spawnprotection`, `dropeverythingondespawn`.
- **Cavernas** não são chave de nível: são outro shard; para não existirem, o servidor simplesmente não sobe o shard das cavernas. O nível do mod é só da floresta (`world = {"forest"}` nas opções).

Decisão para a US #29: nível `AddLevel(LEVELTYPE.SURVIVAL, ...)` com `location = "forest"`, task set e task próprios com a sala `Blank`, start location apontando para um static layout da mesa (com `multiplayer_portal` dentro), e `overrides` zerando chefes, invasões, clima, eventos e estações pela lista acima.

## Tiles e câmera (para a US #30)

Tiles:

- **Identificadores**: `WORLD_TILES` (`constants.lua`) é a tabela atual; `GROUND` é a antiga, mantida por compatibilidade (`GetWorldTileMap` junta as duas). Cada tile tem 4 unidades de mundo (`TILE_SCALE = 4`). Tiles prontos que servem para uma mesa: `CHECKER`, `CARPET`, `CARPET2`, `WOODFLOOR`, `MOSAIC_GREY`, `MOSAIC_RED`, `MOSAIC_BLUE`, `LAVAARENA_FLOOR`, `LAVAARENA_TRIM`, `BRICK`, `TILES`, `TRIM` (`tiledefs.lua`).
- **Na geração**: o chão vem da camada `BG_TILES` do static layout (ver "Mapa customizado"); é o caminho natural para o tabuleiro fixo.
- **Em jogo** (servidor): `TheWorld.Map:SetTile(tile_x, tile_y, WORLD_TILES.X)` (`components/map.lua` envolve a função do motor e dispara `onterraform`). Para converter posição em tile: `Map:GetTileCoordsAtPoint(x, y, z)` e `Map:GetTileCenterPoint(tile_x, tile_y)`; `Map:GetTileAtPoint` lê o tile. Exemplos: `components/terraformer.lua` (pá), `prefabs/wurt_swamp_terraformer.lua`, `prefabs/atrium_markers.lua`. O `components/undertile.lua` guarda o tile que ficou por baixo quando se troca um piso.
- **Tile novo com textura própria**: `AddTile(nome, "LAND", { ground_name }, ground_tile_def, minimap_tile_def, turf_def)` em `modutil.lua` chama `TileManager.AddTile` (`tilemanager.lua`). `ground_tile_def` exige `name` (atlas e textura `levels/tiles/<name>.xml`/`.tex`, resolvidos por `GroundImage`/`GroundAtlas`) e `noise_texture` (`levels/textures/<noise>.tex`); aceita `runsound`, `walksound`, `flooring`, `hard`, `cannotbedug`, `nogroundoverlays`. `minimap_tile_def` exige `name` e `noise_texture`; `turf_def` é opcional (só se o tile virar item). O id é alocado na faixa `LAND` (`WORLD_TILES_LAND_START = 256` em diante). Como o id é gerado por ordem de registro, todos os clientes precisam do mod (`all_clients_require_mod`). O exemplo mais próximo de uma mesa é `CARPET` em `tiledefs.lua`. [provável] Para o primeiro protótipo os tiles prontos (`CHECKER`, `MOSAIC_*`) bastam; o tile próprio fica para quando houver arte.

Câmera (`cameras/followcamera.lua`, complementa a seção "Câmera" das decisões):

- `TheCamera:SetTarget(inst)` segue uma entidade; passar uma entidade invisível no centro da mesa prende a câmera ali. `TheCamera:SetDistance(d)`, `SetMinDistance`, `SetMaxDistance` controlam o zoom; `SetHeadingTarget(graus)` a direção; `Snap()` aplica sem interpolar. Tudo é do cliente, então cada jogador tem a sua.
- `components/playercontroller.lua` é quem reage a `RotLeft`/`RotRight` e ao zoom; o bloqueio só da rotação já está decidido acima.

## Rede e inventário (para a US #37)

RPCs de mod (`modutil.lua` expõe; a implementação está em `networkclientrpc.lua`):

- **Cliente → servidor**: `AddModRPCHandler(namespace, nome, fn)` registra no servidor; `fn` recebe o jogador que mandou (`player`) e depois os argumentos. O cliente chama `SendModRPCToServer(GetModRPC(namespace, nome), ...)`. Há limite de fila por remetente (`RPC_QUEUE_RATE_LIMIT`, somado por mod) e validadores de argumento (`checknumber`, `checkuint`, `checkstring`, `checkbool`, `checkentity` e as versões `opt*`) para o handler recusar dados errados.
- **Servidor → cliente**: `AddClientModRPCHandler(namespace, nome, fn)` registra no cliente; o servidor chama `SendModRPCToClient(GetClientModRPC(namespace, nome), users, ...)`, onde `users` é `nil` (todos), um `userid` ou uma lista de `userid` (comentário acima de `SendRPCToClient`). É por aqui que o servidor avisa só um jogador (por exemplo, a mão dele).
- **Entre shards**: `AddShardModRPCHandler`/`SendModRPCToShard`; não se aplica (só floresta).
- Os ids são gerados pela ordem de registro, então servidor e clientes precisam registrar as mesmas RPCs na mesma ordem (mesma versão do mod).

Variáveis de rede (`netvars.lua`, cabeçalho do arquivo):

- Tipos: `net_bool`, `net_tinybyte` (0–7), `net_smallbyte` (0–63), `net_byte`, `net_shortint`, `net_ushortint`, `net_int`, `net_uint`, `net_float`, `net_hash`, `net_string`, `net_entity`, `net_bytearray`, `net_smallbytearray`, `net_ushortarray` (arrays até 31, caros), e `net_event` para disparos sem valor.
- Uso: `net_x(inst.GUID, "nome", "eventodirty")`; `set` no servidor sincroniza e dispara o evento "dirty" nos dois lados; `value` lê; `set_local` muda sem sincronizar (é o que o `clock` usa para o cliente andar sozinho dentro do segmento).
- Regra que importa para o mod: as netvars têm de existir e ser declaradas igual no servidor e nos clientes para cada entidade, senão a entidade não desserializa; ou seja, **todos os clientes precisam do mod** (`all_clients_require_mod = true` no `modinfo.lua`).
- O `clock` é um bom exemplo de componente de mundo com netvars; `prefabs/inventory_classified.lua` é o exemplo de entidade "classificada" que só o dono recebe (`Network:SetClassifiedTarget`, em `components/inventory_replica.lua`, `OnOpen`/`OnClose`). O mod pode usar o mesmo padrão para o estado privado da partida (mão, baralho) se não quiser depender só de RPCs.

Inventário (como as cartas aparecem):

- O servidor define a imagem no componente: `inventoryitem.atlasname` e `inventoryitem.imagename` (`components/inventoryitem.lua`) são repassados para a réplica (`inventoryitem_replica.lua`, `SetAtlas`/`SetImage`), que os guarda em netvars da classificada do item. Sem atlas, `GetInventoryItemAtlas` (`simutil.lua`) procura em `images/inventoryimages1.xml`…`4.xml`; um mod registra o próprio atlas com `RegisterInventoryItemAtlas(atlas, nomeDaImagem)` (`modutil.lua`), e o nome da imagem padrão é `<prefab>.tex`. [provável] As imagens do Álbum (`images/scrapbook_icons*.xml`) podem ser usadas direto como `atlasname`/`imagename` da carta.
- `widgets/itemtile.lua` desenha o item com `inventoryitem:GetAtlas()` e `GetImage()`; `widgets/inventorybar.lua` escuta `itemget`, `itemlose`, `equip`, `unequip`, `newactiveitem` e `refreshinventory` no jogador e atualiza os slots sozinho. Quantidade de slots: `GetMaxItemSlots` (`gamemodes.lua`), por padrão `MAXITEMSLOTS`.
- Dar e tirar: `inventory:GiveItem(item, slot)`, `inventory:RemoveItem(item)`, `inventory:DropItem(item)` (`components/inventory.lua`). `inventoryitem.islockedinslot = true` impede soltar o item (`DropItem` devolve sem fazer nada) e de trocá-lo de lugar; `canbepickedup`, `cangoincontainer` e `canonlygoinpocket` também existem. `inventory:Hide()`/`Show()` escondem a barra (`inventory_replica.lua`, `IsVisible`).
- A regra "mão escondida" já estava confirmada: os slots só são enviados ao dono (`SetClassifiedTarget`).

## Pendências para os próximos passos

- Testar dentro do jogo a escala dos Chefes e os efeitos presos a eles.
- Desenhar como o mod intercepta o relógio sem quebrar as outras partes que dependem dele.
