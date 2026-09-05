#!/usr/bin/env bash
# =============================================================
#  FTPN — выпустить токен доступа для пользователя
#  (вызывает backend API)
# =============================================================
set -Eeuo pipefail

API="${FPTN_API:-http://127.0.0.1:8000}"
USER="${1:-}"
ADMIN_LOGIN="${FPTN_ADMIN_LOGIN:-}"
ADMIN_PASSWORD="${FPTN_ADMIN_PASSWORD:-}"

usage() { echo "Использование: fptn-issue-token <telegram_id>"; exit 1; }
[[ -z "$USER" ]] && usage

# Берём логин/пароль из /opt/fptn/deploy-config.env если не переданы
if [[ -z "$ADMIN_LOGIN" && -f /opt/fptn/deploy-config.env ]]; then
  # shellcheck disable=SC1091
  . /opt/fptn/deploy-config.env
fi
[[ -z "$ADMIN_LOGIN" ]] && { echo "ADMIN_LOGIN пуст" >&2; exit 1; }

# Логинимся → JWT
LOGIN_JSON=$(curl -fsS -X POST "$API/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"login\":\"$ADMIN_LOGIN\",\"password\":\"$ADMIN_PASSWORD\"}" 2>/dev/null) || {
    echo "Не удалось залогиниться в backend" >&2
    exit 1
  }

JWT=$(printf '%s' "$LOGIN_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null) || {
    echo "Не удалось извлечь JWT" >&2
    exit 1
  }

# Запрашиваем токен
RESP=$(curl -fsS -X POST "$API/api/v1/users/$USER/token" \
  -H "Authorization: Bearer $JWT" 2>/dev/null) || {
    echo "Не удалось получить токен для $USER" >&2
    exit 1
  }

ACCESS_TOKEN=$(printf '%s' "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['accessToken'])" 2>/dev/null)
echo "$ACCESS_TOKEN"
