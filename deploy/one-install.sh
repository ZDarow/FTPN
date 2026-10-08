#!/usr/bin/env bash
# =============================================================
#  FPTN — единый установщик «одной командой»
#  ------------------------------------------------------------
#  Использование:
#    sudo bash deploy/one-install.sh
#
#  Что делает:
#    1. Устанавливает системные зависимости
#    2. Клонирует репозиторий в /opt/fptn
#    3. Настраивает VPN (.env + SSL)
#    4. Запускает VPN-сервер
#    5. Настраивает и запускает админ-панель
#    6. Опционально: Telegram-бот
#    7. Выводит итоговую сводку
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
# ---- Проверка root ----
if [[ ${EUID} -ne 0 ]]; then
  err "Требуются права root. Перезапустите: sudo bash $0"
  exit 1
fi

# ---- Пути ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="https://github.com/ZDarow/FTPN.git"
INSTALL_DIR="/opt/fptn"
VPN_ENV="$INSTALL_DIR/fptn/docker-compose/.env"
VPN_DATA="$INSTALL_DIR/fptn/docker-compose/fptn-server-data"
ADMIN_ENV="$INSTALL_DIR/fptn-admin/.env"

# ---- TUI-библиотека ----
if [[ -f "$SCRIPT_DIR/lib/tui.sh" ]]; then
  # shellcheck source=lib/tui.sh
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/tui.sh"
fi

# =============================================================
#  ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# =============================================================
validate_ip() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS='.'
  local -a parts
  read -ra parts <<< "$1"
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

# =============================================================
#  ШАГ 0: Приветствие
# =============================================================
hr
cat <<'EOF'
  ____  _   _  ____   ____   _____ _____ _____ _____
 |  _ \| | | |/ ___| |  _ \ / ____|_   _|_   _|_   _|
 | |_) | | | | |  _  | |_) | |      | |   | |   | |
 |  __/| |_| | |_| | |  __/| |____ _| |_ _| |_ _| |_
 |_|    \___/ \____| |_|    \_____|_____|_____|_____|

  Fast Protected Tunnel Network — единый установщик
EOF
hr

if ! tui_yesno "FPTN Installer" "Начнём установку FPTN на этот сервер?"; then
  warn "Установка отменена."
  exit 0
fi

# =============================================================
#  ШАГ 1: Сбор конфигурации
# =============================================================
hr
say "Шаг 1/6 — Сбор конфигурации"
hr

# ---- 1.1. Публичный IP / домен ----
AUTO_IP=""
if [[ -z "$AUTO_IP" ]]; then
  AUTO_IP=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
fi
DEFAULT_HOST="${AUTO_IP:-1.2.3.4}"

while true; do
  HOST_INPUT=$(tui_input "Шаг 1/6 — Домен/IP" "Домен или IP для админ-панели и VPN.\nПусто = авто-определённый IP:" "$DEFAULT_HOST") || true
  HOST_INPUT="${HOST_INPUT:-$DEFAULT_HOST}"
  if validate_ip "$HOST_INPUT" || validate_domain "$HOST_INPUT"; then
    break
  fi
  tui_info "Ошибка" "Некорректный домен/IP: $HOST_INPUT"
done
say "Домен/IP: $HOST_INPUT"

# ---- 1.2. Порт VPN ----
while true; do
  VPN_PORT=$(tui_input "Шаг 2/6 — Порт VPN" "Порт VPN-сервера (1-65535):" "443") || true
  VPN_PORT="${VPN_PORT:-443}"
  if validate_port "$VPN_PORT"; then
    break
  fi
  tui_info "Ошибка" "Некорректный порт: $VPN_PORT"
done
say "Порт VPN: $VPN_PORT"

# ---- 1.3. Логин админа ----
ADMIN_LOGIN=$(tui_input "Шаг 3/6 — Логин" "Логин администратора панели:" "admin") || true
ADMIN_LOGIN="${ADMIN_LOGIN:-admin}"
say "Логин: $ADMIN_LOGIN"

# ---- 1.4. Пароль админа ----
while true; do
  ADMIN_PASS=$(tui_password "Шаг 4/6 — Пароль" "Пароль администратора (минимум 1 символ):") || true
  ADMIN_PASS="${ADMIN_PASS:-admin}"
  if [[ ${#ADMIN_PASS} -ge 1 ]]; then
    PASS2=$(tui_password "Шаг 4/6 — Подтверждение" "Повторите пароль:") || true
    if [[ "$ADMIN_PASS" == "$PASS2" ]]; then
      break
    fi
    tui_info "Ошибка" "Пароли не совпадают."
  else
    tui_info "Ошибка" "Пароль слишком короткий."
  fi
done
say "Пароль задан"

# ---- 1.5. Добавить текущий сервер? ----
ADD_SERVER="no"
if tui_yesno "Шаг 5/6 — Сервер" "Добавить текущий сервер ($HOST_INPUT) в список серверов?\n\nЭто позволит выдавать клиентам доступ к этому VPN."; then
  ADD_SERVER="yes"
fi
say "Добавить сервер: $ADD_SERVER"

# ---- 1.6. Telegram-бот ----
TG_ENABLED="no"
TG_TOKEN=""
if tui_yesno "Шаг 6/6 — Telegram-бот" "Включить Telegram-бота?\n\nБот управляет пользователями через /token,\nвыдаёт ссылки и удаляет аккаунты."; then
  TG_ENABLED="yes"
  while true; do
    TG_TOKEN=$(tui_password "Telegram Bot Token" "Токен от @BotFather\n(формат: 123456:ABC-DEF...):") || true
    if [[ "$TG_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]]; then
      break
    fi
    tui_info "Ошибка" "Некорректный формат токена.\nПример: 1234567890:AAHfiqksKZ8WmR2zMnGOEjFyjPwKjOq7EXAMPLE"
  done
  say "Telegram-бот: включён"
else
  say "Telegram-бот: отключён"
fi

# ---- Дополнительно: скорость и фильтры ----
MAX_SPEED=$(tui_input "Дополнительно — Скорость" "Максимальная скорость пользователя (Мбит/с):" "100") || true
MAX_SPEED="${MAX_SPEED:-100}"

if tui_yesno "Дополнительно — Торренты" "Блокировать BitTorrent-трафик?\n\nРекомендуется: да (предотвращает abuse)."; then
  TORRENT_FILTER="false"
else
  TORRENT_FILTER="true"
fi
say "Фильтр торрентов: $([ "$TORRENT_FILTER" = "true" ] && echo "включён" || echo "отключён")"

# ---- Подтверждение ----
SUMMARY=$(cat <<EOF
Конфигурация FPTN:

  Домен/IP:           $HOST_INPUT
  Порт VPN:           $VPN_PORT
  Логин админа:       $ADMIN_LOGIN
  Пароль админа:      ********
  Добавить сервер:    $ADD_SERVER
  Telegram-бот:       $TG_ENABLED
  Лимит скорости:     ${MAX_SPEED} Мбит/с
  Фильтр торрентов:   $TORRENT_FILTER

Продолжить установку?
EOF
)
tui_info "Подтверждение" "$SUMMARY"
if ! tui_yesno "Подтверждение" "Применить эти настройки и начать установку?"; then
  warn "Установка отменена."
  exit 0
fi

# =============================================================
#  ШАГ 2: Системные зависимости
# =============================================================
hr
say "[1/5] Устанавливаю системные зависимости..."
bash "$SCRIPT_DIR/prereq-install.sh"

# =============================================================
#  ШАГ 3: Клонируем/обновляем репозиторий
# =============================================================
hr
say "[2/5] Клонирую/обновляю репозиторий..."
if [[ -d "$INSTALL_DIR/.git" ]]; then
  say "  Обновляю $INSTALL_DIR"
  (cd "$INSTALL_DIR" && git pull --quiet)
else
  say "  Клонирую $REPO → $INSTALL_DIR"
  git clone --depth=1 --quiet "$REPO" "$INSTALL_DIR"
fi

# =============================================================
#  ШАГ 4: VPN-сервер
# =============================================================
hr
say "[3/5] Настраиваю VPN-сервер..."

# .env
if [[ ! -f "$VPN_ENV" ]]; then
  cp "$INSTALL_DIR/fptn/docker-compose/.env.demo" "$VPN_ENV"
  say "  Создан $VPN_ENV"
fi

# Публичный IP
PUBLIC_IP="$HOST_INPUT"
if validate_ip "$PUBLIC_IP"; then
  sed -i "s|^SERVER_EXTERNAL_IPS=.*|SERVER_EXTERNAL_IPS=$PUBLIC_IP|" "$VPN_ENV"
  say "  SERVER_EXTERNAL_IPS=$PUBLIC_IP"
fi

# Порт VPN
sed -i "s|^FPTN_PORT=.*|FPTN_PORT=$VPN_PORT|" "$VPN_ENV"
say "  FPTN_PORT=$VPN_PORT"

# Фильтр торрентов
sed -i "s|^DISABLE_TORRENT_FILTER=.*|DISABLE_TORRENT_FILTER=$TORRENT_FILTER|" "$VPN_ENV"
say "  DISABLE_TORRENT_FILTER=$TORRENT_FILTER"

# SSL-сертификаты
mkdir -p "$VPN_DATA"
if [[ ! -f "$VPN_DATA/server.crt" || ! -f "$VPN_DATA/server.key" ]]; then
  say "  Генерирую SSL-сертификаты..."
  umask 077
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "$VPN_DATA/server.key" \
    -out "$VPN_DATA/server.crt" \
    -subj "/CN=$PUBLIC_IP" 2>/dev/null
  chmod 600 "$VPN_DATA/server.key"
  say "  Сертификаты созданы"
else
  say "  SSL-сертификаты уже существуют"
fi

# users.list
touch "$VPN_DATA/users.list"

# Запуск VPN
cd "$INSTALL_DIR/fptn/docker-compose"
docker compose pull
docker compose up -d --remove-orphans
say "  VPN-сервер запущен"

# =============================================================
#  ШАГ 5: Админ-панель
# =============================================================
hr
say "[4/5] Настраиваю админ-панель..."

# Создаём .env
{
  printf 'JWT_TTL_MINUTES=60\n'
  printf 'ADMIN_LOGIN=%s\n' "$ADMIN_LOGIN"
  printf 'ADMIN_PASSWORD=%s\n' "$ADMIN_PASS"
  printf 'CORS_ORIGINS=https://%s:2663\n' "$HOST_INPUT"
  printf 'ENABLE_BROTLI_COMPRESSION=true\n'
  printf 'FPTN_CONFIGS_FOLDER=%s\n' "$VPN_DATA"
  printf 'TELEGRAM_TOKEN=%s\n' "$TG_TOKEN"
  printf 'BOT_ENABLED=%s\n' "$TG_ENABLED"
  printf 'SERVICE_NAME=fptn\n'
  printf 'MAX_USER_SPEED_LIMIT=%s\n' "$MAX_SPEED"
  printf 'WELCOME_MESSAGE_EN=\n'
  printf 'WELCOME_MESSAGE_RU=\n'
} > "$ADMIN_ENV"
chmod 600 "$ADMIN_ENV"
say "  $ADMIN_ENV создан"

# Добавляем текущий сервер, если нужно
if [[ "$ADD_SERVER" == "yes" ]]; then
  say "  Добавляю текущий сервер в список..."
  mkdir -p "$VPN_DATA"
  # Инициализируем servers.json если нет
  if [[ ! -f "$VPN_DATA/servers.json" ]]; then
    echo '{"regular":[],"premium":[],"censored":[]}' > "$VPN_DATA/servers.json"
  fi
  # Добавляем сервер через Python (идемпотентно)
  python3 - <<'PYEOF' "$VPN_DATA" "$HOST_INPUT" "$VPN_PORT"
import json, sys
from pathlib import Path

data_dir = Path(sys.argv[1])
host = sys.argv[2]
port = int(sys.argv[3])

regular_file = data_dir / "servers.json"
premium_file = data_dir / "premium_servers.json"
censored_file = data_dir / "servers_censored_zone.json"

# Инициализация файлов
for f in [regular_file, premium_file, censored_file]:
    if not f.exists():
        f.write_text('{"regular":[],"premium":[],"censored":[]}')

def load(path):
    return json.loads(path.read_text())

def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2))

# Добавляем в regular
regular = load(regular_file)
entry = {"host": host, "port": port, "name": f"Server-{host}"}
if entry not in regular.get("regular", []):
    regular.setdefault("regular", []).append(entry)
    save(regular_file, regular)
PYEOF
  say "  Сервер обработан: $HOST_INPUT:$VPN_PORT"
fi

# Сборка и запуск панели
cd "$INSTALL_DIR/fptn-admin"
docker compose build
docker compose up -d --remove-orphans
say "  Админ-панель запущена"

# =============================================================
#  ШАГ 6: Telegram-бот (опционально)
# =============================================================
BOT_INSTALLED="нет"
if [[ "$TG_ENABLED" == "yes" ]]; then
  hr
  say "[5/5] Устанавливаю Telegram-бота..."
  # Используем новый стек fptn-admin-bot
  BOT_DIR="$INSTALL_DIR/fptn-admin-bot"
  if [[ ! -d "$BOT_DIR" ]]; then
    mkdir -p "$BOT_DIR"
    cat > "$BOT_DIR/docker-compose.yml" <<'EOF'
services:
  telegram-admin-bot:
    image: fptnvpn/fptn-admin-bot:latest
    restart: unless-stopped
    environment:
      - TELEGRAM_TOKEN=${TELEGRAM_TOKEN}
      - FPTN_CONFIGS_FOLDER=/etc/fptn
      - BOT_SETTINGS_FILE=/etc/fptn/bot_settings.json
      - WELCOME_MESSAGE_EN=${WELCOME_MESSAGE_EN:-}
      - WELCOME_MESSAGE_RU=${WELCOME_MESSAGE_RU:-}
      - MAX_USER_SPEED_LIMIT=${MAX_USER_SPEED_LIMIT:-100}
    volumes:
      - /etc/fptn:/etc/fptn:rw
    networks:
      - fptn-network

networks:
  fptn-network:
    external: true
EOF
  fi

  # Создаём .env для бота
  BOT_ENV="$BOT_DIR/.env"
  {
    printf 'TELEGRAM_TOKEN=%s\n' "$TG_TOKEN"
    printf 'FPTN_CONFIGS_FOLDER=%s\n' "$VPN_DATA"
    printf 'BOT_SETTINGS_FILE=%s/bot_settings.json\n' "$VPN_DATA"
    printf 'WELCOME_MESSAGE_EN=\n'
    printf 'WELCOME_MESSAGE_RU=\n'
    printf 'MAX_USER_SPEED_LIMIT=%s\n' "$MAX_SPEED"
  } > "$BOT_ENV"
  chmod 600 "$BOT_ENV"

  # Запуск
  cd "$BOT_DIR"
  docker compose up -d --build
  BOT_INSTALLED="да"
  say "  Telegram-бот запущен"
else
  say "[5/5] Telegram-бот пропущен"
fi

# =============================================================
#  ШАГ 7: Проверки
# =============================================================
hr
say "Проверяю сервисы..."

# Ждём backend
for _ in $(seq 1 30); do
  if curl -fsS http://localhost:8000/health >/dev/null 2>&1; then
    say "  Backend: healthy"
    break
  fi
  sleep 1
done

# Ждём frontend
for _ in $(seq 1 30); do
  if curl -fsSk https://localhost:2663/health >/dev/null 2>&1; then
    say "  Frontend: healthy"
    break
  fi
  sleep 1
done

# Проверка бота
if [[ "$BOT_INSTALLED" == "да" ]]; then
  if docker ps | grep -q "telegram-admin-bot"; then
    say "  Telegram-бот: запущен"
  else
    warn "  Telegram-бот: не запущен (проверьте логи)"
  fi
fi

# =============================================================
#  ИТОГОВАЯ СВОДКА
# =============================================================
hr
cat <<EOF

============================================================
  FPTN развёрнут!
============================================================

  VPN-сервер:
    Образ:      fptnvpn/fptn-vpn-server:0.4.4
    Порт:       $VPN_PORT/tcp
    SSL:        самоподписанный (CN=$PUBLIC_IP)
    Данные:     $VPN_DATA

  Админ-панель:
    URL:        https://$HOST_INPUT:2663
    Backend:    http://$HOST_INPUT:8000
    Логин:      $ADMIN_LOGIN
    Пароль:     $ADMIN_PASS

  Сервер:
    Добавлен:   $ADD_SERVER
    Хост:       $HOST_INPUT
    Порт:       $VPN_PORT

  Telegram-бот:
    Статус:     $TG_ENABLED
    Установлен: $BOT_INSTALLED

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

say "Готово! Сохраните пароль: $ADMIN_PASS"
