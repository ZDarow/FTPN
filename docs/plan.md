## Аудит репозитория fptn-admin

> **Контекст:** Документ создан как предварительный аудит `fptn-admin` (монолитный репозиторий `FTPN`). С тех пор в `FTPN/deploy/` появились два варианта развёртывания: полный стек (Docker) и облегчённый `deploy/family/` (systemd-нативный, VPN+бот, опционально панель). Развёртывание через `git clone` ниже — пример для полного варианта; для `family` см. `deploy/family/README.md`.

### 1. Общее описание проекта

**FPTN Admin Panel** — это веб-интерфейс для администрирования VPN-сервера [FPTN](https://github.com/batchar2/fptn). Проект состоит из двух частей:

| Компонент | Стек | Назначение |
|-----------|------|------------|
| **Backend** | FastAPI + Poetry + Python 3.13 | REST API, бизнес-логика, Telegram-бот |
| **Frontend** | React 18.3 + TypeScript 5 + Vite 8 + Tailwind 3.4 | SPA-панель администратора |

---

### 2. Архитектура и ключевые особенности

**Хранение данных:**
- Единый источник данных — файл `users.list` (формат: одна строка на пользователя, SHA-256 пароля, скорость, премиум-статус)
- Блокировка реализована через `speed == 0` (сервер FPTN обрезает туннель до нуля)
- Администраторы хранятся в `admins.json` с bcrypt-хешированием
- Настройки бота — в `bot_settings.json`

**Telegram-бот:**
- Запускается в фоновом потоке внутри backend-процесса
- Использует те же файлы данных, что и REST API, с блокировками
- Управляется через настройки панели (вкл/выкл, приветственные сообщения)

**Токены доступа:**
- Формат: `fptn:` + base64(JSON с username, password, servers)
- Пароль передаётся в открытом виде внутри токена (поэтому доступен только при создании или перевыпуске)

**Безопасность:**
- JWT-аутентификация для администраторов
- При первом входе с дефолтным паролем `admin/admin` принудительная смена пароля
- Самоподписанный HTTPS-сертификат генерируется при первом запуске
- CORS-настройки через переменную окружения

---

### 3. Docker-инфраструктура

**docker-compose.yml**:

| Сервис | Порт | Особенности |
|--------|------|-------------|
| `fptn-admin-backend` | 8000 | FastAPI, монтирует `compose-data` в `/etc/fptn` |
| `fptn-admin-frontend` | 2663 (HTTPS), 8080 (HTTP → редирект) | Nginx с SPA-роутингом, проксирует `/api/` в backend |

**Переменные окружения (`.env.demo`)**:
- `JWT_TTL_MINUTES` — время жизни JWT (по умолчанию 60 мин)
- `ADMIN_LOGIN` / `ADMIN_PASSWORD` — первый администратор
- `CORS_ORIGINS` — разрешённые источники
- `ENABLE_BROTLI_COMPRESSION` — сжатие токенов
- `TELEGRAM_TOKEN`, `BOT_ENABLED`, `SERVICE_NAME`, `MAX_USER_SPEED_LIMIT` — настройки бота (только для первого запуска)
- `FPTN_CONFIGS_FOLDER` — путь к папке с данными

**Важно:** после первого запуска настройки бота читаются из `bot_settings.json`, переменные окружения игнорируются.

---

### 4. Сильные стороны

✅ **Минималистичный порог входа** — достаточно Docker и одной команды  
✅ **Единый источник данных** — не требуется отдельная БД  
✅ **Встроенный Telegram-бот** — без дополнительных контейнеров  
✅ **Готовый CI/CD** — GitHub Actions с линтингом, типами, тестами и сборкой  
✅ **Двуязычность** — English/Русский с переключением на лету  
✅ **Тёмная/светлая тема** — сохраняется в localStorage  
✅ **Поддержка development-режима** — без Docker (Poetry + npm)

---

### 5. Слабые стороны и риски

⚠️ **Самоподписанный сертификат** — для production требуется reverse-proxy с Let's Encrypt  
⚠️ **Отсутствие полноценной БД** — файловое хранилище может стать узким местом при росте числа пользователей  
⚠️ **Пароль в токене** — передаётся в открытом виде внутри base64 (шифрование только по TLS)  
⚠️ **Нет автоматического бэкапа** — данные хранятся в монтируемой папке, но бэкап нужно настроить отдельно  
⚠️ **Один backend-процесс** — Telegram-бот работает в том же потоке, что и API  

---

## План реализации на удалённом VPS

> **Два варианта развёртывания:**
> - **Полный стек** (Docker + nginx + Let's Encrypt + Telegram-бот + веб-панель) — этот план ниже.
> - **Облегчённый `deploy/family/`** (systemd-нативно, без Docker, опционально панель) — для домашнего использования, см. `deploy/family/README.md`.

### 1. Подготовка сервера

```bash
# Обновление системы
sudo apt update && sudo apt upgrade -y

# Установка Docker и Docker Compose
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Перезагрузка для применения прав
newgrp docker
```

### 2. Настройка домена и DNS (опционально, но рекомендуется)

Настройте A-запись для домена (например, `admin.example.com`) на IP вашего VPS.

### 3. Установка и настройка Nginx как reverse-proxy (с Let's Encrypt)

```bash
# Установка Nginx и Certbot
sudo apt install nginx certbot python3-certbot-nginx -y

# Создание конфигурации Nginx
sudo nano /etc/nginx/sites-available/admin.example.com
```

```nginx
server {
    listen 80;
    server_name admin.example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name admin.example.com;

    location / {
        proxy_pass https://localhost:2663;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
# Активация сайта
sudo ln -s /etc/nginx/sites-available/admin.example.com /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Получение SSL-сертификата
sudo certbot --nginx -d admin.example.com
```

### 4. Клонирование и настройка проекта

```bash
# Клонирование репозитория (актуальный URL — см. README в корне FTPN)
# Пример для официального форка: https://github.com/batchar2/fptn
git clone https://github.com/batchar2/fptn.git
cd fptn
# либо, если используется форк с fptn-admin: git clone <ваш-fork-url> fptn-admin && cd fptn-admin

# Создание .env из примера
cp .env.demo .env
```

Редактируем `.env`:

```env
# JWT — рекомендуется уменьшить для безопасности
JWT_TTL_MINUTES=120

# Администратор — ОБЯЗАТЕЛЬНО сменить!
ADMIN_LOGIN=your_admin_login
ADMIN_PASSWORD=your_strong_password

# CORS — только ваш домен
CORS_ORIGINS=https://admin.example.com

# Настройки бота (только для первого запуска)
TELEGRAM_TOKEN=your_bot_token
BOT_ENABLED=true
SERVICE_NAME=MyVPN
MAX_USER_SPEED_LIMIT=100

# Путь к данным (внешний том для сохранности)
FPTN_CONFIGS_FOLDER=/opt/fptn-data
```

### 5. Создание директории для данных и запуск

```bash
# Создание папки для данных с правильными правами
sudo mkdir -p /opt/fptn-data
sudo chown $USER:$USER /opt/fptn-data

# Запуск контейнеров
docker compose up -d --build
```

### 6. Проверка работоспособности

```bash
# Статус контейнеров
docker compose ps

# Логи backend
docker compose logs fptn-admin-backend

# Логи frontend
docker compose logs fptn-admin-frontend
```

Откройте в браузере `https://admin.example.com`. Войдите с логином/паролем из `.env` — система сразу потребует сменить пароль.

---

### 7. Настройка бэкапов (рекомендуется)

```bash
# Создание скрипта бэкапа
cat > /opt/backup-fptn.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR
tar -czf "$BACKUP_DIR/fptn-data-$DATE.tar.gz" /opt/fptn-data
# Оставляем только последние 7 бэкапов
ls -tp $BACKUP_DIR/*.tar.gz | grep -v '/$' | tail -n +8 | xargs -I {} rm -- {}
EOF

chmod +x /opt/backup-fptn.sh

# Добавление в cron (ежедневно в 3:00)
(crontab -l 2>/dev/null; echo "0 3 * * * /opt/backup-fptn.sh") | crontab -
```

---

### 8. Обновление проекта

```bash
cd fptn-admin
git pull
docker compose down
docker compose up -d --build
```

---

### 9. Мониторинг (опционально)

Рекомендуется настроить базовый мониторинг:

```bash
# Проверка доступности через curl
curl -k https://localhost:2663/api/v1/dashboard/highlights

# Установка утилиты для просмотра логов в реальном времени
docker compose logs -f
```

---

### 10. Интеграция с существующим FPTN-сервером

Если FPTN-сервер уже запущен на том же VPS:

```env
# В .env указать общую папку конфигов
FPTN_CONFIGS_FOLDER=/path/to/fptn/configs
```

Контейнеры должны иметь доступ к этой папке. Убедитесь, что:
- `users.list` доступен для чтения/записи
- `servers.json`, `premium_servers.json`, `servers_censored_zone.json` доступны
- Права доступа позволяют запись от имени контейнера (UID в контейнере может отличаться)

---

### Резюме

Проект **fptn-admin** — качественное решение для управления FPTN VPN с минимальными требованиями к инфраструктуре. Развёртывание на VPS занимает ~15 минут при использовании Docker и reverse-proxy с Let's Encrypt. Основные рекомендации для production:

1. **Обязательно** сменить дефолтные пароли администратора
2. Использовать reverse-proxy с реальным SSL-сертификатом
3. Настроить регулярные бэкапы папки `FPTN_CONFIGS_FOLDER`
4. Ограничить `CORS_ORIGINS` конкретным доменом
5. При большом количестве пользователей рассмотреть миграцию на СУБД
