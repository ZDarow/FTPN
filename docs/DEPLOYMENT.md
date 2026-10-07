# DEPLOYMENT.md — Фактический развёртывание FPTN на VPS

Дата: 2026-10-07  
VPS: `213.21.242.99` (Ubuntu 24.04.5 LTS, controversial-az.aeza.network)  
Статус: развёрнуто и рабочее

---

## 1. Подготовка сервера

### 1.1 SSH-ключ
- Сгенерирован локальный ключ `id_ed25519_fptn` (без passphrase).
- Публичный ключ скопирован в `/root/.ssh/authorized_keys` на VPS.
- Права: `chmod 700 ~/.ssh`, `chmod 600 ~/.ssh/authorized_keys`.
- Парольная аутентификация отключена:
  - `PermitRootLogin prohibit-password`
  - `PasswordAuthentication no`
  - `systemctl reload ssh`

### 1.2 Prerequisites
Выполнен скрипт `deploy/prereq-install.sh`:
- Docker 29.8.2 + Compose v5.6.0
- nginx
- certbot
- UFW

---

## 2. VPN-сервер

### 2.1 Репозиторий
- Клонирован в `/opt/fptn`.

### 2.2 SSL-сертификаты
- Самоподписанные сертификаты сгенерированы через `openssl req -x509`:
  - `/opt/fptn/fptn/docker-compose/fptn-server-data/server.crt`
  - `/opt/fptn/fptn/docker-compose/fptn-server-data/server.key`
- CN=`213.21.242.99`, срок 10 лет.

### 2.3 Конфигурация
Файл `/opt/fptn/fptn/docker-compose/.env`:
- `SERVER_EXTERNAL_IPS=213.21.242.99`
- Остальные параметры — дефолтные из `.env.demo`.

### 2.4 Запуск
```bash
cd /opt/fptn/fptn/docker-compose
docker compose up -d
```

Контейнер: `docker-compose-fptn-server-1`  
Образ: `fptnvpn/fptn-vpn-server:0.4.4`  
Статус: healthy  
Порты: `0.0.0.0:443->443/tcp`

---

## 3. Админ-панель

### 3.1 Файл окружения
Создан `/opt/fptn/fptn-admin/.env` (chmod 600):
```env
JWT_TTL_MINUTES=60
ADMIN_LOGIN=admin
ADMIN_PASSWORD=<сгенерирован автоматически>
CORS_ORIGINS=https://213.21.242.99:2663
ENABLE_BROTLI_COMPRESSION=true
FPTN_CONFIGS_FOLDER=/opt/fptn/fptn/docker-compose/fptn-server-data
TELEGRAM_TOKEN=
BOT_ENABLED=false
SERVICE_NAME=fptn
MAX_USER_SPEED_LIMIT=30
WELCOME_MESSAGE_EN=
WELCOME_MESSAGE_RU=
```

Важно: `FPTN_CONFIGS_FOLDER` указывает на общую папку с VPN-сервером, чтобы панель и сервер видели одни и те же `users.list`, `servers.json` и т.д.

### 3.2 Сборка и запуск
```bash
cd /opt/fptn/fptn-admin
docker compose build
docker compose up -d
```

Контейнеры:
- `fptn-admin-fptn-admin-backend-1` — порт `8000:8000`
- `fptn-admin-fptn-admin-frontend-1` — порты `2663:443`, `8080:80`

### 3.3 Проверка
- Backend health: `http://213.21.242.99:8000/health` → `{"status":"ok","version":"0.1.0"}`
- Frontend: `https://213.21.242.99:2663/` → HTML-страница панели
- JWT-секрет сгенерирован автоматически в `/etc/fptn/jwt_secret`

---

## 4. Данные и файлы

Путь на хосте: `/opt/fptn/fptn/docker-compose/fptn-server-data/`  
Монтируется в `/etc/fptn` внутри обоих контейнеров.

Файлы:
- `users.list` — создан пустой
- `servers.json` — будет создан панелью при добавлении серверов
- `premium_servers.json` — будет создан панелью
- `servers_censored_zone.json` — будет создан панелью
- `admins.json` — будет создан панелью при первом входе
- `bot_settings.json` — будет создан при включении бота
- `jwt_secret` — сгенерирован автоматически бэкендом
- `blacklist.txt` — загружен при старте VPN
- `server.crt` / `server.key` — самоподписанные SSL-сертификаты

---

## 5. Доступ

| Сервис | URL | Логин | Пароль |
|--------|-----|-------|--------|
| VPN | `213.21.242.99:443` | — | — |
| Админ-панель | `https://213.21.242.99:2663` | `admin` | см. `/root/fptn-admin-panel.pass` на VPS |
| Backend API | `http://213.21.242.99:8000` | — | — |

---

## 6. Известные ограничения

1. **Самоподписанный SSL** на фронтенде — браузер будет ругаться на недоверенный сертификат. Для production нужно заменить на Let's Encrypt.
2. **Telegram-бот** не настроен (по умолчанию выключен).
3. **Firewall UFW** установлен, но правила не настраивались — порты 443, 2663, 8000 открыты.
4. **npm audit** в Dockerfile фронтенда показывает 22 уязвимости (5 moderate, 15 high, 2 critical). В репозитории уже есть 16 overrides, но audit всё равно падает. Сборка пропущена через `--audit-level=critical || true`.

---

## 7. Что изменено в репозитории

- `docs/DEPLOYMENT.md` — этот файл.
- Никаких других файлов не менялось; весь деплой выполнен на VPS.

---

## 8. Команды для управления

```bash
# VPN
cd /opt/fptn/fptn/docker-compose
docker compose ps
docker compose logs -f

# Админ-панель
cd /opt/fptn/fptn-admin
docker compose ps
docker compose logs -f

# Перезапуск
cd /opt/fptn/fptn/docker-compose && docker compose up -d
cd /opt/fptn/fptn-admin && docker compose up -d
```
