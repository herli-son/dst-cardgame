# O mod no Don't Starve Together

Este repositório **é** o mod: a raiz dele vira a pasta do mod dentro do jogo. Os arquivos que o jogo lê ficam na raiz (`modinfo.lua`, `modmain.lua`, `modworldgenmain.lua`) e em `scripts/`; o resto (`docs/`, `tests/`, `README.md`) é ignorado pelo jogo.

| Arquivo | Para quê |
|---|---|
| `modinfo.lua` | Ficha do mod: nome, versão, `api_version`, `all_clients_require_mod`. |
| `modworldgenmain.lua` | Geração do mundo: registra o layout da mesa, a task/task set/start location e o nível **Mesa do duelo** (`DUELO_MESA`). |
| `modmain.lua` | Código em jogo (servidor e clientes). Nesta etapa só carrega a geometria da mesa. |
| `scripts/duelo/mod/mesa.lua` | Geometria da mesa: grade de tiles, posição de cada espaço, conversão para unidades do mundo. |
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

## O que conferir no primeiro teste

Os testes automáticos (`tests/test_mod_arena.lua`) só verificam que os arquivos do mod compilam, o que eles registram e os dados do layout. **O código do mod não roda nos testes**, então estes pontos só se confirmam no jogo:

- **Mundo vazio:** nenhum recurso, animal ou monstro nasce. Fora da mesa deve ser vazio (intransitável); a geração não deve mostrar oceano nem outras ilhas. Se aparecer algo (por exemplo, um spawner residual de `prefabs/forest.lua`), anotar o prefab para desligar na próxima US.
- **Mesa visível:** chão xadrez (`CHECKER`) de 16 x 16 tiles com duas linhas de 6 espaços cinza (`MOSAIC_GREY`), dois espaços azuis (`MOSAIC_BLUE`) atrás de cada linha e o centro de carpete (`CARPET`) de 8 x 4 tiles, como o desenho em `scripts/duelo/mod/mesa.lua`.
- **Portal:** o `multiplayer_portal` fica na margem da mesa (coluna 3, fora do caminho das criaturas) e o jogador nasce ao lado dele. Se o portal aparecer na margem **leste** em vez da oeste, o gerador espelhou o eixo x (`flip_x` em `map/object_layout.lua`); isso não quebra a mesa, mas a US #30 precisa passar `espelhado = true` para `Mesa.origem_pelo_portal`/`Mesa.posicao`.
- **Orientação dos eixos:** conferir que a coluna do tile cresce com o `x` do mundo e a linha com o `z` (`TheWorld.Map:GetTileCoordsAtPoint` no console), que é o que `mesa.lua` assume.
- **Sem cavernas:** o servidor sobe só o shard Master; não há buracos (`cave_entrance`) na mesa.
- **Relógio e clima:** o tempo ainda corre normalmente (o travamento é a US #31). Deve ficar no outono para sempre (as quatro estações em `noseason`) e sem chuva, raios nem geada.
- **Console útil:** `c_select()` em cima do portal e `TheWorld.Map:GetTileCoordsAtPoint(c_sel().Transform:GetWorldPosition())` dão a posição do portal; `TheWorld.Map:GetTile(x, y)` confirma o tile.
- **Meio tile de diferença:** o gerador pode deslocar os objetos do layout em meio tile (2 unidades) em relação à grade do chão (`map/object_layout.lua` centra objetos e tiles de formas diferentes). Se a posição do portal não bater exatamente com `Mesa.PORTAL`, a US #30 deve achar a origem da mesa pelos próprios tiles (`GetTileCoordsAtPoint` sobre o carpete central) e usar o portal só para decidir `espelhado`.

Resultado esperado: um mundo só com a mesa e o portal, sem nada para coletar, sem noite perigosa fora o escuro, e um log limpo de erros do mod (`server_log.txt` do shard Master).
