#!/usr/bin/env bash
# =============================================================
#  FTPN — Вариант-2: минимальный стек для семьи
#  Только VPN-сервер + Telegram-бот.
#  Опционально: веб-панель (на вопрос 'y').
# =============================================================
set -Eeuo pipefail
IFS=$'\n\t'
umask 027

# ---------- цвета ----------
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_RED=''; C_GRN=''; C_YEL=''; C_DIM=''; C_RST=''
fi
say()  { printf '%s[+]%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
err()  { printf '%s[✗]%s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }
hr()   { printf '%s%s%s\n' "$C_DIM" '----------------------------------------' "$C_RST"; }

trap 'err "Прервано на строке $LINENO. Код: $?"' ERR INT TERM

# ---------- проверка root ----------
[[ $EUID -eq 0 ]] || die "Запускай от root:  sudo bash $0"

# ---------- пути ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/fptn"
DATA_DIR="$INSTALL_DIR/data"
COMPOSE_DIR="$INSTALL_DIR/compose"
LOG_DIR="/var/log/fptn"

mkdir -p "$INSTALL_DIR" "$DATA_DIR/fptn-server" \
         "$LOG_DIR" \
         "$COMPOSE_DIR/server" "$COMPOSE_DIR/bot"

# ============================================================
# 1. ПРИВЕТСТВИЕ
# ============================================================
clear
cat <<'BANNER'
================================================================
        F P T N   F A M I L Y   E D I T I O N
        VPN + Telegram-бот (опционально: веб-панель)
        Без лишней сложности. Для дома и друзей.
================================================================
BANNER
hr

require_input() {
  local var_name="$1" prompt="$2" default="${3:-}" secret="${4:-no}" validate="${5:-}"
  local value=""
  while true; do
    if [[ -n "$default" && "$secret" != "yes" ]]; then
      printf '%s [%s]: ' "$prompt" "$default"
    else
      printf '%s: ' "$prompt"
    fi
    if [[ "$secret" == "yes" ]]; then
      read -rs value || true; printf '\n'
    else
      read -r value || true
    fi
    value="${value:-$default}"
    [[ -n "$value" ]] || { warn "Пустое значение недопустимо"; continue; }
    if [[ -n "$validate" ]]; then
      if ! eval "$validate \"\$value\"" 2>/dev/null; then
        warn "Некорректный формат"; continue
      fi
    fi
    printf -v "$var_name" '%s' "$value"
    break
  done
}

is_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r -a o <<< "$ip"
  for oct in "${o[@]}"; do (( oct >= 0 && oct <= 255 )) || return 1; done
}

is_domain() {
  [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

is_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 1 <= 10#$1 && 10#$1 <= 65535 ))
}

# ============================================================
# 2. МИНИМАЛЬНЫЕ ВОПРОСЫ (всегда)
# ============================================================
say "Шаг 1/4: Сеть"
hr
AUTO_IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null \
        || curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)"
require_input SERVER_IP "Внешний IPv4 сервера" "$AUTO_IP" no 'is_ipv4'
require_input SERVER_HOST "Домен (FQDN) для опционального Let's Encrypt" "" no 'is_domain'
[[ -n "$SERVER_HOST" ]] || SERVER_HOST="$SERVER_IP"
require_input VPN_PORT "Порт VPN-туннеля" "443" no 'is_port'

say "Шаг 2/4: Telegram-бот"
hr
require_input TG_TOKEN "Telegram bot token (@BotFather)" "" yes
require_input SERVICE_NAME "Название сервиса (для токенов)" "FPTN" no
require_input MAX_SPEED "Скорость по умолчанию для новых юзеров (Мбит/с)" "100" no '[[ "$1" =~ ^[0-9]+$ ]]'
printf "Brotli-сжатие токенов? (y/n): "; read -r BR
ENABLE_BROTLI="false"; [[ "$BR" =~ ^[YyДд]$ ]] && ENABLE_BROTLI="true"

say "Шаг 3/4: Анти-DPI (Reality)"
hr
require_input DEFAULT_PROXY_DOMAIN "Сайт-прикрытие (Reality fallback)" "yandex.ru" no 'is_domain'
require_input MAIN_SNI "Основной SNI для маскировки" "www.google.com" no 'is_domain'

# ============================================================
# 3. ОПЦИОНАЛЬНАЯ ПАНЕЛЬ
# ============================================================
hr
say "Шаг 4/4: Веб-панель администратора (опционально)"
hr
printf "Ставить веб-панель (React + FastAPI)? (y/n, по умолчанию n): "; read -r WP
INSTALL_PANEL="false"
if [[ "$WP" =~ ^[YyДд]$ ]]; then
  INSTALL_PANEL="true"
  require_input ADMIN_FE_HTTPS "Порт админки HTTPS"  "2663" no 'is_port'
  require_input ADMIN_FE_HTTP  "Порт админки HTTP"   "8080" no 'is_port'
  require_input ADMIN_BE_PORT  "Backend API порт"    "8000" no 'is_port'
  require_input ADMIN_LOGIN    "Логин администратора" "admin" no
  require_input ADMIN_PASSWORD "Пароль администратора" "" yes
fi
[[ "$VPN_PORT" != "${ADMIN_BE_PORT:-0}" ]] || die "Порты VPN и Backend API не должны совпадать"

# ============================================================
# 4. СОХРАНЕНИЕ КОНФИГА
# ============================================================
mkdir -p "$COMPOSE_DIR/admin"
[[ "$INSTALL_PANEL" == "true" ]] || ADMIN_FE_HTTPS=0; ADMIN_FE_HTTP=0; ADMIN_BE_PORT=0
cat > "$INSTALL_DIR/deploy-config.env" <<EOF
# Сгенерировано $(date '+%Y-%m-%d %H:%M:%S') скриптом deploy-family.sh
SERVER_IP=$SERVER_IP
SERVER_HOST=$SERVER_HOST
VPN_PORT=$VPN_PORT
TG_TOKEN=$TG_TOKEN
SERVICE_NAME=$SERVICE_NAME
MAX_SPEED=$MAX_SPEED
ENABLE_BROTLI=$ENABLE_BROTLI
DEFAULT_PROXY_DOMAIN=$DEFAULT_PROXY_DOMAIN
MAIN_SNI=$MAIN_SNI
INSTALL_PANEL=$INSTALL_PANEL
ADMIN_FE_HTTPS=$ADMIN_FE_HTTPS
ADMIN_FE_HTTP=$ADMIN_FE_HTTP
ADMIN_BE_PORT=$ADMIN_BE_PORT
ADMIN_LOGIN=$ADMIN_LOGIN
ADMIN_PASSWORD=$ADMIN_PASSWORD
EOF
chmod 600 "$INSTALL_DIR/deploy-config.env"

# ============================================================
# 5. УСТАНОВКА DOCKER
# ============================================================
hr
say "Устанавливаю Docker + Compose (если нет)"

if ! command -v docker >/dev/null 2>&1; then
  . /etc/os-release
  case "$ID" in
    ubuntu|debian)
      apt-get update -y
      apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/$ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/$ID $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
      apt-get update -y
      apt-get install -y --no-install-recommends \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
      ;;
    *)
      die "Автоустановка Docker только на Ubuntu/Debian. Установи вручную."
      ;;
  esac
else
  say "  Docker: $(docker --version)"
fi

docker compose version >/dev/null 2>&1 || die "Docker Compose v2 не найден"

# ============================================================
# 6. СЕТЬ
# ============================================================
if ! docker network inspect fptn-network >/dev/null 2>&1; then
  docker network create \
    --driver bridge --enable-ipv6 \
    --subnet dead:beef:cafe::/48 --gateway dead:beef:cafe::1 \
    --subnet 192.168.200.0/24  --gateway 192.168.200.1 \
    fptn-network
  say "  Создана сеть fptn-network"
fi

# ============================================================
# 7. КОПИРОВАНИЕ COMPOSE
# ============================================================
hr
say "Копирую compose-файлы из проекта"
SERVICE_PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cp "$SERVICE_PARENT_DIR/fptn/docker-compose/docker-compose.yml" \
   "$COMPOSE_DIR/server/docker-compose.yml"
cp "$SERVICE_PARENT_DIR/fptn/sysadmin-tools/telegram-bot/docker-compose.yml" \
   "$COMPOSE_DIR/bot/docker-compose.yml"

if [[ "$INSTALL_PANEL" == "true" ]]; then
  cp "$SERVICE_PARENT_DIR/fptn-admin/docker-compose.yml" \
     "$COMPOSE_DIR/admin/docker-compose.yml"
fi

# ============================================================
# 8. СЕРВЕРНЫЙ .env
# ============================================================
cat > "$COMPOSE_DIR/server/.env" <<EOF
FPTN_PORT=$VPN_PORT
SERVER_EXTERNAL_IPS=$SERVER_IP
ENABLE_DETECT_PROBING=true
DEFAULT_PROXY_DOMAIN=$DEFAULT_PROXY_DOMAIN
ALLOWED_SNI_LIST=$MAIN_SNI,$DEFAULT_PROXY_DOMAIN,youtube.com,instagram.com,facebook.com,rutube.ru,vk.com
DISABLE_TORRENT_FILTER=false
DISABLE_SPAM_FILTER=false
BLACKLIST_URL=https://raw.githubusercontent.com/fptn-project/fptn/refs/heads/master/deploy/domain_blacklist/russia.txt
MTU_SIZE=1400
USE_REMOTE_SERVER_AUTH=false
REMOTE_SERVER_AUTH_HOST=
REMOTE_SERVER_AUTH_PORT=443
PROMETHEUS_SECRET_ACCESS_KEY=$(openssl rand -hex 24)
MAX_ACTIVE_SESSIONS_PER_USER=3
USING_DNS_SERVER=unbound
DNS_IPV6_ENABLE=false
DNS_IPV4_PRIMARY=8.8.8.8
DNS_IPV4_SECONDARY=8.8.4.4
DNS_IPV6_PRIMARY=2001:4860:4860::8888
DNS_IPV6_SECONDARY=2001:4860:4860::8844
EOF
say "  → $COMPOSE_DIR/server/.env"

# ============================================================
# 9. ОБЩАЯ ПАПКА КОНФИГОВ
# ============================================================
FPTN_CONFIGS_DIR="$DATA_DIR/fptn-server"
mkdir -p "$FPTN_CONFIGS_DIR"
[[ -f "$FPTN_CONFIGS_DIR/users.list" ]] || : > "$FPTN_CONFIGS_DIR/users.list"

# Дефолтные серверы
if [[ ! -f "$FPTN_CONFIGS_DIR/servers.json" ]]; then
  cat > "$FPTN_CONFIGS_DIR/servers.json" <<EOF
{
  "servers": [
    {
      "name": "Home",
      "host": "$SERVER_IP",
      "port": $VPN_PORT,
      "md5_fingerprint": "",
      "ping": 10
    }
  ]
}
EOF
fi
[[ -f "$FPTN_CONFIGS_DIR/premium_servers.json"   ]] || echo '{"servers":[]}' > "$FPTN_CONFIGS_DIR/premium_servers.json"
[[ -f "$FPTN_CONFIGS_DIR/servers_censored_zone.json" ]] || echo '{"servers":[]}' > "$FPTN_CONFIGS_DIR/servers_censored_zone.json"
[[ -f "$FPTN_CONFIGS_DIR/bot_settings.json" ]] || cat > "$FPTN_CONFIGS_DIR/bot_settings.json" <<EOF
{
  "telegram_token": "$TG_TOKEN",
  "bot_enabled": true,
  "service_name": "$SERVICE_NAME",
  "max_user_speed_limit": $MAX_SPEED,
  "welcome_message_en": "⚡ Welcome! ⚡\\nType /token to get your access link.",
  "welcome_message_ru": "⚡ Добро пожаловать! ⚡\\nВведите /token для получения токена."
}
EOF

# ============================================================
# 10. TELEGRAM-БОТ .env
# ============================================================
cat > "$COMPOSE_DIR/bot/.env" <<EOF
TELEGRAM_API_TOKEN=$TG_TOKEN
FPTN_WELCOME_MESSAGE_EN=⚡ Welcome to the FPTN bot! ⚡\\n
Use this bot to get a VPN access token or reset it.\\n\\n
👉 Type /token to receive your connection token.
FPTN_WELCOME_MESSAGE_RU=⚡ Добро пожаловать в бот FPTN! ⚡\\n
Этот бот позволяет получить токен доступа к VPN или сбросить его.\\n\\n
👉 Введите /token для получения токена подключения.
ENABLE_BROTLI_COMPRESSION=$ENABLE_BROTLI
MAX_USER_SPEED_LIMIT=$MAX_SPEED
SERVICE_NAME=$SERVICE_NAME
FPTN_CONFIGS_FOLDER=$FPTN_CONFIGS_DIR
EOF
say "  → $COMPOSE_DIR/bot/.env"

# ============================================================
# 11. ОПЦИОНАЛЬНАЯ ПАНЕЛЬ
# ============================================================
if [[ "$INSTALL_PANEL" == "true" ]]; then
  hr
  say "Настраиваю веб-панель"

  cat > "$COMPOSE_DIR/admin/.env" <<EOF
JWT_TTL_MINUTES=60
ADMIN_LOGIN=$ADMIN_LOGIN
ADMIN_PASSWORD=$ADMIN_PASSWORD
CORS_ORIGINS=https://$SERVER_HOST
ENABLE_BROTLI_COMPRESSION=$ENABLE_BROTLI
FPTN_CONFIGS_FOLDER=$FPTN_CONFIGS_DIR

TELEGRAM_TOKEN=$TG_TOKEN
BOT_ENABLED=true
SERVICE_NAME=$SERVICE_NAME
MAX_USER_SPEED_LIMIT=$MAX_SPEED
WELCOME_MESSAGE_EN=⚡ Welcome! ⚡\\nUse /token to get your access link.
WELCOME_MESSAGE_RU=⚡ Добро пожаловать! ⚡\\nВведите /token для получения токена.
EOF

  # Самоподписанный сертификат для админки
  CERT_DIR="$DATA_DIR/certs"
  mkdir -p "$CERT_DIR"
  if [[ ! -f "$CERT_DIR/fullchain.pem" ]]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
      -keyout "$CERT_DIR/privkey.pem" \
      -out    "$CERT_DIR/fullchain.pem" \
      -subj   "/CN=$SERVER_HOST" \
      -addext "subjectAltName=DNS:$SERVER_HOST,IP:$SERVER_IP,IP:127.0.0.1"
  fi
  cat > "$COMPOSE_DIR/admin/docker-compose.override.yml" <<EOF
services:
  fptn-admin-frontend:
    volumes:
      - $CERT_DIR:/etc/fptn/certs:ro
EOF
  say "  → $COMPOSE_DIR/admin/.env + override"
fi

# ============================================================
# 12. СИСТЕМНЫЕ НАСТРОЙКИ
# ============================================================
hr
say "Включаю TUN и BBR"
modprobe tun 2>/dev/null || true
echo "tun" >> /etc/modules-load.d/fptn.conf 2>/dev/null || true

if ! sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
  {
    echo "net.core.default_qdisc = fq"
    echo "net.ipv4.tcp_congestion_control = bbr"
  } > /etc/sysctl.d/99-fptn.conf
  sysctl -p /etc/sysctl.d/99-fptn.conf || warn "BBR не активирован"
fi

# ============================================================
# 13. SYSTEMD
# ============================================================
hr
say "Устанавливаю systemd-юниты"
install -m 0644 "$SCRIPT_DIR/systemd/fptn-server.service" /etc/systemd/system/
install -m 0644 "$SCRIPT_DIR/systemd/fptn-telegram-bot.service" /etc/systemd/system/

if [[ "$INSTALL_PANEL" == "true" ]]; then
  install -m 0644 "$SCRIPT_DIR/systemd/fptn-admin-backend.service" /etc/systemd/system/
  install -m 0644 "$SCRIPT_DIR/systemd/fptn-admin-frontend.service" /etc/systemd/system/
fi

systemctl daemon-reload
systemctl enable --now fptn-server fptn-telegram-bot
[[ "$INSTALL_PANEL" == "true" ]] && systemctl enable --now fptn-admin-backend fptn-admin-frontend

# ============================================================
# 14. ЗАПУСК КОНТЕЙНЕРОВ
# ============================================================
hr
say "Подтягиваю и запускаю контейнеры"

( cd "$COMPOSE_DIR/server" && docker compose pull && docker compose up -d --remove-orphans )
( cd "$COMPOSE_DIR/bot"    && docker compose build && docker compose up -d --remove-orphans )

if [[ "$INSTALL_PANEL" == "true" ]]; then
  ( cd "$COMPOSE_DIR/admin" && docker compose pull && docker compose up -d --remove-orphans )
fi

# Ждём готовности бота
say "Жду готовности Telegram-бота (до 30 сек)…"
for _ in $(seq 1 15); do
  if docker ps --filter "name=fptn-telegram-bot" --filter "status=running" -q | grep -q .; then
    say "  Бот запущен"
    break
  fi
  sleep 2
done

# ============================================================
# 15. УСТАНОВКА УТИЛИТ
# ============================================================
install -m 0755 "$SCRIPT_DIR/scripts/fptn-status"     /usr/local/bin/fptn-status
install -m 0755 "$SCRIPT_DIR/scripts/fptn-logs"       /usr/local/bin/fptn-logs
install -m 0755 "$SCRIPT_DIR/scripts/fptn-add-user"   /usr/local/bin/fptn-add-user
install -m 0755 "$SCRIPT_DIR/scripts/fptn-list"       /usr/local/bin/fptn-list
install -m 0755 "$SCRIPT_DIR/scripts/fptn-block"      /usr/local/bin/fptn-block
install -m 0755 "$SCRIPT_DIR/scripts/fptn-unblock"    /usr/local/bin/fptn-unblock
install -m 0755 "$SCRIPT_DIR/scripts/fptn-show-config" /usr/local/bin/fptn-show-config
install -m 0755 "$SCRIPT_DIR/scripts/fptn-issue-token" /usr/local/bin/fptn-issue-token
install -m 0755 "$SCRIPT_DIR/scripts/fptn-backup"     /usr/local/bin/fptn-backup
install -m 0755 "$SCRIPT_DIR/scripts/fptn-update"     /usr/local/bin/fptn-update
install -m 0755 "$SCRIPT_DIR/scripts/fptn-reset-speed" /usr/local/bin/fptn-reset-speed
install -m 0755 "$SCRIPT_DIR/scripts/fptn-swap-setup" /usr/local/bin/fptn-swap-setup

# ============================================================
# 16. ИТОГ
# ============================================================
hr
cat <<INFO

${C_GRN}============================================================${C_RST}
${C_GRN}   FPTN FAMILY EDITION — РАЗВЁРНУТ${C_RST}
${C_GRN}============================================================${C_RST}

  VPN-сервер:  $SERVER_IP:$VPN_PORT

  Telegram-бот: запущен ✅
  Веб-панель:  $( [[ "$INSTALL_PANEL" == "true" ]] && echo "https://$SERVER_HOST:$ADMIN_FE_HTTPS" || echo "отключена (опционально)" )

  Данные (users.list / servers.json / bot_settings.json):
    $FPTN_CONFIGS_DIR/

${C_YEL}Утилиты (набери в SSH):${C_RST}
  fptn-status          — общий статус
  fptn-logs            — логи всех контейнеров
  fptn-list            — все пользователи
  fptn-add-user 123    — добавить пользователя
  fptn-block 123       — заблокировать
  fptn-unblock 123 100 — разблокировать + новая скорость
  fptn-reset-speed 123 — сбросить пароль
  fptn-issue-token 123 — получить токен
  fptn-show-config     — серверы и настройки
  fptn-backup          — бэкап
  fptn-update          — обновить

${C_YEL}Следующий шаг:${C_RST}
  1) Напиши боту /start в Telegram
  2) Введи /token — получишь access-токен
  3) Скачай клиент: https://storage.googleapis.com/fptn.org/
  4) Вставь токен → готово

INFO

# Пост-опции
TOTAL_RAM_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
if (( TOTAL_RAM_KB > 0 && TOTAL_RAM_KB < 2000000 )); then
  printf '%s[?]%s VPS имеет %s МБ RAM — создать swap 2 ГБ? (y/n): ' \
    "$C_YEL" "$C_RST" "$(( TOTAL_RAM_KB / 1024 ))"
  read -r SA
  if [[ "$SA" =~ ^[YyДд]$ ]]; then
    bash "$SCRIPT_DIR/scripts/fptn-swap-setup" 2048
  fi
fi

if [[ ! "$SERVER_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$INSTALL_PANEL" == "true" ]]; then
  printf '\n%s[?]%s Настроить Let'\''s Encrypt для админки? (y/n): ' "$C_YEL" "$C_RST"
  read -r LA
  if [[ "$LA" =~ ^[YyДд]$ ]]; then
    warn "Скрипт fptn-setup-letsencrypt в Варианте-1. Запусти его вручную."
  fi
fi

hr
say "Готово. Приятного пользования!"
