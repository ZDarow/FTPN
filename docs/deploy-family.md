# FTPN Family Edition — для дома и друзей

**Минималистичный** вариант развёртывания FPTN. Только то, что нужно для личного использования.

## 🎯 Что входит

- ✅ VPN-сервер (Reality / анти-DPI)
- ✅ Telegram-бот (юзеры сами получают токены через `/start` → `/token`)
- ⚙️ Веб-панель — **опционально**, на ваш выбор (для продвинутых)

## ❌ Что НЕ входит (по сравнению с полным вариантом)

- ❌ React UI админки (не нужна для 5–20 юзеров)
- ❌ FastAPI backend как веб-сервис (бот работает автономно)
- ❌ Healthcheck timer
- ❌ CORS, JWT для панели
- ❌ Let's Encrypt (по желанию)

## 📋 Требования

- VPS с Ubuntu 22.04/24.04 или Debian 12
- 1 vCPU, 1 ГБ RAM (лучше 2 ГБ), 10 ГБ диска
- Открытый TCP 443 (или другой) + SSH 22
- Telegram-бот (создать через [@BotFather](https://t.me/BotFather))

## 🚀 Развёртывание

```bash
# 1. Загрузить на сервер
scp -r FTPN root@server:/tmp/

# 2. Подключиться
ssh root@server
cd /tmp/FTPN

# 3. Запустить
sudo bash deploy/family/deploy.sh
```

Скрипт спросит:
- Внешний IP (определит сам)
- Порт VPN (по умолчанию 443)
- **Telegram bot token**
- Имя сервиса (для токенов)
- Скорость по умолчанию для новых юзеров
- Сайт-прикрытие (Reality fallback)
- **Ставить ли веб-панель?** (по умолчанию **нет**)

Через ~3 минуты всё готово.

## 🛠 Утилиты

| Команда | Что делает |
|---------|-----------|
| `fptn-status` | Общий статус (контейнеры, порты, диск, RAM, юзеры) |
| `fptn-logs [server\|bot\|admin\|all] [N]` | Логи (по умолчанию все, 100 строк) |
| `fptn-list [all\|blocked\|premium]` | Список юзеров |
| `fptn-add-user 123 [pass] [speed] [premium]` | Добавить юзера (пароль генерируется) |
| `fptn-block 123` | Заблокировать (`speed=0`) |
| `fptn-unblock 123 [speed]` | Разблокировать + новая скорость |
| `fptn-reset-speed 123` | Сбросить пароль (новый генерируется) |
| `fptn-issue-token 123` | Получить access-токен |
| `fptn-show-config` | Показать серверы, настройки бота, deploy-конфиг |
| `fptn-backup` | Бэкап users.list / servers.json / bot_settings.json |
| `fptn-update` | Обновить Docker-образы |
| `fptn-swap-setup 2048` | Создать swap 2 ГБ (если VPS 1 ГБ) |

Все утилиты **работают с файлами напрямую** (без API). Это быстрее и проще.

## 📁 Структура

```
/opt/fptn/
├── compose/
│   ├── server/         # fptn-server (Docker)
│   ├── bot/            # telegram-bot (Docker)
│   └── admin/          # админка (если включили)
├── data/fptn-server/   # Общая папка конфигов
│   ├── users.list
│   ├── servers.json
│   ├── premium_servers.json
│   ├── servers_censored_zone.json
│   ├── bot_settings.json
│   └── jwt_secret       (только если стоит админка)
└── deploy-config.env   # Параметры развёртывания
```

## 🔄 Типичный день

```bash
# 1. Утром проверить, что всё работает
fptn-status

# 2. Жена попросила токен для телефона
# → она пишет боту /start, потом /token
# → бот сам создаёт юзера и присылает токен
# → готово, ничего не надо делать

# 3. Друг зашёл в гости и попросил VPN на выходные
fptn-add-user 79123456789
# [+] Добавлен: 79123456789
#     Пароль:  AbCd1234EfGh
#     Скорость: 100 Мбит/с
#     Токен: fptn:eyJ2ZXJzaW9uIjox...

# 4. Друг уехал — блокируем
fptn-block 79123456789

# 5. Сын качает торренты и жалуется на медленный интернет
# Смотрим: fptn-list → может speed=0? или превысил лимит?
# Если всё ок, но медленно — возможно, BT-фильтр блокирует.
# Снимаем фильтр: отредактируй /opt/fptn/compose/server/.env
#   DISABLE_TORRENT_FILTER=true
# sudo systemctl restart fptn-server

# 6. Пятница — бэкап перед выходными
fptn-backup
# [+] Бэкап: /var/backups/fptn/fptn-family-20260904-220000.tar.gz

# 7. Вышла новая версия FPTN
fptn-update
# [1/3] VPN-сервер
# [2/3] Telegram-бот
# [3/4] Админ-панель (если стоит)
```

## 🔐 Безопасность

- `users.list` содержит **SHA-256 от пароля** (не сам пароль)
- `users.list` доступен на чтение VPN-серверу (он же пишет в NAT)
- Telegram-токен — в `/opt/fptn/compose/bot/.env` (chmod 600)
- В токене клиента пароль передаётся в base64 (защита — TLS Telegram)
- Самоподписанный сертификат НЕ генерируется (нет HTTPS-сервиса снаружи)
- **Telegram-бот — единственная точка управления**, защищён токеном

## 🆚 Family Edition vs Полный вариант

| Фича | Family | Полный |
|------|--------|--------|
| VPN-сервер | ✅ | ✅ |
| Telegram-бот | ✅ | ✅ |
| Веб-панель | ❌ (опция) | ✅ |
| Самоподписанный сертификат | ❌ | ✅ |
| Let's Encrypt | ❌ (опция) | ✅ |
| Healthcheck timer | ❌ | ✅ |
| Утилит в `/usr/local/bin` | 11 | 8 |
| RAM нужно | 1 ГБ | 2 ГБ |
| Целевая аудитория | Семья, друзья | SaaS, ISP |

## 📝 Удаление

```bash
sudo systemctl disable --now fptn-server fptn-telegram-bot
[[ -d /opt/fptn/compose/admin ]] && sudo systemctl disable --now fptn-admin-backend fptn-admin-frontend
sudo rm -rf /opt/fptn /var/backups/fptn
sudo rm -f /etc/systemd/system/fptn-*.service
sudo docker network rm fptn-network 2>/dev/null || true
sudo docker system prune -af
```
