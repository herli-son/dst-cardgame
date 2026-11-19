# O mod no Don't Starve Together

Este repositório **é** o mod: a raiz dele vira a pasta do mod dentro do jogo. Os arquivos que o jogo lê ficam na raiz (`modinfo.lua`, `modmain.lua`, `modworldgenmain.lua`) e em `scripts/`; o resto (`docs/`, `tests/`, `README.md`) é ignorado pelo jogo.

| Arquivo | Para quê |
|---|---|
| `modinfo.lua` | Ficha do mod: nome, versão, `api_version`, `all_clients_require_mod`. |
| `modworldgenmain.lua` | Geração do mundo: registra o layout da mesa, a task/task set/start location e o nível **Mesa do duelo** (`DUELO_MESA`). |
| `modmain.lua` | Código em jogo (servidor e clientes). Só liga os módulos de `scripts/duelo/mod/` e expõe `DUELO` (também no console). |
| `scripts/duelo/mod/mesa.lua` | Geometria da mesa: grade de tiles, posição de cada espaço, conversão para unidades do mundo. |
| `scripts/duelo/mod/protecao.lua` | US #31: visão noturna de todos, invencibilidade, fome, sanidade e temperatura paradas. |
| `scripts/duelo/mod/relogio.lua` | US #31: relógio do mundo travado e andado pela partida, divisão 5/5/6, estação fixa. |
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

## O que conferir no primeiro teste

Os testes automáticos (`tests/test_mod_arena.lua`) só verificam que os arquivos do mod compilam, o que eles registram e os dados do layout. **O código do mod não roda nos testes**, então estes pontos só se confirmam no jogo:

- **Mundo vazio:** nenhum recurso, animal ou monstro nasce. Fora da mesa deve ser vazio (intransitável); a geração não deve mostrar oceano nem outras ilhas. Se aparecer algo (por exemplo, um spawner residual de `prefabs/forest.lua`), anotar o prefab para desligar na próxima US.
- **Mesa visível:** chão xadrez (`CHECKER`) de 16 x 16 tiles com duas linhas de 6 espaços cinza (`MOSAIC_GREY`), dois espaços azuis (`MOSAIC_BLUE`) atrás de cada linha e o centro de carpete (`CARPET`) de 8 x 4 tiles, como o desenho em `scripts/duelo/mod/mesa.lua`.
- **Portal:** o `multiplayer_portal` fica na margem da mesa (coluna 3, fora do caminho das criaturas) e o jogador nasce ao lado dele. Se o portal aparecer na margem **leste** em vez da oeste, o gerador espelhou o eixo x (`flip_x` em `map/object_layout.lua`); isso não quebra a mesa, mas a US #30 precisa passar `espelhado = true` para `Mesa.origem_pelo_portal`/`Mesa.posicao`.
- **Orientação dos eixos:** conferir que a coluna do tile cresce com o `x` do mundo e a linha com o `z` (`TheWorld.Map:GetTileCoordsAtPoint` no console), que é o que `mesa.lua` assume.
- **Sem cavernas:** o servidor sobe só o shard Master; não há buracos (`cave_entrance`) na mesa.
- **Relógio e clima:** o relógio nasce travado (US #31, abaixo). Deve ficar no outono (outono muito longo, as outras três estações em `noseason`; a tela exige pelo menos uma estação, e a US #31 ainda trava a estação) e sem chuva, raios nem geada.
- **Console útil:** `c_select()` em cima do portal e `TheWorld.Map:GetTileCoordsAtPoint(c_sel().Transform:GetWorldPosition())` dão a posição do portal; `TheWorld.Map:GetTile(x, y)` confirma o tile.
- **Meio tile de diferença:** o gerador pode deslocar os objetos do layout em meio tile (2 unidades) em relação à grade do chão (`map/object_layout.lua` centra objetos e tiles de formas diferentes). Se a posição do portal não bater exatamente com `Mesa.PORTAL`, a US #30 deve achar a origem da mesa pelos próprios tiles (`GetTileCoordsAtPoint` sobre o carpete central) e usar o portal só para decidir `espelhado`.

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
