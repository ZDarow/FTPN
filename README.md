# FPTN

**FPTN** (Fast Protected Tunnel Network) — VPN-технология с защитой от DPI, маскирующая трафик под легитимный HTTPS. Использует технику **Reality** и пул rolling-туннелей.

> **Версия:** 0.4.4 · **Дата:** 04.09.2026

---

## 📦 Состав репозитория

```
FTPN/
├── fptn/                  # C++20 ядро (VPN-сервер, клиент, протокол)
├── fptn-admin/            # Веб-панель администратора (FastAPI + React)
├── deploy/                # Автоматическое развёртывание (полный стек, Docker)
│   ├── deploy.sh          # 505 строк — главный инсталлятор
│   ├── systemd/           # 6 unit-файлов
│   └── scripts/           # 8 утилит управления
├── deploy/family/         # Облегчённое развёртывание (systemd, без Docker)
│   ├── deploy.sh          # 477 строк — минимальный инсталлятор
│   ├── systemd/           # 4 unit-файла
│   └── scripts/           # 12 CLI-утилит
├── DOCUMENTATION.md       # Полная техническая документация (2267 строк)
├── AUDIT.md               # Аудит качества и безопасности (414 строк)
├── DEPENDENCIES-AUDIT.md  # Аудит зависимостей и фиксы CVE (525 строк)
├── plan.md                # План развёртывания на VPS
├── LICENSE                # MIT
└── .gitignore
```

---

## 🚀 Быстрый старт (production)

### Вариант 1: Полный стек (Docker, веб-панель, Let's Encrypt)

```bash
git clone https://github.com/ZDarow/FTPN.git
cd FTPN
sudo bash deploy/deploy.sh
```

После развёртывания доступны утилиты: `fptn-status`, `fptn-update`, `fptn-backup`, `fptn-logs`, `fptn-add-user`, `fptn-issue-token`, `fptn-setup-letsencrypt`, `fptn-swap-setup`.

### Вариант 2: Облегчённый (systemd, без Docker, опционально панель)

```bash
git clone https://github.com/ZDarow/FTPN.git
cd FTPN
sudo bash deploy/family/deploy.sh
```

После развёртывания доступны 12 утилит: `fptn-add-user`, `fptn-list`, `fptn-block`, `fptn-unblock`, `fptn-reset-speed`, `fptn-issue-token`, `fptn-show-config`, `fptn-status`, `fptn-logs`, `fptn-backup`, `fptn-update`, `fptn-swap-setup`.

---

## 🛡️ Ключевые особенности

| Фича | Описание |
|------|----------|
| **Reality mode** | При пробинге DPI-сканером сервер проксирует запрос на настоящий сайт-прикрытие (например, `yandex.ru`). |
| **Rolling Tunnel** | Пул сокетов с общим `SessionID` (по умолчанию 3 параллельных канала) — устойчивость к блокировкам. |
| **TLS-обфускация** | Поток шифруется с первого байта под видом `TLS Application Data`. |
| **Anti-probing** | Активная защита от сканеров портов. |
| **Встроенный фильтр-стек** | BitTorrent, SMTP/спам, доменный blacklist, anti-scanner. |
| **Telegram-бот** | Пользователи получают/сбрасывают токен через `/start` → `/token`. |
| **JWT + bcrypt** | Аутентификация админ-панели (HS256, секрет в файле 0600). |
| **Авто-деплой** | Один скрипт — от чистого VPS до работающего VPN за 5 минут. |

---

## 📚 Документация

| Файл | Назначение |
|------|-----------|
| [`DOCUMENTATION.md`](./DOCUMENTATION.md) | Полная техническая документация (архитектура, API, классы, troubleshooting). |
| [`AUDIT.md`](./AUDIT.md) | Аудит качества кода, безопасности, зависимостей. 6 критических проблем + план рефакторинга. |
| [`DEPENDENCIES-AUDIT.md`](./DEPENDENCIES-AUDIT.md) | Применённые патчи безопасности (0 CVE в npm после фиксов). |
| [`plan.md`](./plan.md) | Пошаговый план развёртывания на VPS. |
| [`deploy/README.md`](./deploy/README.md) | Документация полного деплоя. |
| [`deploy/family/README.md`](./deploy/family/README.md) | Документация облегчённого деплоя. |

---

## 🛠️ Стек

- **C++20** (Boost 1.90, protobuf 5.29, fmt 12.1, spdlog 1.17, jwt-cpp, nlohmann_json, boringssl)
- **Python 3.13** (FastAPI 0.115.6, uvicorn 0.34.0, PyJWT 2.10.1, bcrypt 4.2.1, brotli 1.1.0, python-telegram-bot 21.11.1)
- **React 18.3.1** + **TypeScript 5.7** + **Vite 8.2** + **Tailwind 3.4** + **react-router 7.18** + **vitest 5.0**
- **Docker** + **systemd** + **nginx** + **certbot** (Let's Encrypt)
- **0 CVE** в npm-деревьях (30 → 0 после применённых фиксов)

---

## 📜 Лицензия

MIT — проект основан на [github.com/batchar2/fptn](https://github.com/batchar2/fptn) (MIT).

---

## 🔗 Ссылки

- **Автор:** ZDarow
- **Оригинальный FPTN:** [github.com/batchar2/fptn](https://github.com/batchar2/fptn)
- **Сайт проекта / клиенты:** [storage.googleapis.com/fptn.org/](https://storage.googleapis.com/fptn.org/)
