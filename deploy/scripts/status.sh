#!/usr/bin/env bash
# =============================================================
#  FTPN — статус всех компонентов одной командой
# =============================================================
set -Eeuo pipefail
DATA_DIR="/opt/fptn/data/fptn-server"

hr() { printf -- '----------------------------------------\n'; }

hr
printf "FPTN • %s • uptime %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$(uptime -p)"

hr
echo "Контейнеры:"
docker ps --filter "name=fptn" --format "  {{.Names}}\t{{.Status}}\t{{.Ports}}" || true

hr
echo "Сетевые подключения (LISTEN):"
ss -tulpn 2>/dev/null | grep -E ":(443|8000|2663|8080|8443) " | sed 's/^/  /' || true

hr
echo "Внешний IP: $(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || echo '?')"

hr
echo "Свободное место:"
df -h /opt /var 2>/dev/null | tail -n +2 | sed 's/^/  /'

hr
echo "Пользователи VPN:"
if [[ -f "$DATA_DIR/users.list" ]]; then
  TOTAL=$(wc -l < "$DATA_DIR/users.list" | tr -d ' ')
  BLOCKED=$(awk '$3==0' "$DATA_DIR/users.list" | wc -l | tr -d ' ')
  PREMIUM=$(awk '$4==1' "$DATA_DIR/users.list" | wc -l | tr -d ' ')
  printf "  всего: %s, заблокировано: %s, премиум: %s\n" "$TOTAL" "$BLOCKED" "$PREMIUM"
else
  echo "  users.list не найден"
fi

hr
echo "Health-check backend:"
if curl -fsS --max-time 3 http://127.0.0.1:8000/health 2>/dev/null; then
  echo "  ✓ OK"
else
  echo "  ✗ FAIL"
fi
