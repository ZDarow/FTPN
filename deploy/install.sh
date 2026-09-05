#!/usr/bin/env bash
# =============================================================
#  FPTN VPN — минимальный инсталлятор (только VPN-сервер)
# -------------------------------------------------------------
#  Использование:
#    curl -fsSL https://raw.githubusercontent.com/ZDarow/FTPN/master/deploy/install.sh | sudo bash
#
#  Что делает:
#    1. Ставит Docker (если нет)
#    2. Копирует docker-compose/.env.demo → .env
#    3. Подставляет SERVER_EXTERNAL_IPS (авто-детект)
#    4. Запускает VPN-сервер
#
#  Для админ-панели и Telegram-бота используйте:
#    - deploy/install-admin.sh
#    - deploy/install-bot.sh
# =============================================================
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "[!] Запустите от root: sudo bash $0"
  exit 1
fi

# ---- Настройки ----
REPO="https://github.com/ZDarow/FTPN.git"
INSTALL_DIR="/opt/fptn"
FPTN_VERSION="0.4.4"

say()  { echo -e "\033[0;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
err()  { echo -e "\033[0;31m[✗]\033[0m $*" >&2; }

# ---- 1. Проверяем/ставим Docker ----
if ! command -v docker >/dev/null 2>&1; then
  say "Docker не найден — устанавливаю"
  curl -fsSL https://get.docker.com | sh
fi

if ! docker compose version >/dev/null 2>&1; then
  err "Docker Compose v2 не найден. Поставьте docker-compose-plugin."
  exit 1
fi

# ---- 2. Клонируем/обновляем репозиторий ----
if [[ -d "$INSTALL_DIR/.git" ]]; then
  say "Обновляю $INSTALL_DIR"
  (cd "$INSTALL_DIR" && git pull --quiet)
else
  say "Клонирую $REPO → $INSTALL_DIR"
  git clone --depth=1 --quiet "$REPO" "$INSTALL_DIR"
fi

# ---- 3. Настраиваем .env ----
ENV_FILE="$INSTALL_DIR/fptn/docker-compose/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  cp "$INSTALL_DIR/fptn/docker-compose/.env.demo" "$ENV_FILE"
  say "Создан $ENV_FILE"
fi

# Интерактивная настройка через TUI (whiptail/dialog/read fallback)
if [[ -t 0 ]]; then
  say "Запускаю TUI-настройку (Ctrl+C для пропуска)"
  bash "$INSTALL_DIR/deploy/configure.sh" "$ENV_FILE" || warn "Настройка пропущена"
else
  # Неинтерактивная сессия — авто-определение IP
  PUBLIC_IP=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
  if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    sed -i "s|^SERVER_EXTERNAL_IPS=.*|SERVER_EXTERNAL_IPS=$PUBLIC_IP|" "$ENV_FILE"
    say "SERVER_EXTERNAL_IPS=$PUBLIC_IP"
  fi
fi

# ---- 4. Запускаем ----
say "Запускаю FPTN VPN (v$FPTN_VERSION)"
cd "$INSTALL_DIR/fptn/docker-compose"
docker compose pull
docker compose up -d --remove-orphans

# ---- 5. Готово ----
cat <<EOF

============================================================
  FPTN VPN запущен!
============================================================

  Статус:    docker ps | grep fptn
  Логи:      cd $INSTALL_DIR/fptn/docker-compose && docker compose logs -f
  Остановка: cd $INSTALL_DIR/fptn/docker-compose && docker compose down

  Следующие шаги:
    - Настройте пользователей: /opt/fptn/data/fptn-server/users.list
    - Сгенерируйте токен:      fptn-passwd
    - Скачайте клиент:         https://storage.googleapis.com/fptn.org/

  Опционально:
    - Админ-панель: bash $INSTALL_DIR/deploy/install-admin.sh
    - Telegram-бот: bash $INSTALL_DIR/deploy/install-bot.sh

============================================================
EOF
