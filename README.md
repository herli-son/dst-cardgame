# dst-cardgame

Card game 1 contra 1 inspirado em **Don't Starve**, feito como mod para o **Don't Starve Together**. A estrutura de turnos vem do **Legends of Runeterra**, e o tabuleiro, as cartas e as criaturas usam a arte e as animações do próprio jogo.

> Projeto de fã, gratuito e sem fins lucrativos. Don't Starve, Don't Starve Together e todos os personagens, criaturas e artes pertencem à Klei Entertainment. Este projeto não é afiliado nem endossado pela Klei.

## O que é

Dois jogadores se enfrentam numa arena dentro do Don't Starve Together. Cada um joga com um baralho de 40 cartas, liderado por um Sobrevivente (Wilson, Willow, Wendy, Webber ou Maxwell), e vence quem reduzir a vida do adversário de 20 a zero.

Principais ideias das regras:

- **Rodadas com ataque alternado**, no estilo do Legends of Runeterra: quem tem o token ataca, o outro bloqueia.
- **Ciclo de manhã, tarde e noite** dentro de cada rodada. À noite, a **fogueira** limita quantas cartas cada jogador ainda pode jogar.
- **Dano permanente** nas criaturas, que só sai com cura.
- **Mecânicas tiradas do jogo:** Fogo, Molhado, eletricidade, Sanidade, Fome, comida que estraga, estações e eventos como Chuva e Lua cheia.
- **Chefes** como Rainha aranha, Varget, Klaus, Bee Queen e Formiga-leão.

## Como vai funcionar no jogo

- A **arena** é um mundo mínimo, só com o campo de batalha.
- Os **espaços do tabuleiro** são tiles no chão: 6 para criaturas e 2 para estruturas de cada lado.
- Ao jogar uma carta de criatura, a **criatura de verdade aparece** em cima do tile. Ela fica parada, se move para atacar e usa as animações originais de ataque, dano e morte.
- A **mão é o inventário** de cada jogador, que só ele enxerga.
- Os **efeitos** (fogo, molhado, eletricidade) reaproveitam os efeitos visuais do jogo.
- O **servidor** decide todas as jogadas. Os jogadores só enviam ações e veem o resultado.

## Arquitetura

O projeto é dividido em duas partes, para que as regras possam ser testadas fora do jogo:

1. **Motor de regras**, em Lua 5.1 puro, sem nenhuma dependência do Don't Starve Together. Contém o estado da partida, as cartas e a resolução de cada jogada, e é testado automaticamente.
2. **Mod do Don't Starve Together**, que liga o motor ao mundo: arena, tiles, criaturas, inventário, interface e comunicação entre servidor e jogadores.

## Roteiro

| Entrega | Objetivo |
|---|---|
| M1: Motor de regras | Uma partida completa roda em Lua puro, com testes |
| M2: Mesa no mundo | Arena, tiles, criaturas aparecendo e mão no inventário |
| M3: Partida jogável | Dois jogadores num servidor dedicado jogam do início ao fim |
| M4: Conteúdo completo | Todas as cartas, eventos, estações, Sanidade e Chefes |
| M5: Infraestrutura | Várias partidas ao mesmo tempo, lobby e espectadores |

A primeira versão jogável usa dois decks fixos, **Wilson contra Webber**, com as regras centrais. O restante entra nas entregas seguintes.

## Status

Em planejamento. As regras completas estão escritas e balanceadas; a implementação começa pelo motor de regras.
