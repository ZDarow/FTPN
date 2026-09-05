#!/usr/bin/env bash
# =============================================================
#  FTPN — единый просмотр логов всех контейнеров
# =============================================================
set -Eeuo pipefail
SERVICE="${1:-all}"
LINES="${2:-100}"

if [[ "$SERVICE" == "all" ]]; then
  docker ps --filter "name=fptn" --format "{{.Names}}" \
    | xargs -I{} sh -c 'echo "==== {} ===="; docker logs --tail '"$LINES"' {} 2>&1 | tail -n '"$LINES"''
else
  case "$SERVICE" in
    server|backend|frontend|bot)
      docker ps --filter "name=fptn-$SERVICE" --format "{{.Names}}" | head -1 \
        | xargs -r docker logs -f --tail "$LINES"
      ;;
    *)
      echo "Использование: fptn-logs [server|backend|frontend|bot|all] [lines]" >&2
      exit 1
      ;;
  esac
fi
