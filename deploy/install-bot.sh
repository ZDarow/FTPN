#!/usr/bin/env bash
# =============================================================
#  FPTN Telegram Bot — установка
#  ------------------------------------------------------------
#  Интерактивный TUI-ввод:
#    - Telegram bot token
#    - Admin chat ID (для уведомлений)
#    - WELCOME-сообщения
#    - Лимит скорости
# =============================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/tui.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/tui.sh"

if [[ ${EUID} -ne 0 ]]; then
  echo "[!] Запустите от root: sudo bash $0"
  exit 1
fi

if [[ ! -d "/opt/fptn/.git" ]]; then
  echo "[!] Сначала установите VPN: bash /opt/fptn/deploy/install.sh"
  exit 1
fi

say()  { echo -e "\033[0;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
err()  { echo -e "\033[0;31m[✗]\033[0m $*" >&2; }

ENV_FILE="/opt/fptn/fptn/sysadmin-tools/telegram-bot/.env"
if [[ -f "$ENV_FILE" ]]; then
  tui_info "FPTN Bot" "Найден существующий $ENV_FILE\n\nБудем перенастраивать."
fi
load_var() {
  local key="$1"
  if [[ -f "$ENV_FILE" ]]; then
    grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true
  fi
}
CUR_TOKEN=$(load_var "TELEGRAM_API_TOKEN")
CUR_SPEED=$(load_var "MAX_USER_SPEED_LIMIT")
CUR_WELCOME_EN=$(load_var "FPTN_WELCOME_MESSAGE_EN" | sed 's|^"||;s|"$||')
CUR_WELCOME_RU=$(load_var "FPTN_WELCOME_MESSAGE_RU" | sed 's|^"||;s|"$||')
# shellcheck disable=SC2034  # CUR_TOKEN зарезервирован для будущей пере-настройки
: "${CUR_TOKEN:=}"

# ---- Шаг 1: Bot token ----
while true; do
  TG_INPUT=$(tui_password "Шаг 1/4 — Bot Token" "Токен от @BotFather\n(формат: 123456:ABC-DEF...):") || true
  if [[ "$TG_INPUT" =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]]; then
    break
  fi
  tui_info "Ошибка" "Некорректный формат токена."
done
say "Token задан"

# ---- Шаг 2: Welcome сообщения ----
WELCOME_EN=$(tui_input "Шаг 2/4 — Welcome EN" "Приветствие (English):" "${CUR_WELCOME_EN:-⚡ Welcome! Use /token to get your access link.}") || true
WELCOME_EN="${WELCOME_EN:-⚡ Welcome! Use /token to get your access link.}"
WELCOME_RU=$(tui_input "Шаг 2/4 — Welcome RU" "Приветствие (Русский):" "${CUR_WELCOME_RU:-⚡ Добро пожаловать! Используйте /token для получения токена.}") || true
WELCOME_RU="${WELCOME_RU:-⚡ Добро пожаловать! Используйте /token для получения токена.}"

# ---- Шаг 3: Лимит скорости ----
SPEED_INPUT=$(tui_input "Шаг 3/4 — Скорость" "Макс. скорость пользователя (Мбит/с):" "${CUR_SPEED:-100}") || true
SPEED_INPUT="${SPEED_INPUT:-100}"

# ---- Шаг 4: Подтверждение ----
SUMMARY=$(cat <<EOF
FPTN Telegram Bot:

  Bot Token:       ${TG_INPUT:0:15}...${TG_INPUT: -5}
  Welcome EN:      $WELCOME_EN
  Welcome RU:      $WELCOME_RU
  Лимит скорости:  ${SPEED_INPUT} Мбит/с

Записать в $ENV_FILE?
EOF
)
tui_info "Подтверждение" "$SUMMARY"
if ! tui_yesno "Подтверждение" "Применить эти настройки?"; then
  warn "Отменено."
  exit 0
fi

# ---- Запись ----
cat > "$ENV_FILE" <<EOF
TELEGRAM_API_TOKEN=$TG_INPUT
FPTN_WELCOME_MESSAGE_EN="$WELCOME_EN"
FPTN_WELCOME_MESSAGE_RU="$WELCOME_RU"
MAX_USER_SPEED_LIMIT=$SPEED_INPUT
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
