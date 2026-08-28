# Contribuindo para AI‑Workbench

## Como submeter mudanças
1. **Fork** o repositório e clone a sua fork.
2. Crie uma branch descriptiva (`git checkout -b feat/descricao`).
3. Siga o estilo de código existente (shell‑scripts usam `set -euo pipefail`, Python usa `pytest`).
4. Adicione/atualize testes se a mudança alterar comportamento.
5. Rode os testes locais:
   ```bash
   make doctor   # diagnósticos lint e shellcheck
   pytest -q    # unidades Python
   ```
6. Abra um *Pull Request* na branch `main` com descrição clara e link para issue (se houver).

## Requisitos de desenvolvimento
- Bash ≥ 5, `git`, `make`, `shellcheck` (>=0.9.0).
- Python 3.12 e dependências de teste (`pip install -r requirements-test.txt`).
- Opcional: Docker para validar `services/*` com `docker‑compose up`.

## Boas práticas
- Mantenha scripts pequenos e focados em **um** propósito.
- Use funções auxiliares de `lib/` quando houver lógica reutilizável.
- Não altere arquivos gerados (`reports/`, `logs/`).
- Não comite credenciais ou chaves.

## Política de Licença
Todo o código está licenciado sob MIT – mantenha o cabeçalho de licença nos novos arquivos.
