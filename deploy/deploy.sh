#!/usr/bin/env bash
# =============================================================
#  FTPN — полное развёртывание VPN-сервера + админ-панели
#  + Telegram-бота на чистом Ubuntu 22.04/24.04 / Debian 12
# =============================================================
#  Запуск:  sudo bash deploy.sh
#  Поведение:
#    • интерактивно запрашивает все необходимые параметры
#    • устанавливает Docker + Compose
#    • копирует и патчит docker-compose'ы
#    • генерирует самоподписанный сертификат
#    • поднимает три стека (vpn, admin-backend, admin-frontend)
#    • пишет systemd-юниты для автоперезапуска
# =============================================================
set -Eeuo pipefail
IFS=$'\n\t'
umask 027

# ---------- цвета ----------
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_DIM=$'\033[2m'; C_RST=$'\033[0m'
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
if [[ $EUID -ne 0 ]]; then
  die "Запускай от root:  sudo bash $0"
fi

# ---------- пути ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_DIR="/opt/fptn"
DATA_DIR="$INSTALL_DIR/data"
LOG_DIR="/var/log/fptn"
BACKUP_DIR="/var/backups/fptn"
COMPOSE_DIR="$INSTALL_DIR/compose"

mkdir -p "$INSTALL_DIR" "$DATA_DIR/fptn-server" \
         "$LOG_DIR" "$BACKUP_DIR" \
         "$COMPOSE_DIR/server" "$COMPOSE_DIR/admin" "$COMPOSE_DIR/bot"

# ============================================================
# 1. ПРИВЕТСТВИЕ + СБОР ПАРАМЕТРОВ
# ============================================================
clear || true
cat <<'BANNER'
================================================================
        F P T N   D E P L O Y   S C R I P T
        VPN-сервер + админ-панель + Telegram-бот
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
    # Если ввод пустой и default задан — берём default без валидации
    if [[ -z "$value" && -n "$default" ]]; then
      printf -v "$var_name" '%s' "$default"
      break
    fi
    # Пустой ввод при пустом default — ошибка (если валидатор не пропускает пустое)
    if [[ -z "$value" ]]; then
      # Если валидатор не задан или пропускает пустую строку — принимаем
      if [[ -z "$validate" ]] || eval "$validate \"\"" 2>/dev/null; then
        printf -v "$var_name" '%s' ""
        break
      fi
      warn "Пустое значение недопустимо"; continue
    fi
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
  local o; IFS='.' read -r -a o <<< "$ip"
  for oct in "${o[@]}"; do
    (( oct >= 0 && oct <= 255 )) || return 1
  done
}

is_domain() {
  [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

# Принимает FQDN (a.b.c.tld), IPv4 (xxx.xxx.xxx.xxx) или пустую строку
is_host() {
  [[ -z "$1" ]] || is_domain "$1" || is_ipv4 "$1"
}

is_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 1 <= 10#$1 && 10#$1 <= 65535 ))
}

say "Шаг 1/8: Сетевые параметры сервера"
hr

# Авто-детект внешнего IP
AUTO_IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null \
        || curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)"
if [[ -z "$AUTO_IP" ]]; then
  warn "Не удалось автоопределить внешний IP — введи вручную"
  AUTO_IP=""
fi
require_input SERVER_IP    "Внешний IPv4 сервера"        "$AUTO_IP" no 'is_ipv4'
require_input SERVER_HOST  "Домен для панели (FQDN или пусто для IP)" "" no 'is_host'
[[ -n "$SERVER_HOST" ]] || SERVER_HOST="$SERVER_IP"

say "Шаг 2/8: Порты"
hr
require_input VPN_PORT        "Порт VPN-туннеля"        "443"  no 'is_port'
require_input ADMIN_FE_HTTPS   "HTTPS порт админ-панели"  "2663" no 'is_port'
require_input ADMIN_FE_HTTP    "HTTP  порт админ-панели (редирект)" "8080" no 'is_port'
require_input ADMIN_BE_PORT    "Backend API порт"        "8000" no 'is_port'

say "Шаг 3/8: Telegram-бот"
hr
require_input TG_TOKEN         "Telegram bot token (@BotFather)" "" yes
require_input SERVICE_NAME     "Название сервиса (для токенов)" "FPTN.ONLINE" no
require_input MAX_SPEED        "Скорость по умолчанию (Мбит/с)" "100" no '[[ "$1" =~ ^[0-9]+$ ]]'
printf "Включить brotli-сжатие токенов? (y/n): "; read -r BR
ENABLE_BROTLI="false"; [[ "$BR" =~ ^[YyДд]$ ]] && ENABLE_BROTLI="true"

printf "Запускать Telegram-бот сразу? (y/n): "; read -r RUN_BOT
BOT_ENABLED="false"; [[ "$RUN_BOT" =~ ^[YyДд]$ ]] && BOT_ENABLED="true"

say "Шаг 4/8: Анти-DPI параметры"
hr
require_input DEFAULT_PROXY_DOMAIN "Сайт-прикрытие (Reality fallback)"  "yandex.ru" no 'is_domain'
require_input MAIN_SNI             "Основной SNI (для маскировки)"      "www.google.com" no 'is_domain'
ALLOWED_SNI_LIST="www.google.com,yandex.ru,youtube.com,instagram.com,facebook.com,twitter.com,whatsapp.com,rutube.ru,vk.com"

say "Шаг 5/8: Админ-панель"
hr
require_input ADMIN_LOGIN    "Логин администратора" "admin" no
require_input ADMIN_PASSWORD "Пароль администратора" "" yes
require_input CORS_ORIGINS   "CORS origins (через запятую, или *)"  "https://$SERVER_HOST" no

say "Шаг 6/8: Доменный blacklist и фильтры"
hr
printf "Включить фильтр BitTorrent? (y/n, по умолчанию y): "; read -r FT_T
DISABLE_TORRENT_FILTER="false"; [[ "$FT_T" =~ ^[NnНн]$ ]] && DISABLE_TORRENT_FILTER="true"
printf "Включить фильтр спама/портов-червей? (y/n, по умолчанию y): "; read -r FT_S
DISABLE_SPAM_FILTER="false"; [[ "$FT_S" =~ ^[NnНн]$ ]] && DISABLE_SPAM_FILTER="true"
require_input MAX_SESSIONS  "Макс. активных сессий на юзера" "3" no '[[ "$1" =~ ^[0-9]+$ ]]'

# ============================================================
# 2. СОХРАНЕНИЕ КОНФИГА
# ============================================================
hr
say "Шаг 7/8: Сохраняю конфигурацию"

cat > "$INSTALL_DIR/deploy-config.env" <<EOF
# Сгенерировано $(date '+%Y-%m-%d %H:%M:%S') скриптом deploy.sh
# Не редактируй вручную без понимания; для изменений используй update-config.sh
SERVER_IP=$SERVER_IP
SERVER_HOST=$SERVER_HOST
VPN_PORT=$VPN_PORT
ADMIN_FE_HTTPS=$ADMIN_FE_HTTPS
ADMIN_FE_HTTP=$ADMIN_FE_HTTP
ADMIN_BE_PORT=$ADMIN_BE_PORT
TG_TOKEN=$TG_TOKEN
SERVICE_NAME=$SERVICE_NAME
MAX_SPEED=$MAX_SPEED
ENABLE_BROTLI=$ENABLE_BROTLI
BOT_ENABLED=$BOT_ENABLED
DEFAULT_PROXY_DOMAIN=$DEFAULT_PROXY_DOMAIN
MAIN_SNI=$MAIN_SNI
ALLOWED_SNI_LIST=$ALLOWED_SNI_LIST
ADMIN_LOGIN=$ADMIN_LOGIN
ADMIN_PASSWORD=$ADMIN_PASSWORD
CORS_ORIGINS=$CORS_ORIGINS
DISABLE_TORRENT_FILTER=$DISABLE_TORRENT_FILTER
DISABLE_SPAM_FILTER=$DISABLE_SPAM_FILTER
MAX_SESSIONS=$MAX_SESSIONS
EOF
chmod 600 "$INSTALL_DIR/deploy-config.env"
say "  → $INSTALL_DIR/deploy-config.env"

# ============================================================
# 3. УСТАНОВКА DOCKER
# ============================================================
hr
say "Шаг 8/8: Устанавливаю Docker + Compose"

if ! command -v docker >/dev/null 2>&1; then
  warn "Docker не найден — устанавливаю"
  # shellcheck disable=SC1091
  . /etc/os-release
  case "$ID" in
    ubuntu|debian)
      apt-get update -y
      apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg lsb-release
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/$ID/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg
      echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/$ID $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
      apt-get update -y
      apt-get install -y --no-install-recommends \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
      ;;
    *)
      die "Автоустановка Docker поддерживается только на Ubuntu/Debian. Установи Docker вручную и перезапусти скрипт."
      ;;
  esac
else
  say "  Docker уже установлен: $(docker --version)"
fi

if ! docker compose version >/dev/null 2>&1; then
  die "Docker Compose v2 не найден. Установи: https://docs.docker.com/compose/install/"
fi
say "  Docker Compose: $(docker compose version)"

# ============================================================
# 4. КОПИРОВАНИЕ COMPOSE-ФАЙЛОВ ИЗ ПРОЕКТА
# ============================================================
hr
say "Копирую compose-файлы из проекта → $COMPOSE_DIR"

cp "$PROJECT_DIR/fptn/docker-compose/docker-compose.yml" \
   "$COMPOSE_DIR/server/docker-compose.yml"
cp "$PROJECT_DIR/fptn-admin/docker-compose.yml" \
   "$COMPOSE_DIR/admin/docker-compose.yml"
cp "$PROJECT_DIR/fptn/sysadmin-tools/telegram-bot/docker-compose.yml" \
   "$COMPOSE_DIR/bot/docker-compose.yml"

# Копируем исходники (compose-файлы используют build: ./)
say "Копирую исходники для сборки образов"
cp -r "$PROJECT_DIR/fptn-admin/backend"  "$COMPOSE_DIR/admin/backend"
cp -r "$PROJECT_DIR/fptn-admin/frontend" "$COMPOSE_DIR/admin/frontend"
mkdir -p "$COMPOSE_DIR/bot/telegram-bot-tmp"
cp -r "$PROJECT_DIR/fptn/sysadmin-tools/telegram-bot/." \
      "$COMPOSE_DIR/bot/telegram-bot-tmp/"
mv "$COMPOSE_DIR/bot/telegram-bot-tmp/Dockerfile" \
   "$COMPOSE_DIR/bot/Dockerfile" 2>/dev/null || true
mv "$COMPOSE_DIR/bot/telegram-bot-tmp/src" \
   "$COMPOSE_DIR/bot/src" 2>/dev/null || true
mv "$COMPOSE_DIR/bot/telegram-bot-tmp/configs" \
   "$COMPOSE_DIR/bot/configs" 2>/dev/null || true
rm -rf "$COMPOSE_DIR/bot/telegram-bot-tmp"

# Сборка внешней сети (чтобы контейнеры видели друг друга по именам)
if ! docker network inspect fptn-network >/dev/null 2>&1; then
  # Docker 25+ включает IPv6 по умолчанию, --enable-ipv6 устарел
  docker network create \
    --driver bridge \
    --subnet 192.168.200.0/24  --gateway 192.168.200.1 \
    fptn-network 2>/dev/null || \
  docker network create \
    --driver bridge --enable-ipv6 \
    --subnet dead:beef:cafe::/48 --gateway dead:beef:cafe::1 \
    --subnet 192.168.200.0/24  --gateway 192.168.200.1 \
    fptn-network
  say "  Создана внешняя сеть fptn-network"
fi

# ============================================================
# 5. СЕРВЕРНЫЙ .env
# ============================================================
cat > "$COMPOSE_DIR/server/.env" <<EOF
FPTN_PORT=$VPN_PORT
SERVER_EXTERNAL_IPS=$SERVER_IP
ENABLE_DETECT_PROBING=true
DEFAULT_PROXY_DOMAIN=$DEFAULT_PROXY_DOMAIN
ALLOWED_SNI_LIST=$ALLOWED_SNI_LIST
DISABLE_TORRENT_FILTER=$DISABLE_TORRENT_FILTER
DISABLE_SPAM_FILTER=$DISABLE_SPAM_FILTER
BLACKLIST_URL=https://raw.githubusercontent.com/fptn-project/fptn/refs/heads/master/deploy/domain_blacklist/russia.txt
MTU_SIZE=1400
USE_REMOTE_SERVER_AUTH=false
REMOTE_SERVER_AUTH_HOST=
REMOTE_SERVER_AUTH_PORT=443
PROMETHEUS_SECRET_ACCESS_KEY=$(openssl rand -hex 24)
MAX_ACTIVE_SESSIONS_PER_USER=$MAX_SESSIONS
USING_DNS_SERVER=unbound
DNS_IPV6_ENABLE=false
DNS_IPV4_PRIMARY=8.8.8.8
DNS_IPV4_SECONDARY=8.8.4.4
DNS_IPV6_PRIMARY=2001:4860:4860::8888
DNS_IPV6_SECONDARY=2001:4860:4860::8844
EOF
say "  → $COMPOSE_DIR/server/.env"

# ============================================================
# 6. АДМИН-ПАНЕЛЬ .env
# ============================================================
FPTN_CONFIGS_DIR="$DATA_DIR/fptn-server"
mkdir -p "$FPTN_CONFIGS_DIR"

# Если users.list ещё не существует — создаём с пустым admin-юзером
[[ -f "$FPTN_CONFIGS_DIR/users.list" ]] || : > "$FPTN_CONFIGS_DIR/users.list"

cat > "$COMPOSE_DIR/admin/.env" <<EOF
JWT_TTL_MINUTES=60
ADMIN_LOGIN=$ADMIN_LOGIN
ADMIN_PASSWORD=$ADMIN_PASSWORD
CORS_ORIGINS=$CORS_ORIGINS
ENABLE_BROTLI_COMPRESSION=$ENABLE_BROTLI
FPTN_CONFIGS_FOLDER=$FPTN_CONFIGS_DIR

TELEGRAM_TOKEN=$TG_TOKEN
BOT_ENABLED=$BOT_ENABLED
SERVICE_NAME=$SERVICE_NAME
MAX_USER_SPEED_LIMIT=$MAX_SPEED
WELCOME_MESSAGE_EN="⚡ Welcome to the FPTN bot! ⚡\nUse /token to get your access link."
WELCOME_MESSAGE_RU="⚡ Добро пожаловать в бот FPTN! ⚡\nИспользуйте /token для получения токена доступа."
EOF
say "  → $COMPOSE_DIR/admin/.env"

# ============================================================
# 7. TELEGRAM-БОТ .env
# ============================================================
cat > "$COMPOSE_DIR/bot/.env" <<EOF
TELEGRAM_API_TOKEN=$TG_TOKEN
FPTN_WELCOME_MESSAGE_EN="⚡ Welcome to the FPTN bot! ⚡\nUse this bot to get a VPN access token or reset it.\n\n👉 Type /token to receive your connection token."
FPTN_WELCOME_MESSAGE_RU="⚡ Добро пожаловать в бот FPTN! ⚡\nЭтот бот позволяет получить токен доступа к VPN или сбросить его.\n\n👉 Введите /token для получения токена подключения."
ENABLE_BROTLI_COMPRESSION=$ENABLE_BROTLI
MAX_USER_SPEED_LIMIT=$MAX_SPEED
SERVICE_NAME=$SERVICE_NAME
FPTN_CONFIGS_FOLDER=$FPTN_CONFIGS_DIR
EOF
say "  → $COMPOSE_DIR/bot/.env"

# ============================================================
# 8. САМОПОДПИСАННЫЙ СЕРТИФИКАТ
# ====================================================================================
hr
say "Генерирую TLS-сертификат для админ-панели"
CERT_DIR="$DATA_DIR/certs"
mkdir -p "$CERT_DIR"
if [[ ! -f "$CERT_DIR/fullchain.pem" ]]; then
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout "$CERT_DIR/privkey.pem" \
    -out    "$CERT_DIR/fullchain.pem" \
    -subj   "/CN=$SERVER_HOST" \
    -addext "subjectAltName=DNS:$SERVER_HOST,DNS:localhost,IP:$SERVER_IP,IP:127.0.0.1"
  say "  Сертификат создан: $CERT_DIR"
else
  say "  Сертификат уже существует"
fi

# Патчим frontend-композ чтобы примонтировать сертификат
cat > "$COMPOSE_DIR/admin/docker-compose.override.yml" <<EOF
services:
  fptn-admin-frontend:
    volumes:
      - $CERT_DIR:/etc/fptn/certs:ro
EOF

# ============================================================
# 9. СИСТЕМНЫЕ НАСТРОЙКИ (BBR, TUN)
# ====================================================================================
hr
say "Включаю BBR и модуль TUN на хосте"
modprobe tun 2>/dev/null || true
echo "tun" >> /etc/modules-load.d/fptn.conf 2>/dev/null || true

if ! sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
  {
    echo "net.core.default_qdisc = fq"
    echo "net.ipv4.tcp_congestion_control = bbr"
  } > /etc/sysctl.d/99-fptn.conf
  sysctl -p /etc/sysctl.d/99-fptn.conf || warn "BBR не удалось активировать — проверь ядро"
else
  say "  BBR уже активен"
fi

# ============================================================
# 10. SYSTEMD-ЮНИТЫ
# ====================================================================================
hr
say "Создаю systemd-юниты для автоперезапуска"

# Удаляем возможные старые юниты из fptn-admin
rm -f /etc/systemd/system/fptn-admin-backend.service \
      /etc/systemd/system/fptn-admin-frontend.service

install -m 0644 "$SCRIPT_DIR/systemd/fptn-server.service"      /etc/systemd/system/
install -m 0644 "$SCRIPT_DIR/systemd/fptn-admin-backend.service" /etc/systemd/system/
install -m 0644 "$SCRIPT_DIR/systemd/fptn-admin-frontend.service" /etc/systemd/system/
install -m 0644 "$SCRIPT_DIR/systemd/fptn-telegram-bot.service"  /etc/systemd/system/
install -m 0644 "$SCRIPT_DIR/systemd/fptn-healthcheck.service"   /etc/systemd/system/
install -m 0644 "$SCRIPT_DIR/systemd/fptn-healthcheck.timer"     /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now fptn-server fptn-admin-backend fptn-admin-frontend fptn-telegram-bot
systemctl enable --now fptn-healthcheck.timer
say "  Юниты включены и запущены (включая healthcheck timer)"

# ============================================================
# 11. ЗАПУСК ВСЕХ СТЕКОВ
# ====================================================================================
hr
say "Поднимаю контейнеры"

( cd "$COMPOSE_DIR/server" && docker compose pull )
( cd "$COMPOSE_DIR/admin"  && docker compose pull )
( cd "$COMPOSE_DIR/bot"    && docker compose pull )

( cd "$COMPOSE_DIR/server" && docker compose up -d --remove-orphans )
( cd "$COMPOSE_DIR/admin"  && docker compose up -d --remove-orphans )
( cd "$COMPOSE_DIR/bot"    && docker compose up -d --remove-orphans )

# Ждём, пока backend поднимется (с таймаутом 60 сек)
say "Жду готовности backend (до 60 сек)…"
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$ADMIN_BE_PORT/health" >/dev/null 2>&1; then
    say "  Backend отвечает!"
    break
  fi
  sleep 2
done

# ============================================================
# 12. УСТАНОВКА ДОПОЛНИТЕЛЬНЫХ СКРИПТОВ
# ============================================================
install -m 0755 "$SCRIPT_DIR/scripts/update.sh"             /usr/local/bin/fptn-update
install -m 0755 "$SCRIPT_DIR/scripts/backup.sh"             /usr/local/bin/fptn-backup
install -m 0755 "$SCRIPT_DIR/scripts/status.sh"             /usr/local/bin/fptn-status
install -m 0755 "$SCRIPT_DIR/scripts/tail-logs.sh"          /usr/local/bin/fptn-logs
install -m 0755 "$SCRIPT_DIR/scripts/add-user.sh"           /usr/local/bin/fptn-add-user
install -m 0755 "$SCRIPT_DIR/scripts/issue-token.sh"        /usr/local/bin/fptn-issue-token
install -m 0755 "$SCRIPT_DIR/scripts/setup-letsencrypt.sh"  /usr/local/bin/fptn-setup-letsencrypt
install -m 0755 "$SCRIPT_DIR/scripts/swap-setup.sh"         /usr/local/bin/fptn-swap-setup

# ============================================================
# 13. ИТОГ
# ============================================================
hr
cat <<INFO

${C_GRN}============================================================${C_RST}
${C_GRN}   FPTN РАЗВЁРНУТ УСПЕШНО${C_RST}
${C_GRN}============================================================${C_RST}

  VPN-сервер (HTTPS, Reality):
    https://$SERVER_HOST:$VPN_PORT  /  $SERVER_IP:$VPN_PORT

  Админ-панель:
    https://$SERVER_HOST:$ADMIN_FE_HTTPS
    http://$SERVER_HOST:$ADMIN_FE_HTTP  (редирект на HTTPS)
    Логин:  $ADMIN_LOGIN
    Пароль: $ADMIN_PASSWORD   ← ОБЯЗАТЕЛЬНО смени при первом входе!

  Backend API (внутр.):
    http://127.0.0.1:$ADMIN_BE_PORT/api/v1/docs  (Swagger)

  Telegram-бот:
    $( [[ "$BOT_ENABLED" == "true" ]] && echo "Запущен" || echo "Отключён (включи через админку → Settings → Telegram Bot") 

  Данные (users.list / admins.json / servers.json):
    $DATA_DIR/fptn-server/

  Конфигурация развёртывания:
    $INSTALL_DIR/deploy-config.env

${C_YEL}Утилиты:${C_RST}
  fptn-status                 — статус всех контейнеров
  fptn-logs                   — просмотр логов всех сервисов
  fptn-backup                 — бэкап users.list/admins.json/servers
  fptn-update                 — обновление Docker-образов
  fptn-add-user <tg_id>       — создать VPN-пользователя
  fptn-issue-token <tg_id>    — выдать токен пользователю
  fptn-setup-letsencrypt      — реальный SSL через Let's Encrypt (если есть FQDN)
  fptn-swap-setup [size_mb]   — создать swap (по умолчанию 2048 МБ)

${C_YEL}Следующие шаги:${C_RST}
  1) Зайди в админ-панель, смени пароль admin
  2) Settings → Telegram Bot → вставь свой токен, включи бота
  3) Servers → добавь сам сервер $SERVER_IP:$VPN_PORT
  4) Скачай клиент: https://storage.googleapis.com/fptn.org/

INFO

# Пост-установочные опции
hr
if [[ ! "$SERVER_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo
  printf '%s[?]%s Настроить Let'\''s Encrypt для https://%s ? (y/n): ' "$C_YEL" "$C_RST" "$SERVER_HOST"
  read -r LE_ANSWER
  if [[ "$LE_ANSWER" =~ ^[YyДд]$ ]]; then
    fptn-setup-letsencrypt || warn "Настройка Let'\''s Encrypt не удалась — настрой вручную позже"
  fi
fi

# Swap, если RAM < 2 ГБ
TOTAL_RAM_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
if (( TOTAL_RAM_KB > 0 && TOTAL_RAM_KB < 2000000 )); then
  echo
  printf '%s[?]%s На VPS всего %s МБ RAM — создать swap 2 ГБ? (y/n): ' \
    "$C_YEL" "$C_RST" "$(( TOTAL_RAM_KB / 1024 ))"
  read -r SWAP_ANSWER
  if [[ "$SWAP_ANSWER" =~ ^[YyДд]$ ]]; then
    fptn-swap-setup 2048 || warn "Swap не удалось создать"
  fi
fi

echo
say "Готово. Можно начинать работу."
hr
