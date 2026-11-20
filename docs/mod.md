# O mod no Don't Starve Together

Este repositório **é** o mod: a raiz dele vira a pasta do mod dentro do jogo. Os arquivos que o jogo lê ficam na raiz (`modinfo.lua`, `modmain.lua`, `modworldgenmain.lua`) e em `scripts/`; o resto (`docs/`, `tests/`, `README.md`) é ignorado pelo jogo.

| Arquivo | Para quê |
|---|---|
| `modinfo.lua` | Ficha do mod: nome, versão, `api_version`, `all_clients_require_mod`. |
| `modworldgenmain.lua` | Geração do mundo: registra o layout da mesa, a task/task set/start location e o nível **Mesa do duelo** (`DUELO_MESA`). |
| `modmain.lua` | Código em jogo (servidor e clientes). Só liga os módulos de `scripts/duelo/mod/` e expõe `DUELO` (também no console). |
| `scripts/duelo/mod/mesa.lua` | Geometria da mesa: grade de tiles, posição de cada espaço (carta e criatura, estruturas, decks, par de combate, espaço de eventos), calibração pura, conversão para unidades do mundo. |
| `scripts/duelo/mod/protecao.lua` | US #31: visão noturna de todos, invencibilidade, fome, sanidade e temperatura paradas. |
| `scripts/duelo/mod/relogio.lua` | US #31: relógio do mundo travado e andado pela partida, divisão 5/5/6, estação fixa. |
| `scripts/duelo/mod/calibracao.lua` | US #30: acha a mesa no mapa (os 4 tiles de estrutura e os 2 de eventos, em volta do portal), guarda a calibração em `Mesa.calibracao` e a manda aos clientes. |
| `scripts/duelo/mod/marcadores.lua` | US #30: número e dono de cada espaço (criaturas, no tile da carta; estruturas; decks) e os rótulos "Combate" e "Eventos" das zonas compartilhadas. |
| `scripts/duelo/mod/contornos.lua` | Bug #147: contorno de cada tile de espaço com o `tile_outline` do jogo (o quadrado do `gridplacer`, sem o componente `placer`), na cor do dono, amarelo no espaço de eventos (local a cada cliente). |
| `scripts/prefabs/duelo_marcador.lua` | US #30: prefab de rede do marcador (só um texto, sem clique nem física). |
| `scripts/duelo/mod/camera.lua` | US #30: lado de cada jogador e câmera fixa no centro da mesa, sem Q/E. |
| `scripts/duelo/mod/layouts/mesa.lua` | Static layout (formato do Tiled) gerado a partir de `mesa.lua`. |
| `scripts/duelo/core`, `cartas`, `decks`, `sim`, `bot`, `terminal` | Motor de regras, Lua puro (ver `docs/terminal.md`). |

## Instalar para testar

O jogo procura mods locais em `mods/` dentro da pasta de instalação. No Windows, com a Steam no lugar padrão:

```text
C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\mods\
```

Copie a pasta do repositório para lá com o nome `dst-cardgame`:

```text
...\Don't Starve Together\mods\dst-cardgame\modinfo.lua
...\Don't Starve Together\mods\dst-cardgame\modmain.lua
...\Don't Starve Together\mods\dst-cardgame\modworldgenmain.lua
...\Don't Starve Together\mods\dst-cardgame\scripts\duelo\...
```

Para não copiar a cada mudança, crie um link simbólico (PowerShell como administrador) apontando para o clone:

```powershell
New-Item -ItemType SymbolicLink `
  -Path "C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\mods\dst-cardgame" `
  -Target "C:\caminho\do\clone\dst-cardgame"
```

Depois, no jogo: **Mods → Mods de servidor**, ative **DST Card Game**. Se o mod não aparecer, confira o nome da pasta e o `client_log.txt` (em `Documents\Klei\DoNotStarveTogether\`), que lista os erros de `modinfo.lua`.

## Criar o mundo

1. **Jogar → Hospedar jogo**, crie um novo servidor (ou use um slot vazio).
2. Em **Mods**, ative o DST Card Game para esse servidor.
3. Na aba do mundo (**Floresta**), em **Predefinições**, escolha **Mesa do duelo**. A predefinição preenche a geração (só a nossa mesa, sem recursos) e as configurações (sem chefes, invasões, clima, eventos nem estações).
4. **Sem Cavernas:** na aba **Cavernas**, desligue-as (ou não adicione o mundo das cavernas). As cavernas são um segundo mundo (shard), não uma opção do nível; se existirem, o jogo gera uma caverna normal.
5. Gere o mundo.

Num servidor dedicado, a predefinição é escolhida no `worldgenoverride.lua` do shard Master:

```lua
return {
  override_enabled = true,
  preset = "DUELO_MESA",
}
```

e o mod é ativado em `modoverrides.lua` com `["workshop-..."]` ou, para o mod local, `["dst-cardgame"] = { enabled = true }` (o nome é o da pasta). Para mod local, a pasta precisa estar no `mods/` da instalação do **servidor dedicado**, não na do cliente; `dedicated_server_mods_setup.lua` só é necessário para mods da Workshop. Não configure o shard Caves.

**Depois de atualizar os arquivos do mod, feche o DST por completo e abra de novo.** O jogo pode continuar com a versão antiga dos scripts carregada ao voltar para o menu ou criar outro mundo (visto no teste da US #31: um comando novo do mod não existia até reabrir). `print(DUELO.Relogio.diagnostico())` no console mostra se a versão carregada tem o diagnóstico e o que o relógio já fez.

Mensagens esperadas no console, que não são do mod nem atrapalham:

- `ERROR: hermitcrab_relocation_manager expected to be able to calculate the set piece angle...` e `ERROR: wagpunk_arena_manager expected...`: dois componentes da floresta (`prefabs/forest.lua`) procuram as ilhas da Rainha dos macacos e da Ermitã, que o nosso mundo não tem; eles só imprimem o aviso e param (`components/hermitcrab_relocation_manager.lua`). Removê-los do mundo arriscaria quebrar outro código que os consulta.
- `ValidateCharacterData failed ... skillxp`: validação da árvore de habilidades do perfil do jogador, do próprio jogo.

## O que conferir no primeiro teste

Os testes automáticos (`tests/test_mod_arena.lua`) só verificam que os arquivos do mod compilam, o que eles registram e os dados do layout. **O código do mod não roda nos testes**, então estes pontos só se confirmam no jogo:

- **Mundo vazio:** nenhum recurso, animal ou monstro nasce. Fora da mesa deve ser vazio (intransitável); a geração não deve mostrar oceano nem outras ilhas. Se aparecer algo (por exemplo, um spawner residual de `prefabs/forest.lua`), anotar o prefab para desligar na próxima US.
- **Mesa visível:** a mesa 15 x 14 do bug #147 (ver "Layout da mesa" abaixo): paralelepípedos (`ROAD`) entre os espaços e na borda, uma moldura de pedra (`ROCKY`) em volta, espaços de criatura de 2 tiles em xadrez (`CHECKER`), estruturas em mosaico cinza (`MOSAIC_GREY`), decks em madeira (`WOODFLOOR`), o par de combate em tapete (`CARPET`) e o espaço de eventos no outro tapete (`CARPET2`).
- **Portal:** o `multiplayer_portal` fica fora da mesa, num pátio de pedra de 3 x 3 encostado na moldura, na altura do combate, do lado oposto aos eventos, e o jogador nasce ao lado dele. No layout o pátio fica a oeste; com o eixo x espelhado pelo gerador (`flip_x` em `map/object_layout.lua`, medido na US #30) ele aparece a **leste** da mesa. A calibração descobre o espelhamento sozinha (ver abaixo).
- **Orientação dos eixos:** medido no jogo, a coluna do layout **decresce** com o `x` do mundo (eixo x espelhado pelo gerador; com a grade 20 x 20 da US #30 deu `x_tile = 38 - col`) e a linha cresce com o `z`. A calibração detecta o espelhamento sozinha.
- **Sem cavernas:** o servidor sobe só o shard Master; não há buracos (`cave_entrance`) na mesa.
- **Relógio e clima:** o relógio nasce travado (US #31, abaixo). Deve ficar no outono (outono muito longo, as outras três estações em `noseason`; a tela exige pelo menos uma estação, e a US #31 ainda trava a estação) e sem chuva, raios nem geada.
- **Console útil:** `c_select()` em cima do portal e `TheWorld.Map:GetTileCoordsAtPoint(c_sel().Transform:GetWorldPosition())` dão a posição do portal; `TheWorld.Map:GetTile(x, y)` confirma o tile.
- **Meio tile de diferença:** o gerador pode deslocar os objetos do layout em meio tile (2 unidades) em relação à grade do chão (`map/object_layout.lua` centra objetos e tiles de formas diferentes). Por isso a calibração acha a origem da mesa pelos próprios tiles (os 4 tiles de estrutura) e o espelhamento pelo lado da coluna de eventos; o portal só diz onde procurar e serve de conferência.

Resultado esperado: um mundo só com a mesa e o portal, sem nada para coletar, sem noite perigosa fora o escuro, e um log limpo de erros do mod (`server_log.txt` do shard Master).

## O que conferir na US #31 (nada do mundo interfere no duelo)

Os testes automáticos (`tests/test_mod_protecao.lua`) rodam `relogio.lua` e `protecao.lua` com um ambiente falso: conferem que o wrapper do relógio chama o original com `dt = 0` travado e com o `dt` real livre, que `avancar(n)` anda `n × SEG_TIME`, que `travar`/`liberar` escrevem na variável de rede, que o servidor manda 5/5/6 e as quatro estações com duração 0 (o nível deixa o outono longo, e aqui ele também trava), e que o post init do jogador faz as chamadas certas em cada lado. O que segue só se confirma no jogo, de preferência com **host + um cliente** (o cliente precisa do mod: `all_clients_require_mod`).

**Opção do mod.** Em **Mods → DST Card Game → Configurar**, a opção **Relógio do mundo** tem `Travado` (padrão) e `Livre`. Com `Livre` o mundo se comporta como o jogo normal (serve de comparação); o resto desta lista assume `Travado`.

**Relógio parado.**

- O ponteiro do relógio no canto da tela não anda, nem no host nem no cliente. A luz não muda. `TheWorld.state.time` e `TheWorld.state.timeinphase` no console devolvem sempre o mesmo valor.
- `DUELO.Relogio.avancar(1)` no console do **host** anda exatamente um segmento (1/16 do relógio): o ponteiro pula uma fatia nos dois lados, sem tremer, e `TheWorld.state.time` sobe 1/16 = 0,0625. Se o cliente ficar para trás ou pular de forma diferente, a sincronia pelas netvars do `clock` não aconteceu como a investigação previu.
- `DUELO.Relogio.avancar(0.5)` anda meio segmento no host. **No cliente** ele só aparece no próximo passo que atravessar um segmento: o `clock` só sincroniza os clientes na troca de segmento. Os passos da partida (meio período = 2,5 ou 3 segmentos) sempre atravessam.
- `c_skip()` com o relógio travado não anda o tempo (o `LongUpdate` passa pelo mesmo bloqueio); use `avancar`.
- `DUELO.Relogio.avancar(5)` a partir do começo do dia troca para o entardecer (`TheWorld.state.phase` → `"dusk"`); mais 5 vai para a noite; mais 6 volta ao dia e `TheWorld.state.cycles` sobe 1. A estação continua `autumn` (`TheWorld.state.season`).
- `DUELO.Relogio.liberar()` deixa o tempo correr nos dois lados; `DUELO.Relogio.travar()` para de novo. No cliente os três comandos só imprimem um aviso (`[duelo] ...`).
- **Divisão 5/5/6:** o relógio da tela mostra 5 fatias de dia, 5 de entardecer e 6 de noite (no outono normal seriam 8/6/2). Depois de um ciclo completo (`avancar(16)`) a divisão continua 5/5/6, o que confirma que o `seasons` passou a reenviar os nossos segmentos. Num mundo criado antes desta correção, o relógio volta a 5/5/6 na próxima vez que o servidor subir (o mod reaplica depois da carga).

**Noite sem Charlie.**

- Com o relógio na noite (`avancar` até `TheWorld.state.phase == "night"`), ficar parado no escuro, longe do portal, não dá o aviso nem o ataque do Charlie, no host e no cliente.
- A noite continua com cara de noite (escura, sem o filtro verde do chapéu de toupeira), mas dá para ver a mesa.
- O Charlie fica parado por dois motivos ao mesmo tempo: visão noturna e invencibilidade (`components/grue.lua` respeita as duas). Desligar só a visão noturna não o traz de volta; não há comparação simples sem desligar a proteção inteira.

**Vida, fome e sanidade paradas.**

- As três barras não se mexem com o tempo (deixe o relógio livre por alguns minutos para ter certeza).
- Bater em si (no console do **host**; no cliente `components.health` não existe): `ThePlayer.components.health:DoDelta(-50)` não tira vida (`DoDelta` ignora o dano com `invincible`); `ThePlayer.components.hunger:DoDelta(-50)` tira fome (é uma chamada direta), mas ela não volta a cair sozinha; `ThePlayer.components.sanity:DoDelta(-50)` não muda nada (`sanity.ignore` faz o `DoDelta` retornar antes). `c_godmode()` **alterna** a invencibilidade (`consolecommands.lua`): ele imprime `God mode: false`, mas no instante seguinte o mod a religa e `IsInvincible()` volta a `true`; é uma forma de testar a reaplicação.
- `ThePlayer.components.health:IsInvincible()` devolve `true` no host. Depois de sair e entrar de novo com o mesmo jogador, continua `true` (o jogo desliga a invencibilidade 1,5 s depois da ativação ao recarregar um jogador salvo; o mod a religa pelo evento `invincibletoggle`).
- `ThePlayer.components.temperature:GetCurrent()` fica em 35 mesmo de noite.
- Com `Livre` e o relógio correndo, as barras também não mexem: a proteção não depende do relógio.

**Log limpo.** `server_log.txt` do shard Master e `client_log.txt` sem erros do mod; procure por `duelo` para ver os avisos dos comandos.

## O que conferir na US #30 (mesa de tiles, números e câmera)

Os tiles da mesa já vêm da geração (US #29). Os testes automáticos (`tests/test_mod_mesa.lua`) conferem a calibração com um modelo do mundo com e sem o espelhamento medido, as posições e a numeração de todos os espaços (inclusive a mesa desenhada como a câmera de cada jogador a mostra), e rodam `calibracao.lua`, `marcadores.lua`, `contornos.lua`, `camera.lua` e o prefab `duelo_marcador` com um ambiente falso (servidor, cliente e dedicado). O que segue só se confirma no jogo, com **host + um cliente**. O layout, os rótulos e os números desta seção são os do bug #147 (seção seguinte).

**Calibração.** Medido no jogo (issue #30, grade 20 x 20 antiga): `TheWorld.Map:GetTileCoordsAtPoint` deu o portal no tile (35, 29) e um ponto do carpete central no tile (29, 28): o gerador espelhou o eixo x (`flip_x = -1` em `map/object_layout.lua`); o eixo z não (`flip_y = 1`). O mod não usa esses números: ao carregar o mundo, o servidor acha o `multiplayer_portal`, lê os tiles em volta (20 para cada lado) e procura dois padrões:

- os 4 tiles de estrutura (`MOSAIC_GREY`, os únicos com esse piso), nos cantos de um retângulo de 3 x 12 tiles (2 colunas e 11 linhas entre os centros). O centro do retângulo é o ponto entre os dois quadrados de combate, e dele sai a origem;
- os 2 tiles do espaço de eventos (`CARPET2`, os únicos com esse piso), que ficam de um lado só das estruturas: o lado em que eles aparecem diz se o eixo x foi espelhado. A geometria não depende mais do portal, que só diz onde procurar e serve de conferência.

Sem os tiles de eventos, o espelhamento sai do lado do portal e o log avisa. Sem as estruturas, a origem sai só do portal (`espelhado = true`) e o log avisa.

- No `server_log.txt` deve aparecer `[duelo] mesa calibrada pelas estruturas: origem (...), espelhado = true (eventos), portal no tile (...)`, sem `[duelo] ... dos 36 tiles de espaço não estão sobre os tiles esperados`, `estruturas da mesa não achadas`, `coluna de eventos não achada`, `portal ... longe do esperado` nem `o lado do portal não bate`.
- Console do host: `DUELO.Mesa.calibracao` mostra `origem_x`, `origem_z`, `espelhado`, `fonte`. No cliente, a mesma tabela chega pela rede (`fonte = "estruturas"`).
- `DUELO.Calibracao.calibrar()` no host refaz a calibração e recria os marcadores e os contornos (não duplica).

**Marcadores.**

- Em cada espaço de criatura aparece `J1 1` … `J1 6` (azul) do lado do jogador 1 e `J2 1` … `J2 6` (vermelho) do lado do 2, **no tile da carta** (o de trás, longe do centro). Na fileira de trás de cada jogador, da esquerda para a direita dele: `Deck`, `E1`, `E2`, `Extra` (com o `J1`/`J2` na frente), atrás dos espaços 1, 3, 4 e 6; os do próprio lado precisam aparecer **acima da barra de inventário** (a câmera fica deslocada para o lado de quem olha por isso). Entre os dois quadrados de combate, `Combate`; entre os 2 tiles do espaço de eventos, `Eventos` (os dois em amarelo claro, sem dono). Os textos ficam de pé e legíveis com a câmera da mesa, no host e no cliente.
- Cada jogador lê os seus números da esquerda para a direita (`1` à esquerda), e o espaço `n` de um fica de frente para o `7 - n` do outro.
- Os marcadores não são clicáveis (o mouse não mostra nome nem ação sobre eles) e não bloqueiam o andar.
- Depois de salvar e recarregar o mundo continuam 22 (não persistem; o servidor os recria): `c_countprefabs("duelo_marcador")` dá 22.

**Câmera.**

- Ao entrar, a câmera fica parada no centro da mesa e mostra as 14 linhas da mesa (as duas fileiras de trás, as cartas, as criaturas e o par de combate) e a coluna de eventos; andar com o personagem não a move. A conta do enquadramento está no cabeçalho de `scripts/duelo/mod/camera.lua` (distância 80, a máxima; alvo no centro geométrico da mesa, 8 unidades para o lado de quem olha).
- Q e E (e o analógico do controle) não giram a câmera; o zoom (roda do mouse) continua, entre 30 e 80. Como a mesa pede a distância máxima, o zoom só aproxima.
- O primeiro jogador a entrar é o jogador 1 e vê o lado sul (as suas criaturas, `J1`) embaixo; o segundo é o jogador 2 e vê a mesa **invertida**, com os `J2` embaixo. Um terceiro (espectador) vê como o jogador 1. `ThePlayer.duelo_lado:value()` no console de cada um dá 1, 2 ou 3.
- Sair e voltar com o mesmo usuário devolve o mesmo lado, se ele ainda estiver livre.
- Teleportar (`c_teleport(...)`) ou outros eventos que resetam a câmera não a tiram da mesa nem do heading.
- `DUELO.Camera.liberar()` no console do cliente devolve a câmera normal (segue o jogador, Q/E giram); `DUELO.Camera.aplicar()` trava de novo.
- `TheCamera:GetHeadingTarget()` dá 90 no jogador 1 e 270 no jogador 2. Se a tela mostrar o próprio lado em cima, a convenção de heading de `cameras/followcamera.lua` (`GetDownVec`) não é a que o mod supõe; anotar.
- Com a câmera travada, o mapa (M) também não gira: os botões de girar o mapa chamam o mesmo `RotLeft`/`RotRight`.

**Log limpo.** `server_log.txt` e `client_log.txt` sem erros do mod; procure por `duelo` para ver a calibração e os avisos.

## Layout da mesa (bug #147)

A mesa da US #29/#30 foi refeita duas vezes no bug #147: primeiro com o layout aprovado na #30 (13 x 11, com uma fileira inteira de combate) e, depois do teste em jogo, com os ajustes pedidos pelo dono, que são o que vale. Visto pelo jogador 1, que fica embaixo (R = paralelepípedos, K = carta, V = criatura, E = estrutura, P = deck principal, X = deck extra, A/D = combate, e = eventos):

```text
R R R R R R R R R R R R R R R
R X R R R E R E R R R P R R R     J2
R R R R R R R R R R R R R R R
R K R K R K R K R K R K R R R
R V R V R V R V R V R V R R R
R R R R R R R R R R R R R R R
R R R R R R D R R R R R R e R
R R R R R R A R R R R R R e R
R R R R R R R R R R R R R R R
R V R V R V R V R V R V R R R
R K R K R K R K R K R K R R R
R R R R R R R R R R R R R R R
R P R R R E R E R R R X R R R     J1
R R R R R R R R R R R R R R R
```

A grade do static layout continua 21 x 21 (quadrada, `map/object_layout.lua` usa `#ground` nos dois eixos; é o tamanho já gerado no jogo com `world_size = "small"`): a mesa 15 x 14, uma moldura de 1 tile de pedra em volta, o pátio do portal 3 x 3 encostado na moldura e o resto fora (0 = o terreno intransitável da sala `Blank`). Na largura cabe justo (coluna 0 fora, pátio, moldura, mesa, moldura). O portal e o spawn ficam no centro do tile (2, 10): um objeto posto no centro de um tile cai num número inteiro de tiles na conta do gerador, com a grade par ou ímpar (cabeçalho de `mesa.lua`). O mapa é gerado por `Mesa.mapa_ascii()` e o teste confere que o cabeçalho de `mesa.lua` é igual a ele ("." = fora, "o" = pedra, "A" = combate do jogador 1, "D" = combate do jogador 2, "@" = portal):

```text
col           1         2
    012345678901234567890
 0  .....................
 1  .....................
 2  ....ooooooooooooooooo   moldura
 3  ....oRRRRRRRRRRRRRRRo
 4  ....oRXRRRERERRRPRRRo   decks e estruturas do jogador 2 (norte)
 5  ....oRRRRRRRRRRRRRRRo
 6  ....oRKRKRKRKRKRKRRRo   cartas do jogador 2
 7  ....oRVRVRVRVRVRVRRRo   criaturas do jogador 2
 8  ....oRRRRRRRRRRRRRRRo
 9  .ooooRRRRRRDRRRRRReRo   combate do jogador 2; pilha de eventos
10  .o@ooRRRRRRARRRRRReRo   combate do jogador 1; evento em vigor
11  .ooooRRRRRRRRRRRRRRRo
12  ....oRVRVRVRVRVRVRRRo   criaturas do jogador 1 (sul)
13  ....oRKRKRKRKRKRKRRRo   cartas do jogador 1
14  ....oRRRRRRRRRRRRRRRo
15  ....oRPRRRERERRRXRRRo   decks e estruturas do jogador 1
16  ....oRRRRRRRRRRRRRRRo
17  ....ooooooooooooooooo   moldura
18  .....................
19  .....................
20  .....................
```

- **Espaço de criatura com 2 tiles:** carta atrás (número, cor do dono e, nas próximas US, as informações da carta) e criatura na frente, virada para o centro. Uma carta de Turf cobre os 2 tiles do espaço.
- **Combate:** não é mais a fileira inteira. É um par de quadrados no centro da mesa, um por jogador, um em cima do outro, cada um do lado do seu dono (`Mesa.espaco_combate(p)`, `Mesa.espaco_combate_abs(p)`). Cada duelo acontece ali, um de cada vez: o quadrado de quem tem o token de ataque é o do atacante e o outro o do defensor (lógica da US #34; aqui só o espaço). O espaço de criatura não tem mais um tile de combate próprio.
- **Fileira de trás:** na numeração de cada jogador, o deck principal atrás do espaço 1, as estruturas atrás dos espaços 3 e 4 e o deck extra atrás do 6 (`Mesa.espaco_deck(p, "principal" | "extra")`, `Mesa.espaco_estrutura(p, n)` e as versões `_abs`). Como o espaço `n` de um fica de frente para o `7 - n` do outro, o principal de um e o extra do outro ficam na mesma coluna.
- **Eventos:** um espaço só, neutro, de 2 tiles (como um espaço de carta), numa coluna própria na borda oposta ao portal, alinhado às duas linhas de combate, com 1 coluna de paralelepípedos entre ele e a última coluna de cartas. Os eventos dos dois jogadores vão para uma pilha só e são sorteados pelo dado: o tile do lado do jogador 2 é a pilha e o do lado do jogador 1 é o evento em vigor (`Mesa.espaco_evento()` devolve `pilha` e `em_vigor`; `Mesa.espaco_evento_abs()` também o `centro`). O lado e as linhas são uma suposição registrada; mudam em `COLUNA_EVENTO` e `LINHAS_EVENTO`, no começo de `mesa.lua`, e o layout, a calibração, os contornos e o rótulo acompanham.
- **Tiles** (índices de `GROUND_TYPES` em `map/static_layout.lua`): paralelepípedos = `ROAD` (2), o chão da mesa; pedra = `ROCKY` (3), a moldura e o pátio; carta e criatura sem turf = `CHECKER` (11); estruturas = `MOSAIC_GREY` (47); decks = `WOODFLOOR` (9); combate = `CARPET` (10); eventos = `CARPET2` (50). Os pisos dos decks, do combate e dos eventos são escolhas de aparência e se trocam numa linha de `Mesa.USO`; a calibração só exige que as estruturas e os eventos tenham cada um um piso que mais nada usa. A justificativa completa está no cabeçalho de `scripts/duelo/mod/mesa.lua`.
- **Ordem de desenho:** em `tiledefs.lua` o `ROAD` vem antes de todos os outros tiles da mesa e dos turfs das cartas, então a borda de cada espaço avança sobre os paralelepípedos e o tile aparece inteiro (com o `ROCKY` de antes, o Pântano ficava por baixo). A pedra da moldura avança um pouco sobre os paralelepípedos da borda da mesa, onde não há espaço nenhum.
- **Velocidade:** o `ROAD` é chão de estrada (`roadways` em `tiledefs.lua`): o personagem anda mais rápido sobre a mesa do que na moldura. Não muda nada no duelo.
- **Pátio do portal:** o portal e o `spawnpoint_master` ficam no centro de um pátio de pedra de 3 x 3 encostado na moldura oeste do layout, na altura do combate (no jogo, com o eixo x espelhado, a leste). O jogador nasce ali e anda até a mesa. Ele fica dentro da tela em 16:9, ao lado da mesa, do lado oposto aos eventos.
- **Contornos:** cada tile de espaço (36: 12 cartas, 12 criaturas, 4 estruturas, 4 decks, 2 de combate e 2 de eventos) tem o contorno do `tile_outline` do jogo (o quadrado do `gridplacer`, sem o componente `placer`, que quebrava mods de posicionamento), azul para o J1, vermelho para o J2 e amarelo para o espaço de eventos. As cores dos contornos são saturadas (`Contornos.CORES`): com as cores claras dos rótulos, o do J1 saiu quase branco e o do J2 laranja no jogo. Ele não tem rede, então cada cliente com tela cria os seus a partir da calibração (o servidor dedicado não cria nenhum). `DUELO.Contornos.destacar(p, "criatura" | "estrutura" | "deck" | "combate", n, true)` (ou `0, "evento"`) clareia um espaço (para a US #38 marcar alvos válidos; ainda não é chamado).

**O layout é gerado na criação do mundo:** para ver a mesa nova é preciso **criar um mundo novo**. Um mundo salvo com a mesa anterior continua com os tiles antigos: a calibração avisa `estruturas da mesa não achadas` e cai para a reserva pelo portal, com os espaços fora do lugar.

**O que conferir no jogo (mundo novo, host + um cliente):**

- O chão bate com o mapa acima: paralelepípedos entre os espaços e na borda da mesa, a moldura de pedra em volta, 12 espaços de 2 tiles em xadrez, 4 estruturas em mosaico cinza atrás dos espaços 3 e 4, 4 decks em madeira atrás dos espaços 1 e 6, o par de combate em tapete no centro, o espaço de eventos (2 tiles do outro tapete) na borda oposta ao portal, e o pátio com o portal ao lado da mesa (a leste, se o espelhamento for o medido).
- **Pisos:** os decks, o combate e os eventos se distinguem bem uns dos outros e dos espaços de carta? Se algum piso não agradar, dizer qual trocar.
- `server_log.txt`: `[duelo] mesa calibrada pelas estruturas: ... espelhado = true (eventos) ...`, sem aviso de tiles fora do lugar, de eventos não achados nem do portal.
- **Portal:** o portal e o ponto de nascimento ficam no meio do pátio (no centro de um tile), sem aviso `portal ... longe do esperado` no log.
- Contornos: um quadrado em cada um dos 36 tiles de espaço, **azul nítido** do lado do J1, **vermelho nítido** do J2 e amarelo nos 2 tiles de eventos, no host e no cliente; o mouse não os seleciona e eles não bloqueiam o andar; continuam visíveis à noite. Depois de `DUELO.Calibracao.calibrar()` no host não aparecem contornos duplicados.
- Rótulos: o número de cada espaço de criatura no tile da carta; `Deck`, `E1`, `E2`, `Extra` na fileira de trás de cada jogador, nessa ordem da esquerda para a direita dele; `Combate` entre os dois quadrados de combate; um `Eventos` só, entre os 2 tiles de eventos.
- Câmera: as 14 linhas aparecem inteiras, com a fileira de trás do próprio lado (decks e estruturas) acima da barra de inventário e a do outro lado abaixo do topo da tela; a mesa centrada na largura, com a coluna de eventos de um lado e o portal do outro, os dois dentro da tela; para o J2, a mesa invertida. A distância é a máxima (80): se algo ficar pequeno demais para ler, anotar.
- Geração: os paralelepípedos (`ROAD`) saem inteiros em toda a mesa. O gerador trata `ROAD` como o tile "reservado" dele (`map/forest_map.lua`), o que não deve afetar o nosso layout único, mas é o primeiro ponto a olhar se faltar chão.
- Lado dos eventos: com o espelhamento do gerador (o caso real), o J1 vê os eventos à direita e o portal à esquerda.
- Carta de Turf "Cascalho": é o mesmo paralelepípedo do chão da mesa, então jogada num espaço ela fica igual ao chão em volta; vai precisar de uma marcação visual (decisão registrada na #30).
- Bordas dos turfs (a conferir quando houver cartas de Turf, registrado na #30): com paralelepípedos em volta, o turf de cada carta (Piso de madeira, Pântano, Cascalho) deve aparecer inteiro nos 2 tiles do espaço.
