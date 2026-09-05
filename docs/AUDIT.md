# 🔍 Аудит FPTN — комплексный отчёт

**Дата:** 04.09.2026 · **Версия:** 0.4.4 · **Объём:** 73 755 строк, 246 файлов

---

## 📊 Сводка по критичности

| Уровень | Кол-во | Что делать |
|---------|--------|------------|
| 🔴 **Критично** | 6 | Исправить в течение 1–2 недель |
| 🟠 **Важно** | 11 | Исправить в течение месяца |
| 🟡 **Желательно** | 9 | При ближайшем рефакторинге |
| 🟢 **Информация** | 5 | Учесть в долгосрочном плане |

---

## 1. Метрики проекта

```
Всего строк кода:     73 755
Файлов исходников:    246
├── C++:               163 (.cpp + .h)
├── Python:             39
├── TypeScript:         44 (.ts + .tsx)
├── Protocol Buffers:   ?
└── Прочее:             (YAML, JSON, MD)

Тесты:
├── C++ (gtest):       17 файлов
├── Python (pytest):    7 файлов
├── JS (vitest):        5 файлов
└── Соотношение src/test: ~1:4 (низкое!)

Классы / функции:
├── C++ классы:         65
├── C++ методы:        470
├── Python классы:      32
├── Python функции:     32
└── TS компоненты:      18 (function declarations)
```

---

## 2. Архитектура

### 2.1. ✅ Что сделано хорошо

| Решение | Оценка |
|---------|--------|
| Единый файл `users.list` через общий том | ⭐⭐⭐⭐⭐ — элегантно, нет БД |
| `fcntl.flock` + atomic write | ⭐⭐⭐⭐⭐ — корректная синхронизация |
| `BaseSettings` через pydantic | ⭐⭐⭐⭐⭐ — type-safe конфиг |
| `yaff` как альтернатива protobuf | ⭐⭐⭐⭐ — компактнее, быстрее |
| `RollingTunnel` как compile-time шаблон | ⭐⭐⭐⭐⭐ — zero-cost абстракция |
| Multi-stage Dockerfiles с test-gate | ⭐⭐⭐⭐⭐ — лучшие практики |
| `HealthCheck` через systemd timer | ⭐⭐⭐⭐ — лучше cron |
| Разделение docker-сети для ботов | ⭐⭐⭐⭐ — изоляция стеков |

### 2.2. 🟠 Архитектурные проблемы

| # | Проблема | Критичность | Где |
|---|----------|-------------|-----|
| A1 | `fptn/src/fptn-server/web/session/session.cpp` — 1450 строк, 114 условных переходов. Цикломатическая сложность **очень высокая**. Нарушение SRP. | 🟠 | `web/session/session.cpp` |
| A2 | `fptn-client/routing/route_manager.cpp` — 1533 строки, нет unit-тестов. Маршрутизация — критическая логика. | 🟠 | `routing/route_manager.cpp` |
| A3 | `BotRunner` использует глобальный singleton (`bot_runner`) — нарушение DI, проблема для тестирования. | 🟡 | `app/telegram_bot.py` |
| A4 | `fptn-admin/backend/app/stores/*` — нет интерфейса (`Protocol`/`ABC`). Все Store-классы связаны через конкретные классы. | 🟡 | `app/stores/*.py` |
| A5 | `Settings` (pydantic) — 24 поля, все в одном классе. Нет группировки (DB, Bot, JWT, Paths). | 🟡 | `app/config.py` |
| A6 | Frontend: `App.tsx` и `AuthContext` напрямую импортируют `localStorage` — нет абстракции storage. | 🟡 | `context/AuthContext.tsx` |
| A7 | Дублирование логики "чтение JSON + fcntl lock" в каждом store. Нет базового класса `JsonStore`. | 🟠 | `stores/{admin,vpn_user,server,bot_settings}_store.py` |
| A8 | `fptn/src/common/network/ip_packet.h` — 737 строк (только заголовок!). Нарушение ODR-безопасности. | 🟠 | `common/network/ip_packet.h` |

---

## 3. Зависимости

### 3.1. 🔴 Критические проблемы

| # | Пакет | Текущая | Актуальная | Проблема |
|---|-------|---------|------------|----------|
| **D1** | `python:3.14-slim` | 3.14 | 3.14 (стабильный с 2025-10) | EOL **2030-10**, но в продакшене сыроват. Подождать 3.13 LTS или 3.12. |
| **D2** | `react` | 18.2.0 | 19.0 | React 19 stable вышел. Безопасность, performance, новые API. |
| **D3** | `vite` | 4.1.1 | 6.x | Vite 5/6 даёт в 2-3 раза быстрее сборку, улучшенный HMR. |
| **D4** | `typescript` | 4.9.5 | 5.7+ | 4.x не получает фиксы с 2024. |
| **D5** | `tailwindcss` | 3.2.6 | 4.x | Tailwind 4 — новый движок, в 10 раз быстрее, oxide. |
| **D6** | `eslint` (и плагины) | 8.34.0 | 9.x | ESLint 9 — flat config, новые правила. |

### 3.2. 🟠 Устаревшие (но не критичные)

| # | Пакет | Текущая | Актуальная | Комментарий |
|---|-------|---------|------------|-------------|
| D7 | `vitest` | 0.32.2 | 2.x | Vitest 1→2: API стабилизировался, лучше mock. |
| D8 | `jsdom` | 22.1.0 | 25.x | Больше совместимости. |
| D9 | `lucide-react` | 1.25.0 | 0.4xx | Major version 0.x → icon API изменился. |
| D10 | `i18next` | 23.16.8 | 24.x | Критичные фиксы. |
| D11 | `react-i18next` | 14.1.3 | 15.x |  |
| D12 | `brotli-wasm` | 3.0.1 | последняя | Не критично, 3.x стабилен. |

### 3.3. 🟢 Актуальные (OK)

| Пакет | Версия | Статус |
|-------|--------|--------|
| `python-telegram-bot` | 21.4–22.0 | Актуально, поддерживается |
| `pydantic-settings` | 2.7+ | Актуально |
| `fastapi` | 0.115+ | Актуально |
| `bcrypt` | 4.x | Стабильно |
| `boost` (C++) | 1.90 | Актуально (2025-12) |
| `protobuf` | 5.29.3 | Актуально |

### 3.4. 🟠 Проблемы манифестов

| # | Проблема | Файл | Критичность |
|---|----------|------|-------------|
| M1 | `pylint` отключает `too-many-arguments` — скрывает реальные проблемы. | `pyproject.toml` | 🟡 |
| M2 | `pylint` отключает `duplicate-code` — допускает копипасту. | `pyproject.toml` | 🟡 |
| M3 | `eslint` — старая версия 8.x, несовместима с flat config. | `package.json` | 🟠 |
| M4 | `conanfile.py` — 30+ `boost/*:without_*` опций. Можно заменить на `boost/*:without_default=True` + явный список. | `conanfile.py` | 🟡 |
| M5 | `package.json` — нет `"engines"` поля (минимальные версии Node). | `package.json` | 🟡 |
| M6 | `pyproject.toml` — `requires-python = ">=3.13"` жёстко, нет `python_requires` метаданных для колеса. | `pyproject.toml` | 🟡 |

---

## 4. Безопасность

### 4.1. 🔴 Критические

| # | Проблема | Где | Воздействие |
|---|----------|-----|-------------|
| **S1** | **SHA-256 для VPN-паролей** (без salt). Атакующий с доступом к `users.list` мгновенно восстанавливает пароли через rainbow tables для коротких/простых паролей. | `stores/vpn_user_store.py` | 🔴 компрометация всех VPN-аккаунтов |
| **S2** | **Пароль передаётся в access-токене открытым текстом** (base64, не шифрованный). Перехват токена = компрометация аккаунта. | `app/vpn_token.py` | 🔴 утечка при перехвате |
| **S3** | **CORS по умолчанию `*`** в backend. CSRF-атаки возможны, если админ залогинен в админку и зайдёт на вредоносный сайт. | `app/main.py` | 🔴 угон сессии админа |
| **S4** | **JWT secret в файле `/etc/fptn/jwt_secret`** без ротации. Компрометация файла = подделка любых токенов навсегда. | `app/secret.py` | 🔴 утечка = полный контроль над админкой |
| **S5** | **Нет rate-limiting** на `/auth/login`. Brute-force пароля админа не ограничен. | `routers/auth.py` | 🔴 подбор пароля |
| **S6** | **Нет HTTPS-only** флагов для JWT-токена. Хранится в `localStorage` — доступен XSS. | `frontend/context/AuthContext.tsx` | 🔴 XSS = утечка токена |

### 4.2. 🟠 Важные

| # | Проблема | Воздействие |
|---|----------|-------------|
| S7 | Самоподписанный сертификат на 10 лет (`-days 3650`) в nginx entrypoint. | MITM при первом подключении. |
| S8 | Нет `httponly` cookies — JWT в `localStorage`. | XSS = угон. |
| S9 | `get_jwt_secret()` создаёт файл с дефолтным `0o600`, но не проверяет владельца. | Неправильные права = утечка. |
| S10 | Telegram-токен передаётся через `settings` → `bot_settings.json` в открытом виде. | Файл читаем root'ом. |
| S11 | Docker-контейнеры работают **под root** (`USER root` нет, но privileged + cap_add). | Компрометация = root на хосте. |

### 4.3. 🟡 Желательно

| # | Проблема | Воздействие |
|---|----------|-------------|
| S12 | `bcrypt.checkpw` без тайминг-атак защиты (но bcrypt сам защищён). | OK |
| S13 | Нет CSRF-токенов (не нужны, если JWT в header, но при `*` CORS — опасно). | Cross-origin. |
| S14 | Нет аудит-лога действий админа (кто блокировал/изменял юзеров). | Неотслеживаемость. |
| S15 | `users.list` chmod 644, доступен на чтение всем в контейнере. | Side-channel. |

---

## 5. Качество кода

### 5.1. C++ ядро

| Метрика | Значение | Оценка |
|---------|----------|--------|
| `using namespace` | 0 | ✅ отлично |
| Raw `new` без smart ptr | 154 | 🟠 умеренно (в 53 .cpp файлах) |
| Магические числа (не `constexpr`) | 69 | 🟡 местами |
| `/** */` docstrings | 7 (на 163 файла!) | 🔴 плохо |
| Файлы >500 строк | 9 (макс 1533) | 🟠 god-файлы |
| Цикломатика >50 | 1 (session.cpp — 114) | 🟠 refactor |

**Проблемные файлы (LOC):**

```
1533  fptn-client/routing/route_manager.cpp
1512  fptn-client/gui/settingswidget/settings.cpp
1450  fptn-server/web/session/session.cpp        ← критично
1195  fptn-client/gui/tray/tray.cpp
1175  fptn-protocol-lib/https/api_client/api_client.cpp
 920  fptn-client/gui/settingsmodel/settingsmodel.cpp
 911  fptn-protocol-lib/https/websocket_client/websocket_client.cpp
 795  frontend/src/pages/Servers.tsx
 737  common/network/ip_packet.h                  ← header-only 737 строк!
 616  fptn-client/fptn-client-cli.cpp
```

### 5.2. Python backend

| Метрика | Значение | Оценка |
|---------|----------|--------|
| `Any` типы | 0 | ✅ |
| Pydantic models | 18 | ✅ правильный подход |
| Тесты | 7 | 🟠 мало (нужно ≥15) |
| `print()` | 0 | ✅ |
| `"""` docstrings | 18 | 🟡 базовое покрытие |
| Цикломатика в больших файлах | ≤33 | ✅ |

### 5.3. Frontend (React/TS)

| Метрика | Значение | Оценка |
|---------|----------|--------|
| `any` типы | 0 | ✅ |
| `console.log` | 0 | ✅ |
| `/** */` JSDoc | 0 | 🔴 нет документации |
| Class components | 0 | ✅ все функциональные |
| Тесты | 5 | 🟠 мало |
| `Dockerfile USER` | нет | 🟠 контейнер под root |

---

## 6. CI/CD и инфраструктура

| # | Проблема | Критичность |
|---|----------|-------------|
| I1 | `renovate.json` обновляет **только conan** — npm/pip не покрыты. | 🟠 |
| I2 | `package-lock.json` есть, но `npm ci` без `npm audit` в CI. | 🟠 |
| I3 | Нет `dependabot.yml` для GitHub. | 🟡 |
| I4 | Нет security-сканирования (Trivy, Grype, Snyk). | 🟠 |
| I5 | Нет matrix-build для нескольких версий Python (только latest 3.14). | 🟡 |
| I6 | CI не запускает `frontend build` (только `lint + tsc + vitest`). | 🟡 |
| I7 | Docker-образ публикуется **только на release** (нет `latest` тега). | 🟡 |
| I8 | Backend Dockerfile — обе стадии `FROM python:3.14-slim` (test + runtime). Можно кэшировать базовый слой. | 🟢 |
| I9 | Нет `.dockerignore` — в образ может попасть `node_modules`, `.git`, тесты. | 🟠 |

---

## 7. Структура директорий

### 7.1. ✅ Хорошо

- `fptn/src/{common, fptn-protocol-lib, fptn-server, fptn-client, fptn-passwd}` — **строгое разделение** по ответственности
- `fptn-admin/{backend, frontend}` — чистое разделение фронт/бэк
- `tests/` рядом с `src/` не смешаны

### 7.2. 🟠 Проблемы

| # | Проблема | Где |
|---|----------|-----|
| D1 | Глубина вложенности 6 уровней (`fptn/src/common/network/ip_utils/...`) | `fptn/src/common/network/` |
| D2 | Дублирование: `fptn-admin/.env.demo` vs `fptn/.env.demo` vs `fptn/sysadmin-tools/telegram-bot/.env.demo` — 3 разных формата | Корень |
| D3 | `fptn-admin/frontend/assets/` и `fptn-admin/frontend/src/assets/` — две папки для assets. | `frontend/` |
| D4 | `fptn/src/fptn-protocol-lib/protocol/protobuf/` (сгенерированное) рядом с `.proto` файлами — нет `.gitignore` для generated. | `protocol/` |
| D5 | `depends/` (conan overrides) рядом с `conanfile.py` — нестандартное расположение. | `fptn/` |
| D6 | `cpplint.py` лежит в корне `fptn/`, а не в `tools/` или `scripts/`. | `fptn/` |
| D7 | Нет `docs/` архитектурной диаграммы. `DOCUMENTATION.md` (создан) — вне проекта. | Корень |
| D8 | `.sandbox/` (эксперименты) коммитится в репо. | Корень |

### 7.3. 🟡 CamelCase в именах файлов

В `fptn-admin/frontend/src/pages/` — все файлы в **PascalCase** (`Login.tsx`, `Users.tsx`), что **не соответствует snake_case/kebab-case**, рекомендованному в `AGENTS.md` (имя пользователя).

Файлы: `Login.tsx`, `ChangePassword.tsx`, `Dashboard.tsx`, `Users.tsx`, `Servers.tsx`, `TelegramBot.tsx`, `GivePremiumAccess.tsx`, `ComingSoon.tsx`, `fptnToken.ts`.

**Рекомендация:** оставить PascalCase для React-компонентов (стандарт сообщества React), но переименовать `fptnToken.ts` → `fptn_token.ts` для соответствия AGENTS.md.

---

## 8. Управление состоянием

### 8.1. Frontend

- **Локальное состояние:** `useState` в компонентах — OK.
- **Глобальное состояние:** только `AuthContext` (JWT) — минимально, OK.
- **Серверное состояние:** нет React Query/SWR — **каждый компонент делает fetch напрямую**. Это ведёт к дублированию запросов.
- **Кеширование:** нет.

**Проблема:** нет слоя управления серверным состоянием. Решение — добавить **TanStack Query (React Query)** или **SWR**.

### 8.2. Backend

- **Singleton-объекты:** `admin_store`, `vpn_store`, `server_store`, `bot_settings_store` (через `Depends`).
- **Concurrency:** `fcntl.flock` — корректно.
- **Bot:** `bot_runner` — глобальный singleton, стартует/останавливается через lifespan.
- **No database migrations** — файловое хранилище, нет схемы для миграций.

### 8.3. C++

- **`vpn::Manager`** — большой класс с состоянием всего сервера. Один mutex?
- **`NATTable`** — мьютекс на всю таблицу. Под нагрузкой — bottleneck. Решение: шардирование по `SessionID % N`.
- **`LeakyBucket`** — глобальный словарь по `SessionID`. Потенциальная race condition.
- **`ConnectionMultiplexer`** — на каждый WS-сокет, синхронизация?

---

## 9. Алгоритмы и корректность

| # | Файл | Алгоритм | Проблема |
|---|------|----------|----------|
| K1 | `fptn-server/web/handshake/handshake_cache_manager.cpp` | Кэш ServerHello, TTL 1 час | Нет LRU — при большом количестве SNI память растёт. |
| K2 | `common/network/ip_packet.h` | Парсинг IP-пакета | **737 строк в header** — ODR-нарушение возможно, медленная компиляция. |
| K3 | `connection/strategies/rolling_tunnel` | Пул сокетов | Логика `stagger` — нет проверки, что все сокеты не умирают одновременно. |
| K4 | `nat/table.cpp` | Поиск по SessionID | O(1) — OK, но линейный поиск по virtual_ip при истечении. |
| K5 | `traffic_shaper/leaky_bucket` | Rate-limiting | На каждом пакете вычисление — нет token bucket refill раз в N миллисекунд. |

---

## 10. План рефакторинга (приоритизированный)

### Фаза 1 — Критические фиксы (1–2 недели)

| # | Действие | Трудоёмкость | Воздействие |
|---|----------|--------------|-------------|
| **1.1** | Заменить SHA-256 на **Argon2id** для VPN-паролей. C++ сервер должен поддержать. | 3 дня | Безопасность |
| **1.2** | Ограничить CORS по умолчанию до конкретного домена (убрать `*`). | 1 час | Безопасность |
| **1.3** | Добавить rate-limiting на `/auth/login` (slowapi или nginx). | 1 день | Безопасность |
| **1.4** | Заменить `localStorage` JWT на `httpOnly + Secure + SameSite=Strict` cookies. | 2 дня | Безопасность |
| **1.5** | Добавить `.dockerignore` файлы. | 1 час | Размер образа |
| **1.6** | Включить `npm audit` и `pip-audit` в CI. | 2 часа | Безопасность |

### Фаза 2 — Архитектурный рефакторинг (1 месяц)

| # | Действие | Трудоёмкость | Воздействие |
|---|----------|--------------|-------------|
| **2.1** | Разбить `session.cpp` (1450 строк) на 5–7 классов по фазам протокола. | 1 неделя | Поддерживаемость |
| **2.2** | Ввести базовый класс `JsonStore` для всех stores. | 2 дня | DRY |
| **2.3** | Ввести интерфейсы (`Protocol`) для Store и Bot. | 2 дня | Тестируемость |
| **2.4** | Добавить `abc.ABC` для всех `*Store` классов. | 1 день | SOLID-D |
| **2.5** | Группировать `Settings` по доменам: `JWTSettings`, `BotSettings`, `PathSettings`. | 2 дня | SRP |
| **2.6** | Внедрить TanStack Query (React Query) на фронте. | 3 дня | UX (кеш, retries) |
| **2.7** | Расширить renovate до `npm` и `pip`. | 2 часа | Безопасность |
| **2.8** | Добавить `Trivy` сканирование в CI. | 2 часа | Безопасность |

### Фаза 3 — Обновление зависимостей (2 недели)

| # | Действие | Трудоёмкость | Риск |
|---|----------|--------------|------|
| **3.1** | React 18 → 19 (проверить совместимость react-router-dom 6.11). | 1 неделя | Средний |
| **3.2** | Vite 4 → 6 + Vitest 0.32 → 2. | 2 дня | Низкий |
| **3.3** | TypeScript 4.9 → 5.7. | 1 день | Низкий |
| **3.4** | Tailwind 3.2 → 4.x. | 2 дня | Средний (breaking) |
| **3.5** | Python 3.14 → 3.13 (LTS) **на проде** (разработка может остаться на 3.14). | 1 день | Низкий |
| **3.6** | ESLint 8 → 9 + flat config. | 1 день | Низкий |

### Фаза 4 — Качество и долги (1 месяц)

| # | Действие | Трудоёмкость |
|---|----------|--------------|
| **4.1** | Увеличить покрытие тестов: backend до 80%, C++ до 60% (gtest — добавить 20+ новых тестов). | 2 недели |
| **4.2** | Добавить docstrings: C++ Doxygen, Python (Google style), TypeScript JSDoc. | 1 неделя |
| **4.3** | Извлечь `ip_packet.cpp` из `ip_packet.h`. | 2 дня |
| **4.4** | LRU-кеш для `handshake_cache_manager`. | 1 день |
| **4.5** | Удалить `.sandbox/` из репозитория (перенести в git sub-module или игнорировать). | 1 час |
| **4.6** | Включить `eslint` правила `no-explicit-any`, `no-console`. | 1 час |

### Фаза 5 — Долгосрочно

| # | Действие |
|---|----------|
| **5.1** | Миграция с файлового хранилища на SQLite (если > 100 юзеров) |
| **5.2** | gRPC для внутренних сервисов (заменить REST для admin↔backend) |
| **5.3** | WebSocket-push для UI вместо polling |
| **5.4** | Kubernetes Helm chart для развёртывания |
| **5.5** | OpenTelemetry для трассировки |

---

## 11. Сводка рисков

| Риск | Вероятность | Воздействие | Митигация |
|------|-------------|-------------|-----------|
| Атака через SHA-256 rainbow tables | Высокая | Компрометация всех VPN | Argon2id (Фаза 1.1) |
| CORS `*` + украденный JWT | Средняя | Угон админки | CORS + httpOnly cookies (Фаза 1.2, 1.4) |
| Утечка `users.list` через бэкап | Средняя | Все пароли восстановимы | Argon2id |
| React 18 / Vite 4 уязвимости | Низкая | XSS, supply chain | Обновление (Фаза 3) |
| `session.cpp` регрессия при правке | Высокая | Падение сервера | Рефакторинг (Фаза 2.1) |
| Docker образ с уязвимыми пакетами | Средняя | Container escape | Trivy в CI (Фаза 2.8) |

---

## 12. Что **не нужно** менять

| Решение | Почему OK |
|---------|-----------|
| `users.list` вместо БД | Для 5–100 юзеров — оптимально, нет миграций |
| `fcntl.flock` для синхронизации | Корректно для file-based store |
| `protobuf` + `yaff` | Два формата для разных клиентов — OK |
| `nginx:1.27-alpine` | Актуальная LTS-версия |
| `python:3.14-slim` | Для dev — OK, для prod — обсуждаемо |
| Multi-stage Dockerfiles | Best practice, оставить |
| `systemd` юниты | Правильный подход |
| `brotli` для токенов | Экономия 30% места — OK |

---

## 13. Метрики для отслеживания

После рефакторинга целевые показатели:

```
Покрытие тестами:        ≥80% (backend), ≥60% (C++), ≥70% (frontend)
Файлов > 500 строк:      0
Файлов > 1000 строк:     0 (или явно обоснованы)
Использование Any:       0
TODO/FIXME в коде:       0
Magic numbers:           0 (все constexpr)
C++ Cyclomatic > 30:     0
Цикломатика в Python:    ≤20
```

---

## ✅ Итог

| Категория | Оценка |
|-----------|--------|
| Архитектура | 8/10 (хорошо, есть god-файлы) |
| Безопасность | 5/10 (SHA-256 + CORS `*` + JWT в localStorage) |
| Зависимости | 6/10 (frontend устарел, C++ актуален) |
| Качество кода | 7/10 (нет документации, мало тестов) |
| Инфраструктура | 8/10 (multi-stage, healthchecks, systemd) |
| Структура директорий | 8/10 (один CamelCase, нет docs/) |
| **Среднее** | **7/10** |

**Главный приоритет:** безопасность (S1, S3, S5) → архитектура (A1, A7) → обновления (D2, D3, D4, D6).

**Что НЕ критично:** философия, именование, мелкие оптимизации.
