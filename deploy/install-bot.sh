#!/usr/bin/env bash
# =============================================================
#  FPTN Telegram Bot — установка (отдельный стек fptn-admin-bot)
#  ------------------------------------------------------------
#  Интерактивный TUI-ввод:
#    - Telegram bot token
#    - Admin chat ID (белый список, кто может управлять ботом)
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

# Новый стек бота (отдельный контейнер с проверкой ADMIN_IDS).
# Старый legacy-бот из fptn/sysadmin-tools/telegram-bot удалён
# в merge-коммите d404aea.
BOT_DIR="/opt/fptn/fptn-admin-bot"
ENV_FILE="$BOT_DIR/.env"
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
CUR_ADMIN_IDS=$(load_var "ADMIN_IDS")
CUR_SPEED=$(load_var "MAX_USER_SPEED_LIMIT")
CUR_WELCOME_EN=$(load_var "FPTN_WELCOME_MESSAGE_EN" | sed 's|^"||;s|"$||')
CUR_WELCOME_RU=$(load_var "FPTN_WELCOME_MESSAGE_RU" | sed 's|^"||;s|"$||')
# shellcheck disable=SC2034  # CUR_TOKEN зарезервирован для будущей пере-настройки
: "${CUR_TOKEN:=}"

# ---- Шаг 1: Bot token ----
while true; do
  TG_INPUT=$(tui_password "Шаг 1/5 — Bot Token" "Токен от @BotFather\n(формат: 123456:ABC-DEF...):" ) || true
  if [[ "$TG_INPUT" =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]]; then
    break
  fi
  tui_info "Ошибка" "Некорректный формат токена."
done
say "Token задан"

# ---- Шаг 2: Admin IDs ----
# Белый список Telegram User ID. Пустое значение = бот доступен
# ЛЮБОМУ пользователю (is_admin() возвращает True) — небезопасно.
ADMIN_IDS_INPUT=$(tui_input "Шаг 2/5 — Admin IDs" "Telegram User ID админов (через запятую).\nУзнать свой ID: @userinfobot\nПусто = доступ ВСЕМ (небезопасно):" "${CUR_ADMIN_IDS:-}") || true
if [[ -n "$ADMIN_IDS_INPUT" ]]; then
  say "Admin IDs: $ADMIN_IDS_INPUT"
else
  warn "ADMIN_IDS не задан — бот сможет контролировать ЛЮБОЙ Telegram-аккаунт!"
fi

# ---- Шаг 3: Welcome сообщения ----
WELCOME_EN=$(tui_input "Шаг 3/5 — Welcome EN" "Приветствие (English):" "${CUR_WELCOME_EN:-⚡ Welcome! Use /token to get your access link.}") || true
WELCOME_EN="${WELCOME_EN:-⚡ Welcome! Use /token to get your access link.}"
WELCOME_RU=$(tui_input "Шаг 4/5 — Welcome RU" "Приветствие (Русский):" "${CUR_WELCOME_RU:-⚡ Добро пожаловать! Используйте /token для получения токена.}") || true
WELCOME_RU="${WELCOME_RU:-⚡ Добро пожаловать! Используйте /token для получения токена.}"

# ---- Шаг 4: Лимит скорости ----
SPEED_INPUT=$(tui_input "Шаг 5/5 — Скорость" "Макс. скорость пользователя (Мбит/с):" "${CUR_SPEED:-100}") || true
SPEED_INPUT="${SPEED_INPUT:-100}"

# ---- Шаг 5: Подтверждение ----
SUMMARY=$(cat <<EOF
FPTN Telegram Bot:

  Bot Token:       ${TG_INPUT:0:15}...${TG_INPUT: -5}
  Admin IDs:       ${ADMIN_IDS_INPUT:-<не заданы — доступ всем!>}
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
# compose и bot/config.py читают TELEGRAM_API_TOKEN и ADMIN_IDS
# (НЕ TELEGRAM_TOKEN — это переменная для встроенного бота backend).
{
  printf 'TELEGRAM_API_TOKEN=%s\n' "$TG_INPUT"
  printf 'ADMIN_IDS=%s\n' "$ADMIN_IDS_INPUT"
  printf 'FPTN_WELCOME_MESSAGE_EN=%s\n' "$WELCOME_EN"
  printf 'FPTN_WELCOME_MESSAGE_RU=%s\n' "$WELCOME_RU"
  printf 'MAX_USER_SPEED_LIMIT=%s\n' "$SPEED_INPUT"
  printf 'SERVICE_NAME=FPTN.ONLINE\n'
  printf 'ENABLE_BROTLI_COMPRESSION=true\n'
  printf 'USERS_FILE=/etc/fptn/users.list\n'
  printf 'SERVERS_LIST_FILE=/etc/fptn/servers.json\n'
  printf 'PREMIUM_SERVERS_FILE=/etc/fptn/premium_servers.json\n'
  printf 'SERVERS_CENSORED_LIST_FILE=/etc/fptn/servers_censored_zone.json\n'
  printf 'BLACKLIST_FILE=/etc/fptn/blocked_users.txt\n'
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

warn "Бот монтирует docker.sock (rw) — доступ к боту = доступ к Docker."
cd "$BOT_DIR"
docker compose up -d --build

cat <<EOF

===========================================================
  Telegram Bot запущен
===========================================================
  Логи:  cd $BOT_DIR && docker compose logs -f
  Юзеры: пишите /start боту в Telegram
===========================================================
EOF
