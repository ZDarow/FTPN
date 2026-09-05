#!/usr/bin/env bash
# =============================================================
#  FTPN — обновление Docker-образов и рестарт
# =============================================================
set -Eeuo pipefail
COMPOSE_DIR="/opt/fptn/compose"

hr() { printf -- '----------------------------------------\n'; }
say() { printf '[+] %s\n' "$*"; }
err() { printf '[!] %s\n' "$*" >&2; }

[[ $EUID -eq 0 ]] || { err "Нужен root: sudo fptn-update"; exit 1; }

hr
say "1/4 — Подтягиваю новые образы сервера"
( cd "$COMPOSE_DIR/server" && docker compose pull )

hr
say "2/4 — Подтягиваю/пересобираю админ-панель"
( cd "$COMPOSE_DIR/admin" && docker compose pull )

hr
say "3/4 — Пересобираю Telegram-бот (если менялся код)"
( cd "$COMPOSE_DIR/bot" && docker compose build --pull )

hr
say "4/4 — Перезапускаю стеки"
( cd "$COMPOSE_DIR/server" && docker compose up -d --remove-orphans )
( cd "$COMPOSE_DIR/admin"  && docker compose up -d --remove-orphans )
( cd "$COMPOSE_DIR/bot"    && docker compose up -d --remove-orphans )

hr
say "Готово. Проверить:  fptn-status"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
