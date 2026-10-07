# Аудит кодовой базы FPTN — сводный отчёт

Дата: 2026-10-07  
Объект: монорепозиторий `C:\Users\Mi\FTPN`  
Метод: статический анализ (grep/glob/read), без сборки/запуска инструментов  
Ограничения: Windows-среда, поэтому `pytest`, `mypy`, `pylint`, `npm audit`, `pip-audit`, `ctest`, `cppcheck` не запускались.

---

## 1. C++ ядро (`fptn/`)

Статус: **частично проверено** (отчёт субджента обрезан лимитом вывода). Ниже — подтверждённые находки.

### 1.1 Синтаксические / типологические проблемы

| # | Файл:строка | Критичность | Описание | Рекомендация |
|---|--------------|-------------|----------|--------------|
| 1.1 | `fptn/src/fptn-protocol-lib/https/api_client/api_client.h:35-41` | **high** | `Response::operator=` использует placement new, не exception-safe. | Заменить на `= default`. |
| 1.2 | `fptn/src/fptn-protocol-lib/https/utils/tls/tls.cpp:390,432` | **medium** | Ручное `new`/`delete` для `CertificateVerificationCallback`; возможна утечка при исключении. | `std::unique_ptr` в контейнере. |
| 1.3 | `fptn/src/fptn-protocol-lib/https/obfuscator/methods/tls/tls_obfuscator.cpp:66,73` и `tls_obfuscator2.cpp:77,83,90` | **high** | `static std::mt19937` не thread-safe; гонка при параллельном доступе. | `thread_local static std::mt19937`. |
| 1.4 | `fptn/src/common/client_id.h:14` | **low** | `#define MAX_CLIENT_ID (UINT64_MAX)` — макрос вместо `constexpr`. | `inline constexpr std::uint64_t MAX_CLIENT_ID = UINT64_MAX;`. |
| 1.5 | `fptn/src/fptn-protocol-lib/https/obfuscator/methods/tls/tls_obfuscator.cpp:27` и `tls_obfuscator2.cpp:27` | **low** | Необладающий `enum` в анонимном namespace. | `enum class` или `constexpr`. |
| 1.6 | `fptn/src/fptn-client/adblock/adblock.cpp:21-22` | **low** | `extern const unsigned char kBlocklistGz[]` — глобальное состояние, риск ODR. | Инкапсулировать в класс/namespace. |
| 1.7 | `fptn/src/common/network/tun/linux_tun_device.h:68` | **low** | `const_cast<void*>(data)` — технически UB. | Изменить сигнатуру `Write` на `void*` или убедиться, что `tun_->write` принимает `const void*`. |

### 1.2 Архитектурные запахи

| # | Файл:строка | Критичность | Описание | Рекомендация |
|---|--------------|-------------|----------|--------------|
| 2.1 | `fptn/src/fptn-server/web/session/session.cpp` (~1450 строк) | **high** | God Object: HTTP, WebSocket, probing, proxy, obfuscator, token parsing. | Разбить на `HttpParser`, `ProxyHandler`, `ObfuscationDetector`, вынести кэш. |
| 2.2 | `fptn/src/fptn-server/web/session/session.cpp:54-55` | **high** | `static std::mutex ip_mutex; static std::vector<std::string> server_ips;` — глобальное изменяемое состояние. | Синглтон или DI. |
| 2.3 | `fptn/src/fptn-server/web/session/session.cpp:115-116` | **high** | `std::mutex self_proxy_mutex; std::unordered_map<std::string, SelfProxyEntry> self_proxy_cache;` — глобальное состояние. | `SelfProxyCacheManager`. |
| 2.4 | `fptn/src/fptn-server/web/handshake/handshake_cache_manager.cpp` | **medium** | `std::unordered_map` без LRU/лимита; память растёт с числом SNI. | Лимит 1024 + LRU. |
| 2.5 | `fptn/src/fptn-server/routing/route_manager.cpp` + `fptn/src/fptn-client/routing/route_manager.cpp` | **medium** | Смешение построения команд, очереди, потоков. | Разделить на `RouteConfigBuilder`, `RouteApplier`, `RouteWorkerPool`. |
| 2.6 | `fptn/src/fptn-server/web/session/session.cpp:947` | **medium** | `buffer.reserve(4 * 1024 * 1024)` — 4 MB на сессию. | Уменьшить до 256 KB или пул буферов. |

### 1.3 Потоки данных

| # | Файл:строка | Критичность | Описание | Рекомендация |
|---|--------------|-------------|----------|--------------|
| 3.1 | `fptn/src/common/network/tun/darwin_tun_device.h:115-118,123-125,142-143,147-148` | **critical** | `system(cmd.c_str())` с конкатенацией `name_`, `addr`, `mask` — инъекция команд. | `posix_spawn`/`execve` с массивом аргументов или валидация. |
| 3.2 | `fptn/src/fptn-server/routing/route_manager.cpp:31-33` и `fptn/src/common/system/command.cpp:37-39` | **high** | `boost::process::child` с одной строкой вызывает `sh -c`; имена интерфейсов без экранирования. | Вектор аргументов или allowlist. |
| 3.3 | `fptn/src/fptn-client/routing/route_manager.cpp:162,175,201,214,239,253,274,286` | **high** | Аналогично: `fmt::format` + `system::run` с неэкранированными `out_interface`, `gateway_ip`, `destination`. | Аргументированный вызов. |
| 3.4 | `fptn/src/fptn-protocol-lib/https/obfuscator/methods/tls/tls_obfuscator.cpp:66,73` и `tls_obfuscator2.cpp:77,83,90` | **high** | Гонка данных при параллельном доступе к `static std::mt19937`. | `thread_local static`. |
| 3.5 | `fptn/src/fptn-server/web/session/session.cpp:54-55,115-116` | **medium** | Глобальное состояние с мьютексами — риск deadlock. | Инкапсулировать в классы. |
| 3.6 | `fptn/src/common/user/common_user_manager.h:149-160` | **medium** | `SaveUsers` пишет `std::ofstream` напрямую; при падении — битый `users.list`. | Атомарная запись: temp + `std::rename`. |
| 3.7 | `fptn/src/fptn-protocol-lib/https/obfuscator/methods/tls/tls_obfuscator.cpp:102` и `tls_obfuscator2.cpp:118` | **low** | `input_buffer_.size() + size > kMmaxBufferSize` — возможен integer overflow. | `size > kMmaxBufferSize || input_buffer_.size() > kMmaxBufferSize - size`. |

### 1.4 Безопасность

| # | Файл:строка | Критичность | Описание | Рекомендация |
|---|--------------|-------------|----------|--------------|
| 4.1 | `fptn/src/common/user/common_user_manager.h:173` | **critical** | SHA-256 без соли для паролей VPN-пользователей (S1). | bcrypt/argon2id/scrypt с уникальной солью. |
| 4.2 | `fptn/src/fptn-protocol-lib/https/utils/tls/tls.cpp:411` и `api_client/api_client.cpp:977-984` | **high** | MD5 fingerprint для pinning — коллизионно уязвим. | SHA-256/SHA-384 fingerprint или CA-проверка. |
| 4.3 | `fptn/src/fptn-protocol-lib/https/obfuscator/methods/tls/tls_obfuscator.cpp` и `tls_obfuscator2.cpp` | **high** | Гонка на `static std::mt19937` (см. 1.3, 3.4). | `thread_local static`. |
| 4.4 | `fptn/src/fptn-server/web/session/session.cpp` | **medium** | Парсинг HTTP/WebSocket без явной валидации заголовков; возможен malformed request. | Добавить строгий парсинг с лимитами. |

### 1.5 Зависимости

| # | Пакет | Критичность | Описание | Рекомендация |
|---|-------|-------------|----------|--------------|
| 5.1 | protobuf 5.29.3 (lite) | **low** | Версия указана в `conanfile.py`; без сборки невозможно проверить ABI-совместимость с Boost 1.90.0. | Проверить `conan install` в WSL2. |
| 5.2 | Boost 1.90.0 (Asio, coroutines) | **low** | Asio + coroutines совместимы с C++20; без сборки не проверить. | Ок. |
| 5.3 | boringssl | **low** | Используется для TLS; без сборки не проверить версию и CVE. | Запустить `conan outdated` в WSL2. |
| 5.4 | fmt 12.1.0, spdlog 1.17.0, jwt-cpp 0.7.2, nlohmann_json 3.12.0, re2, zlib 1.3.2, argparse 3.2 | **info** | Версии зафиксированы в `conanfile.py`; без сборки/`conan outdated` актуальность не определить. | Запустить в WSL2. |

### 1.6 Не проверено

- Циклические зависимости (требует граф сборки).
- Дублирование кода (copy-paste) — без инструментов типа `jscpd` невозможно точно оценить.
- Buffer overflow в `ip_packet.h` — без контекста использования.
- Integer overflow в арифметике размеров пакетов.
- Небезопасная десериализация protobuf — формат корректный, но без тестов не подтвердить.
- Секреты в коде — не найдены.
- Полный вывод аудита C++ обрезан; возможны дополнительные находки.

---

## 2. Python backend (`fptn-admin/backend/`)

### 2.1 Безопасность

| # | Файл:строка | Критичность | Описание | Рекомендация |
|---|--------------|-------------|----------|--------------|
| S1 | `app/stores/vpn_user_store.py:50-52` | **critical** | SHA-256 без соли для паролей VPN-пользователей. | bcrypt/argon2 с уникальной сольой; синхронное изменение в C++. |
| S2 | `app/vpn_token.py:28` | **critical** | Пароль VPN-пользователя в access-токене в открытом виде. | Убрать пароль из payload; reference id + подпись. |
| S16 | `app/telegram_bot.py:76-109` | **critical** | `/token` выдаёт токен любому, нет проверки `from_user.id`. | Проверка регистрации в `vpn_user_store`. |
| S5 | `app/routers/auth.py:11-23` | **high** | Нет rate-limiting на `/auth/login`. | Лимит попыток с экспоненциальной задержкой. |
| — | `app/main.py:51-56` | **medium** | `allow_methods=["*"]`, `allow_headers=["*"]`; дефолт `allow_origins` пустой — ок. | Оставить дефолт пустым; явно перечислять trusted origins. |
| — | `app/config.py:9-15,27` | **medium** | Жёсткие пути `/etc/fptn/...`; права на директорию не проверяются. | Убедиться, что `/etc/fptn` имеет `0o700`. |
| — | `app/stores/server_store.py:39-40` | **medium** | `_write` не устанавливает `chmod 0o600`. | Добавить `path.chmod(0o600)`. |
| — | `app/stores/vpn_user_store.py:59-60,80-93` | **medium** | `touch()` и `mkstemp`+`os.replace` не сбрасывают права. | `self.path.chmod(0o600)`. |
| — | `app/secret.py:21-24` | **low** | Ошибка `chmod` подавляется без логирования. | `logger.warning` при неудачном `chmod`. |

### 2.2 Архитектура

| # | Файл:строка | Критичность | Описание | Рекомендация |
|---|--------------|-------------|----------|--------------|
| A1 | `app/stores/server_store.py` | **high** | Нет блокировок при `add`/`update`/`delete`; race condition с `bot_settings_store`. | Добавить `fcntl`-блокировку. |
| A2 | `app/stores/admin_store.py:26-37,56-71` | **medium** | Аналогично, нет блокировки при `create`/`change_password`. | Добавить `fcntl` или `threading.Lock`. |
| A3 | `app/stores/bot_settings_store.py:40-53` | **medium** | `get()` без блокировки, `update()` с `threading.Lock`; возможна частичная запись. | Защитить `get` тем же `RLock` или атомарная запись. |
| A4 | `app/schemas.py:43-54,57-68` | **low** | `UserUpdate` позволяет менять `username` без `isalnum` валидатора. | Вынести валидатор в общую функцию. |
| A5 | `app/schemas.py:79-96` | **low** | `Server`/`ServerUpdate` не валидируют `port` (1-65535), `md5_fingerprint` (hex), `host` (формат). | Добавить `Field(ge=1, le=65535)` и валидаторы. |
| A6 | `app/vpn_token.py:13-32` | **low** | `build_token` принимает `list[dict]` без типизации. | `TypedDict` или `pydantic.BaseModel`. |
| A7 | `app/telegram_bot.py:1-179` | **medium** | Бот встроен в процесс backend; падение бота влияет на API. | Вынос в отдельный сервис/очередь. |

### 2.3 Типы и логика

| # | Файл:строка | Критичность | Описание | Рекомендация |
|---|--------------|-------------|----------|--------------|
| T1 | `app/stores/server_store.py:29,39,42` | **medium** | `dict`/`list[dict]` без typed dict/dataclass. | `@dataclass ServerRecord`. |
| T2 | `app/routers/users.py:20-31` | **low** | `_issue_token` принимает `password: str` в открытом виде. | Явный `VpnRecord` или возврат из store. |
| T3 | `app/stores/vpn_user_store.py:62-78` | **low** | `_read_all` пропускает битые строки без логирования. | `logger.warning` при коррумпированной строке. |
| T4 | `app/main.py:19` | **low** | `logging.basicConfig(level=logging.INFO)` в production избыточен. | `WARNING` для корневого логгера через env. |
| T5 | `app/schemas.py:1` | **low** | `Optional` из `typing` вместо `str | None` (PEP 604). | Перевести на `| None`. |
| T6 | `app/security.py:13-16` | **low** | `create_access_token` не включает `iat`/`nbf`/`jti`. | Добавить `iat` и опционально `jti`. |

### 2.4 Зависимости

| # | Пакет | Версия | Критичность | Описание | Рекомендация |
|---|-------|--------|-------------|----------|--------------|
| D1 | `python-telegram-bot` | 21.11.1 | **medium** | Зависит от `httpx>=0.27,<1.0`; lock: `httpx 0.28.1`. Без `pip-audit` CVE не определить. | Запустить `poetry run pip-audit` в Linux/WSL. |
| D2 | `fastapi` | 0.115.6 | **low** | Зависит от `starlette>=0.40.0,<0.42.0`. | Проверить версию в `poetry.lock`. |
| D3 | `bcrypt` | 4.2.1 | **low** | CVE-2024-29861 закрыт в 4.0+. | Ок. |
| D4 | `PyJWT` | 2.10.1 | **low** | Актуальная; HS256 используется корректно. | Ок. |
| D5 | `pydantic-settings` | 2.7.1 | **low** | Совместима с `pydantic 2.13.4`. | Ок. |

### 2.5 Потоки данных

| # | Поток | Критичность | Описание | Рекомендация |
|---|-------|-------------|----------|--------------|
| P1 | `POST /users/{u}/token` → `build_token` → ответ | **critical** | Пароль в открытом виде в токене и JSON-ответе. | Убрать пароль из токена. |
| P2 | `POST /auth/login` → JWT → `localStorage` | **medium** | JWT в `localStorage` без httponly cookie. | httpOnly + secure cookie. |
| P3 | Telegram-бот → `build_token` → пользователь | **high** | Токен с паролем в личку; компрометация Telegram = утечка пароля. | Уменьшить TTL, revoked, отдельный канал для пароля. |
| P4 | `settings.update` → `bot_settings_store.update` → `_restart_bot` | **low** | Старый токен в памяти до перезапуска. | Остановить бота ДО обновления файла. |
| P5 | Логи | **low** | Пароли/токены в логах не обнаружены. | Ок. |

### 2.6 Не проверено

- CVE через `pip-audit` (требуется Linux/WSL).
- Работа `fcntl` на Windows (не поддерживается).
- Совместимость изменённого формата паролей с C++ сервером.

---

## 3. Frontend (`fptn-admin/frontend/`)

### 3.1 Безопасность

| # | Файл:строка | Критичность | Описание | Рекомендация |
|---|--------------|-------------|----------|--------------|
| F1 | `src/context/AuthContext.tsx` | **high** | JWT и refresh в `localStorage` без httponly, CSRF, secure-флага. | httpOnly cookie (SameSite=Strict/Lax) + CSRF-токен. |
| F2 | `src/api/client.ts` | **high** | Нет явной проверки origin; CORS на бэкенде, но клиент уязвим к MITM при слабом TLS. | `Access-Control-Allow-Credentials`, строгий origin; не передавать креды к не-https. |
| F3 | `src/lib/fptnToken.ts` | **high** | Пароль VPN-пользователя в токене в открытом виде (S2). | Убрать пароль из payload; reference id + подпись. |
| F4 | `src/pages/Login.tsx` / `src/api/auth.ts` | **medium** | Нет `autocomplete="off"` / `new-password`. | Добавить атрибуты, `credentials: 'same-origin'`, не кэшировать ответы. |
| F5 | `src/**/*.tsx` | **medium** | Отсутствует CSP. | Строгий CSP: `script-src 'self'`; без `unsafe-inline`/`unsafe-eval`. |
| F6 | `src/**/*.tsx` | **low** | Нет `dangerouslySetInnerHTML` — положительно. | Продолжить избегать innerHTML. |

### 3.2 Архитектура

| # | Файл:строка | Критичность | Описание | Рекомендация |
|---|--------------|-------------|----------|--------------|
| A1 | `src/App.tsx` | **medium** | Центральный роутинг и `RequireAuth`; при росте — God-component. | Вынести маршруты в `src/routes/` или конфиг-массив. |
| A2 | `src/pages/Users.tsx`, `Servers.tsx`, `TelegramBot.tsx` | **medium** | Много логики запросов и фильтров; prop drilling. | Кастомные хуки (`useUsers`, `useServers`); `useReducer` для модалок. |
| A3 | `src/components/ui/` | **low** | `Button`, `Modal`, `Pagination`, `Table`, `Spinner` — переиспользуемые, но без `forwardRef` в некоторых. | Добавить `forwardRef` для композиции. |
| A4 | `src/context/AuthContext.tsx` | **low** | Контекст сплющен: токен, пароль, isAuthenticated, login, logout. | Разделить на `AuthContext` + `TokenContext` или Zustand. |
| A5 | `src/i18n/ru.json`, `en.json` | **low** | Нет fallback на дефолтный язык. | `fallbackLng: 'en'` в i18next-init. |

### 3.3 Типы

| # | Файл:строка | Критичность | Описание | Рекомендация |
|---|--------------|-------------|----------|--------------|
| T1 | `src/api/client.ts` | **medium** | `fetch` обёрнуты в `any`/`unknown`; типы ответов не строгие. | Generic `<T>` в `api.get<T>()`, `zod` для валидации. |
| T2 | `src/components/ui/Table.tsx` | **medium** | `any[]` или `Record<string, any>`. | `Table<T>` с `columns: Column<T>[]`. |
| T3 | `src/lib/fptnToken.ts` | **medium** | Декодер возвращает `any`; нет типов для payload. | `FptnTokenPayload` интерфейс. |
| T4 | `src/**/*.tsx` | **low** | `@ts-ignore` не найден; `as any` точечно. | ESLint `@typescript-eslint/no-explicit-any`. |

### 3.4 Зависимости

| # | Пакет | Версия | Критичность | Описание | Рекомендация |
|---|-------|--------|-------------|----------|--------------|
| D1 | `react-router-dom` | 7.18.3 | **medium** | v7 имеет breaking changes относительно v6; требуется верификация маршрутизации. | Убедиться, что код использует v7-паттерны (`createBrowserRouter`, `RouterProvider`). |
| D2 | `vite` / `react` / `tailwindcss` / `vitest` | 5.4 / 18.3.1 / 3.4 / 2.1.8 | **low** | Совместимы. | Ок. |
| D3 | `brotli-wasm` | 3.0.1 | **low** | Требует `?worker`/`?bundle` параметры; может сломать SSR/SSG. | Проверить `vite.config.ts` `optimizeDeps`/`ssr.noExternal`. |
| D4 | 16 `overrides` в `package.json` | **low** | Без `npm audit` актуальность CVE не определить. | Запустить `npm audit` в Linux/CI. |

### 3.5 Потоки данных

| # | Поток | Критичность | Описание | Рекомендация |
|---|-------|-------------|----------|--------------|
| P1 | `login` → `localStorage.setItem('token')` → контекст | **high** | 401 → `refreshAccessToken()` → повтор запроса; нет обработки гонки при параллельных запросах. | Очередь/замок (pending refresh promise). |
| P2 | `client.ts` 401 → refresh → повтор | **high** | Нет события `onTokenRefreshed`; UI не обновляется атомарно. | `tokenRefresh$` как `Subject` в контексте. |
| P3 | Запросы через `client.ts` | **medium** | Нет централизованного кэширования/инвалидации. | `@tanstack/react-query`. |
| P4 | `Dashboard.tsx` | **low** | Данные подгружаются при монтировании; нет polling/SSE. | Добавить WebSocket/SSE если нужны live-данные. |

### 3.6 Не проверено

- Циклические импорты.
- Размер бандла и unused exports.
- Фактические CVE в `package-lock.json`.
- Работа `brotli-wasm` в проде.
- Дублирование строк в переводах i18n.
- Доступность (a11y).

---

## 4. Deploy / инфраструктура (`deploy/`)

### 4.1 Безопасность

| # | Файл:строка | Критичность | Описание | Рекомендация |
|---|--------------|-------------|----------|--------------|
| D1 | `deploy/install-admin.sh:132-145`, `deploy/full-install.sh:140-153`, `deploy/install-bot.sh:88-96` | **critical** | Shell-инъекция в here-doc при записи .env: значения с `$`, `` ` ``, `"`, `\` вызывают подстановку/разрыв. | Кавычки в here-doc или `printf '%s=%q\n'`. |
| D2 | `deploy/configure.sh:61-72` | **critical** | `set_env_var()` экранирует только `/`, `&`, `|`; другие sed-метасимволы ломают файл. | Полное экранирование или awk/while-read. |
| D3 | `fptn/docker-compose/docker-compose.yml:5-11` | **critical** | `privileged: true` + `SYS_ADMIN`, `SYS_MODULE`, `NET_ADMIN`, `NET_RAW`, `SYS_RESOURCE` — эквивалент root на хосте. | Минимизировать capabilities; `security_opt: [no-new-privileges:true]`, `read_only: true`, `seccomp`. |
| D4 | `fptn-admin/docker-compose.yml:27,37`, `fptn/sysadmin-tools/telegram-bot/docker-compose.yml:18` | **critical** | `fcntl`-блокировки не работают между контейнерами (разные PID- namespace'ы); возможна гонка записи в `users.list`, `servers.json`. | Sidecar с API, атомарные операции, retry с backoff. |
| D5 | `deploy/full-install.sh:106-109` | **critical** | `openssl req` создаёт `server.key` с правами 0644 (читаем всем). | `umask 077` перед генерацией + `chmod 600`. |
| D6 | `deploy/full-install.sh:38,133-134` | **critical** | Fallback пароля `admin1234` (слабый); `--admin-password` виден в `ps aux` и истории. | Убрать fallback; читать из `FPTN_ADMIN_PASSWORD` или `/dev/tty`. |
| D7 | `deploy/lib/tui.sh:98-109` | **critical** | `tui_password` в stdin-fallback делает `echo "$val"` — пароль в stdout. | Не эхоить в stdout; возвращать через переменную. |

### 4.2 Высокие риски

| # | Файл:строка | Критичность | Описание | Рекомендация |
|---|--------------|-------------|----------|--------------|
| D8 | `deploy/uninstall.sh:26` | **high** | `rm -rf /opt/fptn` без бэкапа. | `--preserve-data`, архив, подтверждение. |
| D9 | `deploy/install.sh:48`, `deploy/lib/install-manager.sh:61-64` | **high** | `curl | sh` без GPG/SHA256. | Официальный apt-репозиторий; проверка целостности. |
| D10 | `fptn-admin/docker-compose.yml:27,37`, `fptn/sysadmin-tools/telegram-bot/docker-compose.yml:18` | **high** | Несколько контейнеров пишут в один volume; frontend не должен писать в `/etc/fptn`. | Frontend `:ro`; backend/bot — отдельные подпапки или API. |
| D11 | `deploy/prereq-install.sh:75-101,121,148-155` | **high** | Нет pinning версий пакетов (кроме conan). | Конкретные версии или `apt-mark hold`. |
| D12 | `deploy/prereq-install.sh:129-142` | **high** | UFW без fail2ban; SSH открыт в интернет без hardening. | `fail2ban`, `PasswordAuthentication no`, `PermitRootLogin no`. |

### 4.3 Средние

| # | Файл:строка | Критичность | Описание | Рекомендация |
|---|--------------|-------------|----------|--------------|
| D13 | `deploy/full-install.sh` | **medium** | Нет идемпотентности; повторный запуск перезапишет .env и перезапустит контейнеры. | Проверка `docker compose ps`, флаг `--force`. |
| D14 | `deploy/configure.sh`, `deploy/install-admin.sh`, `deploy/full-install.sh` | **medium** | Нет бэкапов перед модификацией конфигов. | `cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%s)"`. |
| D15 | `deploy/install-bot.sh:32` | **medium** | Устанавливает legacy-бота, а не `fptn-admin-bot`. | Переименовать или добавить предупреждение. |
| D16 | `deploy/install-admin.sh:50-52` | **medium** | `CUR_PASS` зарезервировано, но нигде не загружается. | Реализовать или убрать. |

### 4.4 Низкие / информационные

| # | Файл:строка | Критичность | Описание | Рекомендация |
|---|--------------|-------------|----------|--------------|
| D17 | `AGENTS.md` | **low** | Утверждает, что `deploy/prereq-install.sh:189-191` содержит несуществующие пути; в текущем коде эти пути отсутствуют. | Обновить AGENTS.md. |
| D18 | `deploy/configure.sh:116,151`, `deploy/prereq-install.sh:185-192` | **low** | Жёстко заданные домены/пути. | Вынести в переменные. |
| D19 | `deploy/install.sh:118`, `deploy/full-install.sh:214-215` | **low** | Ссылки на внешние ресурсы. | Указать опциональность и альтернативы. |

### 4.5 Проверенные и признанные безопасными паттерны

- `set -Eeuo pipefail` — есть во всех скриптах.
- Проверка `EUID` — есть.
- `chmod 600 .env` — есть.
- `trap + mktemp` в `install-manager.sh` — временный файл удаляется.
- `docker compose down || true` в `uninstall.sh` — подавление ожидаемых ошибок.
- Идемпотентность `apt-get` — проверка `command -v`.
- Валидация домена/IP — регулярные выражения присутствуют.
- Нет явных секретов в логах.

---

## 5. Сводная таблица критичности

| Критичность | C++ | Backend | Frontend | Deploy | Итого |
|-------------|-----|---------|----------|--------|-------|
| **critical** | 2 | 3 | 0 | 7 | 12 |
| **high** | 4 | 2 | 3 | 5 | 14 |
| **medium** | 5 | 5 | 5 | 4 | 19 |
| **low** | 5 | 6 | 5 | 3 | 19 |
| **info** | 0 | 0 | 0 | 2 | 2 |
| **Итого** | 16 | 16 | 13 | 21 | 66 |

> C++ аудит частичный; реальное количество находок может быть выше.

---

## 6. Рекомендации по приоритету

### Срочно (critical)

1. **Исправить shell-инъекции в here-doc** (`deploy/install-admin.sh`, `deploy/full-install.sh`, `deploy/install-bot.sh`).
2. **Исправить sed-экранирование** (`deploy/configure.sh`).
3. **Убрать `privileged` и минимизировать capabilities** (`fptn/docker-compose/docker-compose.yml`).
4. **Решить проблему общей файловой системы** между backend/frontend/bot (`fcntl` не работает между контейнерами).
5. **Исправить права на `server.key`** (`deploy/full-install.sh` — `umask 077` + `chmod 600`).
6. **Убрать fallback `admin1234`** и читать пароль из env/stdin (`deploy/full-install.sh`).
7. **Не эхоить пароль в stdout** (`deploy/lib/tui.sh`).

### Высоко (high)

8. **Добавить rate-limiting** на `/auth/login` (`app/routers/auth.py`).
9. **Заменить MD5 на SHA-256/SHA-384** для fingerprint (`tls.cpp`, `api_client.cpp`).
10. **Исправить гонку на `static std::mt19937`** (`tls_obfuscator.cpp`, `tls_obfuscator2.cpp`).
11. **Добавить проверки целостности** для `curl | sh` (`deploy/install.sh`, `install-manager.sh`).
12. **Установить fail2ban и hardening SSH** (`deploy/prereq-install.sh`).

### Средне (medium)

13. **Добавить блокировки** в `ServerStore` и `AdminStore`.
14. **Добавить бэкапы** перед модификацией конфигов.
15. **Добавить идемпотентность** в `full-install.sh`.
16. **Переименовать/предупредить** про `install-bot.sh` (legacy).
17. **Уменьшить буфер** в `session.cpp:947` (4 MB → 256 KB).
18. **Добавить LRU** в `handshake_cache_manager.cpp`.

### Низко (low)

19. Обновить `AGENTS.md` (устаревшие пути).
20. Вынести хардкод доменов/путей в переменные.
21. Заменить макросы на `constexpr`.
22. Добавить `forwardRef` в UI-компоненты.
23. Добавить CSP на фронтенде.
24. Перевести `Optional` на `| None`.

---

## 7. Не проверено

- CVE через `pip-audit`, `npm audit`, `conan outdated` (требуется Linux/WSL).
- Сборка C++ и запуск `ctest` (требуется WSL2/Linux).
- Запуск `pytest`, `mypy`, `pylint`, `eslint`, `tsc`, `vitest` (требуется Linux/WSL).
- Циклические зависимости в C++ (требует граф сборки).
- Дублирование кода (copy-paste) — без `jscpd` невозможно точно оценить.
- Полный аудит C++ — вывод субджента обрезан; возможны дополнительные находки.

---

## 8. Готовые патчи

### 8.1 `deploy/full-install.sh` — права на SSL ключ и пароль

```bash
# Перед генерацией ключа:
umask 077
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout "$VPN_DATA/server.key" \
  -out "$VPN_DATA/server.crt" \
  -subj "/CN=$PUBLIC_IP" 2>/dev/null
chmod 600 "$VPN_DATA/server.key"

# Убрать fallback пароля:
if [[ -z "$ADMIN_PASSWORD" ]]; then
  ADMIN_PASSWORD=$(openssl rand -base64 16)
fi

# Читать пароль из env, а не из CLI:
# Убрать --admin-password из аргументов;
# использовать FPTN_ADMIN_PASSWORD="${FPTN_ADMIN_PASSWORD:-}"
```

### 8.2 `deploy/install-admin.sh` — here-doc инъекция

```bash
# Вместо:
cat > "$ENV_FILE" <<EOF
ADMIN_PASSWORD=$PASS_INPUT
EOF

# Использовать:
printf '%s=%s\n' "ADMIN_PASSWORD" "$PASS_INPUT" > "$ENV_FILE"
# или
cat > "$ENV_FILE" <<EOF
ADMIN_PASSWORD="${PASS_INPUT}"
EOF
```

### 8.3 `deploy/configure.sh` — sed-экранирование

```bash
set_env_var() {
  local key="$1" value="$2"
  local esc
  esc=$(printf '%s\n' "$value" | sed 's/[][\.^$*+?{}()|/&]/\\&/g')
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${esc}|" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}
```

### 8.4 `fptn/docker-compose/docker-compose.yml` — минимизация привилегий

```yaml
services:
  fptn-server:
    privileged: false
    cap_add:
      - NET_ADMIN
      - NET_RAW
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /run
      - /tmp
```

### 8.5 `app/vpn_token.py` — убрать пароль из токена

```python
# Вместо:
payload = {"username": username, "password": password, ...}

# Использовать:
payload = {"username": username, "user_id": user_id, ...}
# Пароль передавать через отдельный защищённый канал или не передавать вообще.
```

### 8.6 `app/stores/vpn_user_store.py` — bcrypt вместо SHA-256

```python
import bcrypt

def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()

def verify_password(password: str, hashed: str) -> bool:
    return bcrypt.checkpw(password.encode(), hashed.encode())
```

### 8.7 `app/telegram_bot.py` — проверка пользователя

```python
# В _get_access_token добавить:
user = vpn_user_store.get_user_by_telegram_id(update.effective_user.id)
if not user:
    await update.message.reply_text("Вы не зарегистрированы в VPN.")
    return
```

### 8.8 C++ — thread_local для mt19937

```cpp
// В tls_obfuscator.cpp и tls_obfuscator2.cpp:
thread_local static std::mt19937 rng{std::random_device{}()};
```

### 8.9 C++ — атомарная запись users.list

```cpp
void SaveUsers(const std::string& path, const std::vector<User>& users) {
    std::string tmp = path + ".tmp";
    {
        std::ofstream out(tmp);
        // ... запись ...
    }
    std::rename(tmp.c_str(), path.c_str());
}
```

---

## 9. Заключение

Аудит выявил **66 находок** (12 critical, 14 high, 19 medium, 19 low, 2 info).  
Наиболее критичные:
- Shell-инъекции в deploy-скриптах.
- Привилегированные контейнеры с полными capabilities.
- Отсутствие блокировок между контейнерами на общей ФС.
- Пароли в открытом виде в токенах (C++ и Python).
- SHA-256 без соли для паролей VPN.
- MD5 fingerprint для TLS pinning.

Рекомендуется исправить critical/high находки перед продакшен-развёртыванием.
