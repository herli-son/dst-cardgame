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
| Travar o relógio | A implementar | `components/clock.lua` (`OnUpdate`) | O relógio avança sozinho a cada atualização. O mod precisa interceptar essa atualização para o tempo só andar com as jogadas. |
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

### Câmera

- **Rotação desligada, zoom liberado:** o mod bloqueia só `RotLeft` e `RotRight` (`components/playercontroller.lua`), em vez de usar `TheCamera:SetControllable(false)`, que desligaria o zoom junto.
- **Ângulo da câmera:** a referência é a visão isométrica do mod Zoom+. O nosso mod define o próprio ângulo e a distância da câmera (`cameras/followcamera.lua`), sem depender de outro mod instalado.
- **Cada jogador vê a mesa do seu lado:** a câmera é de cada cliente, então o mod define a direção com `TheCamera:SetHeadingTarget` (`cameras/followcamera.lua`). Um jogador fica com a direção oposta à do outro (diferença de 180°), e cada um vê o próprio campo na parte de baixo da tela.

## Pendências para os próximos passos

- Testar dentro do jogo a escala dos Chefes e os efeitos presos a eles.
- Desenhar como o mod intercepta o relógio sem quebrar as outras partes que dependem dele.
