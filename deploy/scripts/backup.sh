#!/usr/bin/env bash
# =============================================================
#  FTPN — бэкап users.list, admins.json, servers.json
# =============================================================
set -Eeuo pipefail
BACKUP_DIR="/var/backups/fptn"
DATA_DIR="/opt/fptn/data/fptn-server"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

[[ $EUID -eq 0 ]] || { echo "Нужен root: sudo fptn-backup" >&2; exit 1; }
mkdir -p "$BACKUP_DIR"

STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="$BACKUP_DIR/fptn-config-$STAMP.tar.gz"

if [[ ! -d "$DATA_DIR" ]]; then
  echo "Каталог $DATA_DIR не найден" >&2
  exit 1
fi

tar -czf "$ARCHIVE" \
  -C "$(dirname "$DATA_DIR")" \
  "$(basename "$DATA_DIR")" \
  2>/dev/null

# Подчищаем бэкапы старше RETENTION_DAYS
find "$BACKUP_DIR" -name "fptn-config-*.tar.gz" -mtime "+$RETENTION_DAYS" -delete

# Ротация: последние 7 — копируем ещё и сюда
cp -a "$ARCHIVE" "$BACKUP_DIR/latest.tar.gz" 2>/dev/null || true

echo "[+] Бэкап создан: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
echo "    Всего бэкапов: $(ls -1 "$BACKUP_DIR"/fptn-config-*.tar.gz 2>/dev/null | wc -l)"
