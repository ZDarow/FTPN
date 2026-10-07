#!/usr/bin/env bash
# =============================================================
#  FPTN — единый установщик VPN + Admin Panel
#  ------------------------------------------------------------
#  Использование:
#    sudo bash deploy/full-install.sh [--with-cpp] [--admin-login admin] [--admin-password pass] [--domain example.com]
#
#  Что делает:
#    1. Устанавливает системные зависимости (Docker, nginx, certbot, UFW)
#    2. Клонирует репозиторий в /opt/fptn
#    3. Генерирует SSL-сертификаты для VPN
#    4. Настраивает .env VPN
#    5. Запускает VPN-сервер
#    6. Собирает и запускает админ-панель
#    7. Выводит доступы
#
#  Поддерживает: Ubuntu 22.04+, Debian 12+
# =============================================================
set -Eeuo pipefail

# ---- Цвета и лог ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
say()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
hr()   { echo -e "${BLUE}------------------------------------------------------------${NC}"; }

# ---- Аргументы ----
INSTALL_CPP_BUILD=false
ADMIN_LOGIN="admin"
ADMIN_PASSWORD=""
DOMAIN=""
for arg in "$@"; do
  case "${arg}" in
    --with-cpp)    INSTALL_CPP_BUILD=true ;;
    --without-cpp) INSTALL_CPP_BUILD=false ;;
    --admin-login=*) ADMIN_LOGIN="${arg#*=}" ;;
    --admin-password=*) ADMIN_PASSWORD="${arg#*=}" ;;
    --domain=*) DOMAIN="${arg#*=}" ;;
    -h|--help)
      echo "Использование: $0 [--with-cpp] [--admin-login admin] [--admin-password pass] [--domain example.com]"
      echo "  --with-cpp          дополнительно ставит toolchain для сборки C++"
      echo "  --admin-login       логин админа (по умолчанию: admin)"
      echo "  --admin-password    пароль админа (минимум 8 символов, по умолчанию: случайный)"
      echo "  --domain            домен/IP для админки (по умолчанию: auto-detect)"
      exit 0
      ;;
  esac
done

# ---- Проверка root ----
if [[ ${EUID} -ne 0 ]]; then
  err "Требуются права root. Перезапустите: sudo bash $0"
  exit 1
fi

hr
say "FPTN full installer (VPN + Admin Panel)"
hr

# ---- 1. Prerequisites ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/prereq-install.sh" ]]; then
  say "[1/6] Устанавливаю системные зависимости..."
  bash "$SCRIPT_DIR/prereq-install.sh" ${INSTALL_CPP_BUILD:+--with-cpp} ${INSTALL_CPP_BUILD:+-without-cpp}
else
  err "Не найден $SCRIPT_DIR/prereq-install.sh"
  exit 1
fi

# ---- 2. Клонируем/обновляем репозиторий ----
REPO="https://github.com/ZDarow/FTPN.git"
INSTALL_DIR="/opt/fptn"
hr
say "[2/6] Клонирую/обновляю репозиторий..."
if [[ -d "$INSTALL_DIR/.git" ]]; then
  say "  Обновляю $INSTALL_DIR"
  (cd "$INSTALL_DIR" && git pull --quiet)
else
  say "  Клонирую $REPO → $INSTALL_DIR"
  git clone --depth=1 --quiet "$REPO" "$INSTALL_DIR"
fi

# ---- 3. Настраиваем .env VPN ----
VPN_ENV="$INSTALL_DIR/fptn/docker-compose/.env"
if [[ ! -f "$VPN_ENV" ]]; then
  cp "$INSTALL_DIR/fptn/docker-compose/.env.demo" "$VPN_ENV"
  say "  Создан $VPN_ENV"
fi

# Авто-определение публичного IP
PUBLIC_IP=""
if [[ -z "$PUBLIC_IP" ]]; then
  PUBLIC_IP=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
fi
if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  sed -i "s|^SERVER_EXTERNAL_IPS=.*|SERVER_EXTERNAL_IPS=$PUBLIC_IP|" "$VPN_ENV"
  say "  SERVER_EXTERNAL_IPS=$PUBLIC_IP"
fi

# ---- 4. SSL-сертификаты для VPN ----
VPN_DATA="$INSTALL_DIR/fptn/docker-compose/fptn-server-data"
mkdir -p "$VPN_DATA"
if [[ ! -f "$VPN_DATA/server.crt" || ! -f "$VPN_DATA/server.key" ]]; then
  say "[3/6] Генерирую SSL-сертификаты для VPN..."
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "$VPN_DATA/server.key" \
    -out "$VPN_DATA/server.crt" \
    -subj "/CN=$PUBLIC_IP" 2>/dev/null
  say "  Сертификаты: $VPN_DATA/server.crt, $VPN_DATA/server.key"
else
  say "[3/6] SSL-сертификаты уже существуют, пропускаю"
fi

# ---- 5. Запускаем VPN ----
hr
say "[4/6] Запускаю VPN-сервер..."
cd "$INSTALL_DIR/fptn/docker-compose"
docker compose pull
docker compose up -d --remove-orphans
say "  VPN запущен"

# ---- 6. Админ-панель ----
hr
say "[5/6] Настраиваю админ-панель..."

# Домен/IP для панели
if [[ -z "$DOMAIN" ]]; then
  DOMAIN="$PUBLIC_IP"
fi

# Пароль админа
if [[ -z "$ADMIN_PASSWORD" ]]; then
  ADMIN_PASSWORD=$(openssl rand -base64 16 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "admin1234")
fi

# Создаём .env для панели
ADMIN_ENV="$INSTALL_DIR/fptn-admin/.env"
mkdir -p "$INSTALL_DIR/fptn-admin"
cat > "$ADMIN_ENV" <<EOF
JWT_TTL_MINUTES=60
ADMIN_LOGIN=$ADMIN_LOGIN
ADMIN_PASSWORD=$ADMIN_PASSWORD
CORS_ORIGINS=https://$DOMAIN:2663
ENABLE_BROTLI_COMPRESSION=true
FPTN_CONFIGS_FOLDER=$VPN_DATA
TELEGRAM_TOKEN=
BOT_ENABLED=false
SERVICE_NAME=fptn
MAX_USER_SPEED_LIMIT=30
WELCOME_MESSAGE_EN=
WELCOME_MESSAGE_RU=
EOF
chmod 600 "$ADMIN_ENV"
say "  $ADMIN_ENV создан"

# Создаём users.list если нет
touch "$VPN_DATA/users.list"

# Собираем и запускаем панель
cd "$INSTALL_DIR/fptn-admin"
docker compose build
docker compose up -d --remove-orphans
say "  Админ-панель запущена"

# ---- 7. Проверки ----
hr
say "[6/6] Проверяю..."

# Ждём запуска backend
for i in $(seq 1 30); do
  if curl -fsS http://localhost:8000/health >/dev/null 2>&1; then
    say "  Backend: healthy"
    break
  fi
  sleep 1
done

# Ждём запуска frontend
for i in $(seq 1 30); do
  if curl -fsSk https://localhost:2663/health >/dev/null 2>&1; then
    say "  Frontend: healthy"
    break
  fi
  sleep 1
done

# ---- Итог ----
hr
cat <<EOF

============================================================
  FPTN развёрнут!
============================================================

  VPN:
    Образ:      fptnvpn/fptn-vpn-server:0.4.4
    Порт:       443/tcp
    SSL:        самоподписанный (CN=$PUBLIC_IP)
    Данные:     $VPN_DATA

  Админ-панель:
    URL:        https://$DOMAIN:2663
    Backend:    http://$DOMAIN:8000
    Логин:      $ADMIN_LOGIN
    Пароль:     $ADMIN_PASSWORD

  Управление:
    VPN логи:   cd $INSTALL_DIR/fptn/docker-compose && docker compose logs -f
    Панель логи: cd $INSTALL_DIR/fptn-admin && docker compose logs -f
    Остановка:  cd $INSTALL_DIR/fptn/docker-compose && docker compose down
                cd $INSTALL_DIR/fptn-admin && docker compose down

  ⚠️  Самоподписанный SSL — браузер будет ругаться на недоверенный сертификат.
      Для production замените на Let's Encrypt.

============================================================
EOF
hr
