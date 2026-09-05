#!/usr/bin/env bash
# =============================================================
#  FPTN Admin Panel — установка
#  ------------------------------------------------------------
#  Интерактивный TUI-ввод параметров:
#    - Домен/IP админки
#    - Логин + пароль администратора
#    - Telegram bot token (опционально)
#    - WELCOME-сообщения (EN/RU)
#    - Лимит скорости (Мбит/с)
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

# Загрузить существующие значения, если .env уже есть
ENV_FILE="/opt/fptn/fptn-admin/.env"
if [[ -f "$ENV_FILE" ]]; then
  tui_info "FPTN Admin" "Найден существующий $ENV_FILE\n\nБудем перенастраивать."
fi
load_var() {
  local key="$1"
  if [[ -f "$ENV_FILE" ]]; then
    grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true
  fi
}
CUR_HOST=$(load_var "CORS_ORIGINS" | sed 's|^https\?://||')
CUR_LOGIN=$(load_var "ADMIN_LOGIN")
CUR_TG=$(load_var "TELEGRAM_TOKEN")
CUR_SPEED=$(load_var "MAX_USER_SPEED_LIMIT")
CUR_WELCOME_EN=$(load_var "WELCOME_MESSAGE_EN" | sed 's|^"||;s|"$||')
CUR_WELCOME_RU=$(load_var "WELCOME_MESSAGE_RU" | sed 's|^"||;s|"$||')
# shellcheck disable=SC2034  # зарезервировано для будущей пере-настройки
: "${CUR_PASS:=}"
: "${CUR_TG:=}"

# ---- Шаг 1: Домен ----
while true; do
  HOST_INPUT=$(tui_input "Шаг 1/5 — Домен" "Домен или IP для админки.\nПусто = localhost (только HTTP):" "${CUR_HOST:-}") || true
  HOST_INPUT="${HOST_INPUT:-localhost}"
  if [[ -z "$HOST_INPUT" || "$HOST_INPUT" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ || "$HOST_INPUT" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    break
  fi
  tui_info "Ошибка" "Некорректный домен/IP: $HOST_INPUT"
done
say "Домен: $HOST_INPUT"

# ---- Шаг 2: Логин ----
LOGIN_INPUT=$(tui_input "Шаг 2/5 — Логин" "Логин администратора:" "${CUR_LOGIN:-admin}") || true
LOGIN_INPUT="${LOGIN_INPUT:-admin}"
say "Логин: $LOGIN_INPUT"

# ---- Шаг 3: Пароль ----
while true; do
  PASS_INPUT=$(tui_password "Шаг 3/5 — Пароль" "Пароль администратора\n(минимум 8 символов):") || true
  if [[ ${#PASS_INPUT} -ge 8 ]]; then
    PASS2=$(tui_password "Шаг 3/5 — Подтверждение" "Повторите пароль:") || true
    if [[ "$PASS_INPUT" == "$PASS2" ]]; then
      break
    fi
    tui_info "Ошибка" "Пароли не совпадают."
  else
    tui_info "Ошибка" "Пароль слишком короткий (нужно >= 8)."
  fi
done
say "Пароль задан"

# ---- Шаг 4: Telegram-бот (опционально) ----
if tui_yesno "Шаг 4/5 — Telegram-бот" "Включить Telegram-бота?\n\nБот управляет пользователями через /token,\nвыдаёт ссылки и удаляет аккаунты."; then
  while true; do
    TG_INPUT=$(tui_password "Telegram Bot Token" "Токен от @BotFather\n(формат: 123456:ABC-DEF...):") || true
    if [[ "$TG_INPUT" =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]]; then
      break
    fi
    tui_info "Ошибка" "Некорректный формат токена.\nПример: 1234567890:AAHfiqksKZ8WmR2zMnGOEjFyjPwKjOq7EXAMPLE"
  done
  say "Telegram: включён"
  BOT_ENABLED="true"
else
  TG_INPUT=""
  BOT_ENABLED="false"
  say "Telegram: отключён"
fi

# ---- Шаг 5: Дополнительно ----
SPEED_INPUT=$(tui_input "Шаг 5/5 — Лимит скорости" "Максимальная скорость пользователя (Мбит/с):" "${CUR_SPEED:-100}") || true
SPEED_INPUT="${SPEED_INPUT:-100}"
WELCOME_EN=$(tui_input "Welcome EN" "Приветствие (English):" "${CUR_WELCOME_EN:-⚡ Welcome! Use /token to get your access link.}") || true
WELCOME_EN="${WELCOME_EN:-⚡ Welcome! Use /token to get your access link.}"
WELCOME_RU=$(tui_input "Welcome RU" "Приветствие (Русский):" "${CUR_WELCOME_RU:-⚡ Добро пожаловать! Используйте /token для получения токена.}") || true
WELCOME_RU="${WELCOME_RU:-⚡ Добро пожаловать! Используйте /token для получения токена.}"

# ---- Подтверждение ----
SUMMARY=$(cat <<EOF
FPTN Admin Panel:

  Домен:           $HOST_INPUT
  Логин:           $LOGIN_INPUT
  Пароль:          ********
  Telegram-бот:    $BOT_ENABLED
  Лимит скорости:  ${SPEED_INPUT} Мбит/с
  Welcome EN:      $WELCOME_EN
  Welcome RU:      $WELCOME_RU

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
JWT_TTL_MINUTES=60
ADMIN_LOGIN=$LOGIN_INPUT
ADMIN_PASSWORD=$PASS_INPUT
CORS_ORIGINS=https://$HOST_INPUT
ENABLE_BROTLI_COMPRESSION=true
FPTN_CONFIGS_FOLDER=/opt/fptn/data/fptn-server
TELEGRAM_TOKEN=$TG_INPUT
BOT_ENABLED=$BOT_ENABLED
SERVICE_NAME=FPTN.ONLINE
MAX_USER_SPEED_LIMIT=$SPEED_INPUT
WELCOME_MESSAGE_EN="$WELCOME_EN"
WELCOME_MESSAGE_RU="$WELCOME_RU"
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
  URL:    http://<server>:2663 (или https://$HOST_INPUT:2663)
  Логин:  $LOGIN_INPUT
  Пароль: $PASS_INPUT

  ⚠️ Сразу смените пароль после первого входа!

  Логи: cd /opt/fptn/fptn-admin && docker compose logs -f
============================================================
EOF
