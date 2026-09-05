#!/usr/bin/env bash
# =============================================================
#  FPTN — полное удаление
# =============================================================
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "[!] Запустите от root: sudo bash $0"
  exit 1
fi

read -rp "Удалить ВСЁ (VPN + админка + бот + /opt/fptn + сеть)? (y/n): " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Отменено"; exit 0; }

# Остановить и удалить контейнеры
cd /opt/fptn/fptn/docker-compose 2>/dev/null && docker compose down 2>/dev/null || true
cd /opt/fptn/fptn-admin 2>/dev/null && docker compose down 2>/dev/null || true
cd /opt/fptn/fptn/sysadmin-tools/telegram-bot 2>/dev/null && docker compose down 2>/dev/null || true

# Удалить сеть
docker network rm fptn-network 2>/dev/null || true

# Удалить данные
rm -rf /opt/fptn

echo "[+] FPTN полностью удалён"
