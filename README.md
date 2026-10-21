# Multiverse

App iOS de comunidade, diário e biblioteca Marvel/DC, com API NestJS/PostgreSQL
e funções Firebase de autenticação por e-mail.

- `apps/ios`: app SwiftUI, widgets e testes; projeto gerado com XcodeGen.
- `backend/api`: API, migrations e testes unitários/HTTP.
- `backend/firebase/functions`: funções Firebase e testes locais.

## Validação

Com as dependências instaladas e Docker em execução:

```sh
make localization-check  # Catálogo completo PT-BR/EN
make api-check           # Formatação, lint, tipos, build e testes com banco temporário
make backend-test        # Firebase Functions
make ios-test            # Build e testes no simulador (macOS/Xcode/XcodeGen)
make test                # Todas as verificações acima
```

Preparação, versões, execução sem Docker e funcionamento do CI estão no
[guia de testes](docs/TESTING.md). O banco temporário é removido ao final;
`make api-check` não utiliza o banco de desenvolvimento nem o de produção.

## Estado do projeto

- [Plano de preparação para lançamento](docs/LAUNCH_READINESS.md): prioridades,
  mocks, critérios de conclusão e progresso.
- [Retomada de sessões](docs/SESSION_HANDOFF.md): histórico das entregas.
- [API](backend/api/README.md) e [iOS](apps/ios/README.md): configuração e detalhes.
