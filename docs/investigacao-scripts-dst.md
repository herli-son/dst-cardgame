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
| Imagens do Álbum para as cartas | Confirmado | `simutil.lua` (`GetScrapbookIconAtlas`) | Os ícones do Álbum ficam em `images/scrapbook_icons1.xml` a `scrapbook_icons3.xml`. |
| Mão escondida no inventário | Confirmado | `components/inventory_replica.lua` (`SetClassifiedTarget`) | Os dados do inventário só são enviados ao próprio dono. |
| Comunicação jogador e servidor | Confirmado | `modutil.lua` (`AddModRPCHandler`, `AddClientModRPCHandler`, `AddShardModRPCHandler`) | O mod tem canais próprios para enviar ações e receber eventos. |
| Criatura sem IA própria | Confirmado | `entityscript.lua` (`StopBrain`, `SetBrain`) | Dá para desligar o comportamento automático de cada criatura. |
| Jogadores protegidos no duelo | Confirmado | `components/health.lua` (`SetInvincible`), `components/hunger.lua` (`Pause`), `components/sanity.lua` (`ignore`) | Invulnerabilidade, fome pausada e sanidade ignorada durante a partida. |
| Mover criatura até o alvo | Confirmado | `components/locomotor.lua` | O movimento existe; a ida e a volta ao tile serão comandadas pelo mod. |
| Reduzir criaturas grandes | A testar no jogo | Motor do jogo (`Transform:SetScale`) | A escala funciona no modelo; efeitos presos ao modelo precisam ser conferidos dentro do jogo. |

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

## Pendências para os próximos passos

- Testar dentro do jogo a escala dos Chefes e os efeitos presos a eles.
- Desenhar como o mod intercepta o relógio sem quebrar as outras partes que dependem dele.
