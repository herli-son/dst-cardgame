# Jogar pelo terminal contra o bot

Interface em texto para testar as regras do duelo sem o Don't Starve Together. Roda com Lua 5.1 puro, no Windows, no Linux ou no macOS. Você joga pelo jogador 1; o bot (`scripts/duelo/bot/bot.lua`) joga pelo 2.

## Instalar o Lua 5.1 no Windows

Qualquer interpretador Lua 5.1 serve. Duas opções:

1. **winget** (se o Windows tiver o App Installer): abra o PowerShell e rode

   ```powershell
   winget install rjpcomputing.luaforwindows
   ```

   Esse pacote é o Lua for Windows, com o Lua 5.1. Feche e abra o PowerShell de novo depois da instalação, para o `lua` entrar no `PATH`.

2. **LuaBinaries**: baixe o pacote "lua-5.1.5_Win64_bin.zip" (ou Win32) em <https://luabinaries.sourceforge.net/>, descompacte numa pasta (por exemplo `C:\lua51`) e adicione essa pasta ao `PATH`, ou chame o executável pelo caminho completo (`C:\lua51\lua5.1.exe`).

Para conferir: `lua -v` (ou `lua5.1 -v`) deve mostrar `Lua 5.1.x`.

## Rodar

Abra o PowerShell na pasta do repositório (a que tem `scripts/` e `tests/`). A tela usa acentos em UTF-8, e o console do Windows em português vem com outra codificação, então antes de jogar troque a codificação do console (uma vez por janela):

```powershell
chcp 65001
```

Depois rode:

```powershell
lua scripts\duelo\terminal\jogar.lua
```

Com uma semente, a partida é sempre a mesma (mesmo embaralhamento e mesmas respostas do bot para as mesmas jogadas), o que ajuda a reproduzir um bug:

```powershell
lua scripts\duelo\terminal\jogar.lua 42
```

Se o executável se chamar `lua5.1`, troque `lua` por `lua5.1`. O script acha a pasta `scripts/` a partir do próprio caminho, então também funciona chamado de outra pasta.

Para rodar os testes: `lua tests\runner.lua`.

## A tela

A tela mostra, de cima para baixo: rodada, período (manhã, tarde, noite) e fogueira; vida e mana dos dois jogadores; quem tem o token de ataque e de quem é a vez; a pilha e o combate, quando existem; o campo do oponente (estruturas `oe1`/`oe2` e criaturas `o1`..`o6`); o seu campo (criaturas `c1`..`c6` e estruturas `e1`/`e2`); a sua mão numerada, o Inventário e as cartas separadas, se houver; e a escolha pendente, quando for sua.

Cada criatura aparece com nome, ataque/vida, o dano marcado entre parênteses, a velocidade, as palavras-chave e os equipamentos entre chaves.

Antes de cada tela vêm, uma por linha, as coisas que aconteceram desde a última: jogadas do bot, golpes, mortes, dano aos jogadores, mudanças de período e de rodada.

## Comandos

Os espaços são os mesmos nomes da tela: `c1`..`c6` (minhas criaturas), `o1`..`o6` (criaturas do oponente), `e1`/`e2` e `oe1`/`oe2` (estruturas), `eu` e `ele` (jogadores).

| Comando | O que faz |
|---|---|
| `jogar <n>` | Joga a carta `n` da mão. Uma criatura entra no primeiro espaço livre |
| `jogar <n> em <espaço>` | Escolhe o espaço (`em 3` ou `em c3`); com o campo cheio, use `substituindo c3` |
| `jogar <n> em <alvo>` | Feitiço ou efeito com alvo: `jogar 2 em o4`, `jogar 3 em eu`. Equipamento: `jogar 4 em c2` |
| `jogar <n> sacrificando <espaços>` | Para cartas que pedem sacrifício: `sacrificando c1 c2` |
| `jogar <n> substituindo <espaço>` | Substitui uma criatura (`c3`) ou estrutura (`e1`) com a zona cheia |
| `inv <n>` ou `jogar inv <n>` | Joga a carta `n` do Inventário (aceita os mesmos complementos) |
| `sep <n>` | Joga a carta `n` das separadas |
| `atacar <espaços...>` | Declara o ataque: `atacar c1 c3`. `atacar todos` ataca com todas |
| `bloquear <atacante>=<bloqueador> ...` | Declara os bloqueios na primeira resposta ao ataque: `bloquear o1=c2 o3=c1` |
| `bloquear nada` | Declara que não há bloqueios |
| `ativar <estrutura>` | Ativa o efeito de uma estrutura sua: `ativar e1`; com alvo, `ativar e1 em o2` |
| `ativar <criatura> [mao\|peito\|cabeca]` | Ativa o efeito da criatura ou do equipamento dela: `ativar c2 mao` |
| `escolher <n>` | Responde a escolha pendente; `escolher nada` quando a escolha permitir |
| `passar` | Passa a vez; com a pilha aberta, é o "pronto" |
| `jogadas` | Lista as jogadas válidas numeradas; `j <n>` executa a jogada `n` |
| `ajuda` | Mostra a lista de comandos |
| `sair` | Encerra a partida |

Quando um comando está incompleto, a mensagem diz o que falta (o alvo, o espaço, o sacrifício). Quando o motor recusa a jogada, a mensagem é a do motor (`mana insuficiente`, `não é a sua vez`, `atacante Frágil deve ser bloqueado por uma criatura Agressiva`).

## Exemplo

```text
> jogar 4
Você jogou Coelho (custo 1).
Coelho entra em c1.
O bot jogou Aranha (custo 2).
Aranha entra em o3.
> passar
Fim da rodada 1.
Rodada 2: token de ataque com você.
> jogar 2 em c2
> atacar c1
Você ataca com Coelho.
O bot bloqueia: Aranha bloqueia Coelho.
> passar
Fase rápida:
  Aranha golpeia Coelho por 2.
Coelho (sua) morre por Aranha.
```

## Baralho de demonstração

As cartas vêm de `scripts/duelo/terminal/deck_demo.lua`: criaturas com Frágil, Agressivo e Velocidade 2 e 3, um Sobrevivente que usa equipamentos, um feitiço com alvo (Raio), um instantâneo que cura (Curativo), uma estrutura ativável (Tocha) e dois equipamentos (Lanca e Armadura de grama). São cartas de exemplo para testar o motor, não as cartas do jogo. Para testar outras cartas, defina-as com `Cards.define` e troque os baralhos em `jogar.lua`.
