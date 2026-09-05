#!/usr/bin/env bash
# =============================================================
#  FTPN — настройка Let's Encrypt через системный Nginx
#  reverse-proxy к админ-панели на 2663
#  Применимо ТОЛЬКО если указан реальный FQDN (а не IP)
# =============================================================
set -Eeuo pipefail
IFS=$'\n\t'

say()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
err()  { printf '[✗] %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }
hr()   { printf -- '----------------------------------------\n'; }

[[ $EUID -eq 0 ]] || die "Нужен root: sudo $0"

# Берём домен из конфига развёртывания
if [[ -f /opt/fptn/deploy-config.env ]]; then
  # shellcheck disable=SC1091
  . /opt/fptn/deploy-config.env
fi
DOMAIN="${SERVER_HOST:-}"
[[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && die "SERVER_HOST — это IP, нужен FQDN для Let's Encrypt"
[[ -n "$DOMAIN" && "$DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] \
  || die "В /opt/fptn/deploy-config.env нет валидного SERVER_HOST (FQDN)"

ADMIN_HTTPS_PORT="${ADMIN_FE_HTTPS:-2663}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@$DOMAIN}"

hr
say "Домен: $DOMAIN"
say "Email: $ADMIN_EMAIL (используется для уведомлений Let's Encrypt)"
hr

# ------------------------------------------------------------
# 1. Установка Nginx + Certbot
# ------------------------------------------------------------
say "Устанавливаю nginx + certbot"
if command -v apt >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends nginx certbot python3-certbot-nginx
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y nginx certbot python3-certbot-nginx
else
  die "Поддерживаются только apt/dnf"
fi
say "  nginx: $(nginx -v 2>&1 | head -1)"
say "  certbot: $(certbot --version 2>&1)"

# ------------------------------------------------------------
# 2. Конфиг reverse-proxy
# ------------------------------------------------------------
say "Создаю конфиг /etc/nginx/sites-available/fptn-admin"
cat > "/etc/nginx/sites-available/fptn-admin" <<NGINX
# Автогенерировано fptn-deploy $(date '+%Y-%m-%d %H:%M:%S')
# Reverse proxy для FPTN Admin Panel
# Внутри Docker уже есть свой nginx на 2663 — этот — снаружи, с настоящим SSL.

upstream fptn_admin_backend {
    server 127.0.0.1:$ADMIN_HTTPS_PORT;
    keepalive 32;
}

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    # Для certbot webroot
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Всё остальное → на HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    # SSL-сертификаты Let's Encrypt
    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # Современные настройки TLS
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # Заголовки безопасности
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Клиентский лимит (для админки достаточно)
    client_max_body_size 2M;

    # Проксирование на Docker-nginx
    location / {
        proxy_pass https://fptn_admin_backend;
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        proxy_set_header Upgrade           \$http_upgrade;
        proxy_set_header Connection        "upgrade";
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host  \$host;

        # SSL к бэкенду (там самоподписанный)
        proxy_ssl_verify off;
        proxy_ssl_server_name on;

        proxy_connect_timeout 10s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;
    }
}
NGINX

# Включаем сайт
ln -sf /etc/nginx/sites-available/fptn-admin /etc/nginx/sites-enabled/fptn-admin
# Снимаем дефолтный, если есть
rm -f /etc/nginx/sites-enabled/default
nginx -t
say "  Конфиг nginx валиден"

# ------------------------------------------------------------
# 3. Получение сертификата
# ------------------------------------------------------------
hr
say "Получаю сертификат Let's Encrypt для $DOMAIN"
# Сначала запускаем nginx на 80, чтобы certbot мог проверить домен
systemctl enable --now nginx

# Используем webroot — не прерываем работу других сервисов
mkdir -p /var/www/html
certbot certonly --webroot -w /var/www/html \
  --non-interactive --agree-tos -m "$ADMIN_EMAIL" \
  --no-eff-email \
  -d "$DOMAIN" \
  || die "Не удалось получить сертификат. Проверь DNS A-запись $DOMAIN → $(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null)"

say "  Сертификат получен: /etc/letsencrypt/live/$DOMAIN/"

# ------------------------------------------------------------
# 4. Применяем HTTPS-конфиг и перезапускаем
# ------------------------------------------------------------
hr
say "Применяю HTTPS-конфигурацию"
systemctl reload nginx
sleep 2
if ! curl -fsS -o /dev/null -w "%{http_code}\n" "https://$DOMAIN/health" --max-time 5 2>/dev/null \
   | grep -qE "^(200|301|302)$"; then
  warn "Проверь вручную:  curl -I https://$DOMAIN"
else
  say "  ✓ https://$DOMAIN отвечает"
fi

# ------------------------------------------------------------
# 5. Автопродление
# ------------------------------------------------------------
hr
say "Настраиваю автопродление сертификата (certbot timer уже активен в systemd)"
systemctl enable --now certbot.timer 2>/dev/null || true
systemctl list-timers certbot.timer 2>/dev/null | grep certbot || true

# Certbot сам подвешивает hook на deploy-hook — добавим reload nginx после обновления
HOOK="/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh"
cat > "$HOOK" <<'HOOKEOF'
#!/bin/sh
systemctl reload nginx
HOOKEOF
chmod +x "$HOOK"
say "  Hook /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh создан"

hr
cat <<INFO

${C_GRN:-}[+] Let's Encrypt настроен${C_GRN:-}

  Админ-панель теперь доступна по настоящему HTTPS:
    https://$DOMAIN

  Самоподписанный сертификат Docker-контейнера (порт $ADMIN_HTTPS_PORT)
  больше НЕ используется снаружи — он остался для проксирования.

  Проверка:
    curl -I https://$DOMAIN

  Автопродление: certbot.timer (каждые 12 часов проверка, обновление за 30 дней до истечения)

INFO
