#!/usr/bin/env bash
# =============================================================
#  FPTN Admin Panel — установка
# -------------------------------------------------------------
#  Требует запущенный install.sh (наличие /opt/fptn/fptn-server)
# =============================================================
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "[!] Запустите от root: sudo bash $0"
  exit 1
fi

if [[ ! -d "/opt/fptn/.git" ]]; then
  echo "[!] Сначала установите VPN: bash /opt/fptn/deploy/install.sh"
  exit 1
fi

say()  { echo -e "\033[0;32m[+]\033[0m $*"; }
err()  { echo -e "\033[0;31m[✗]\033[0m $*" >&2; }

# Спросить параметры
read -rp "Домен для админки (или IP, пусто — отключить HTTPS): " ADMIN_HOST
read -rsp "Пароль администратора: " ADMIN_PASS; echo
read -rp "Telegram bot token (пусто — отключить бота): " TG_TOKEN

# .env файл
ENV_FILE="/opt/fptn/fptn-admin/.env"
cat > "$ENV_FILE" <<EOF
JWT_TTL_MINUTES=60
ADMIN_LOGIN=admin
ADMIN_PASSWORD=$ADMIN_PASS
CORS_ORIGINS=https://${ADMIN_HOST:-localhost}
ENABLE_BROTLI_COMPRESSION=true
FPTN_CONFIGS_FOLDER=/opt/fptn/data/fptn-server
TELEGRAM_TOKEN=$TG_TOKEN
BOT_ENABLED=$([ -n "$TG_TOKEN" ] && echo true || echo false)
SERVICE_NAME=FPTN.ONLINE
MAX_USER_SPEED_LIMIT=100
WELCOME_MESSAGE_EN="⚡ Welcome! Use /token to get your access link."
WELCOME_MESSAGE_RU="⚡ Добро пожаловать! Используйте /token для получения токена."
EOF

# Создать users.list если нет
touch /opt/fptn/data/fptn-server/users.list

# Запуск
cd /opt/fptn/fptn-admin
docker compose up -d --build

cat <<EOF

============================================================
  FPTN Admin Panel запущена
============================================================
  URL:    http://<server>:2663 (или https://$ADMIN_HOST:2663)
  Логин:  admin
  Пароль: $ADMIN_PASS

  ⚠️ Сразу смените пароль после первого входа!

  Логи: cd /opt/fptn/fptn-admin && docker compose logs -f
============================================================
EOF
