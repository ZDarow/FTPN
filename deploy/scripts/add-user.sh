#!/usr/bin/env bash
# =============================================================
#  FTPN — добавить VPN-пользователя в users.list
#  Формат строки: <telegram_id> <sha256_password> <speed_mbps> <is_premium>
# =============================================================
set -Eeuo pipefail
USERS_FILE="/opt/fptn/data/fptn-server/users.list"
DATA_DIR="/opt/fptn/data/fptn-server"

[[ $EUID -eq 0 ]] || { echo "Нужен root" >&2; exit 1; }
mkdir -p "$DATA_DIR"
[[ -f "$USERS_FILE" ]] || : > "$USERS_FILE"

usage() { echo "Использование: fptn-add-user <telegram_id> [password] [speed_mbps] [is_premium 0|1]"; exit 1; }

TG_ID="${1:-}"; [[ "$TG_ID" =~ ^[0-9]+$ ]] || usage
PASSWORD="${2:-$(openssl rand -base64 12)}"
SPEED="${3:-100}"
PREMIUM="${4:-0}"

# Если пользователь уже есть — выходим
if grep -qE "^${TG_ID} " "$USERS_FILE"; then
  echo "Пользователь $TG_ID уже существует. Используй fptn-issue-token."
  exit 0
fi

HASH=$(printf '%s' "$PASSWORD" | sha256sum | awk '{print $1}')
printf '%s %s %s %s\n' "$TG_ID" "$HASH" "$SPEED" "$PREMIUM" >> "$USERS_FILE"

# Рестартим сервер, чтобы он подхватил нового юзера
docker ps --filter "name=fptn-server" --format "{{.Names}}" | head -1 \
  | xargs -r docker kill -s HUP 2>/dev/null || true

echo "[+] Добавлен: $TG_ID"
echo "    Логин:   $TG_ID"
echo "    Пароль:  $PASSWORD"
echo "    Скорость: ${SPEED} Мбит/с"
echo "    Премиум: $PREMIUM"
echo
echo "Токен:"
fptn-issue-token "$TG_ID" 2>/dev/null || echo "  (запусти fptn-issue-token $TG_ID)"
