# FTPN — скрипт развёртывания

Полностью автоматическая установка FPTN-стека на чистый VPS:
- VPN-сервер (Reality / анти-DPI)
- Админ-панель (FastAPI + React)
- Telegram-бот (встроен в backend)

## Требования к VPS

| Параметр | Минимум |
|----------|---------|
| OS       | Ubuntu 22.04 / 24.04 / Debian 12 |
| CPU      | 1 vCPU (рекомендую 2) |
| RAM      | 1 ГБ (рекомендую 2) |
| Диск     | 10 ГБ |
| Сеть     | Публичный IPv4, открытый TCP 443 (или другой) |
| Доступ   | root по SSH |
| Ядро     | ≥ 5.x с поддержкой `tun` и `tcp_bbr` |

**Открыть порты на файерволе**:
```bash
# UFW
ufw allow 22/tcp
ufw allow 443/tcp     # VPN-туннель
ufw allow 2663/tcp    # админка HTTPS
ufw allow 8080/tcp    # админка HTTP (редирект)
# (опционально 8000/tcp для прямого доступа к API — лучше НЕ открывать)
ufw enable
```

**Telegram**: перед запуском создай бота через [@BotFather](https://t.me/BotFather) и получи токен вида `1234567890:AA...`.

## Развёртывание

```bash
# 1) Загрузить проект на сервер
scp -r FTPN user@your.server:/tmp/

# 2) Подключиться и запустить
ssh user@your.server
cd /tmp/FTPN
sudo bash deploy/deploy.sh
```

Скрипт попросит ввести:
- Внешний IP сервера (определит автоматически)
- Домен для админ-панели
- Порты (по умолчанию 443 / 2663 / 8080 / 8000)
- **Telegram-токен бота**
- Логин/пароль администратора
- Параметры анти-DPI (SNI, сайт-прикрытие)

После завершения (~5 минут) выведет сводку:
- URL VPN-сервера
- URL админ-панели + логин/пароль
- Команды управления

## Что устанавливается

```
/opt/fptn/
├── compose/
│   ├── server/         # fptn/docker-compose.yml + .env
│   ├── admin/          # fptn-admin/docker-compose.yml + .env + override (сертификат)
│   └── bot/            # telegram-bot/docker-compose.yml + .env
├── data/
│   ├── fptn-server/    # users.list, admins.json, servers.json, bot_settings.json
│   └── certs/          # fullchain.pem, privkey.pem (для админки)
└── deploy-config.env   # заполненные параметры развёртывания
```

## Команды управления

| Команда | Описание |
|---------|----------|
| `fptn-status` | Статус контейнеров, дисков, health-check |
| `fptn-logs [server\|backend\|frontend\|bot] [N]` | Логи (по умолчанию all, 100 строк) |
| `fptn-update` | Подтянуть новые образы и рестарт |
| `fptn-backup` | Бэкап конфигов в `/var/backups/fptn` |
| `fptn-add-user <telegram_id> [pass] [speed] [premium]` | Создать VPN-пользователя |
| `fptn-issue-token <telegram_id>` | Выпустить access-токен |
| `fptn-setup-letsencrypt` | Реальный SSL через Let's Encrypt (если есть FQDN) |
| `fptn-swap-setup [size_mb]` | Создать swap (по умолчанию 2 ГБ) |

Systemd-юниты:
```bash
systemctl status fptn-server
systemctl restart fptn-admin-backend
systemctl stop fptn-telegram-bot
systemctl list-timers fptn-healthcheck.timer   # мониторинг каждые 5 минут
journalctl -u fptn-server -f
```

## Первые шаги после развёртывания

1. Открой `https://your.domain:2663` → войди как `admin` / *введённый_пароль*
2. **Сразу смени пароль** (админка попросит сама)
3. Перейди в **Settings → Telegram Bot**:
   - Вставь токен (если не сделал при развёртывании)
   - Включи `Bot Enabled = true`
   - Сохрани
4. Перейди в **Servers → Add Server**:
   - Name: `MyVPN`
   - Host: `<внешний IP сервера>`
   - Port: `443`
   - MD5 fingerprint: оставь пустым
   - Ping: `10`
5. **Добавь тестового пользователя**:
   ```bash
   fptn-add-user 123456789 mysecret 100 0
   ```
   → скопируй access-токен
6. Скачай клиент с [fptn.org](https://storage.googleapis.com/fptn.org/) и вставь токен
7. **Telegram-бот**: напиши ему `/start`, затем `/token` — бот сам создаст пользователя и пришлёт токен

## Обновление

```bash
sudo fptn-update
```

Подтянет новые Docker-образы и перезапустит все стеки через systemd.

## Бэкап

```bash
sudo fptn-backup                  # разово
echo "0 3 * * * root fptn-backup" > /etc/cron.d/fptn-backup   # ежедневно в 03:00
```

Бэкапы хранятся в `/var/backups/fptn/fptn-config-YYYYMMDD-HHMMSS.tar.gz` (ротация 30 дней).

## Удаление

```bash
sudo systemctl disable --now fptn-server fptn-admin-backend fptn-admin-frontend fptn-telegram-bot
sudo rm -rf /opt/fptn /var/backups/fptn /etc/systemd/system/fptn-*
sudo docker network rm fptn-network 2>/dev/null || true
```

## Безопасность

- Панель на HTTPS (самоподписанный сертификат → замени на Let's Encrypt в проде)
- JWT с TTL 60 мин + bcrypt для паролей админов
- CORS ограничен доменом панели
- Telegram-токен хранится в `/opt/fptn/compose/admin/.env` (chmod 600)
- users.list доступен только root-у (т.к. контейнеры работают от root в привилегированном режиме)
- Реальный SSL через Let's Encrypt + reverse-proxy:
  ```bash
  # Установить, если у тебя есть FQDN (например admin.example.com)
  sudo fptn-setup-letsencrypt
  ```
  Скрипт автоматически:
  - устанавливает nginx + certbot
  - создаёт конфиг reverse-proxy `nginx → 127.0.0.1:2663` (Docker-nginx с самоподписанным)
  - получает сертификат через webroot
  - настраивает `certbot.timer` для автопродления
  - добавляет security-заголовки (HSTS, X-Frame-Options, X-Content-Type-Options)

- **Healthcheck каждые 5 минут** через systemd timer (`fptn-healthcheck.timer`).
  Если backend или VPN-сервер упал — в `journalctl -u fptn-healthcheck` будет `[FAIL]`.
