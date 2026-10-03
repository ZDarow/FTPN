# AGENTS.md — FPTN

Правила, контекст и гайдлайны для AI-агентов, работающих в этом репозитории.
Документ самодостаточен: агент, прочитавший только его, должен понять, где что лежит,
как собрать, как проверить и чего делать нельзя.

---

## 1. Что это за проект

**FPTN** (Fast Protected Tunnel Network) — VPN с защитой от DPI. Трафик маскируется под
легитимный HTTPS, используется техника **Reality** и пул **rolling-туннелей** (3 параллельных
канала с общим SessionID).

| Параметр | Значение |
|----------|----------|
| Версия | 0.4.4 |
| Лицензия | MIT |
| Форк | `github.com/batchar2/fptn` |
| Нас | `github.com/ZDarow/FTPN` |
| Назначение | VPN-сервер + веб-панель админа + Telegram-бот |

Репозиторий — **монорепо с четырьмя независимыми стеками**. Между ними нет общей сборки:
каждый стек собирается, тестируется и версионируется отдельно. Любая правка в одном стеке
не должна требовать изменений в остальных, кроме случая изменения API/протокола.

---

## 2. Структура репозитория

```
FTPN/
├── fptn/                  # C++20 ядро (сервер, клиент, протокол)   — 143 .cpp/.h, ~22.9k LOC
│   ├── src/               # common, fptn-server, fptn-client, fptn-protocol-lib, fptn-passwd
│   ├── tests/             # 16 gtest-файлов, ~3.1k LOC
│   ├── docker-compose/    # compose VPN-сервера (privileged)
│   └── sysadmin-tools/    # grafana/, telegram-bot/ (пользовательский, legacy)
├── fptn-admin/            # Веб-панель: два независимых стека
│   ├── backend/           # Python 3.13, FastAPI, Poetry
│   └── frontend/          # React 18 + TypeScript + Vite
├── fptn-admin-bot/        # Telegram-бот на Python (отдельный, минимальный стек)
├── deploy/                # bash-скрипты установки на сервер (только Linux)
│   └── lib/               # tui.sh, install-manager.sh
├── docs/                  # AUDIT.md, DEPENDENCIES-AUDIT.md, DOCUMENTATION.md, plan.md, ROADMAP.md
├── fptn-manager           # gitlink (CLI-менеджер от FarazFe) — НЕ редактировать
├── .vscode/               # Настройки и рекомендации расширений
└── AGENTS.md              # этот файл
```

### 2.1 Ключевые файлы каждого стека

| Стек | Манифест | Точка входа | Тесты |
|------|----------|-------------|-------|
| C++ | `fptn/CMakeLists.txt`, `fptn/conanfile.py` | `src/fptn-server/fptn-server.cpp` | `fptn/tests/` |
| Backend | `fptn-admin/backend/pyproject.toml` | `app/main.py` | `backend/tests/` (7 файлов, 521 LOC) |
| Frontend | `fptn-admin/frontend/package.json` | `src/main.tsx` → `src/App.tsx` | `src/**/*.test.ts(x)` (4 файла) |
| Бот | `fptn-admin-bot/requirements.txt` | `src/bot.py` | **нет** |
| Deploy | — | 6 скриптов + `lib/` | **нет** |

### 2.2 Backend: карта модулей

```
app/
├── main.py            # FastAPI, lifespan, CORS, роутеры, /health
├── config.py          # Pydantic Settings, env_file=".env"
├── security.py        # create_access_token / get_current_admin (JWT HS256, bearer)
├── secret.py          # get_jwt_secret() — читает/генерирует /etc/fptn/jwt_secret
├── deps.py            # синглтоны admin_store, bot_settings_store, ...
├── schemas.py         # Pydantic-схемы запросов/ответов
├── exceptions.py      # register_exception_handlers
├── vpn_token.py       # сборка access-токена VPN-пользователя
├── telegram_bot.py    # бот внутри процесса backend (поток)
├── routers/           # auth, users, servers, dashboard, settings  → префикс /api/v1
└── stores/            # JSON-хранилища с fcntl-локом:
                       #   admin_store, vpn_user_store, server_store, bot_settings_store
```

Хранилище — **файловое**, пути из `Settings` (`/etc/fptn/...`, см. `config.py:9-27`).
Базы данных нет, миграций нет. Любой store работает через «прочитай JSON → измени → запиши атомарно».

### 2.3 Frontend: карта модулей

```
src/
├── main.tsx / App.tsx        # Точка входа, RequireAuth, маршруты
├── api/                      # client.ts (fetch-обёртка) + auth/users/servers/dashboard/settings
├── context/AuthContext.tsx   # JWT в localStorage (S6 — см. §7)
├── components/
│   ├── layout/               # DashboardLayout, Header, Sidebar, LanguageSwitcher
│   └── ui/                   # Button, Modal, Pagination, Spinner, Table
├── pages/                    # Login, Dashboard, Users, Servers, TelegramBot,
│                             #   GivePremiumAccess, ChangePassword, ComingSoon
├── i18n/                     # ru.json / en.json, i18next
├── lib/fptnToken.ts          # парс/сборка токена VPN-пользователя (brotli-wasm)
└── theme/ThemeProvider.tsx
```

---

## 3. Технологический стек (версии зафиксированы — не обновлять без согласования)

### 3.1 C++20 ядро

CMake ≥ 3.18 · Conan 2 (`CMakeDeps`) · Boost 1.90.0 (Asio, coroutines) · protobuf 5.29.3 (lite)
· fmt 12.1.0 · spdlog 1.17.0 · boringssl · brotli 1.2.0 · cpp-httplib 0.46.1 · jwt-cpp 0.7.2
· nlohmann_json 3.12.0 · re2 · zlib 1.3.2 · argparse 3.2

Определения по умолчанию задаются в `fptn/CMakeLists.txt` (`FPTN_DEFAULT_SNI`, MTU 1420,
`FPTN_IP_PACKET_MAX_SIZE=1400`, split-tunnel домены, blacklist доменов).

### 3.2 Backend

Python **>=3.13,<3.14** · FastAPI 0.115.6 · uvicorn[standard] 0.34.0 · pydantic-settings 2.7.1
· PyJWT 2.10.1 · bcrypt 4.2.1 · brotli 1.1.0 · python-telegram-bot 21.11.1

Dev: pytest ≥8 · httpx · black 120 · pylint 120 · pip-audit.
**ruff и mypy НЕ подключены** — не предлагай их как проверку, пока их нет в `pyproject.toml`.
`DOCUMENTATION.md` в разделе «Стиль Python» устарел и указывает mypy strict — при расхождении
ориентируйся на `pyproject.toml`.

### 3.3 Frontend

React 18.3.1 · TypeScript 5.4 · Vite 5.4 · Tailwind 3.4 · react-router-dom 7.18.3 · vitest 2.1.8
· i18next 23 / react-i18next 14 · lucide-react 0.469 · brotli-wasm 3.0.1
· ESLint 8.57 (+ prettier, import) · husky + commitlint (Conventional Commits)

В `package.json` есть 16 `overrides` — они закрывают известные CVE транзитивных зависимостей
(`@babel/traverse`, `rollup`, `lodash`, `minimatch`, `esbuild` и др.). **Не удаляй `overrides`
без проверки `npm audit`.**

### 3.4 Инфраструктура

Docker + готовые образы `fptnvpn/*` с DockerHub · bash-скрипты с TUI (whiptail > dialog > stdin) ·
GitHub Actions: **два** workflow — `fptn-admin/.github/workflows/ci.yml` (backend + frontend) и
`fptn/.github/workflows/main.yml` (C++: conan + cpplint + cppcheck + ctest, 4 платформы) ·
Renovate — только Conan.

**Оба workflow лежат в подкаталогах, а не в `.github/workflows/` в корне** — GitHub Actions
читает только корневой путь, поэтому сейчас не выполняется ни один из них. Любая правка
о CI ниже описывает задуманное состояние, а не фактическое.

---

## 4. Команды разработчика

> На Windows рабочая среда для C++ и deploy-скриптов **нерабочая**. Используй WSL2 или Linux.
> Backend и frontend на Windows работают.

### 4.1 Backend (`fptn-admin/backend/`)

```bash
cd fptn-admin/backend
poetry install                      # обязательно под Python 3.13
poetry run pytest -q                # тесты
poetry run black --check app tests  # форматирование (120)
poetry run pylint app               # линтер (120)
poetry run pip-audit                # аудит зависимостей
```

### 4.2 Frontend (`fptn-admin/frontend/`)

```bash
cd fptn-admin/frontend
npm ci
npm run lint                        # eslint
npx tsc --noEmit                    # типы
npx vitest run                      # тесты (НЕ npm run test — он запускает watch!)
npm run build                       # tsc && vite build
npm run audit:report                # JSON-отчёт npm audit
```

### 4.3 C++ (`fptn/`)

```bash
cd fptn
export FPTN_VERSION=0.4.4           # без него conan-версия = 0.0.0
conan install . --output-folder=build --build=missing
cmake -B build -S .
cmake --build build --parallel
ctest --test-dir build
```

### 4.4 Docker

```bash
cd fptn/docker-compose       && docker compose up -d   # VPN-сервер (privileged!)
cd fptn-admin                && docker compose up -d   # панель: backend 8000, frontend 2663/8080
cd fptn-admin-bot            && docker compose up -d   # бот (docker.sock!)
```

Сеть `fptn-network` объявляется в `fptn/docker-compose/docker-compose.yml` и используется
`fptn-admin-bot` как `external`.

### 4.5 Deploy

Все скрипты требуют **root** и, кроме `prereq-install.sh`/`configure.sh`, наличия
уже развёрнутого клона в `/opt/fptn` (`install-admin.sh:19,24` завершается с `exit 1` иначе).
То есть порядок такой: склонировать репозиторий в `/opt/fptn` и запускать скрипты оттуда.

```bash
sudo bash /opt/fptn/deploy/prereq-install.sh   # Docker, nginx, certbot, UFW
sudo bash /opt/fptn/deploy/install.sh          # VPN-сервер, TUI
sudo bash /opt/fptn/deploy/install-admin.sh    # панель, TUI
sudo bash /opt/fptn/deploy/configure.sh        # перенастройка .env, TUI
```

**`install-bot.sh` ставит не `fptn-admin-bot`, а legacy-бота** из
`fptn/sysadmin-tools/telegram-bot` (`install-bot.sh:32,98`). Стек `fptn-admin-bot`
(тот, на который указывает находка S10 с `docker.sock`) разворачивается отдельно, по §4.4.

`deploy/uninstall.sh` заканчивается `rm -rf /opt/fptn` и **агентам запрещён** (§8).
Он приведён здесь только для полноты и запускается вручную оператором.

Полный воркфлоу сервера: `docs/plan.md` — **устарел**: клонирует upstream
`batchar2/fptn` (без панели и `fptn-admin-bot`) и ссылается на несуществующий `deploy/family/`.
Ориентируйся на скрипты выше.

---

## 5. Правила оформления кода и репозитория

- **Язык**: комментарии и документация — русский; идентификаторы — английский
  (`snake_case` для функций/переменных Python, `CamelCase` для классов и TS-компонентов,
  `SCREAMING_SNAKE` для CMake-опций).
- **Коммиты**: русский, повелительное наклонение, Conventional Commits-префикс —
  `feat(bot):`, `fix(backend):`, `refactor(deploy):`, `docs:`, `chore:`.
  Фронтенд дополнительно валидируется husky + commitlint (footer `Signed-off-by` не требуется).
- **Ветки**: `kebab-case` на английском — `fix/auth-rate-limit`, `refactor/session-cpp`,
  `test/bot-coverage`.
- **Lock-файлы коммитить**: `poetry.lock`, `package-lock.json`. `conan.lock` — в `.gitignore`.
- **PR-описание**: на русском, со ссылкой на пункт `docs/AUDIT.md` или `docs/ROADMAP.md`.
- **Стиль Python**: black 120. Линтер pylint; в `pyproject.toml` отключены
  `duplicate-code`, `too-many-arguments`, `missing-*-docstring` — не пытайся «чинить» код,
  добавляя docstring'и ради линтера, но и не добавляй новые отключения без согласования.
- **Стиль TypeScript**: `strict` через `tsc --noEmit`, без `any`, без `console.log`,
  функциональные компоненты + хуки (классов в коде нет — не вводи).
- **Стиль C++**: Google-стиль, `clang-format` при наличии `.clang-format`, без `using namespace`
  в заголовках, RAII, без голого `new`/`delete`.

---

## 6. Правила безопасности (нарушение = блокирующий баг)

1. **Секреты — только через `.env`.** Никогда не хардкодь токены, пароли, JWT-секреты,
   Telegram-токены в коде. Шаблоны — `.env.demo` / `.env.example` (коммитятся),
   рабочие — `.env` (игнорируются).
2. **Никогда не выводи секреты в лог/ответ.** В логах маскируй: `sk-****abcd`.
   Уже сделано для httpx в `app/main.py:20-21` (URL Telegram API содержит токен).
3. **Не коммитить** `.env`, `*.pem`, `*.key`, `*.p12`, `*.secret`, `users.list`, `admins.json`,
   `bot_settings.json`, `servers*.json`, `jwt_secret`.
4. **Аутентификация**: JWT HS256 (`app/security.py`), bcrypt для паролей админа.
   Не добавляй эндпоинты без проверки `Depends(get_current_admin)`.
5. **Privilege escalation через Docker**: `fptn/docker-compose/docker-compose.yml` —
   `privileged: true` + `cap_add: SYS_ADMIN|SYS_MODULE|NET_ADMIN|NET_RAW|SYS_RESOURCE`.
   `fptn-admin-bot/docker-compose.yml:20` монтирует `/var/run/docker.sock` в **rw**.
   Правки сюда — только с явным согласованием и комментарием в PR о радиусе компрометации.
6. **Ввод пользователя в shell**: `subprocess` — только списком аргументов, `shell=False`.
   Имя сервиса для `docker logs|restart` — **обязательно** проверять по whitelist
   (сейчас в `fptn-admin-bot/src/bot.py` есть путь из callback-данных в `docker restart` без валидации).
7. **Изменение криптографии хранилища пользователей** (bcrypt/argon2, соль, формат `users.list`)
   требует синхронной правки C++-сервера — пароли сверяются на его стороне.
8. `git push` не выполнять без явного указания.

---

## 7. Известные проблемы (проверено по коду на 2026-10)

Полные списки с приоритетами: `docs/AUDIT.md`, `docs/DEPENDENCIES-AUDIT.md`, план работ — `docs/ROADMAP.md`.

> **Про ID.** Эта таблица использует собственное пространство идентификаторов, которое
> **не совпадает** с `docs/AUDIT.md` (там `S8` — про httponly cookies, `S10` — про Telegram-токен
> в `bot_settings.json`, а `I1`–`I3` сдвинуты). При работе с `docs/ROADMAP.md` сверяйся с
> колонкой «Источник» там, а не с этим разделом; при расхождении считать верным `pyproject.toml`
> и фактический код.

| ID | Проблема | Место |
|----|----------|-------|
| S1 | SHA-256 без соли для паролей VPN-пользователей | `bot.py:89-92`, `stores/vpn_user_store.py` |
| S2 | Пароль пользователя внутри access-токена открытым текстом | `app/vpn_token.py` |
| S3 | `cors_origins = "*"` по умолчанию | `app/config.py:34` |
| S5 | Нет rate-limiting на `/auth/login` | `app/routers/auth.py` |
| S6 | JWT в `localStorage` без httponly-альтернативы | `frontend/src/context/AuthContext.tsx` |
| S7 | Самоподписанный TLS-сертификат на 10 лет в nginx-entrypoint | `fptn-admin/frontend/docker-entrypoint.sh` |
| S8 | `ADMIN_LOGIN=admin` / `ADMIN_PASSWORD=admin` в compose-дефолтах | `fptn-admin/docker-compose.yml:7-8` |
| S10 | `docker.sock` rw + имя сервиса из callback без whitelist | `fptn-admin-bot/docker-compose.yml:20`, `bot.py:675-681` |
| A1 | `session.cpp` — 1450 строк, нарушение SRP | `fptn/src/fptn-server/web/session/session.cpp` |
| A2 | `route_manager.cpp` (1533 строки) без unit-тестов | `fptn/src/fptn-client/routing/route_manager.cpp` |
| K1 | Кэш ServerHello без LRU — рост памяти по числу SNI | `fptn/src/fptn-server/web/handshake/handshake_cache_manager.cpp` |
| M4 | 30+ опций `boost/*:without_*` вместо `without_default=True` | `fptn/conanfile.py` |
| I1 | CI поднимает Python 3.14, а `pyproject.toml` требует `<3.14` | `fptn-admin/.github/workflows/ci.yml:44` |
| I2 | CI не проверяет shell-скрипты и бота; ни один workflow не запускается | нет каталога `.github/workflows/` в корне |
| I3 | Renovate покрывает только Conan | `fptn/renovate.json` |

### Дрейф документации (обязательно учитывать)

- `docs/AUDIT.md` и `docs/DEPENDENCIES-AUDIT.md` датированы 04.09.2026 и частично описывают
  **дорефакторинговое** состояние. По версиям зависимостей актуальнее `DEPENDENCIES-AUDIT.md`.
- В документах встречаются версии, которых в коде нет («Vite 8», «TS 5.7», «React 19»).
  Фактические версии — в §3 и в `package.json` / `pyproject.toml`.
- `docs/plan.md` ссылается на `deploy/family/` — такого каталога в репозитории **нет**.
- `deploy/prereq-install.sh:189-191` тоже ссылается на несуществующие `deploy/deploy.sh`
  и `deploy/family/deploy.sh`. Реальные скрипты: `install.sh`, `install-admin.sh`,
  `install-bot.sh`, `configure.sh`, `uninstall.sh`.
- В рабочем дереве есть неотслеживаемый дубликат C++-части — `fptn-master/fptn-master/`
  (полный клон upstream). Он закрыт через `.gitignore` и исключения в `.vscode/settings.json`,
  поэтому удалять его **не требуется**; не редактировать и не искать в нём правки.

---

## 8. Что агенту делать нельзя

- Собирать C++ и запускать `deploy/*.sh` на Windows.
- Править `fptn-manager` (это gitlink на чужой репозиторий) и `.kilo/worktrees/**`.
- Обновлять версии зависимостей без явной задачи и без проверки `npm audit` / `pip-audit`.
- Удалять `overrides` в `package.json` или пины `==` в `pyproject.toml` без причины.
- Коммитить `.env`, секреты, артефакты сборки (`build/`, `dist/`, `node_modules/`).
- Ломать формат `users.list`, `servers.json`, `bot_settings.json` без миграции
  (C++-сервер читает эти файлы напрямую).
- Менять публичные имена Telegram-контейнеров
  (`fptn-admin-bot-telegram-admin-bot-1`, `fptn-admin-fptn-admin-backend-1`) —
  они зашиты в `bot.py:214-227`.
- Выполнять `git push`, `deploy/uninstall.sh`, `rm -rf` вне рабочего каталога.
- Планировать работу, не сверяясь с `docs/AUDIT.md` и `docs/ROADMAP.md` (они уже содержат
  приоритизированный список — не плодить конкурирующие планы).

---

## 9. Definition of Done (самопроверка перед отчётом)

Перед тем как сообщить о завершении задачи, агент обязан выполнить и привести в отчёте
фактический вывод команд:

```bash
# затронут C++           → ctest --test-dir build  (в WSL2/Linux)
# затронут backend       → poetry run black --check app tests && poetry run pylint app && poetry run pytest -q
# затронут frontend      → npm run lint && npx tsc --noEmit && npx vitest run && npm run build
# затронут deploy-скрипты→ shellcheck deploy/*.sh deploy/lib/*.sh
# затронут бот           → тестов нет; обязателен ручной разбор + python -m py_compile src/bot.py
# затронуты зависимости  → npm audit / poetry run pip-audit / conan outdated
```

Дополнительно:
- Просмотреть свой diff глазами ревьюера: нет `TODO`, заглушек, `print()` для отладки,
  закомментированного кода, `console.log`, лишних `Any`.
- `git status` чист по незапланированным файлам; новые артефакты — в `.gitignore`.
- В отчёте указать: что изменено, какие команды запускались, их результат, что осталось непроверенным.

---

## 10. Карта документации

| Файл | Содержание |
|------|-----------|
| `README.md` | Установка, стек, структура, ключевые особенности |
| `DOCUMENTATION.md` | Полная техническая документация (архитектура, API, классы, troubleshooting) |
| `docs/AUDIT.md` | Аудит качества и безопасности: 6 critical, 11 high, 9 medium |
| `docs/DEPENDENCIES-AUDIT.md` | Аудит зависимостей и CVE, применённые патчи |
| `docs/plan.md` | Пошаговое развёртывание на VPS |
| `docs/ROADMAP.md` | Приоритетный план дальнейших работ с критериями готовности |
| `docs/links.md` | Справочник ссылок |
| `docs/upstream/` | Оригинальная HTML-документация upstream (справочно, не редактировать) |
| `.vscode/extensions.json` | Рекомендуемые расширения VS Code |
| `.vscode/settings.json` | Настройки рабочей области (CMake, Python, поиск) |

---

## 11. Инструменты VS Code: включить и отключить

Рекомендуемые расширения — `.vscode/extensions.json`. Расширения, которые в этом
репозитории бесполезны или вредны, и команды для их отключения:

```bash
# Список установленных расширений
code --list-extensions --show-versions

# Убрать лишнее глобально (осторожно: влияет на все проекты)
code --uninstall-extension ms-vscode.cpptools-extension-pack   # тяжёлый C++ пакет, сборка только в WSL2
code --uninstall-extension ms-python.python                    # deprecated, заменён ms-python.vscode-pylance
code --uninstall-extension ms-python.debugpy                   # отладка Python здесь не используется

# Отключить расширения только в этой рабочей области
code --disable-extension ms-vscode.cpptools                   # CMake/CMake Tools: проект не собирается на Windows
code --disable-extension ms-azuretools.vscode-docker           # docker.sock бота опасен локально на Windows
code --disable-extension ms-vscode-remote.remote-ssh

# Убрать дубликат исходников из индекса поиска и файлового watcher
# Уже сделано без удаления: .gitignore закрывает fptn-master/, а .vscode/settings.json
# исключает его через files.exclude / search.exclude / files.watcherExclude.
# Удалять каталог не нужно и не следует.
```

Агент не должен самостоятельно удалять глобальные расширения: сначала показать список
установленных и предложить выбор.