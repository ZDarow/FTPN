# CONTRIBUTING

Спасибо за интерес к проекту FPTN.

## Как помочь

1. Создайте ветку от `master` с описательным именем (`kebab-case`).
2. Ведите коммиты на русском, в повелительном наклонении, с Conventional Commits-префиксом.
3. Убедитесь, что затронутые проверки проходят:

   ```bash
   # Backend
   cd fptn-admin/backend
   poetry run black --check app tests
   poetry run pylint app
   poetry run pytest -q

   # Frontend
   cd fptn-admin/frontend
   npm run lint
   npx tsc --noEmit
   npx vitest run
   npm run build

   # Deploy-скрипты
   shellcheck deploy/*.sh deploy/lib/*.sh
   ```

4. Откройте PR с описанием изменений и ссылкой на `docs/AUDIT.md` или `docs/ROADMAP.md`, если применимо.

## Правила

- Секреты — только через `.env`.
- Не коммитьте `*.pem`, `*.key`, `*.secret`, `.env`.
- Не ломайте формат `users.list` и `servers.json` без миграции.
