#!/usr/bin/env bash
# =============================================================
#  FPTN — установка системных зависимостей
# -------------------------------------------------------------
#  Однострочный запуск (с чистого Ubuntu/Debian):
#
#    bash <(curl -fsSL https://raw.githubusercontent.com/ZDarow/FTPN/master/deploy/prereq-install.sh)
#
#  Или локально:
#
#    sudo bash deploy/prereq-install.sh
#
#  Что ставит:
#    - Базовые утилиты: curl, wget, git, ca-certificates, gnupg
#    - Docker Engine + Docker Compose v2 (для deploy/ и deploy/family/)
#    - Nginx, certbot (Let's Encrypt) — для HTTPS админки
#    - UFW, chrony, htop, jq, dnsutils
#    - Опционально: build-essential, cmake, conan (для C++ сборки)
#
#  Идемпотентно: повторный запуск безопасен, переустанавливает
#  только недостающее. Проверки уже установленных пакетов.
#
#  Поддерживает: Ubuntu 22.04+, Debian 12+
# =============================================================
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "[!] Требуются права root. Перезапустите: sudo bash $0"
  exit 1
fi

# ---- Цвета и лог ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
say()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
hr()   { echo -e "${BLUE}------------------------------------------------------------${NC}"; }

hr
say "FPTN prereq installer (Ubuntu/Debian)"
hr

# ---- Определение ОС ----
. /etc/os-release
say "ОС: ${PRETTY_NAME}"

if [[ "${ID}" != "ubuntu" && "${ID}" != "debian" ]]; then
  err "Поддерживается только Ubuntu/Debian. Текущая ОС: ${ID}"
  exit 1
fi

# ---- Аргументы ----
INSTALL_CPP_BUILD=false
for arg in "$@"; do
  case "${arg}" in
    --with-cpp)    INSTALL_CPP_BUILD=true ;;
    --without-cpp) INSTALL_CPP_BUILD=false ;;
    -h|--help)
      echo "Использование: $0 [--with-cpp] [--without-cpp]"
      echo "  --with-cpp    дополнительно ставит build-essential, cmake, conan (для сборки C++ из исходников)"
      echo "  --without-cpp (по умолчанию) ставит только рантайм-зависимости"
      exit 0
      ;;
  esac
done

# ---- 1. Базовые пакеты ----
hr
say "[1/5] Базовые утилиты: curl, wget, git, jq, htop, ufw, …"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl wget git gnupg lsb-release \
  apt-transport-https software-properties-common \
  net-tools iproute2 iputils-ping dnsutils \
  htop tmux mc jq tree ripgrep \
  ufw chrony unzip xz-utils \
  bash-completion sudo

# ---- 2. Docker Engine + Compose v2 ----
hr
say "[2/5] Docker Engine + Docker Compose v2"
if command -v docker >/dev/null 2>&1; then
  say "  Docker уже установлен: $(docker --version)"
else
  say "  Устанавливаю Docker из официального репозитория…"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  say "  Docker установлен: $(docker --version)"
fi

# Compose v2 — subcommand `docker compose`
if ! docker compose version >/dev/null 2>&1; then
  err "Docker Compose v2 не найден. Переустанови docker-compose-plugin."
  exit 1
fi
say "  Docker Compose: $(docker compose version)"

# Запуск Docker daemon
if ! systemctl is-active --quiet docker; then
  systemctl enable --now docker
  say "  Docker daemon запущен"
fi

# ---- 3. Nginx + certbot (Let's Encrypt) ----
hr
say "[3/5] Nginx + certbot (Let's Encrypt) — для HTTPS админки"
apt-get install -y --no-install-recommends nginx certbot python3-certbot-nginx
systemctl enable --now nginx
say "  Nginx: $(nginx -v 2>&1 | head -1)"
say "  Certbot: $(certbot --version 2>&1 | head -1)"

# ---- 4. UFW (файрвол) ----
hr
say "[4/5] UFW — базовая настройка файрвола"
if ! ufw status | grep -q "Status: active"; then
  ufw --force default deny incoming
  ufw --force default allow outgoing
  ufw allow 22/tcp comment "SSH"
  ufw allow 80/tcp comment "HTTP (LE challenge)"
  ufw allow 443/tcp comment "VPN tunnel / HTTPS"
  # Порты админки: 2663 (HTTPS), 8080 (HTTP→HTTPS redirect)
  ufw allow 2663/tcp comment "FPTN admin HTTPS"
  ufw allow 8080/tcp comment "FPTN admin HTTP"
  ufw --force enable
  say "  UFW активирован: разрешены 22, 80, 443, 2663, 8080"
else
  say "  UFW уже активен"
fi

# ---- 5. (Опционально) C++ build toolchain ----
hr
if [[ "${INSTALL_CPP_BUILD}" == "true" ]]; then
  say "[5/5] C++ build toolchain (--with-cpp): gcc, cmake, conan"
  apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build pkg-config \
    python3 python3-pip python3-venv \
    libssl-dev zlib1g-dev libbz2-dev liblz4-dev \
    libsodium-dev
  # Conan 2.x
  if ! command -v conan >/dev/null 2>&1; then
    pip3 install --break-system-packages --no-cache-dir conan==2.32.0
    say "  Conan установлен: $(conan --version)"
  else
    say "  Conan уже установлен: $(conan --version)"
  fi
else
  say "[5/5] C++ toolchain пропущен (используй --with-cpp для сборки из исходников)"
fi

# ---- 6. Проверки ----
hr
say "[✓] Проверка установленного ПО:"
printf "  %-25s %s\n" "OS:"           "${PRETTY_NAME}"
printf "  %-25s %s\n" "Kernel:"       "$(uname -r)"
printf "  %-25s %s\n" "Docker:"       "$(docker --version 2>/dev/null || echo '—')"
printf "  %-25s %s\n" "Docker Compose:" "$(docker compose version --short 2>/dev/null || echo '—')"
printf "  %-25s %s\n" "Nginx:"        "$(nginx -v 2>&1 | head -1)"
printf "  %-25s %s\n" "Certbot:"      "$(certbot --version 2>&1 | head -1)"
printf "  %-25s %s\n" "Git:"          "$(git --version)"
printf "  %-25s %s\n" "Curl:"         "$(curl --version | head -1)"
printf "  %-25s %s\n" "UFW status:"   "$(ufw status 2>/dev/null | head -1 | xargs)"
if [[ "${INSTALL_CPP_BUILD}" == "true" ]]; then
  printf "  %-25s %s\n" "GCC:"        "$(gcc --version | head -1)"
  printf "  %-25s %s\n" "CMake:"      "$(cmake --version | head -1)"
  printf "  %-25s %s\n" "Conan:"      "$(conan --version 2>/dev/null || echo '—')"
fi
hr

say "Готово! Теперь клонируй FPTN и запускай deploy:"
echo
cat <<'EOF'
  cd /tmp
  git clone https://github.com/ZDarow/FTPN.git
  cd FTPN
  sudo bash deploy/deploy.sh          # полный стек (Docker)
  # или
  sudo bash deploy/family/deploy.sh   # облегчённый (systemd)
EOF
hr
