# FPTN — полная техническая документация

> **FPTN** (Fast Protected Tunnel Network) — VPN-технология с защитой от DPI, маскирующая трафик под легитимный HTTPS с использованием техники **«Reality»** и пула rolling-туннелей. Проект включает VPN-сервер и клиент на C++20, веб-панель администратора (FastAPI + React) и встроенный Telegram-бот.

**Версия документации:** 0.4.4 · **Дата:** 04.09.2026

---

## 📑 Оглавление

1. [Обзор архитектуры и стека](#1-обзор-архитектуры-и-стека)
   - 1.1. [Назначение и ключевые особенности](#11-назначение-и-ключевые-особенности)
   - 1.2. [Высокоуровневая архитектура](#12-высокоуровневая-архитектура)
   - 1.3. [Технологический стек](#13-технологический-стек)
   - 1.4. [Сетевая модель](#14-сетевая-модель)
2. [Структура директорий и описание ключевых модулей](#2-структура-директорий-и-описание-ключевых-модулей)
   - 2.1. [Корень репозитория](#21-корень-репозитория)
   - 2.2. [`fptn/` — C++ ядро](#22-fptn--c-ядро)
   - 2.3. [`fptn-admin/backend/` — FastAPI](#23-fptn-adminbackend--fastapi)
   - 2.4. [`fptn-admin/frontend/` — React SPA](#24-fptn-adminfrontend--react-spa)
   - 2.5. [`deploy/` — скрипты развёртывания](#25-deploy--скрипты-развёртывания)
3. [Установка, настройка окружения и запуск](#3-установка-настройка-окружения-и-запуск)
   - 3.1. [Системные требования](#31-системные-требования)
   - 3.2. [Быстрый старт (production на VPS)](#32-быстрый-старт-production-на-vps)
   - 3.3. [Локальная разработка — C++](#33-локальная-разработка--c)
   - 3.4. [Локальная разработка — backend](#34-локальная-разработка--backend)
   - 3.5. [Локальная разработка — frontend](#35-локальная-разработка--frontend)
   - 3.6. [Переменные окружения](#36-переменные-окружения)
4. [API, классы и основные функции](#4-api-классы-и-основные-функции)
   - 4.1. [Бинарный протокол туннеля](#41-бинарный-протокол-туннеля)
   - 4.2. [REST API админ-панели](#42-rest-api-админ-панели)
   - 4.3. [Ключевые классы C++ (сервер)](#43-ключевые-классы-c-сервер)
   - 4.4. [Ключевые классы C++ (клиент)](#44-ключевые-классы-c-клиент)
   - 4.5. [Telegram-бот — команды](#45-telegram-бот--команды)
   - 4.6. [Формат access-токена](#46-формат-access-токена)
5. [Примеры использования](#5-примеры-использования)
   - 5.1. [Сценарий 1 — развёртывание с нуля](#51-сценарий-1--развёртывание-с-нуля)
   - 5.2. [Сценарий 2 — ежедневная работа администратора](#52-сценарий-2--ежедневная-работа-администратора)
   - 5.3. [Сценарий 3 — пользователь подключается через Telegram-бот](#53-сценарий-3--пользователь-подключается-через-telegram-бот)
   - 5.4. [Сценарий 4 — выдача премиум-доступа](#54-сценарий-4--выдача-премиум-доступа)
   - 5.5. [Сценарий 5 — обновление и откат](#55-сценарий-5--обновление-и-откат)
   - 5.6. [Примеры HTTP-запросов к API](#56-примеры-http-запросов-к-api)
6. [Troubleshooting и FAQ](#6-troubleshooting-и-faq)
   - 6.1. [Часто задаваемые вопросы](#61-часто-задаваемые-вопросы)
   - 6.2. [Типовые проблемы и решения](#62-типовые-проблемы-и-решения)
   - 6.3. [Логи и диагностика](#63-логи-и-диагностика)
   - 6.4. [Где получить помощь](#64-где-получить-помощь)

---


## 1. Обзор архитектуры и стека

### 1.1. Назначение и ключевые особенности

**FPTN** — VPN-решение, ориентированное на обход **Deep Packet Inspection (DPI)** и блокировок на уровне провайдера. В отличие от классических VPN (OpenVPN, WireGuard), FPTN маскирует VPN-трафик под обычный HTTPS, что делает его неотличимым от легитимного веб-серфинга.

**Ключевые инновации:**

| Фича | Описание |
|-------|----------|
| **Reality mode** | При пробинге DPI-сканером сервер проксирует запрос на настоящий сайт-прикрытие (например, `yandex.ru`), возвращая настоящий TLS-ответ. |
| **Rolling Tunnel** | Пул сокетов с общим `SessionID` (по умолчанию 3 параллельных канала) — повышает устойчивость к блокировкам по соединению. |
| **TLS-обфускация** | Поток шифруется с первого байта под видом `TLS Application Data`, с заголовком `0x17 0x03 0x03` и полем `time`. |
| **Anti-probing** | Активная защита: на сканирование порта сервер отвечает настоящим сайтом. |
| **Встроенный фильтр-стек** | BitTorrent, SMTP/спам, доменный blacklist, anti-scanner. |
| **Telegram-бот** | Пользователи получают/сбрасывают токен через `/start` → `/token`. |
| **JWT + bcrypt** | Современная аутентификация админ-панели. |

**Анти-DPI техники**, реализованные в FPTN:
1. SNI-спуфинг (маскировка под легитимный домен)
2. Reality-проксирование (реальный TLS-ответ от настоящего сайта)
3. Обфускация TLS-потока
4. Шардирование соединения (rolling tunnel)
5. Кэш ServerHello на 1 час (ускорение повторных соединений)
6. Шумоподобные пакеты (рандомизация padding)

### 1.2. Высокоуровневая архитектура

```
┌────────────────────────────────────────────────────────────────────┐
│                         УСТРОЙСТВО КЛИЕНТА                         │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────────────────┐  │
│  │ Приложения│───►│ TUN-интерфейс │───►│ fptn-client (vpn_manager) │  │
│  │          │◄───│  (10.10.0.7)  │◄───│  TUN ↔ WebSocket         │  │
│  └──────────┘    └──────────────┘    └──────────┬───────────────┘  │
│                                                  │                  │
└──────────────────────────────────────────────────┼──────────────────┘
                                                   │ TLS:443 (Reality)
                                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│                          V P S  С Е Р В Е Р                        │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │             fptn-server (C++20, Boost.Asio)                 │  │
│  │  ┌──────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ │  │
│  │  │Web/      │ │NAT/    │ │Leaky   │ │Filters │ │TUN-    │ │  │
│  │  │Handshake │ │Table   │ │Bucket  │ │AntiSpam│ │Virtual │ │  │
│  │  │(Reality) │ │        │ │rate-lmt│ │BT/DNSBL│ │Iface   │ │  │
│  │  └────┬─────┘ └───┬────┘ └────┬───┘ └────────┘ └────┬───┘ │  │
│  │       └────────────┴───────────┴─────────────────────┘     │  │
│  │                          │                                    │  │
│  └──────────────────────────┼────────────────────────────────────┘  │
│  ┌──────────────┐  ┌────────▼─────────┐  ┌────────────────────┐  │
│  │  Backend     │  │  Users.list /     │  │  Telegram Bot      │  │
│  │  (FastAPI)   │  │  Admins.json /    │  │  (встроен в backend│  │
│  │  REST API    │  │  Servers.json     │  │   /start /token)   │  │
│  │  :8000       │  │  (общий том)      │  │                    │  │
│  └──────┬───────┘  └────────▲─────────┘  └────────────────────┘  │
│  ┌──────▼───────┐          │ общий                                │
│  │  Frontend    │          │ /etc/fptn                            │
│  │  (React+nginx)│          │                                      │
│  │  :2663 (TLS) │          │                                      │
│  │  :8080 (HTTP)│          │                                      │
│  └──────────────┘                                                  │
└────────────────────────────────────────────────────────────────────┘
```

**Ключевое архитектурное решение** — единый каталог `/etc/fptn/` (монтируется во все три контейнера на сервере):
- `users.list` — общий для VPN-сервера, backend и Telegram-бота
- `servers.json`, `premium_servers.json`, `servers_censored_zone.json` — общие для backend и VPN-сервера
- `admins.json`, `bot_settings.json` — общие для backend и Telegram-бота
- `jwt_secret` — общий для backend

Это исключает необходимость в БД и обеспечивает атомарную согласованность через `fcntl`-блокировки.

### 1.3. Технологический стек

**C++ ядро (VPN-сервер и клиент)**

| Компонент | Версия | Назначение |
|-----------|--------|------------|
| C++ | 20 | Язык реализации |
| CMake | ≥ 3.18 | Система сборки |
| Conan | 2.32 | Менеджер зависимостей |
| Boost | 1.90 (conan) | Asio, Beast, System, ProgramOptions, Filesystem |
| protobuf | 5.29 | Сериализация сообщений |
| fmt | 12.1 | Форматирование |
| spdlog | 1.17 | Логирование |
| jwt-cpp | latest | JWT для API |
| nlohmann_json | latest | JSON для конфигов |
| mimalloc | latest | Аллокатор (опционально) |
| re2 | latest | Регулярные выражения (фильтры) |
| brotli | latest | Сжатие токенов |
| cpp-httplib | latest | Лёгкий HTTP-сервер |
| boringssl | (local) | TLS (Reality / обфускация) |
| Qt6 | (опц.) | GUI клиента |

**Backend (FastAPI)** — версии зафиксированы в `pyproject.toml` (см. `DEPENDENCIES-AUDIT.md`)

| Компонент | Версия | Назначение |
|-----------|--------|------------|
| Python | **3.13** (LTS, `<3.14`) | Язык |
| FastAPI | **0.115.6** | Web-фреймворк |
| uvicorn[standard] | **0.34.0** | ASGI-сервер |
| pydantic-settings | **2.7.1** | Конфигурация из .env |
| PyJWT | **2.10.1** | JWT-валидация |
| bcrypt | **4.2.1** | Хеширование паролей |
| brotli | **1.1.0** | Сжатие токенов |
| python-telegram-bot | **21.11.1** | Telegram API |
| pip-audit | ≥ 2.9 | Аудит зависимостей (dev) |
| poetry | 2.3.2 | Менеджер зависимостей |

**Frontend (React SPA)** — версии зафиксированы в `package.json` (CVE-fix через `overrides`)

| Компонент | Версия | Назначение |
|-----------|--------|------------|
| React | **18.3.1** | UI-фреймворк |
| TypeScript | **5.4.5** | Типизация |
| Vite | **5.4.21** | Бандлер + dev-сервер (стабильная LTS) |
| Tailwind CSS | **3.4.17** | Стили |
| react-router-dom | **7.18.3** | Маршрутизация (CVE-fix) |
| react-i18next | 14.1.3 | i18n (en/ru) |
| i18next | 23.16.8 | i18n-ядро |
| brotli-wasm | 3.0.1 | Декодирование токенов в браузере |
| lucide-react | **0.469.0** | Иконки |
| vitest | **2.1.9** | Тесты |
| jsdom | **25.0.1** | Тестовое окружение |
| prettier | **3.4.2** | Форматирование |
| eslint | **8.57.1** | Линтинг |
| @vitejs/plugin-react | **4.7.0** | React-fast-refresh |

**Инфраструктура**

- Docker + Docker Compose v2
- nginx 1.27 (внутри frontend-контейнера + reverse-proxy снаружи)
- certbot (Let's Encrypt)
- BBR congestion control
- systemd (4 unit-файла + healthcheck timer)

### 1.4. Сетевая модель

**Фазы соединения клиент → сервер:**

```
[Фаза 1 — Reality приманка]
  Client → Server: TLS ClientHello { SNI=www.example.com,
                                   session_id=[random 28B][sha1(unix_time) 4B][random 4B] }
  Server → Cover site: тот же ClientHello (прокси)
  Cover site → Server: ServerHello + ChangeCipherSpec + EncryptedExtensions + Certificate + Finished
  Server → Client: те же записи, но session_id = клиентский (со sha1(время))
  Client → Server: ChangeCipherSpec (конец приманки)

[Фаза 2 — настоящий TLS под обфускацией]
  Каждая запись: 0x17 0x03 0x3 [8B random] [4B time] [1B XOR] [2B len] [2B pad] [payload^XOR] [4..8KB шум]
  Обфускатор на сервере: побайтный поиск 0x17 0x03 0x3, time в окне ±120 сек
  После Finished обфускатор ВЫКЛЮЧАЕТСЯ

[Фаза 3 — WebSocket вход в туннель]
  Client → Server: GET /api/v1/fptn
                 Authorization: Bearer <JWT>
                 X-Serializer: yaff|protobuf
                 SessionID: <общий для пула>
  Server → Client: 101 Switching Protocols
  Server → Client: MSG_IP_ASSIGNMENT {ipv4=10.10.0.7, ipv6=fd00::7}

[Фаза 4 — Транспорт]
  Бинарный фрейм: MSG_BATCH_IP_PACKET {
    protocol_version=1
    msg_type=0x03
    packets=[{payload: IP-пакет, padding: 64-128 случайных байт}, ...]
  }
  На клиента: до 32 пакетов в батче
  От сервера:  до 128 пакетов в батче
```

**Rolling Tunnel**: шаблон `RollingTunnel<ConnectionCount=3, LifetimeSeconds=600, StaggerSeconds=200>` — 3 параллельных сокета, живут 600 сек, заменяются последовательно каждые 200 сек. Все 3 канала делят один `SessionID`, TCP/UDP-флоу закрепляются за сокетом по номеру порта (сохранение порядка).

**MTU**: 1420 байт (1400 полезных + 20 padding overhead).

---

## 2. Структура директорий и описание ключевых модулей

### 2.1. Корень репозитория

```
FTPN/
├── fptn/                      # C++ ядро (VPN-сервер + клиент + протокол-библиотека)
├── fptn-admin/                # Web-панель администратора (backend + frontend)
├── deploy/                    # Скрипты автоматического развёртывания на VPS
│   ├── deploy.sh              # Главный скрипт (505 строк)
│   ├── README.md              # Подробная инструкция
│   ├── systemd/               # 4 unit-файла + healthcheck.timer
│   └── scripts/               # 9 утилит управления
├── .sandbox/                  # Локальная изолированная среда для экспериментов
├── .vscode/                   # Конфигурация VS Code (tasks, launch, clangd)
├── AGENTS.md                  # Гайдлайны для AI-агентов
├── LICENSE                    # Лицензия проекта
├── README.md                  # Основной README
└── README_RU.md               # README на русском
```

### 2.2. `fptn/` — C++ ядро

```
fptn/
├── CMakeLists.txt             # C++20, глобальные дефайны (FPTN_VERSION, MTU_SIZE=1420, SNI=rutube.ru)
├── conanfile.py               # Conan 2 рецепт (11+ зависимостей, опции: with_gui_client)
├── cpplint.py                 # Скрипт Google C++ Style Guide линтинга
├── pyproject.toml             # Conan build helpers
├── depends/                   # Локальные overrides для boringssl и др.
├── src/
│   ├── common/                # Кроссплатформенные утилиты
│   │   ├── client_id/         # Уникальный ID сессии
│   │   ├── logger/            # spdlog-обёртка
│   │   ├── network/           # TUN, IP-пакеты, DNS, rate
│   │   │   ├── tun_linux/     # Linux TUN (ioctl TUNSETIFF)
│   │   │   ├── tun_darwin/    # macOS utun
│   │   │   ├── tun_win/       # Windows wintun
│   │   │   ├── ip_packet/     # IPv4/v6 парсинг
│   │   │   ├── ip_address/    # Адресные типы
│   │   │   ├── ipv4_generator/# Генератор адресов для клиентов (10.10.0.0/16)
│   │   │   ├── ipv6_generator/# fd00::/64
│   │   │   ├── ip_utils/      # checksum, fragment handling
│   │   │   ├── resolv/        # DNS-резолвер
│   │   │   ├── data_rate_calculator/  # Подсчёт скорости
│   │   │   └── utils/         # Хелперы
│   │   ├── jwt_token/         # JWT-обёртка
│   │   ├── system/command/    # Запуск shell-команд
│   │   ├── api/handle/        # HTTP API сервера (метрики)
│   │   ├── utils/base64/      # base64-кодирование
│   │   └── user/common_user_manager/  # Парсинг users.list
│   │
│   ├── fptn-protocol-lib/     # Кроссплатформенная сетевая библиотека
│   │   ├── protocol/
│   │   │   ├── protocol.proto # Protobuf-схема
│   │   │   ├── protocol.cpp   # Сериализация/десериализация
│   │   │   └── yaff/          # Альтернативный сериализатор
│   │   ├── time/              # Утилиты времени
│   │   ├── https/
│   │   │   ├── obfuscator/    # TLS-обфускация (tls, tls2)
│   │   │   ├── methods/tls/   # Метод TLS + Reality
│   │   │   ├── websocket_client/  # WS-клиент
│   │   │   ├── api_client/    # REST API клиент (login)
│   │   │   └── connection_config/  # Параметры соединения
│   │   ├── connection/
│   │   │   ├── connection_manager/   # Главный менеджер + JWT login
│   │   │   └── strategies/
│   │   │       ├── base_strategy_connection/  # Базовый класс
│   │   │       ├── rolling_tunnel/             # Шаблон пула
│   │   │       ├── single_rolling_tunnel/      # 1 канал
│   │   │       ├── dual_rolling_tunnel/        # 2 канала
│   │   │       └── triple_rolling_tunnel/      # 3 канала
│   │   ├── censorship/        # Анти-DPI
│   │   │   ├── strategy.h
│   │   │   ├── fingerprint.h  # Отпечатки браузеров
│   │   │   └── strategies/    # kSni, kTlsObfuscator, kSniRealityMode
│   │   └── dns/               # DNS-over-HTTPS, DNS-резолвер
│   │
│   ├── fptn-server/           # VPN-сервер
│   │   ├── fptn-server.cpp    # Точка входа (argc/argv → config → main loop)
│   │   ├── config/
│   │   │   └── server_config.h # argparse-конфиг
│   │   ├── user/
│   │   │   └── user_manager.h  # users.list I/O
│   │   ├── nat/
│   │   │   ├── table/          # NAT-таблица + мультиплексор
│   │   │   ├── connection_multiplexer/  # Объединяет сокеты одного клиента
│   │   │   ├── connect_params/ # Параметры подключения
│   │   │   └── client_connection/       # Логический клиент
│   │   ├── routing/
│   │   │   └── route_manager/  # ip route add/del
│   │   ├── network/
│   │   │   └── virtual_interface/  # TUN на сервере
│   │   ├── traffic_shaper/
│   │   │   └── leaky_bucket/   # Rate-limiting per user
│   │   ├── vpn/
│   │   │   └── manager/        # Главный цикл сервера
│   │   ├── filter/
│   │   │   ├── manager/        # Менеджер фильтров
│   │   │   └── filters/
│   │   │       ├── antiscan/   # Защита от сканеров портов
│   │   │       ├── antispam/   # Блок SMTP/NetBIOS/SMB
│   │   │       ├── bittorrent/# Блок BT-трафика
│   │   │       └── domain_blacklist/  # DNSBL
│   │   ├── web/
│   │   │   ├── server.h        # Boost.Beast HTTP/WS-сервер
│   │   │   ├── session/session.h  # Сессия клиента
│   │   │   ├── handshake/      # Reality handshake + кэш
│   │   │   ├── listener/       # TCP listener
│   │   │   └── api/            # /metrics endpoint
│   │   ├── client/session/     # Логика сессии
│   │   └── statistic/metrics/  # Prometheus-метрики
│   │
│   ├── fptn-client/           # VPN-клиент
│   │   ├── fptn-client-gui.cpp # Qt6 точка входа
│   │   ├── vpn/
│   │   │   └── vpn_manager/    # Start/Stop/reconnect с exponential backoff
│   │   ├── http/client/        # HTTP-клиент
│   │   ├── plugins/
│   │   │   ├── split/tunneling/  # Split-tunneling
│   │   │   └── adblock/adblock/  # Блокировка рекламы
│   │   ├── routing/route_manager/  # Системные маршруты
│   │   ├── config/config_file/  # Парсинг access-токена
│   │   ├── censorship/         # Клиентская сторона анти-DPI
│   │   └── gui/                # Qt-интерфейс
│   │       ├── tray/           # System tray
│   │       ├── sni_manager/    # Сканер SNI
│   │       ├── speedwidget/    # Виджет скорости
│   │       └── i18n/           # en/ru/fa
│   │
│   └── fptn-passwd/           # CLI-утилита
│       └── passwd.cpp         # Создание/изменение users.list
│
├── docker-compose/            # Продакшн-стек сервера
│   ├── docker-compose.yml     # 1 сервис (fptn-server:0.4.4)
│   └── .env.demo              # Все env-переменные
│
├── deploy/                    # Готовые пакеты
│   ├── docker/                # Скрипты сборки Docker
│   ├── domain_blacklist/      # Списки блокировки (russia.txt, etc.)
│   ├── icons/                 # Иконки приложения
│   ├── linux/macos/windows/   # Пакеты для ОС
│   └── sni/                   # Списки SNI
│
├── sysadmin-tools/
│   ├── telegram-bot/          # Standalone Telegram-бот
│   │   ├── src/               # Исходники
│   │   ├── Dockerfile
│   │   ├── docker-compose.yml
│   │   └── .env.demo
│   └── grafana/               # Grafana + Prometheus
│       ├── proxy-server/      # Обратный прокси для метрик
│       ├── docker-compose.yml
│       └── docker-compose.build.yml
│
└── tests/                     # CTest тесты (gtest)
```

### 2.3. `fptn-admin/backend/` — FastAPI

```
fptn-admin/backend/
├── Dockerfile                 # python:3.13-slim, 2 stage: test → runtime
├── pyproject.toml             # Poetry 2.3.2
├── poetry.lock
├── app/
│   ├── __init__.py
│   ├── main.py                # FastAPI app, lifespan, CORS, exception handlers
│   ├── config.py              # pydantic-settings, пути к файлам
│   ├── deps.py                # FastAPI Depends (singleton stores)
│   ├── exceptions.py          # Глобальные обработчики
│   ├── secret.py              # JWT secret (load/generate в /etc/fptn/jwt_secret)
│   ├── security.py            # bcrypt + JWT HS256
│   ├── schemas.py             # Pydantic-модели (UserCreate, VpnUser, Server, ...)
│   ├── telegram_bot.py        # BotRunner (asyncio loop в отдельном потоке)
│   ├── vpn_token.py           # build_token(), build_access_link() (brotli q=11, lgwin=24)
│   ├── routers/
│   │   ├── auth.py            # POST /auth/login, /change-password
│   │   ├── users.py           # GET/POST/PUT/DELETE /users, POST /users/{id}/token
│   │   ├── servers.py         # CRUD /servers, /servers/premium, /servers/censored
│   │   ├── settings.py        # GET/PUT /settings (bot config)
│   │   └── dashboard.py       # GET /dashboard/highlights, /stats
│   └── stores/
│       ├── admin_store.py     # admins.json (bcrypt)
│       ├── vpn_user_store.py  # users.list (atomic write + fcntl.flock)
│       ├── server_store.py    # 3 JSON файла
│       └── bot_settings_store.py  # bot_settings.json
└── tests/                     # 7 pytest-тестов
    ├── conftest.py            # Fixtures (temp data dir, fresh stores)
    ├── test_admin_store.py    # bcrypt + JSON
    ├── test_api.py            # End-to-end REST
    ├── test_secret.py         # JWT secret load/generate
    ├── test_settings.py       # pydantic-settings
    ├── test_telegram_bot.py   # Mocked bot
    ├── test_token_and_servers.py  # build_token + server selection
    └── test_vpn_user_store.py # users.list CRUD
```

**Особенности backend:**

- **Файловое хранилище** без БД — использует `fcntl.flock` для межпроцессной блокировки и атомарной записи через `tempfile + os.replace`.
- **JWT-секрет** персистится в `/etc/fptn/jwt_secret` (chmod 600), генерируется один раз при первом запуске.
- **Telegram-бот** стартует в фоне через `bot_runner.start()` если `bot_enabled=true` в `bot_settings.json`; останавливается через `bot_runner.stop()`.
- **First-run seed**: если `admins.json` пустой, создаётся пользователь из `ADMIN_LOGIN`/`ADMIN_PASSWORD` env-переменных; `must_change_password=true` если пароль дефолтный.
- **CORS** — из env `CORS_ORIGINS` (comma-separated).

### 2.4. `fptn-admin/frontend/` — React SPA

```
fptn-admin/frontend/
├── Dockerfile                 # node:20-slim → nginx:1.27-alpine
├── docker-entrypoint.sh       # Генерация самоподписанного SSL
├── nginx.conf                 # SPA-роутинг + /api proxy
├── package.json
├── vite.config.ts             # Прокси /api → :8000, vitest jsdom
├── tailwind.config.js         # Темы, кастомные цвета
├── tsconfig.json
├── postcss.config.js
├── commitlint.config.js
├── index.html                 # Точка входа SPA
├── src/
│   ├── main.tsx               # React root
│   ├── App.tsx                # Routes + AuthProvider
│   ├── index.css              # Tailwind directives
│   ├── test/setup.ts          # Vitest setup
│   ├── assets/                # SVG/PNG
│   ├── context/
│   │   └── AuthContext.tsx    # JWT в localStorage
│   ├── api/
│   │   ├── client.ts          # apiRequest<T>() + ApiError
│   │   ├── auth.ts            # login, changePassword
│   │   ├── users.ts           # CRUD + token issue
│   │   ├── servers.ts
│   │   ├── settings.ts
│   │   ├── dashboard.ts
│   │   └── index.ts
│   ├── lib/
│   │   └── fptnToken.ts       # decodeFptnToken (brotli-wasm)
│   ├── i18n/
│   │   ├── config.ts          # i18next init
│   │   ├── locales/
│   │   │   ├── en.json
│   │   │   └── ru.json
│   │   └── LanguageSwitcher.tsx
│   ├── data/
│   │   └── navigation.ts      # Конфиг сайдбара
│   ├── components/
│   │   ├── RequireAuth.tsx
│   │   ├── layout/
│   │   │   ├── DashboardLayout.tsx
│   │   │   ├── Header.tsx
│   │   │   ├── Sidebar.tsx
│   │   │   ├── LanguageSwitcher.tsx
│   │   │   └── LayoutContext.tsx
│   │   └── ui/
│   │       ├── Button.tsx
│   │       ├── Modal.tsx
│   │       ├── Table.tsx
│   │       ├── Pagination.tsx
│   │       ├── Input.tsx
│   │       ├── ToggleBadge.tsx
│   │       └── ...
│   └── pages/
│       ├── Login.tsx
│       ├── ChangePassword.tsx
│       ├── Dashboard.tsx
│       ├── Users.tsx          # Таблица, поиск, фильтры, генерация токена
│       ├── Servers.tsx
│       ├── TelegramBot.tsx
│       ├── GivePremiumAccess.tsx
│       └── ComingSoon.tsx
└── tests/                     # vitest
    ├── Login.test.tsx
    ├── api.test.ts
    └── fptnToken.test.ts
```

**Архитектура UI:**

- **App** оборачивает `AuthProvider` (контекст с JWT в `localStorage`).
- **Routes**: `/login` (публичный) → после логина все маршруты обёрнуты в `RequireAuth`.
- **DashboardLayout** — общий layout с Header (логотип, язык, юзер, logout) + Sidebar (динамическая навигация).
- **API-клиент** (`apiRequest<T>`) — единая обёртка с Bearer-авторизацией и типизированными ошибками.
- **Token-декодирование** через `brotli-wasm` (только в браузере) для токенов формата `fptnb:`.
- **i18n** — переключение на лету, сохранение в localStorage.

### 2.5. `deploy/` — скрипты развёртывания

5 простых скриптов, **без копирования исходников** (для VPN-сервера используется готовый образ `fptnvpn/fptn-vpn-server:0.4.4` с DockerHub):

```
deploy/
├── prereq-install.sh     # ~190 строк — установка Docker, UFW, nginx, certbot на чистый сервер
├── install.sh            # ~100 строк — VPN-сервер (3 вопроса, авто-детект IP)
├── install-admin.sh      # ~60 строк — админ-панель (FastAPI + React, build из исходников)
├── install-bot.sh        # ~40 строк — Telegram-бот (только если есть токен)
└── uninstall.sh          # ~25 строк — полное удаление
```

**Установка на сервер** (3 команды):

```bash
# 1. (только для чистого сервера) prereq
bash <(curl -fsSL https://raw.githubusercontent.com/ZDarow/FTPN/master/deploy/prereq-install.sh)

# 2. VPN-сервер
bash <(curl -fsSL https://raw.githubusercontent.com/ZDarow/FTPN/master/deploy/install.sh)

# 3. (опционально) админка и бот
bash /opt/fptn/deploy/install-admin.sh
bash /opt/fptn/deploy/install-bot.sh
```

**Где что лежит после установки:**

```
/opt/fptn/
├── .git/                       # Клон репозитория (для обновления через git pull)
├── fptn/docker-compose/        # docker-compose VPN-сервера + .env
├── fptn-admin/                 # docker-compose админ-панели
├── fptn/sysadmin-tools/        # docker-compose Telegram-бота
├── data/fptn-server/           # users.list, servers.json, jwt_secret
└── deploy/                     # Скрипты (для повторного запуска и удаления)
```

**Принципы:**

- `install.sh` — клонирует репо в `/opt/fptn`, копирует upstream `.env.demo` в `.env`, подставляет публичный IP, запускает `docker compose up -d`.
- `install-admin.sh` / `install-bot.sh` — собирают образы локально из исходников (`docker compose up -d --build`).
- `uninstall.sh` — `docker compose down` для всех 3-х стеков, удаление `/opt/fptn` и сети.
- Никаких systemd-юнитов, certbot'а в скрипте, UFW-автонастройки, копирования исходников — это всё **наружу** скрипта, на усмотрение админа.

Подробности — в [README.md](../../README.md).

---

## 3. Установка, настройка окружения и запуск

### 3.1. Системные требования

**Для production (VPS)**

| Параметр | Минимум | Рекомендуется |
|----------|---------|---------------|
| OS | Ubuntu 22.04 / Debian 12 | Ubuntu 24.04 |
| CPU | 1 vCPU | 2 vCPU |
| RAM | 1 ГБ (нужен swap 2 ГБ) | 2 ГБ |
| Диск | 10 ГБ | 20 ГБ SSD |
| Сеть | публичный IPv4 | IPv4 + IPv6 |
| Порты | TCP 443 (или другой) — VPN; 2663/8080 — админка | |
| Ядро | ≥ 5.x с `tun` и `tcp_bbr` | |
| Права | root (для Docker) | |

**Для локальной разработки C++**

- Компилятор: GCC ≥ 11, Clang ≥ 14, MSVC 2022
- CMake ≥ 3.18
- Conan 2.32+
- Python 3.10+ (для Conan)
- Qt 6.x (только для GUI клиента, опционально)
- ~3 ГБ свободного места на диске (для conan-кэша)

**Для локальной разработки backend**

- Python **3.13.x** (`>=3.13,<3.14` — фиксация в `pyproject.toml`; 3.14 не поддерживается)
- Poetry 2.3+

**Для локальной разработки frontend**

- Node.js **20.x** (минимум 20.0.0, зафиксировано в `engines`)
- npm **10.x** (минимум 10.0.0, зафиксировано в `engines`)

### 3.2. Быстрый старт (production на VPS)

**3 команды** для развёртывания:

```bash
# 1. (опционально) prereq — установка Docker, UFW, nginx, certbot
bash <(curl -fsSL https://raw.githubusercontent.com/ZDarow/FTPN/master/deploy/prereq-install.sh)

# 2. VPN-сервер (использует готовый образ fptnvpn/fptn-vpn-server:0.4.4)
bash <(curl -fsSL https://raw.githubusercontent.com/ZDarow/FTPN/master/deploy/install.sh)

# 3. (опционально) админ-панель и Telegram-бот
bash /opt/fptn/deploy/install-admin.sh
bash /opt/fptn/deploy/install-bot.sh
```

**Что делает install.sh:**

1. Клонирует репозиторий в `/opt/fptn`
2. Копирует upstream `.env.demo` → `.env`
3. Авто-определяет публичный IP и подставляет в `SERVER_EXTERNAL_IPS`
4. `docker compose pull` + `up -d` (готовый образ `fptnvpn/fptn-vpn-server:0.4.4`)

**После установки (≈ 1 минута):**

```
============================================================
  FPTN VPN запущен!
============================================================

  Статус:    docker ps | grep fptn
  Логи:      cd /opt/fptn/fptn/docker-compose && docker compose logs -f
  Остановка: cd /opt/fptn/fptn/docker-compose && docker compose down
============================================================
```

**Следующие шаги:**

1. **Создать пользователя** в `/opt/fptn/data/fptn-server/users.list`:
   ```
   123456789 5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8 100 0
   ```
   (формат: `<id> <sha256(pass)> <speed_mbps> <is_premium 0|1>`)

2. **Запустить админ-панель** (`install-admin.sh`) для UI-управления.

3. **Скачать клиент** [fptn.org](https://storage.googleapis.com/fptn.org/) и вставить токен.

**Удаление:**

```bash
bash /opt/fptn/deploy/uninstall.sh
```

### 3.3. Локальная разработка — C++

**Шаг 1. Установи Conan**

```bash
pip install conan==2.32.0
conan profile detect --force
```

**Шаг 2. Установи зависимости и собери**

```bash
cd fptn
mkdir build && cd build

# Установка conan-зависимостей (без GUI клиента)
conan install .. \
  --output-folder=. \
  --build=missing \
  -s compiler.cppstd=17 \
  -o with_gui_client=False \
  --settings build_type=Release

# Конфигурация и сборка
cmake .. -DCMAKE_BUILD_TYPE=Release \
         -DFPTN_BUILD_TESTS=ON
cmake --build . -j$(nproc)

# Опционально: запуск тестов
ctest --output-on-failure
```

**Шаг 3. Запуск сервера (требует root для TUN)**

```bash
sudo ./src/fptn-server/fptn-server \
  --server-ip 10.10.0.1 \
  --port 443 \
  --users-file /tmp/users.list \
  ...
```

**Шаг 4. Генерация users.list**

```bash
# Пароль генерируется как sha256(password)
echo "123456789 $(echo -n 'mypassword' | sha256sum | cut -d' ' -f1) 100 0" > /tmp/users.list
```

### 3.4. Локальная разработка — backend

```bash
cd fptn-admin/backend
poetry install --with dev
cp ../.env.demo .env
# отредактируй .env (FPTN_CONFIGS_FOLDER, TELEGRAM_TOKEN, ...)

# Запуск
poetry run uvicorn app.main:app --reload --port 8000

# Swagger UI
open http://localhost:8000/api/v1/docs

# Тесты
poetry run pytest -q
poetry run black --check app tests
poetry run pylint app
```

### 3.5. Локальная разработка — frontend

```bash
cd fptn-admin/frontend
npm install
cp .env.example .env
# VITE_API_URL=http://localhost:8000

# Dev-сервер (проксирует /api → http://localhost:8000)
npm run dev
# → http://localhost:5173

# Production build
npm run build
npm run preview

# Линт, типы, тесты
npm run lint
npm run typecheck
npm test
```

### 3.6. Переменные окружения

**VPN-сервер (`fptn/docker-compose/.env`)**

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `FPTN_PORT` | 443 | Порт VPN-туннеля |
| `SERVER_EXTERNAL_IPS` | — | Через запятую публичные IP сервера (предотвращает петли) |
| `ENABLE_DETECT_PROBING` | true | Активная защита от сканеров |
| `DEFAULT_PROXY_DOMAIN` | yandex.ru | Сайт-прикрытие для Reality |
| `ALLOWED_SNI_LIST` | (whitelist) | Через запятую — кому проксировать настоящий SNI |
| `DISABLE_TORRENT_FILTER` | false | Отключить BT-фильтр |
| `DISABLE_SPAM_FILTER` | false | Отключить SMTP/SMB-фильтр |
| `BLACKLIST_URL` | (russia.txt) | URL списка заблокированных доменов |
| `MTU_SIZE` | 1400 | Макс. размер IP-пакета |
| `USE_REMOTE_SERVER_AUTH` | false | Кластерный режим |
| `REMOTE_SERVER_AUTH_HOST` | — | Хост master-сервера для авторизации |
| `REMOTE_SERVER_AUTH_PORT` | 443 | Порт master-сервера |
| `PROMETHEUS_SECRET_ACCESS_KEY` | — | Ключ доступа к Prometheus-метрикам |
| `MAX_ACTIVE_SESSIONS_PER_USER` | 3 | Лимит одновременных сессий |
| `USING_DNS_SERVER` | unbound | DNS-сервер для клиентов (`unbound` или `dnsmasq`) |
| `DNS_IPV4_PRIMARY` | 8.8.8.8 | Первичный IPv4 DNS |
| `DNS_IPV4_SECONDARY` | 8.8.4.4 | Вторичный IPv4 DNS |
| `DNS_IPV6_ENABLE` | false | Включить IPv6 DNS |
| `DNS_IPV6_PRIMARY` | 2001:4860:4860::8888 | Первичный IPv6 DNS |
| `DNS_IPV6_SECONDARY` | 2001:4860:4860::8844 | Вторичный IPv6 DNS |

**Backend (`fptn-admin/.env`)**

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `JWT_TTL_MINUTES` | 60 | Время жизни JWT в минутах |
| `ADMIN_LOGIN` | admin | Логин первого админа (только при первом запуске) |
| `ADMIN_PASSWORD` | admin | Пароль (только при первом запуске) |
| `CORS_ORIGINS` | * | Через запятую разрешённые origins (в проде — конкретный домен) |
| `ENABLE_BROTLI_COMPRESSION` | false | Сжимать токены через brotli |
| `FPTN_CONFIGS_FOLDER` | ./compose-data | Путь к общему тому (должен совпадать с VPN-сервером) |
| `TELEGRAM_TOKEN` | — | Токен бота (только для first-run seed) |
| `BOT_ENABLED` | false | Запустить бота при старте |
| `SERVICE_NAME` | fptn | Имя сервиса в токенах |
| `MAX_USER_SPEED_LIMIT` | 30 | Скорость по умолчанию (Мбит/с) |
| `WELCOME_MESSAGE_EN` | — | Приветствие на английском |
| `WELCOME_MESSAGE_RU` | — | Приветствие на русском |

**Frontend (`.env.example`)**

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `VITE_API_URL` | (прокси) | Базовый URL API (если не проксируется через Vite) |

---

## 4. API, классы и основные функции

### 4.1. Бинарный протокол туннеля

**Protobuf-схема** (`fptn/src/fptn-protocol-lib/protocol/protocol.proto`)

```protobuf
syntax = "proto3";

package fptn;

enum MessageType {
  MSG_ERROR            = 0;
  MSG_IP_PACKET        = 1;
  MSG_IP_ASSIGNMENT    = 2;
  MSG_BATCH_IP_PACKET  = 3;
}

enum ErrorType {
  ERR_UNAUTHORIZED     = 0;
  ERR_BAD_REQUEST      = 1;
  ERR_PAYMENT_REQUIRED = 2;
  ERR_FORBIDDEN        = 3;
  ERR_NOT_FOUND        = 4;
  ERR_INTERNAL         = 5;
  ERR_SERVER_UNAVAILABLE = 6;
}

message IPPacket {
  bytes payload = 1;     // IP-пакет (IPv4 или IPv6)
  bytes padding = 2;     // 64-128 случайных байт
}

message IPAssignment {
  uint32 ipv4 = 1;       // Назначенный IPv4 (например, 0x0A0A0007 = 10.10.0.7)
  bytes  ipv6 = 2;       // IPv6 (16 байт)
  uint32 mtu  = 3;       // MTU
}

message BatchIPPacket {
  repeated IPPacket packets = 1;
}

message Message {
  uint32 protocol_version = 1;  // = 0x01
  MessageType msg_type    = 2;
  oneof payload {
    Error            error    = 3;
    IPPacket         packet   = 4;
    IPAssignment     assign   = 5;
    BatchIPPacket    batch    = 6;
  }
}
```

**WebSocket-фрейм:**

```
Client → Server:
  GET /api/v1/fptn HTTP/1.1
  Host: <server>
  Authorization: Bearer <JWT>
  X-Serializer: yaff|protobuf
  SessionID: <shared-by-all-sockets>
  Upgrade: websocket
  Connection: Upgrade
  Sec-WebSocket-Key: ...
  Sec-WebSocket-Version: 13

Server → Client:
  HTTP/1.1 101 Switching Protocols
  Upgrade: websocket
  Connection: Upgrade
  Sec-WebSocket-Accept: ...

  [binary frame: Message{protocol_version=1, msg_type=MSG_IP_ASSIGNMENT,
                          assign={ipv4=10.10.0.7, ipv6=fd00::7, mtu=1420}}]
```

**Альтернативный сериализатор `yaff`** (Yet Another Fast Format) — компактнее protobuf, быстрее, нативный в `fptn-protocol-lib/yaff/`. Выбирается через `X-Serializer: yaff`.

### 4.2. REST API админ-панели

**Базовый URL:** `http://localhost:8000/api/v1`
**Swagger UI:** `http://localhost:8000/api/v1/docs`
**OpenAPI JSON:** `http://localhost:8000/api/v1/openapi.json`

Все эндпоинты (кроме `/auth/login`) требуют заголовок `Authorization: Bearer <JWT>`.

---

#### `POST /auth/login` — логин администратора

**Request:**
```json
{ "login": "admin", "password": "secret" }
```

**Response 200:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expiresAt": "2026-09-04T21:00:00Z",
  "mustChangePassword": false
}
```

**Response 401:** `{ "error": "Invalid credentials" }`

---

#### `POST /auth/change-password` — смена пароля

**Request:**
```json
{ "oldPassword": "old", "newPassword": "newpassword123" }
```

**Response 200:** `{ "ok": true }`

---

#### `GET /users` — список VPN-пользователей

**Query params:**
- `page` (int, default=1, ≥1)
- `pageSize` (int, default=20, 1..1000)
- `search` (string, optional) — substring по telegramId
- `filter` (enum, default=`all`) — `all` | `blocked` | `premium`

**Response 200:**
```json
{
  "users": [
    { "username": "123456789", "blocked": false, "premiumAccess": true, "maxSpeed": 100 },
    ...
  ],
  "total": 42
}
```

---

#### `POST /users` — создать пользователя

**Request:**
```json
{ "username": "123456789", "maxSpeed": 100, "premiumAccess": false }
```

**Response 201:** `VpnUser` объект + сгенерированный пароль (только при создании)

---

#### `GET /users/{username}` — получить одного

**Response 200:** `VpnUser`
**Response 404:** `UserNotFound`

---

#### `PUT /users/{username}` — обновить

**Request:**
```json
{ "maxSpeed": 200, "premiumAccess": true, "blocked": false }
```

`blocked=true` автоматически устанавливает `maxSpeed=0`.
`maxSpeed > 0` автоматически снимает блокировку.

---

#### `DELETE /users/{username}` — удалить

**Response 204**

---

#### `POST /users/{username}/token` — выпустить access-токен

**Response 200:**
```json
{ "accessToken": "fptnb:..." }
```

Формат токена: `fptn:<base64-json>` или `fptnb:<base64-brotli-json>` (если `ENABLE_BROTLI_COMPRESSION=true`).

---

#### `GET /servers` — список обычных серверов
#### `GET /servers/premium` — премиум-серверы
#### `GET /servers/censored` — серверы для заблокированных зон

**Response 200:**
```json
{
  "servers": [
    {
      "name": "Main",
      "host": "1.2.3.4",
      "port": 443,
      "md5Fingerprint": "",
      "ping": 10
    }
  ]
}
```

---

#### `POST /servers` / `PUT /servers/{name}` / `DELETE /servers/{name}`

CRUD-операции для серверов.

---

#### `GET /settings` — настройки бота и сервиса

**Response 200:**
```json
{
  "telegramToken": "***",
  "botEnabled": true,
  "serviceName": "FPTN.ONLINE",
  "maxUserSpeedLimit": 100,
  "welcomeMessageEn": "...",
  "welcomeMessageRu": "..."
}
```

#### `PUT /settings` — обновить настройки

**Request:**
```json
{
  "telegramToken": "1234567890:AA...",
  "botEnabled": true,
  "serviceName": "MyVPN",
  "maxUserSpeedLimit": 50,
  "welcomeMessageEn": "Welcome!",
  "welcomeMessageRu": "Привет!"
}
```

При смене токена или включении/выключении бота — автоматический рестарт `bot_runner`.

---

#### `GET /dashboard/highlights` — статистика

**Response 200:**
```json
{
  "totalUsers": 42,
  "premiumUsers": 5,
  "blockedUsers": 3
}
```

---

#### `GET /health` — healthcheck (без авторизации)

**Response 200:** `{ "status": "ok" }`

Используется в `HEALTHCHECK` Docker-контейнера и `fptn-healthcheck.service`.

### 4.3. Ключевые классы C++ (сервер)

#### `fptn::vpn::Manager`
**Файл:** `fptn/src/fptn-server/vpn/manager/`
**Назначение:** Главный цикл VPN-сервера, связывает Web-сервер, TUN-интерфейс, NAT-таблицу и фильтры.

```cpp
class Manager {
public:
    Manager(ServerConfig config);
    ~Manager();
    void Run();      // блокирующий главный цикл
    void Stop();
private:
    ServerConfig config_;
    std::unique_ptr<WebServer> web_server_;
    std::unique_ptr<VirtualInterface> tun_;
    std::unique_ptr<NATTable> nat_table_;
    std::unique_ptr<FilterManager> filters_;
    std::unique_ptr<LeakyBucket> traffic_shaper_;
    std::unique_ptr<UserManager> user_manager_;
    std::unique_ptr<RouteManager> route_manager_;
    std::unique_ptr<Metrics> metrics_;
};
```

#### `fptn::web::Server`
**Файл:** `fptn/src/fptn-server/web/server.h`
**Назначение:** HTTP/WebSocket-сервер на Boost.Beast. Принимает входящие TCP-соединения, определяет фазу (Reality приманка / обфускация / WebSocket-туннель).

```cpp
class Server {
public:
    Server(boost::asio::io_context& ioc, uint16_t port,
           std::shared_ptr<NATTable> nat,
           std::shared_ptr<UserManager> users,
           std::shared_ptr<HandshakeCacheManager> cache);
    void Start();
    void Stop();
private:
    void OnAccept(boost::system::error_code ec, tcp::socket socket);
    void HandleProbingDetection(/* ... */);  // Reality
    SessionPtr CreateSession(WebSocketStream<tcp::socket> ws);
};
```

#### `fptn::nat::Table`
**Файл:** `fptn/src/fptn-server/nat/table/`
**Назначение:** NAT-таблица, привязка `SessionID → виртуальный_IP`.

```cpp
class Table {
public:
    using SessionId = uint32_t;
    SessionId Register(std::shared_ptr<ClientConnection> conn);
    void Unregister(SessionId id);
    std::optional<std::shared_ptr<ClientConnection>> Get(SessionId id);
    std::shared_ptr<ClientConnection> GetByVirtualIPv4(uint32_t ipv4);
    std::shared_ptr<ClientConnection> GetByVirtualIPv6(const std::array<uint8_t, 16>& ipv6);
private:
    std::mutex mu_;
    std::unordered_map<SessionId, std::shared_ptr<ClientConnection>> sessions_;
    IPv4Generator ipv4_gen_;   // 10.10.0.0/16
    IPv6Generator ipv6_gen_;   // fd00::/64
};
```

#### `fptn::nat::ConnectionMultiplexer`
**Назначение:** Объединяет несколько WebSocket-сокетов одного клиента (rolling tunnel) в единый `ClientConnection`. TCP/UDP-флоу закрепляются за сокетом по номеру порта.

```cpp
class ConnectionMultiplexer {
public:
    void AddSocket(uint16_t src_port, WebSocketStreamPtr ws);
    void RemoveSocket(WebSocketStreamPtr ws);
    void SendTo(uint16_t src_port, IPPacket pkt);
    void Broadcast(IPPacket pkt);  // для ответов от сервера
};
```

#### `fptn::traffic_shaper::LeakyBucket`
**Назначение:** Rate-limiting per user. Реализует классический Leaky Bucket — равномерный выпуск с заданной скоростью.

```cpp
class LeakyBucket {
public:
    LeakyBucket(size_t capacity_mb, size_t rate_mbps);
    bool TryConsume(size_t bytes);  // true если можно пропустить
    void Refill();                   // периодически пополняет "уровень"
};
```

#### `fptn::filter::Manager`
**Назначение:** Запускает все фильтры пакета. Пакет отбрасывается, если хоть один фильтр вернёт `false`.

```cpp
class Manager {
public:
    Manager(std::vector<std::unique_ptr<Filter>> filters);
    bool Allow(const IPPacket& pkt) const;
private:
    std::vector<std::unique_ptr<Filter>> filters_;
    // BitTorrent, AntiSpam, DomainBlacklist, AntiScan
};
```

#### `fptn::web::handshake::CacheManager`
**Назначение:** Кэш ServerHello от сайта-прикрытия (TTL 1 час). Используется в Reality для ускорения повторных соединений — не нужно ходить на настоящий сайт каждый раз.

```cpp
class CacheManager {
public:
    std::vector<uint8_t> Get(const std::string& sni);
    void Put(const std::string& sni, std::vector<uint8_t> server_hello);
private:
    struct Entry { std::vector<uint8_t> data; std::chrono::steady_clock::time_point expires; };
    std::unordered_map<std::string, Entry> cache_;
    std::mutex mu_;
};
```

#### `fptn::routing::RouteManager`
**Назначение:** Управление системными маршрутами через `ip route add/del` (нужен root + capability `NET_ADMIN`).

```cpp
class RouteManager {
public:
    void AddDefaultRouteViaTun(const std::string& tun_name);
    void RemoveDefaultRoute();
    void AddSplitTunnelRoute(const std::string& subnet_via, const std::string& gateway);
};
```

### 4.4. Ключевые классы C++ (клиент)

#### `fptn::client::vpn::Manager`
**Файл:** `fptn/src/fptn-client/vpn/vpn_manager/`
**Назначение:** Главный менеджер VPN-клиента. Связывает TUN-интерфейс с пулом WebSocket-соединений.

```cpp
class Manager {
public:
    Manager(std::string tun_name, std::string config_file);
    ~Manager();
    bool Start();      // запускает TUN + WS-пул
    void Stop();
    void Reconnect();  // с exponential backoff: 2 → 5 → 15 → 30 сек, макс 10 рестартов
    Status GetStatus() const;
private:
    void SupervisorLoop();   // отдельный поток, следит за соединениями
    void TunReadLoop();      // TUN → WS (батчинг по 32 пакета)
    void TunWriteLoop();     // WS → TUN (до 128 пакетов в батче)
    std::unique_ptr<VirtualInterface> tun_;
    std::unique_ptr<ConnectionManager> conn_mgr_;
    std::unique_ptr<RouteManager> route_mgr_;
    std::unique_ptr<AdBlock> adblock_;
    std::atomic<int> reconnect_count_{0};
    std::atomic<bool> running_{false};
};
```

#### `fptn::protocol_lib::ConnectionManager`
**Файл:** `fptn/src/fptn-protocol-lib/connection/connection_manager/`
**Назначение:** Управляет JWT-логином и пулом rolling-tunnel сокетов.

```cpp
class ConnectionManager {
public:
    ConnectionManager(ConnectionConfig cfg);
    bool Login();      // POST /api/v1/auth/login → JWT
    void Start();      // запускает стратегию (например, TripleRollingTunnel)
    void Stop();
private:
    ConnectionConfig config_;
    std::unique_ptr<ApiClient> api_client_;
    std::unique_ptr<BaseStrategyConnection> strategy_;
    std::string jwt_token_;
    SessionId session_id_;
};
```

#### `fptn::protocol_lib::RollingTunnel<N, L, S>`
**Файл:** `fptn/src/fptn-protocol-lib/connection/strategies/rolling_tunnel/`
**Назначение:** Шаблон пула сокетов.

```cpp
template <size_t ConnectionCount, uint32_t LifetimeSeconds, uint32_t StaggerSeconds>
class RollingTunnel : public BaseStrategyConnection {
public:
    // Каждые StaggerSeconds запускается новый сокет
    // Старый сокет умирает через LifetimeSeconds
    // Все сокеты пула отправляют один SessionID
};
using SingleRollingTunnel = RollingTunnel<1, 600, 600>;
using DualRollingTunnel   = RollingTunnel<2, 600, 300>;
using TripleRollingTunnel = RollingTunnel<3, 600, 200>;
```

#### `fptn::censorship::Strategy`
**Назначение:** Маскировка клиента под легитимный браузер.

```cpp
enum class CensorshipStrategy : uint8_t {
    kSni             = 0,  // SNI-спуфинг
    kTlsObfuscator   = 1,  // + обфускация TLS
    kSniRealityMode  = 2,  // + Reality
};

// Готовые отпечатки
namespace fingerprints {
    extern const Fingerprint CHROME_145;
    extern const Fingerprint FIREFOX_149;
    extern const Fingerprint YANDEX_BROWSER_24;
    extern const Fingerprint SAFARI_26;
    // ...
}
```

### 4.5. Telegram-бот — команды

Бот встроен в backend (`fptn-admin/backend/app/telegram_bot.py`). Язык определяется по `language_code` пользователя Telegram (`ru`/`en`).

| Команда | Описание |
|---------|----------|
| `/start` | Приветствие + инструкция. Если пользователь новый — автоматически создаётся в `users.list` со скоростью по умолчанию. |
| `/token` | Выдаёт (или перевыпускает) access-токен. Пароль генерируется автоматически, отправляется только в этом сообщении. |
| `/reset` | Сбрасывает пароль пользователя (новый отправляется в ответе). |
| `/info` | Показывает username, скорость, статус блокировки, премиум. |
| `/support` | Ссылка на поддержку (опционально). |

**Реализация:** `BotRunner` — отдельный поток с собственным `asyncio` event loop, использует `python-telegram-bot` 21.x.

```python
class BotRunner:
    def __init__(self, token: str, vpn_store, bot_settings, on_token_change):
        self._token = token
        self._thread: Optional[Thread] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None

    def start(self) -> None:
        self._thread = Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        if self._loop:
            self._loop.call_soon_threadsafe(self._loop.stop)
```

При смене токена бота или переключении `bot_enabled` — `bot_runner.stop()` → `bot_runner.start()` с новыми параметрами.

### 4.6. Формат access-токена

**Структура JSON внутри токена:**

```json
{
  "version": 1,
  "service_name": "FPTN.ONLINE",
  "username": "123456789",
  "password": "abc123secret",
  "servers": {
    "regular": [
      { "name": "Main", "host": "1.2.3.4", "port": 443, "md5_fingerprint": "", "ping": 10 }
    ],
    "premium": [
      { "name": "Premium-1", "host": "5.6.7.8", "port": 443, "md5_fingerprint": "", "ping": 5 }
    ],
    "censored": [
      { "name": "Censored-1", "host": "9.10.11.12", "port": 443, "md5_fingerprint": "", "ping": 20 }
    ]
  }
}
```

**Внешний формат:**

- Без сжатия: `fptn:` + `base64(json)`
- С brotli: `fptnb:` + `base64(brotli_compress(json, quality=11, lgwin=24, lgblock=24, mode=MODE_TEXT))`

**Декодирование на клиенте** (Python / JS):

```python
# Python
import brotli, base64, json

def decode(token: str) -> dict:
    if token.startswith("fptnb:"):
        compressed = base64.b64decode(token[6:])
        raw = brotli.decompress(compressed)
    elif token.startswith("fptn:"):
        raw = base64.b64decode(token[5:])
    else:
        raise ValueError("Invalid token prefix")
    return json.loads(raw)
```

```typescript
// TypeScript (frontend)
import brotliDecode from 'brotli-wasm/decode.js'

export async function decodeFptnToken(token: string): Promise<TokenPayload> {
  if (token.startsWith('fptnb:')) {
    const compressed = Uint8Array.from(atob(token.slice(6)), c => c.charCodeAt(0))
    const raw = brotliDecode(compressed)
    return JSON.parse(new TextDecoder().decode(raw))
  }
  if (token.startsWith('fptn:')) {
    const raw = Uint8Array.from(atob(token.slice(5)), c => c.charCodeAt(0))
    return JSON.parse(new TextDecoder().decode(raw))
  }
  throw new Error('Invalid token prefix')
}
```

---

## 5. Примеры использования

### 5.1. Сценарий 1 — развёртывание с нуля

**Цель:** Развернуть FPTN на VPS `1.2.3.4` с доменом `admin.example.com`.

**Шаги:**

```bash
# 1. С локальной машины загружаем проект
scp -r FTPN root@1.2.3.4:/tmp/

# 2. На сервере открываем порты
ssh root@1.2.3.4
ufw allow 22,443,2663,8080/tcp
ufw enable

# 3. Убеждаемся, что DNS A-запись настроена
dig +short admin.example.com
# Должно вернуть: 1.2.3.4

# 4. Запускаем развёртывание
cd /tmp/FTPN
sudo bash deploy/deploy.sh
```

**Интерактивный ввод:**

```
Внешний IPv4 сервера [1.2.3.4]: 1.2.3.4
Домен для панели (FQDN): admin.example.com
Порт VPN-туннеля [443]: 443
HTTPS порт админ-панели [2663]: 2663
HTTP порт админ-панели (редирект) [8080]: 8080
Backend API порт [8000]: 8000
Telegram bot token (@BotFather): ************
Название сервиса (для токенов) [FPTN.ONLINE]: MyVPN
Скорость по умолчанию (Мбит/с) [100]: 100
Включить brotli-сжатие токенов? (y/n): y
Запускать Telegram-бот сразу? (y/n): y
Сайт-прикрытие (Reality fallback) [yandex.ru]: yandex.ru
Основной SNI (для маскировки) [www.google.com]: www.google.com
Логин администратора [admin]: admin
Пароль администратора: ********
CORS origins (через запятую, или *) [https://admin.example.com]: https://admin.example.com
Включить фильтр BitTorrent? (y/n, по умолчанию y): y
Включить фильтр спама/портов-червей? (y/n, по умолчанию y): y
Макс. активных сессий на юзера [3]: 3
```

**После завершения (≈ 5 минут):**

```
[+] Настроить Let's Encrypt для https://admin.example.com ? (y/n): y
[+] Загружаю nginx + certbot
[+] Создаю конфиг /etc/nginx/sites-available/fptn-admin
[+] Получаю сертификат Let's Encrypt
[+] Сертификат получен: /etc/letsencrypt/live/admin.example.com/
[+] Настраиваю автопродление (certbot.timer)
[+] На VPS всего 1024 МБ RAM — создать swap 2 ГБ? (y/n): y
[+] Создаю swap-файл 2048 МБ
[+] Готово. Можно начинать работу.
```

**Проверка:**

```bash
fptn-status

# Контейнеры:
#   fptn-server                Up 5 minutes
#   fptn-admin-backend         Up 5 minutes
#   fptn-admin-frontend        Up 5 minutes
#   fptn-telegram-bot          Up 5 minutes

# Проверка из браузера:
#   https://admin.example.com → реальный сертификат Let's Encrypt ✓
#   https://1.2.3.4:443       → VPN-туннель работает ✓
```

### 5.2. Сценарий 2 — ежедневная работа администратора

```bash
# Проверить общий статус
fptn-status

# Посмотреть логи backend
fptn-logs backend 200

# Добавить нового пользователя
fptn-add-user 987654321 MyP@ssw0rd 50 0
# [+] Добавлен: 987654321
#     Логин:   987654321
#     Пароль:  MyP@ssw0rd
#     Скорость: 50 Мбит/с
#     Премиум: 0
# [+] Токен: fptnb:...

# Выдать токен существующему пользователю
fptn-issue-token 123456789
# fptnb:eyJzb21ldGhpbmci...

# Заблокировать пользователя (скорость = 0)
# → через UI: Users → выбрать → Edit → maxSpeed=0

# Сделать бэкап
fptn-backup
# [+] Бэкап создан: /var/backups/fptn/fptn-config-20260904-120000.tar.gz (2.1K)

# Обновить до последней версии
fptn-update
# [+] Подтягиваю новые образы
# [+] Перезапускаю стеки
# [+] Готово.
```

**Через UI (https://admin.example.com):**

- **Dashboard** — общая статистика (всего / премиум / заблокированные)
- **Users** — таблица с поиском, фильтрами, пагинацией, генерацией токена
- **Servers** — управление regular / premium / censored серверами
- **Telegram Bot** — настройки токена, приветственных сообщений
- **Premium** — выдача премиум-доступа

### 5.3. Сценарий 3 — пользователь подключается через Telegram-бот

**Шаги пользователя:**

1. Открывает Telegram, находит бота (например, `@MyVPN_bot`)
2. Нажимает `/start` → бот присылает приветствие + инструкцию
3. Нажимает `/token` → бот создаёт пользователя (если нового) и присылает:

   ```
   🔑 Ваш токен доступа (действителен бессрочно):

   fptnb:eyJ2ZXJzaW9uIjoxLCJzZXJ2aWNlX25hbWUiOiJNeVZQQiIsInVzZXJuYW1lIjoiMTIzNDU2Nzg5IiwicGFzc3dvcmQiOiJBYkNERjAxMjM0NTY3ODlBQkNERjAxMjM0NTY3ODlBQkNERjAxMjM0NTY3ODkifQ==

   📱 Скачайте клиент: https://storage.googleapis.com/fptn.org/
   ```

4. Скачивает клиент для своей ОС (Windows / macOS / Linux / Android / iOS)
5. Вставляет токен в клиент → нажимает «Подключиться»
6. Устанавливается TUN-интерфейс с адресом `10.10.0.X`, DNS перенаправляется на сервер

**Что происходит «под капотом»:**

```
Telegram API → BotRunner (asyncio loop)
  → команда /token
  → vpn_store.create(username=telegram_id, password=generated, speed=default)
  → atomic write в users.list (fcntl.flock)
  → server_store.list() → 3 списка серверов
  → build_token(...) + build_access_link(..., brotli=True)
  → reply с токеном
```

### 5.4. Сценарий 4 — выдача премиум-доступа

**Вариант A — через UI:**

1. Зайти в `https://admin.example.com`
2. **Users** → найти пользователя (поиск по telegramId)
3. Нажать **Edit**
4. Переключить `Premium Access = ON`
5. Установить `Max Speed = 1000` (или любое значение)
6. Нажать **Generate Token**
7. Скопировать новый токен (содержит `premium` серверы) → отправить пользователю

**Вариант B — через CLI:**

```bash
# API-запрос напрямую (нужен JWT админа)
TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"login":"admin","password":"secret"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# Включить премиум и увеличить скорость
curl -X PUT "http://localhost:8000/api/v1/users/123456789" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"premiumAccess": true, "maxSpeed": 500}'

# Получить токен
curl -X POST "http://localhost:8000/api/v1/users/123456789/token" \
  -H "Authorization: Bearer $TOKEN"
```

**Ответ:**

```json
{
  "accessToken": "fptnb:eyJ2ZXJzaW9uIjoxLCJzZXJ2aWNlX25hbWUiOiJNeVZQQi..."
}
```

Токен **включает** `servers.premium` список → клиент автоматически выберет премиум-сервер.

### 5.5. Сценарий 5 — обновление и откат

**Обновление до последней версии:**

```bash
sudo fptn-update
# [+] Подтягиваю новые образы сервера
# [+] Подтягиваю/пересобираю админ-панель
# [+] Пересобираю Telegram-бот
# [+] Перезапускаю стеки
# [+] Готово.
```

**Что происходит:**

1. `docker compose pull` — загружает новые образы из DockerHub (`fptnvpn/fptn-vpn-server:0.4.5` и т.д.)
2. `docker compose up -d` — пересоздаёт контейнеры с новыми образами
3. `users.list`, `admins.json`, `servers.json` остаются нетронутыми (общий том)
4. `JWT secret` остаётся (тоже в общем томе)

**Откат при проблемах:**

```bash
# Остановить контейнеры
cd /opt/fptn/compose/server
docker compose down

# Восстановить бэкап
cd /var/backups/fptn
LATEST=$(ls -t fptn-config-*.tar.gz | head -1)
tar -xzf "$LATEST" -C /

# Запустить
cd /opt/fptn/compose/server && docker compose up -d
cd /opt/fptn/compose/admin && docker compose up -d
cd /opt/fptn/compose/bot && docker compose up -d
```

**Ручной откат на конкретную версию:**

```bash
# Временно указать старую версию
cd /opt/fptn/compose/server
sed -i 's/image: fptnvpn\/fptn-vpn-server:0.4.4/image: fptnvpn\/fptn-vpn-server:0.4.3/' docker-compose.yml
docker compose pull
docker compose up -d
```

### 5.6. Примеры HTTP-запросов к API

**cURL примеры (полный набор):**

```bash
API="http://localhost:8000/api/v1"

# 1. Логин
JWT=$(curl -s -X POST "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"login":"admin","password":"admin"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

echo "JWT: $JWT"

# 2. Список пользователей
curl -s "$API/users?page=1&pageSize=20" \
  -H "Authorization: Bearer $JWT" | python3 -m json.tool

# 3. Поиск
curl -s "$API/users?search=123&filter=premium" \
  -H "Authorization: Bearer $JWT" | python3 -m json.tool

# 4. Создать пользователя
curl -s -X POST "$API/users" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"username":"987654321","maxSpeed":50,"premiumAccess":false}'

# 5. Обновить (заблокировать)
curl -s -X PUT "$API/users/987654321" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"blocked":true}'

# 6. Разблокировать + дать премиум
curl -s -X PUT "$API/users/987654321" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"blocked":false,"premiumAccess":true,"maxSpeed":200}'

# 7. Получить токен
curl -s -X POST "$API/users/987654321/token" \
  -H "Authorization: Bearer $JWT" | python3 -m json.tool

# 8. Удалить
curl -s -X DELETE "$API/users/987654321" \
  -H "Authorization: Bearer $JWT" -w "%{http_code}\n"

# 9. Список серверов
curl -s "$API/servers" -H "Authorization: Bearer $JWT" | python3 -m json.tool
curl -s "$API/servers/premium" -H "Authorization: Bearer $JWT" | python3 -m json.tool
curl -s "$API/servers/censored" -H "Authorization: Bearer $JWT" | python3 -m json.tool

# 10. Добавить сервер
curl -s -X POST "$API/servers" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"name":"NewServer","host":"2.3.4.5","port":443,"md5Fingerprint":"","ping":15}'

# 11. Обновить настройки бота
curl -s -X PUT "$API/settings" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "telegramToken":"NEW_TOKEN_HERE",
    "botEnabled":true,
    "serviceName":"MyVPN",
    "maxUserSpeedLimit":100,
    "welcomeMessageEn":"Hi!",
    "welcomeMessageRu":"Привет!"
  }'

# 12. Dashboard
curl -s "$API/dashboard/highlights" -H "Authorization: Bearer $JWT" | python3 -m json.tool

# 13. Healthcheck (без авторизации)
curl -s "$API/health"
```

**Python-клиент:**

```python
import requests

class FptnClient:
    def __init__(self, base_url, login, password):
        self.base = base_url
        self.session = requests.Session()
        r = self.session.post(f"{base_url}/auth/login",
                              json={"login": login, "password": password})
        r.raise_for_status()
        self.token = r.json()["token"]
        self.session.headers["Authorization"] = f"Bearer {self.token}"

    def list_users(self, page=1, search=None, filter="all"):
        params = {"page": page, "pageSize": 50, "filter": filter}
        if search:
            params["search"] = search
        return self.session.get(f"{self.base}/users", params=params).json()

    def issue_token(self, username):
        return self.session.post(f"{self.base}/users/{username}/token").json()["accessToken"]

    def block_user(self, username):
        return self.session.put(f"{self.base}/users/{username}",
                               json={"blocked": True}).json()

# Использование
client = FptnClient("http://localhost:8000/api/v1", "admin", "secret")
print(client.list_users(filter="premium"))
print(client.issue_token("123456789"))
```

---

## 6. Troubleshooting и FAQ

### 6.1. Часто задаваемые вопросы

#### Q: Чем FPTN отличается от обычного VPN (WireGuard, OpenVPN)?

**A:** FPTN **маскирует** VPN-трафик под легитимный HTTPS. На уровне DPI-сканера соединение выглядит как обычный визит на сайт. Это критично в странах с активной блокировкой VPN (Россия, Китай, Иран, Туркменистан и т.д.). Классические VPN блокируются по characteristic patterns (handshake-сигнатура, размер пакетов, энтропия).

#### Q: Можно ли использовать FPTN без админ-панели?

**A:** Да. Минимальная установка — только `fptn-server` через `fptn/docker-compose/`. Пользователи создаются вручную через `fptn-passwd` (формат строки в `users.list`).

#### Q: Как обновить FPTN?

**A:** `sudo fptn-update` — подтянет новые образы из DockerHub и перезапустит контейнеры через systemd.

#### Q: Нужен ли IPv6?

**A:** Нет, но рекомендуется. В `fptn-network` (bridge) включён IPv6 (`dead:beef:cafe::/48`). Клиенты получают IPv6 `fd00::/64` адреса.

#### Q: Можно ли запустить FPTN за Cloudflare / CDN?

**A:** Нет, потому что Reality требует прямого TCP-соединения с сервером для пробинга. CDN подменит IP и сломает анти-DPI.

#### Q: Сколько пользователей выдержит 1 vCPU / 1 ГБ RAM?

**A:** Зависит от нагрузки. На практике: 50–100 активных пользователей с умеренным трафиком (стриминг видео) — это предел. Для > 100 пользователей нужен 2 vCPU + 2 ГБ RAM.

#### Q: Как работает пробинг-защита?

**A:** При первом TCP-соединении на порт 443 сервер проксирует TLS-handshake на сайт-прикрытие (`DEFAULT_PROXY_DOMAIN=yandex.ru`). Сканер видит настоящий сертификат `yandex.ru` и думает, что это обычный сайт. FPTN-клиент же посылает специальный `session_id` с SHA1(unix_time), сервер распознаёт его и переключается в режим туннеля.

#### Q: Пароль в токене — это нормально?

**A:** Да, при условии что токен передаётся по защищённому каналу (Telegram, HTTPS, E2E-мессенджер). Внутри токена пароль в base64, без шифрования. Если злоумышленник перехватит токен — он получит доступ к VPN. Поэтому рекомендуется передавать токены только через защищённые каналы и периодически перевыпускать.

#### Q: Что делать, если VPS заблокирован провайдером?

**A:** Варианты:
1. Сменить IP (пересоздать VPS)
2. Использовать FPTN-сервер на незаблокированном хостинге
3. Применить дополнительные анти-DPI техники (например, сменить `DEFAULT_PROXY_DOMAIN`)

#### Q: Можно ли собрать C++ без conan?

**A:** Теоретически да, если вручную установить все зависимости (Boost, protobuf, fmt, spdlog, jwt-cpp, nlohmann_json, brotli, cpp-httplib, re2, boringssl). Но это намного сложнее — рекомендуется использовать conan.

#### Q: Почему в Docker — root, а не user?

**A:** VPN-сервер требует `NET_ADMIN` capability для создания TUN-интерфейса и изменения маршрутов. Это работает только в privileged-режиме или с `cap_add`. Безопасность обеспечивается изоляцией контейнера (нет доступа к host FS, кроме `/dev/net/tun`).

#### Q: Что произойдёт, если бот-токен утечёт?

**A:** Любой может управлять ботом. **Сразу** смени токен через @BotFather (`/revoke`), затем обнови в `Settings → Telegram Bot` в админке. Бот автоматически перезапустится.

#### Q: Можно ли использовать FPTN как reverse-proxy (без VPN)?

**A:** Да, сервер умеет проксировать произвольные HTTPS-запросы на указанный домен. Это by-design для Reality.

### 6.2. Типовые проблемы и решения

#### Проблема 1: Backend не стартует — `PermissionError: /etc/fptn`

```
FileNotFoundError: [Errno 2] No such file or directory: '/etc/fptn/users.list'
```

**Решение:**
```bash
# Убедись, что FPTN_CONFIGS_FOLDER указывает на существующую папку
sudo mkdir -p /opt/fptn/data/fptn-server
sudo touch /opt/fptn/data/fptn-server/users.list
# Проверь, что в /opt/fptn/compose/admin/.env:
#   FPTN_CONFIGS_FOLDER=/opt/fptn/data/fptn-server
sudo systemctl restart fptn-admin-backend
```

---

#### Проблема 2: VPN-сервер не может создать TUN-интерфейс

```
[ERROR] Cannot create TUN device: Operation not permitted
```

**Решение:**
```bash
# На хосте должен быть загружен модуль tun
sudo modprobe tun
echo "tun" | sudo tee /etc/modules-load.d/fptn.conf

# Проверь capabilities в docker-compose
grep -A 3 "cap_add:" /opt/fptn/compose/server/docker-compose.yml
# Должно быть:
#   cap_add:
#     - NET_ADMIN
#     - SYS_MODULE
#     - NET_RAW
#     - SYS_ADMIN
#     - SYS_RESOURCE
# devices:
#   - /dev/net/tun:/dev/net/tun

sudo systemctl restart fptn-server
```

---

#### Проблема 3: Клиент подключается, но нет интернета

**Симптомы:** TUN создан, IP-пакеты идут, но `curl google.com` зависает.

**Диагностика:**
```bash
# На сервере: проверь NAT
sudo docker exec fptn-server ip route
# Должно быть что-то вроде:
#   10.10.0.0/16 dev fptn-tun0
#   default via 192.168.200.1 dev eth0

# Проверь форвардинг
sudo sysctl net.ipv4.ip_forward
# Должно быть: net.ipv4.ip_forward = 1

# Проверь iptables
sudo iptables -L -t nat
# Должна быть цепочка для маскарадинга
```

**Решение:**
```bash
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-fptn.conf
sudo sysctl -p /etc/sysctl.d/99-fptn.conf
```

---

#### Проблема 4: Telegram-бот не отвечает

**Диагностика:**
```bash
fptn-logs bot 100
# [ERROR] telegram.error.Unauthorized: Bot token is invalid
# или
# [ERROR] ConnectionError: Cannot connect to api.telegram.org
```

**Решение:**
```bash
# 1. Проверь токен через @BotFather
# 2. Убедись, что бот не заблокирован
# 3. Проверь файрвол (исходящий 443/tcp к api.telegram.org должен быть открыт)
curl -I https://api.telegram.org

# 4. Обнови токен через UI или API
curl -X PUT http://localhost:8000/api/v1/settings \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"telegramToken":"NEW_TOKEN","botEnabled":true,"serviceName":"MyVPN","maxUserSpeedLimit":100,"welcomeMessageEn":"","welcomeMessageRu":""}'
```

---

#### Проблема 5: 502 Bad Gateway от nginx (админка)

**Симптомы:** `https://admin.example.com:2663` отдаёт 502.

**Решение:**
```bash
# Проверь, что backend работает
fptn-status
# Если fptn-admin-backend не Up:
sudo systemctl restart fptn-admin-backend

# Проверь сетевую связность между контейнерами
docker exec fptn-admin-frontend wget -O- http://fptn-admin-backend:8000/health
# Должен вернуть {"status":"ok"}

# Если пишет "Name or service not known" — общая сеть не настроена
docker network ls | grep fptn
# Должна быть: fptn-network (bridge)
# Если нет:
docker network create --driver bridge --enable-ipv6 \
  --subnet dead:beef:cafe::/48 --gateway dead:beef:cafe::1 \
  --subnet 192.168.200.0/24 --gateway 192.168.200.1 \
  fptn-network
```

---

#### Проблема 6: Самоподписанный сертификат в браузере

**Симптомы:** Браузер показывает предупреждение о небезопасном соединении.

**Решение A — установить Let's Encrypt (рекомендуется):**
```bash
sudo fptn-setup-letsencrypt
```

**Решение B — добавить сертификат в доверенные (только для тестов):**
```bash
# На клиентской машине (НЕ на сервере!)
scp root@server:/opt/fptn/data/certs/fullchain.pem /tmp/fptn.crt
sudo cp /tmp/fptn.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates   # Debian/Ubuntu
```

---

#### Проблема 7: OOM (out of memory) на VPS 1 ГБ

**Симптомы:** Контейнеры падают с `docker inspect ... OOMKilled: true`.

**Решение:**
```bash
# Создать swap 2 ГБ
sudo fptn-swap-setup 2048

# Или вручную
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
```

---

#### Проблема 8: Контейнер падает в цикле рестарта

**Диагностика:**
```bash
docker logs --tail 50 fptn-server
# Покажет exit reason
```

**Типичные причины:**
- `TUN device not found` → см. Проблема 2
- `Port already in use` → другой процесс занял порт 443
  ```bash
  sudo lsof -i :443
  # Если это apache2 / nginx — останови:
  sudo systemctl stop apache2 nginx
  ```
- `users.list not readable` → `sudo chmod 644 /opt/fptn/data/fptn-server/users.list`

---

#### Проблема 9: Healthcheck timer падает

**Симптомы:** `journalctl -u fptn-healthcheck` показывает `[FAIL]`.

**Решение:**
```bash
# 1. Проверь руками
sudo /usr/bin/docker ps --filter "name=fptn-admin-backend" --filter "status=running"
sudo /usr/bin/docker exec fptn-admin-backend python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=5).read())"

# 2. Если backend контейнер не запущен
sudo systemctl restart fptn-admin-backend

# 3. Если /health не отвечает
sudo /usr/bin/docker logs --tail 20 fptn-admin-backend
```

---

#### Проблема 10: Conan не может собрать Boost (C++)

**Симптомы:** Сборка прерывается на этапе `b2 install`.

**Решение:**
```bash
# Увеличь таймаут и количество параллельных потоков
conan install .. --output-folder=. --build=missing \
  -s compiler.cppstd=17 \
  -o with_gui_client=False \
  --settings build_type=Release \
  --build=boost/[<1.85]  # использовать pre-built binary если доступен

# Или собирай Boost отдельно
conan install .. --build=boost --build=missing -j 2  # только 2 параллельных задачи
```

### 6.3. Логи и диагностика

**Где лежат логи:**

| Источник | Расположение | Как смотреть |
|----------|--------------|--------------|
| Docker-контейнеры | journald | `journalctl -u fptn-server -f` |
| Docker-контейнеры | stdout/stderr | `docker logs -f fptn-server` |
| Все контейнеры сразу | утилита | `fptn-logs` |
| Healthcheck | journald | `journalctl -u fptn-healthcheck -f` |
| Let's Encrypt | /var/log/letsencrypt/ | `cat /var/log/letsencrypt/letsencrypt.log` |
| nginx (reverse-proxy) | /var/log/nginx/ | `tail -f /var/log/nginx/error.log` |
| Bэкапы | /var/backups/fptn/ | `ls -lh /var/backups/fptn/` |

**Уровни логирования C++:**
```cpp
SPDLOG_LOGGER_INFO(logger, "Client connected: {}", client_id);
SPDLOG_LOGGER_WARN(logger, "Rate limit exceeded for user {}", username);
SPDLOG_LOGGER_ERROR(logger, "Failed to create TUN: {}", ec.message());
```

Переменные окружения:
- `SPDLOG_LEVEL=debug` (по умолчанию info)
- `FPTN_LOG_FILE=/var/log/fptn/server.log`

**Уровни логирования backend:**
```python
import logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logging.getLogger("httpx").setLevel(logging.WARNING)  # подавить шум от httpx
```

**Полезные команды:**

```bash
# Проверить, что VPN-сервер слушает
ss -tulpn | grep 443

# Проверить активные соединения к VPN
ss -tn state established '( sport = :443 or dport = :443 )' | head

# Проверить использование трафика per user
docker exec fptn-server cat /proc/$(docker inspect --format '{{.State.Pid}}' fptn-server)/net/dev

# Проверить, что TUN-интерфейс существует
ip link show | grep fptn

# Проверить NAT-таблицу
docker exec fptn-server iptables -L -t nat -n -v

# Проверить загруженные модули ядра
lsmod | grep -E "tun|bbr"

# Проверить BBR
sysctl net.ipv4.tcp_congestion_control
# Должно быть: net.ipv4.tcp_congestion_control = bbr
```

### 6.4. Где получить помощь

**Официальные ресурсы:**

- **GitHub репозиторий:** [github.com/batchar2/fptn](https://github.com/batchar2/fptn)
- **Сайт проекта / клиенты:** [storage.googleapis.com/fptn.org/](https://storage.googleapis.com/fptn.org/)
- **CI/CD:** вкладка Actions в GitHub

**Перед тем как спрашивать, собери информацию:**

```bash
# Версии
fptn-status > /tmp/fptn-status.txt
docker --version >> /tmp/fptn-status.txt
docker compose version >> /tmp/fptn-status.txt
cat /etc/os-release >> /tmp/fptn-status.txt
uname -a >> /tmp/fptn-status.txt

# Логи
fptn-logs server 500 > /tmp/fptn-logs.txt
fptn-logs backend 500 >> /tmp/fptn-logs.txt

# Конфигурация
cat /opt/fptn/deploy-config.env > /tmp/fptn-config.txt
docker network inspect fptn-network >> /tmp/fptn-config.txt

# Архив для отправки
tar -czf /tmp/fptn-diagnostics.tar.gz /tmp/fptn-*.txt
```

**При сообщении об ошибке укажи:**

1. Версия ОС сервера
2. Версия Docker
3. Что делал, когда произошла ошибка
4. Полные логи (не выжимка)
5. Результат `fptn-status`
6. Любые изменения в `/opt/fptn/deploy-config.env` или `.env` файлах

**Полезные каналы сообщества:**

- GitHub Issues (для багов)
- GitHub Discussions (для вопросов)
- Telegram-чаты проекта (см. README)

---

## 📎 Приложения

### Приложение А. Глобальные дефайны C++

Задаются в `fptn/CMakeLists.txt`:

| Дефайн | Значение | Назначение |
|--------|----------|------------|
| `FPTN_VERSION` | 0.4.4 | Версия |
| `FPTN_DEFAULT_MTU_SIZE` | 1420 | MTU по умолчанию |
| `FPTN_IP_PACKET_MAX_SIZE` | 1400 | Макс. размер IP-пакета |
| `FPTN_DEFAULT_SNI` | "rutube.ru" | SNI по умолчанию |
| `FPTN_WITH_LIBIDN2` | ON | IDN-поддержка |
| `FPTN_WITH_MIMALLOC` | OFF | mimalloc-аллокатор |
| `CXX_STANDARD` | 20 | Стандарт C++ |
| `msvc /bigobj` | ON | Для MSVC |

### Приложение Б. Формат `users.list`

```
<telegram_id> <sha256_password_hex> <speed_mbps> <is_premium 0|1>
```

Пример:

```
123456789 5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8 100 0
987654321 ef92b778bafe771e89245b89ecbc08a44a4e166c06659911881f383d4473e94f 500 1
111222333 0000000000000000000000000000000000000000000000000000000000000000 0 0  # заблокирован
```

**Особенности:**
- `speed == 0` → пользователь **заблокирован** (leaky bucket не пропускает ничего)
- `speed > 0` → пользователь активен
- `is_premium == 1` → клиент видит `servers.premium` в токене
- Файл читается и сервером, и backend, и Telegram-ботом через общий том + `fcntl.flock`
- Формат записи: ровно 4 поля, разделённых пробелами

### Приложение В. Права доступа к файлам

| Файл / каталог | Права | Владелец | Зачем |
|----------------|-------|----------|-------|
| `/opt/fptn/` | 755 | root | Корневая папка |
| `/opt/fptn/data/` | 750 | root | Данные |
| `/opt/fptn/data/fptn-server/` | 750 | root | Общий том конфигов |
| `/opt/fptn/data/fptn-server/users.list` | 644 | root | Список пользователей |
| `/opt/fptn/data/fptn-server/admins.json` | 600 | root | Хеши паролей админов |
| `/opt/fptn/data/fptn-server/jwt_secret` | 600 | root | Секрет JWT |
| `/opt/fptn/data/fptn-server/bot_settings.json` | 644 | root | Настройки бота |
| `/opt/fptn/deploy-config.env` | 600 | root | Конфиг развёртывания |
| `/opt/fptn/compose/*/.env` | 600 | root | Docker-конфиги |
| `/opt/fptn/compose/*/fullchain.pem` | 644 | root | TLS-сертификат |
| `/opt/fptn/compose/*/privkey.pem` | 600 | root | TLS-ключ |
| `/var/backups/fptn/` | 700 | root | Бэкапы |
| `/usr/local/bin/fptn-*` | 755 | root | Утилиты |

---

## 📝 Лицензия

Проект распространяется под лицензией MIT (см. LICENSE в корне репозитория).

---

*Документация сгенерирована 04.09.2026. Версия FPTN: 0.4.4*
*Структура и содержание соответствуют актуальному состоянию `main` ветки.*
