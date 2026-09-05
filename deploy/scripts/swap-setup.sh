#!/usr/bin/env bash
# =============================================================
#  FTPN — создание swap-файла для VPS с малым RAM (1 ГБ)
#  Рекомендуется 2 ГБ swap, чтобы Docker не падал под OOM
# =============================================================
set -Eeuo pipefail
SWAP_SIZE_MB="${1:-2048}"
SWAP_FILE="/swapfile"

[[ $EUID -eq 0 ]] || { echo "Нужен root: sudo $0 [size_mb]" >&2; exit 1; }

# Проверяем, не создан ли уже
if swapon --show | grep -q "$SWAP_FILE"; then
  echo "[+] Swap уже активен: $(swapon --show | grep "$SWAP_FILE")"
  exit 0
fi

echo "[+] Создаю swap-файл $SWAP_FILE размером ${SWAP_SIZE_MB} МБ"
fallocate -l "${SWAP_SIZE_MB}M" "$SWAP_FILE" 2>/dev/null \
  || dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB" status=none

chmod 600 "$SWAP_FILE"
mkswap "$SWAP_FILE" >/dev/null
swapon "$SWAP_FILE"

# Автомонтирование при перезагрузке
if ! grep -q "$SWAP_FILE" /etc/fstab; then
  echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
  echo "[+] Добавлено в /etc/fstab"
fi

# Настройка swappiness (низкое значение — реже использовать swap)
SYSCTL_FILE="/etc/sysctl.d/99-fptn-swap.conf"
cat > "$SYSCTL_FILE" <<'EOF'
# FPTN swap tuning
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
sysctl -p "$SYSCTL_FILE" >/dev/null

echo "[+] Готово. Состояние памяти:"
free -h
