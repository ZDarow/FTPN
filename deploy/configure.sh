#!/usr/bin/env bash
# =============================================================
#  FPTN — интерактивный TUI-мастер настройки
#  ------------------------------------------------------------
#  Шаги:
#    1. Публичный IP / домен
#    2. VPN-порт
#    3. Домен по умолчанию (для перенаправления сканеров)
#    4. SNI-whitelist (разрешённые домены)
#    5. Фильтр торрентов
#    6. Часовой пояс
#    7. Подтверждение + запись в .env
#
#  Использование:
#    bash deploy/configure.sh
#    bash deploy/configure.sh /path/to/.env
#
#  Если файл .env уже существует — предлагает перенастроить
#  или выйти.
# =============================================================
set -Eeuo pipefail

# ---- путь к TUI-библиотеке ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/tui.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/tui.sh"

# ---- путь к .env ----
ENV_FILE="${1:-}"
if [[ -z "$ENV_FILE" ]]; then
  # Авто-детект
  if [[ -f /opt/fptn/fptn/docker-compose/.env ]]; then
    ENV_FILE="/opt/fptn/fptn/docker-compose/.env"
  else
    ENV_FILE="$SCRIPT_DIR/../fptn/docker-compose/.env"
  fi
fi
# Шаблон .env.demo всегда берётся из репозитория (рядом со скриптом)
ENV_DIR="$(dirname "$ENV_FILE")"
ENV_DEMO="$ENV_DIR/.env.demo"
if [[ ! -f "$ENV_DEMO" ]]; then
  # Fallback: попробовать в репозитории
  if [[ -f "$SCRIPT_DIR/../fptn/docker-compose/.env.demo" ]]; then
    ENV_DEMO="$SCRIPT_DIR/../fptn/docker-compose/.env.demo"
  fi
fi

# ---- проверки ----
if [[ ! -f "$ENV_DEMO" ]]; then
  echo "[!] Не найден шаблон $ENV_DEMO" >&2
  echo "    Сначала выполните: bash deploy/install.sh" >&2
  exit 1
fi

# ---- хелперы ----
say()  { echo -e "\033[0;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
err()  { echo -e "\033[0;31m[✗]\033[0m $*" >&2; }

set_env_var() {
  local key="$1" value="$2"
  # Экранируем /, &, | для sed
  local esc="${value//\//\\/}"
  esc="${esc//&/\&}"
  esc="${esc//|/\|}"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${esc}|" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

get_env_var() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true
}

validate_ip() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS='.'
  local -a parts
  read -ra parts <<< "$ip"
  for p in "${parts[@]}"; do
    (( p >= 0 && p <= 255 )) || return 1
  done
  return 0
}

validate_domain() {
  [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

# ---- определение текущих значений ----
if [[ -f "$ENV_FILE" ]]; then
  tui_info "FPTN Configure" "Найден существующий $ENV_FILE\n\nБэкенд UI: $(tui_backend)"
  if ! tui_yesno "FPTN Configure" "Перенастроить существующий .env?"; then
    say "Настройка отменена."
    exit 0
  fi
  CUR_IP=$(get_env_var "SERVER_EXTERNAL_IPS")
  CUR_PORT=$(get_env_var "FPTN_PORT")
  CUR_PROXY=$(get_env_var "DEFAULT_PROXY_DOMAIN")
  CUR_SNI=$(get_env_var "ALLOWED_SNI_LIST")
  CUR_TZ=$(get_env_var "TZ")
else
  cp "$ENV_DEMO" "$ENV_FILE"
  say "Создан $ENV_FILE из шаблона"
  CUR_IP=""
  CUR_PORT="443"
  CUR_PROXY="yandex.ru"
  CUR_SNI=""
  CUR_TZ="UTC"
fi

# ---- Шаг 1: Публичный IP / домен ----
tui_info "Шаг 1/6" "Укажите публичный IP вашего сервера.\n\nЭтот IP увидит VPN-клиент в конфиге.\nМожно указать домен — DNS должен резолвиться в IP."

AUTO_IP=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)
DEFAULT_IP="${CUR_IP:-$AUTO_IP}"
DEFAULT_IP="${DEFAULT_IP:-1.2.3.4}"

while true; do
  IP_INPUT=$(tui_input "Шаг 1/6 — Сервер" "Публичный IP или домен:" "$DEFAULT_IP") || true
  IP_INPUT="${IP_INPUT:-$DEFAULT_IP}"
  if validate_ip "$IP_INPUT" || validate_domain "$IP_INPUT"; then
    break
  fi
  tui_info "Ошибка" "Некорректный IP/домен: $IP_INPUT\n\nПримеры:\n  213.21.242.99\n  vpn.example.com"
done
say "IP: $IP_INPUT"

# ---- Шаг 2: VPN-порт ----
while true; do
  PORT_INPUT=$(tui_input "Шаг 2/6 — Порт" "Порт VPN-сервера (1-65535):" "${CUR_PORT:-443}") || true
  PORT_INPUT="${PORT_INPUT:-443}"
  if validate_port "$PORT_INPUT"; then
    break
  fi
  tui_info "Ошибка" "Некорректный порт: $PORT_INPUT"
done
say "Порт: $PORT_INPUT"

# ---- Шаг 3: Default proxy domain ----
while true; do
  PROXY_INPUT=$(tui_input "Шаг 3/6 — Default proxy" "Домен для перенаправления сканеров\n(когда кто-то сканирует ваш сервер):" "${CUR_PROXY:-yandex.ru}") || true
  PROXY_INPUT="${PROXY_INPUT:-yandex.ru}"
  if validate_domain "$PROXY_INPUT"; then
    break
  fi
  tui_info "Ошибка" "Некорректный домен: $PROXY_INPUT"
done
say "Default proxy: $PROXY_INPUT"

# ---- Шаг 4: SNI whitelist ----
SNI_INPUT=$(tui_input "Шаг 4/6 — SNI whitelist" "Разрешённые домены через запятую.\nПусто = разрешить все." "${CUR_SNI:-}") || true
say "SNI whitelist: ${SNI_INPUT:-<все домены>}"

# ---- Шаг 5: Torrent filter ----
if tui_yesno "Шаг 5/6 — Фильтр торрентов" "Блокировать BitTorrent-трафик?\n\nРекомендуется: да\n(предотвращает abuse и блокировку IP)"; then
  TORRENT_VAL="true"
else
  TORRENT_VAL="false"
fi
say "Torrent filter: $TORRENT_VAL"

# ---- Шаг 6: Часовой пояс ----
TZ_INPUT=$(tui_input "Шаг 6/6 — Часовой пояс" "Часовой пояс (IANA):" "${CUR_TZ:-UTC}") || true
TZ_INPUT="${TZ_INPUT:-UTC}"
say "Timezone: $TZ_INPUT"

# ---- Подтверждение ----
SUMMARY=$(cat <<EOF
Конфигурация FPTN:

  IP/домен сервера:   $IP_INPUT
  Порт VPN:           $PORT_INPUT
  Default proxy:      $PROXY_INPUT
  SNI whitelist:      ${SNI_INPUT:-<все домены>}
  Фильтр торрентов:   $TORRENT_VAL
  Часовой пояс:       $TZ_INPUT

Записать в $ENV_FILE?
EOF
)
tui_info "Подтверждение" "$SUMMARY"
if ! tui_yesno "Подтверждение" "Применить эти настройки?"; then
  warn "Отменено. Файл не изменён."
  exit 0
fi

# ---- Запись ----
set_env_var "SERVER_EXTERNAL_IPS"   "$IP_INPUT"
set_env_var "FPTN_PORT"             "$PORT_INPUT"
set_env_var "DEFAULT_PROXY_DOMAIN"  "$PROXY_INPUT"
set_env_var "ALLOWED_SNI_LIST"      "$SNI_INPUT"
set_env_var "DISABLE_TORRENT_FILTER" "$TORRENT_VAL"
set_env_var "TZ"                    "$TZ_INPUT"

say "Конфигурация записана в $ENV_FILE"
tui_info "Готово" "Конфигурация записана.\n\nСледующий шаг:\n  cd $(dirname "$ENV_DIR") && docker compose up -d"
