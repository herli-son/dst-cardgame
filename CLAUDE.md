# Instruções do projeto dst-cardgame

## Padrão de commits (obrigatório)

Todo commit deste repositório segue o padrão abaixo, baseado em Conventional Commits. Ele foi adaptado do padrão do time (Azure Boards) para o GitHub: o prefixo `AB#n` virou `#n`, onde `n` é o número da issue no GitHub.

### Estrutura

```text
!#activity - ?activity_type - !type(?scope): !subject

<?body>

<?footer>
```

- `!` = obrigatório; `?` = opcional.
- `#activity`: número da issue principal do commit (normalmente uma Feature ou um Bug). Obrigatório. O GitHub só cria o vínculo depois do `push`.
- `activity_type`: tipo da issue principal, por exemplo `Feature` ou `Bug`. Opcional.
- `type`: obrigatório, um só por commit (lista abaixo).
- `scope`: opcional, recomendado quando ajuda a dizer onde a mudança aconteceu. Vários escopos podem ser separados por `/`, `\` ou `,`.
- `subject`: obrigatório, breve, claro e **no imperativo** (teste: "Se aplicado, este commit vai [subject]").

### Atividades extras

Uma única atividade principal na primeira linha. Atividades adicionais vão abaixo da mensagem principal, no corpo ou no rodapé, uma por linha, no formato `#n`. Elas não substituem a principal.

```text
#12 - Feature - feat(regras): adicionar resolução de combate

#15
#18
```

### Tipos

| Tipo | Uso |
|---|---|
| `feat` | Nova funcionalidade |
| `fix` | Correção de bug |
| `refactor` | Refatoração sem mudar regra de negócio |
| `style` | Formatação ou visual, sem mudar comportamento |
| `test` | Criação ou manutenção de testes |
| `docs` | Documentação |
| `build` | Build ou dependências |
| `perf` | Performance |
| `ci` | Integração contínua |
| `revert` | Reverter commit anterior |

O tipo `promote` (CherryFlow) não se aplica a este projeto.

### Exemplos

```bash
git commit -m "#1 - Feature - docs: adicionar README do projeto"
git commit -m "#7 - Feature - feat(regras): implementar fogueira noturna"
git commit -m "#9 - Bug - fix(combate): corrigir ordem de golpes com Velocidade 3"
git commit -m "#10 - test(regras): adicionar testes de fim de rodada"
```

### Número da feature no commit

Todo commit precisa identificar a feature a que pertence. Se a atividade principal não for a própria feature (por exemplo, uma User Story ou um Bug), inclua o número da feature no fim da mensagem, no rodapé, no formato `Feature: #n`.

```text
#23 - feat(combate): adicionar bloqueio obrigatório de Frágil

Feature: #12
```

### Regras práticas

- Um `type` por commit; se estiver difícil escolher um, o commit está grande demais e deve ser dividido.
- `#activity` e `type` são obrigatórios.
- Prefira commits pequenos e com responsabilidade única.
- Linhas de atribuição exigidas pela ferramenta (por exemplo `Co-Authored-By`) vão no rodapé e não alteram a primeira linha.

### Checklist antes de commitar

- [ ] O `type` está correto.
- [ ] O `#activity` foi informado corretamente.
- [ ] Atividades extras estão abaixo da mensagem principal, no formato `#n`.
- [ ] O `subject` está no imperativo.
- [ ] A mensagem descreve uma única intenção.
- [ ] O `scope` foi adicionado quando ajuda a dar contexto.
- [ ] O commit está pequeno o suficiente para ser entendido isoladamente.

## Estratégia de branches (git flow)

Hierarquia: `main` → `develop` → `feature` → `user`.

| Branch | Nome | Sai de | Volta para | Papel |
|---|---|---|---|---|
| `main` | `main` | | | Versão estável, que está funcionando |
| `develop` | `develop` | `main` | `main` | Versão beta: o que ainda não está pronto para a `main` e o que está em teste |
| Feature | `feature/[n° da feature]` | `develop` | `develop` | Desenvolvimento de uma Feature; uma Feature pode ter várias User Stories |
| User Story | `feature/user/[n° da user story]-[n° da feature]` | a branch da sua Feature | a branch da sua Feature | Onde as Tasks da User Story são desenvolvidas |
| Hotfix | `hotfix/[n° do bug]` | `main` | `main` | Bug encontrado na `main` |
| Bugfix | `bugfix/[n° do bug]` | `develop` | `develop` | Bug encontrado na `develop` |

Exemplos: `feature/12`, `feature/user/23-12`, `hotfix/40`, `bugfix/41`.

Regras:

- `main` e `develop` **nunca** são deletadas.
- As Tasks não têm branch própria: são feitas na branch da sua User Story.
- Depois do merge da User Story na Feature, a branch da User Story é deletada.
- Depois do merge da Feature na `develop`, a branch da Feature é deletada.
- Bugs são resolvidos a partir da branch onde foram encontrados.
- **Hotfix:** sai da `main`. Depois do merge na `main`, delete a branch e faça merge da `main` na `develop`.
- **Bugfix:** sai da `develop`. Depois do merge na `develop`, delete a branch.
- Toda integração entre branches é feita por Pull Request.

Referência: [Conventional Commits](https://www.conventionalcommits.org/pt-br/v1.0.0/)
