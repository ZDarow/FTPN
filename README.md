# FPTN

**FPTN** (Fast Protected Tunnel Network) — VPN-технология с защитой от DPI, маскирующая трафик под легитимный HTTPS. Использует технику **Reality** и пул rolling-туннелей.

> **Версия:** 0.4.4 · **Лицензия:** MIT

---

## 🚀 Установка (3 команды)

```bash
# 1. (опционально) prereq — только если сервер чистый
bash <(curl -fsSL https://raw.githubusercontent.com/ZDarow/FTPN/master/deploy/prereq-install.sh)

# 2. VPN-сервер
bash <(curl -fsSL https://raw.githubusercontent.com/ZDarow/FTPN/master/deploy/install.sh)

# 3. (опционально) админ-панель и Telegram-бот
bash /opt/fptn/deploy/install-admin.sh
bash /opt/fptn/deploy/install-bot.sh
```

Каждый скрипт — **минимальный**, читаемый, понятный. Открывайте и смотрите что делает.

---

## 📂 Структура репозитория

```
FTPN/
├── fptn/                 # C++20 ядро (VPN-сервер, клиент, протокол)
├── fptn-admin/           # Веб-панель (FastAPI + React)
│   ├── backend/          # Python 3.13, FastAPI 0.115
│   └── frontend/         # React 18.3 + Vite 5.4 + react-router 7.18
├── deploy/               # 5 скриптов (см. ниже)
└── docs/                 # Документация
```

```
deploy/
├── prereq-install.sh     # Установка Docker, Compose, UFW на чистый сервер
├── install.sh            # VPN-сервер (готовый образ fptnvpn/* с DockerHub)
├── install-admin.sh      # Админ-панель (сборка backend/frontend из исходников)
├── install-bot.sh        # Telegram-бот
└── uninstall.sh          # Полное удаление
```

---

## 📚 Документация → [docs/](./docs/)

| Документ | Назначение |
|----------|-----------|
| [docs/DOCUMENTATION.md](./docs/DOCUMENTATION.md) | Архитектура, API, классы, troubleshooting |
| [docs/AUDIT.md](./docs/AUDIT.md) | Аудит качества/безопасности |
| [docs/DEPENDENCIES-AUDIT.md](./docs/DEPENDENCIES-AUDIT.md) | Аудит зависимостей |
| [docs/plan.md](./docs/plan.md) | План развёртывания |
| [docs/links.md](./docs/links.md) | Справочник ссылок |
| [docs/upstream/](./docs/upstream/) | Оригинальная HTML-документация upstream |

---

## 🛠️ Стек

- **C++20** (Boost 1.90, protobuf 5.29, fmt 12.1, spdlog 1.17, boringssl)
- **Python 3.13** (FastAPI 0.115.6, uvicorn 0.34.0, PyJWT 2.10.1, bcrypt 4.2.1, brotli 1.1.0, python-telegram-bot 21.11.1)
- **React 18.3.1** + **TypeScript 5.4** + **Vite 5.4.21** + **Tailwind 3.4** + **react-router 7.18** + **vitest 2.1**
- **Docker** + готовые образы `fptnvpn/*` с DockerHub

**Версии фронтенда зафиксированы**: см. `fptn-admin/frontend/package.json`. Build проверен: 6 сек, 1637 модулей, 326 КБ JS, 34/34 тестов.

---

## 🔑 Ключевые особенности

- **Reality mode** — проксирование на настоящий сайт при пробинге DPI
- **Rolling Tunnel** — 3 параллельных канала с общим SessionID
- **TLS-обфускация** — шифрование с первого байта
- **Anti-probing** — активная защита от сканеров
- **Фильтр-стек** — BitTorrent, SMTP, DNSBL, anti-scanner
- **Telegram-бот** — `/start` → `/token` для пользователей
- **JWT + bcrypt** — аутентификация админ-панели

---

## 📜 Лицензия

MIT. Основан на [github.com/batchar2/fptn](https://github.com/batchar2/fptn).
