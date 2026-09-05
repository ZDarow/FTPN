# FPTN

**FPTN** (Fast Protected Tunnel Network) — VPN-технология с защитой от DPI, маскирующая трафик под легитимный HTTPS. Использует технику **Reality** и пул rolling-туннелей.

> **Версия:** 0.4.4 · **Дата:** 04.09.2026 · **Лицензия:** MIT

---

## 🚀 Быстрый старт

### Полный стек (Docker, веб-панель, Let's Encrypt)
```bash
git clone https://github.com/ZDarow/FTPN.git
cd FTPN
sudo bash deploy/deploy.sh
```

### Облегчённый (systemd, без Docker, опционально панель)
```bash
git clone https://github.com/ZDarow/FTPN.git
cd FTPN
sudo bash deploy/family/deploy.sh
```

После развёртывания становятся доступны CLI-утилиты (`fptn-status`, `fptn-add-user`, `fptn-issue-token`, `fptn-backup`, `fptn-update`, …) — подробности в [docs/deploy-full.md](./docs/deploy-full.md) и [docs/deploy-family.md](./docs/deploy-family.md).

---

## 📂 Структура репозитория

```
FTPN/
├── fptn/                # C++20 ядро (VPN-сервер, клиент, протокол-lib)
├── fptn-admin/          # Веб-панель (FastAPI + React)
│   ├── backend/         # Python 3.13, FastAPI 0.115
│   └── frontend/        # React 18.3 + TypeScript 5 + Vite 8
├── deploy/              # Развёртывание полного стека
│   ├── deploy.sh        # 505 строк — главный инсталлятор
│   ├── systemd/         # 6 unit-файлов + healthcheck timer
│   └── scripts/         # 8 утилит управления
├── deploy/family/       # Развёртывание облегчённого варианта
│   ├── deploy.sh        # 477 строк — минимальный инсталлятор
│   ├── systemd/         # 4 unit-файла
│   └── scripts/         # 12 CLI-утилит
├── docs/                # Вся документация (см. ниже)
├── LICENSE              # MIT
└── .gitignore
```

---

## 📚 Документация → [docs/](./docs/)

| Документ | Назначение |
|----------|-----------|
| **[docs/DOCUMENTATION.md](./docs/DOCUMENTATION.md)** | Полная техническая документация (2267 строк): архитектура, API, классы C++, troubleshooting. |
| **[docs/AUDIT.md](./docs/AUDIT.md)** | Аудит качества кода, безопасности, зависимостей (6 критических проблем + план рефакторинга). |
| **[docs/DEPENDENCIES-AUDIT.md](./docs/DEPENDENCIES-AUDIT.md)** | Применённые патчи безопасности (0 CVE в npm после фиксов, 30 → 0). |
| **[docs/plan.md](./docs/plan.md)** | Пошаговый план развёртывания на VPS. |
| **[docs/deploy-full.md](./docs/deploy-full.md)** | Документация полного деплоя (Docker). |
| **[docs/deploy-family.md](./docs/deploy-family.md)** | Документация облегчённого деплоя (systemd). |
| **[docs/links.md](./docs/links.md)** | Справочник ссылок: upstream, сайты, клиенты, инструменты. |
| **[docs/upstream/](./docs/upstream/)** | Оригинальная HTML-документация upstream-проекта. |

---

## 🛡️ Ключевые особенности

| Фича | Описание |
|------|----------|
| **Reality mode** | При пробинге DPI-сканером сервер проксирует запрос на настоящий сайт-прикрытие. |
| **Rolling Tunnel** | Пул сокетов с общим `SessionID` (3 параллельных канала) — устойчивость к блокировкам. |
| **TLS-обфускация** | Поток шифруется с первого байта под видом `TLS Application Data`. |
| **Anti-probing** | Активная защита от сканеров портов. |
| **Фильтр-стек** | BitTorrent, SMTP/спам, доменный blacklist, anti-scanner. |
| **Telegram-бот** | Пользователи получают токен через `/start` → `/token`. |
| **JWT + bcrypt** | Аутентификация админ-панели. |
| **Авто-деплой** | Один скрипт — от чистого VPS до работающего VPN за 5 минут. |

---

## 🛠️ Стек

- **C++20** (Boost 1.90, protobuf 5.29, fmt 12.1, spdlog 1.17, jwt-cpp, nlohmann_json, boringssl)
- **Python 3.13** (FastAPI 0.115.6, uvicorn 0.34.0, PyJWT 2.10.1, bcrypt 4.2.1, brotli 1.1.0, python-telegram-bot 21.11.1)
- **React 18.3.1** + **TypeScript 5.7** + **Vite 8.2** + **Tailwind 3.4** + **react-router 7.18** + **vitest 5.0**
- **Docker** + **systemd** + **nginx** + **certbot** (Let's Encrypt)
- **0 CVE** в npm-деревьях (30 → 0 после применённых фиксов)

---

## 📜 Лицензия

MIT — проект основан на [github.com/batchar2/fptn](https://github.com/batchar2/fptn).

---

## 🔗 Полезные ссылки

См. [docs/links.md](./docs/links.md) — upstream-репозитории, сайт проекта, клиенты, документация.
