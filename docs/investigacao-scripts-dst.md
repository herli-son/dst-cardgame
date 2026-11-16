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

## Pendências para os próximos passos

- Testar dentro do jogo a escala dos Chefes e os efeitos presos a eles.
- Desenhar como o mod intercepta o relógio sem quebrar as outras partes que dependem dele.
