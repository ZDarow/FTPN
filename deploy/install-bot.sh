#!/usr/bin/env bash
# =============================================================
#  FPTN Telegram Bot — установка
# -------------------------------------------------------------
#  Требует запущенный install.sh и доступ к users.list
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

read -rp "Telegram bot token: " TG_TOKEN
[[ -n "$TG_TOKEN" ]] || { echo "Токен обязателен"; exit 1; }

ENV_FILE="/opt/fptn/fptn/sysadmin-tools/telegram-bot/.env"
cat > "$ENV_FILE" <<EOF
TELEGRAM_API_TOKEN=$TG_TOKEN
FPTN_WELCOME_MESSAGE_EN="⚡ Welcome! Use /token to get your access link."
FPTN_WELCOME_MESSAGE_RU="⚡ Добро пожаловать! Используйте /token для получения токена."
MAX_USER_SPEED_LIMIT=100
SERVICE_NAME=FPTN.ONLINE
ENABLE_BROTLI_COMPRESSION=true
FPTN_CONFIGS_FOLDER=/opt/fptn/data/fptn-server
EOF

cd /opt/fptn/fptn/sysadmin-tools/telegram-bot
docker compose up -d --build

cat <<EOF

============================================================
  Telegram Bot запущен
============================================================
  Логи: cd /opt/fptn/fptn/sysadmin-tools/telegram-bot && docker compose logs -f
  Юзеры: пишите /start боту в Telegram
============================================================
EOF
