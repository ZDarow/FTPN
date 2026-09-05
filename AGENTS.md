# AGENTS.md — FPTN

## Repo layout
- `fptn/` — C++20 ядро (CMake 3.18+, gtest, Conan). Не собирать на Windows без Linux-подобной среды.
- `fptn-admin/` — FastAPI backend + React/Vite frontend. Два независимых стека.
- `deploy/` — bash-скрипты установки на сервер. Только Linux.
- `fptn-admin-bot/` — Telegram-бот (Python, docker-compose). Отдельный стек.
- `docs/AUDIT.md` — актуальный техдолг и известные проблемы.

## Developer commands

### Backend (`fptn-admin/backend/`)
```bash
cd fptn-admin/backend
poetry install
poetry run pytest
```
- Требует **Python 3.13** (>=3.13,<3.14). `poetry.lock` закоммичен и должен генерироваться под 3.13.
- Линтер: `pylint` (макс. 120 символов). Форматтер: `black` (120).
- Тесты: `pytest` в `tests/`.

### Frontend (`fptn-admin/frontend/`)
```bash
cd fptn-admin/frontend
npm install
npm run lint
npm run test
npm run build
```
- Node >=20, npm >=10.
- `npm run build` падал из-за `npm audit` блокировки в Dockerfile; в локальной разработке audit не блокирует.
- Версии зафиксированы в `package.json`; не обновлять без согласования.

### C++ (`fptn/`)
```bash
cd fptn
conan install . --output-folder=build --build=missing
cmake -B build -S .
cmake --build build --parallel
ctest --test-dir build
```
- Зависимости: Boost 1.90, protobuf 5.29, fmt 12.1, spdlog 1.17, boringssl.
- На Windows сборка не тестировалась; используйте WSL2 или Linux.

### Docker (все сервисы)
```bash
# VPN
cd fptn/docker-compose && docker compose up -d

# Админка
cd fptn-admin && docker compose up -d

# Бот
cd fptn-admin-bot && docker compose up -d
```
- Админ-бот монтирует `/var/run/docker.sock` и `/usr/bin/docker` для управления контейнерами.
- Сеть `fptn-network` создаётся в `fptn/docker-compose/docker-compose.yml`.

## Deploy на сервер
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ZDarow/FTPN/master/deploy/prereq-install.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/ZDarow/FTPN/master/deploy/install.sh)
bash /opt/fptn/deploy/install-admin.sh
bash /opt/fptn/deploy/install-bot.sh
```
- Скрипты используют TUI (`whiptail`/`dialog`/`stdin`). В неинтерактивной сессии — авто-определение IP.
- Данные VPN: `/etc/fptn/` (volume `fptn-server-data`).
- Локальные изменения на сервере коммитить осторожно; `git pull` может сломать рабочую конфигурацию.

## Style / workflow
- Коммиты: русский язык, повелительное наклонение.
- Ветки: `kebab-case` на английском.
- PR: описание на русском.
- poetry.lock и package-lock.json коммитить.
- `.env` и секреты — никогда не коммитить.

## Known pitfalls
- Python 3.13 обязателен для backend; на сервере может быть 3.12 — нужно ставить отдельно.
- Frontend Dockerfile отключает `npm audit` блокировку; при обновлении зависимостей проверяйте уязвимости.
- `fptn-admin-bot/` — отдельный репозиторий внутри монорепо; имеет свой `Dockerfile`, `docker-compose.yml`, `.env`.
- В `fptn-admin-bot/src/bot.py` callback-хендлеры вызывают docker-команды напрямую; контейнер должен иметь доступ к docker.sock.
