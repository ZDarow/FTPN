#!/usr/bin/env bash
# =============================================================
#  fptn-manager — установка CLI-менеджера от FarazFe
#  ------------------------------------------------------------
#  Скачивает upstream-скрипт:
#    https://raw.githubusercontent.com/FarazFe/fptn-manager/main/fptn-manager.sh
#  и кладёт его в /usr/local/bin/fptn-manager.
#
#  Возможности менеджера:
#    - Создание VPN-пользователей
#    - Генерация токенов (fptn:...)
#    - Сброс паролей
#    - Просмотр логов и статуса
#    - Обновление Docker-образа
#
#  Использование:
#    sudo bash deploy/lib/install-manager.sh
#
#  После установки:
#    sudo fptn-manager
# =============================================================
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "[!] Запустите от root: sudo bash $0" >&2
  exit 1
fi

say()  { echo -e "\033[0;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
err()  { echo -e "\033[0;31m[✗]\033[0m $*" >&2; }

MANAGER_URL="https://raw.githubusercontent.com/FarazFe/fptn-manager/main/fptn-manager.sh"
DEST="/usr/local/bin/fptn-manager"
TMP="$(mktemp /tmp/fptn-manager.XXXXXX.sh)"
trap 'rm -f "$TMP"' EXIT

# ---- Уже установлен? ----
if [[ -x "$DEST" ]]; then
  say "fptn-manager уже установлен: $DEST"
  echo "    Версия: $($DEST --version 2>/dev/null || echo 'неизвестно')"
  echo "    Запуск:  sudo fptn-manager"
  exit 0
fi

# ---- Зависимости ----
if ! command -v curl >/dev/null 2>&1; then
  warn "curl не найден — устанавливаю"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y curl
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl
  else
    err "Не удалось установить curl. Поставьте вручную."
    exit 1
  fi
fi

# ---- Скачиваем ----
say "Скачиваю fptn-manager с $MANAGER_URL"
if ! curl -fsSL --max-time 60 "$MANAGER_URL" -o "$TMP"; then
  err "Не удалось скачать fptn-manager"
  exit 1
fi

# ---- Проверка ----
if ! head -1 "$TMP" | grep -q bash; then
  err "Скачанный файл не похож на bash-скрипт"
  exit 1
fi
if ! bash -n "$TMP"; then
  err "Скачанный файл содержит синтаксические ошибки"
  exit 1
fi

# ---- Устанавливаем ----
install -m 0755 "$TMP" "$DEST"
say "Установлен: $DEST"

# ---- Конфиг-папка (создаётся автоматически при первом запуске) ----
mkdir -p /etc/fptn

cat <<EOF

============================================================
  fptn-manager установлен!
============================================================

  Запуск:    sudo fptn-manager
  Удаление:  sudo rm $DEST

  Возможности:
    - Создание VPN-пользователей
    - Генерация токенов (fptn:...) для клиентов
    - Сброс паролей
    - Просмотр логов и статуса
    - Обновление Docker-образа

  Источник: github.com/FarazFe/fptn-manager (MIT)

============================================================
EOF
