# FPTN — Technical Documentation

**Version:** 0.4.4  
**Last updated:** 2026-09-05  
**Repository:** https://github.com/ZDarow/FTPN  

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture & Stack](#2-architecture--stack)
3. [Directory Structure](#3-directory-structure)
4. [Installation & Deployment](#4-installation--deployment)
5. [Configuration](#5-configuration)
6. [API Reference](#6-api-reference)
7. [Core Components](#7-core-components)
8. [Usage Examples](#8-usage-examples)
9. [Operations & Maintenance](#9-operations--maintenance)
10. [Troubleshooting & FAQ](#10-troubleshooting--faq)
11. [Security Considerations](#11-security-considerations)
12. [Development](#12-development)
13. [Changelog](#13-changelog)

---

## 1. Overview

**FPTN** is an open-source VPN solution designed for simplicity, performance, and extensibility. It provides:
- A high-performance C++20 VPN core with Reality protocol and Rolling Tunnel support.
- A web-based admin panel (FastAPI + React) for user and server management.
- Telegram bots for end-user access and administrative control.
- Automated deployment scripts for Ubuntu/Debian servers.

### Key Features
- Anti-probing protection and filter stack.
- JWT-based authentication with bcrypt password hashing.
- Brotli-compressed access tokens.
- Multi-server support with premium and censored-zone routing.
- Docker-based deployment with isolated services.

---

## 2. Architecture & Stack

### High-Level Architecture
```
+-------------------+     +-------------------+     +-------------------+
|   VPN Client      |<--->|  VPN Server       |<--->|  Docker Host      |
| (Reality/Rolling) |     |  (C++20 core)     |     |  (Ubuntu/Debian)  |
+-------------------+     +-------------------+     +-------------------+
                                |
                                v
                       +-------------------+
                       |  Admin Panel      |
                       |  FastAPI + React  |
                       +-------------------+
                                |
                                v
                       +-------------------+
                       |  Telegram Bots    |
                       |  User + Admin     |
                       +-------------------+
```

### Technology Stack

| Layer | Technology |
|-------|------------|
| **VPN Core** | C++20, Boost.Asio, OpenSSL, Reality protocol |
| **Backend** | Python 3.13, FastAPI 0.115+, Poetry, SQLAlchemy (async), JWT, bcrypt |
| **Frontend** | React 18.3, TypeScript 5.4, Vite 5.4, Tailwind CSS 3.4 |
| **Bots** | Python 3.13, python-telegram-bot 21.6, Brotli |
| **Deployment** | Docker, Docker Compose, Bash scripts |
| **CI/CD** | GitHub Actions (lint, test, build) |

---

## 3. Directory Structure

```
FTPN/
├── fptn/                          # C++20 VPN core
│   ├── common/                    # Shared utilities
│   ├── protocol-lib/              # Protocol implementation
│   ├── server/                    # VPN server daemon
│   ├── client/                    # VPN client library
│   └── passwd/                    # Password management
├── fptn-admin/                    # Admin panel
│   ├── backend/                   # FastAPI backend
│   │   ├── app/
│   │   │   ├── main.py            # Application entry point
│   │   │   ├── config.py          # Configuration management
│   │   │   ├── models/            # SQLAlchemy models
│   │   │   ├── routers/           # API routes
│   │   │   ├── services/          # Business logic
│   │   │   └── utils/             # Helpers
│   │   ├── tests/                 # Backend tests (pytest)
│   │   ├── pyproject.toml         # Poetry dependencies
│   │   └── Dockerfile             # Multi-stage build
│   └── frontend/                  # React frontend
│       ├── src/
│       │   ├── api/               # API client
│       │   ├── components/        # Reusable UI components
│       │   ├── pages/             # Page components
│       │   ├── context/           # React contexts
│       │   ├── lib/               # Utilities (fptnToken)
│       │   └── test/              # Test setup
│       ├── package.json
│       ├── vite.config.ts
│       ├── tailwind.config.js
│       └── Dockerfile             # Multi-stage build
├── deploy/                        # Deployment scripts
│   ├── install.sh                 # Main installer (TUI)
│   ├── install-admin.sh           # Admin panel installer
│   ├── install-bot.sh             # User bot installer
│   ├── configure.sh               # Reconfiguration script
│   ├── uninstall.sh               # Removal script
│   ├── prereq-install.sh          # Prerequisites installer
│   └── lib/                       # Shared libraries
│       ├── tui.sh                 # Text UI (whiptail/dialog/stdin)
│       └── install-manager.sh     # fptn-manager installer
├── docs/                          # Documentation
│   ├── DOCUMENTATION.md            # This file
│   ├── AUDIT.md                   # Security & code audit
│   ├── plan.md                    # Development plan
│   └── DEPENDENCIES-AUDIT.md      # Dependency audit
├── fptn-admin-bot/                 # Admin Telegram bot (local dev copy)
│   ├── src/
│   │   └── bot.py                 # Bot source code
│   ├── docker-compose.yml
│   └── Dockerfile
├── .github/                       # CI/CD workflows
├── README.md                      # Project README
├── AGENTS.md                      # Kilo agent instructions (if present)
└── docker-compose.yml              # Root compose (optional)
```

---

## 4. Installation & Deployment

### 4.1 Prerequisites
- **OS:** Ubuntu 20.04+ / Debian 11+
- **Access:** Root SSH access
- **Network:** Open ports 443 (VPN), 80/443 (admin panel if exposed)
- **Docker:** Installed via `prereq-install.sh` or manually

### 4.2 Automated Installation (Recommended)

```bash
# Step 1: Install prerequisites (Docker, Compose, UFW)
bash <(curl -fsSL https://raw.githubusercontent.com/ZDarow/FTPN/master/deploy/prereq-install.sh)

# Step 2: Install VPN server (interactive TUI)
bash <(curl -fsSL https://raw.githubusercontent.com/ZDarow/FTPN/master/deploy/install.sh)

# Step 3 (optional): Install admin panel
bash /opt/fptn/deploy/install-admin.sh

# Step 4 (optional): Install user Telegram bot
bash /opt/fptn/deploy/install-bot.sh
```

### 4.3 Manual Installation

#### VPN Server
```bash
git clone https://github.com/ZDarow/FTPN.git /opt/fptn
cd /opt/fptn/fptn/docker-compose
cp .env.example .env
# Edit .env with your settings
docker compose up -d --build
```

#### Admin Panel
```bash
cd /opt/fptn/fptn-admin
cp .env.example .env
# Edit .env: JWT_TTL_MINUTES, ADMIN_LOGIN, ADMIN_PASSWORD, etc.
docker compose up -d --build
```

#### Telegram Bots
```bash
# User bot
cd /opt/fptn/fptn/sysadmin-tools/telegram-bot
cp .env.demo .env
# Set TELEGRAM_API_TOKEN and other vars
docker compose up -d --build

# Admin bot (custom deployment)
cd /opt/fptn/fptn-admin-bot
cp .env.example .env
# Set TELEGRAM_API_TOKEN, ADMIN_IDS, etc.
docker compose up -d --build
```

### 4.4 Environment Variables

#### VPN Server (`.env`)
| Variable | Description | Default |
|----------|-------------|---------|
| `TZ` | Timezone | `UTC` |
| `FPTN_SERVER_PORT` | VPN port | `443` |
| `FPTN_SERVER_SNI` | SNI whitelist | IP address |
| `FPTN_DATA_FOLDER` | Data directory | `./fptn-server-data` |

#### Admin Panel (`.env`)
| Variable | Description | Default |
|----------|-------------|---------|
| `JWT_TTL_MINUTES` | Token lifetime | `60` |
| `ADMIN_LOGIN` | Admin username | `admin` |
| `ADMIN_PASSWORD` | Admin password | `admin12345` |
| `CORS_ORIGINS` | Allowed CORS origins | `*` |
| `FPTN_CONFIGS_FOLDER` | Path to VPN configs | `/opt/fptn/fptn/docker-compose/fptn-server-data` |
| `TELEGRAM_TOKEN` | Bot token (optional) | — |
| `BOT_ENABLED` | Enable bot integration | `false` |

#### Telegram Bots (`.env`)
| Variable | Description | Default |
|----------|-------------|---------|
| `TELEGRAM_API_TOKEN` | Bot token from @BotFather | — |
| `FPTN_WELCOME_MESSAGE_EN` | English welcome message | — |
| `FPTN_WELCOME_MESSAGE_RU` | Russian welcome message | — |
| `MAX_USER_SPEED_LIMIT` | Default speed limit (Mbps) | `20` |
| `SERVICE_NAME` | Service display name | `FPTN.ONLINE` |
| `FPTN_CONFIGS_FOLDER` | Path to server data | `/etc/fptn` |
| `ENABLE_BROTLI_COMPRESSION` | Enable Brotli tokens | `true` |
| `ADMIN_IDS` | Comma-separated Telegram IDs | `0` (open) |

---

## 5. Configuration

### 5.1 VPN Server Configuration
- **`servers.json`** — List of VPN servers (`id`, `name`, `host`, `port`, `sni`, `premium`).
- **`premium_servers.json`** — Premium-only server list.
- **`servers_censored_zone.json`** — Servers for censored regions.
- **`users.list`** — User database: `username hashed_password speed [premium_flag]`.
- **`admins.json`** — Admin credentials.
- **`bot_settings.json`** — Bot configuration.
- **`blacklist.txt`** — Domain blacklist for censorship (2150+ entries).

### 5.2 Admin Panel Configuration
- Accessible via `https://<host>:2663` (default self-signed HTTPS).
- Default credentials: `admin` / `admin12345`.
- JWT tokens stored in browser `localStorage` (consider httpOnly cookies for production).

### 5.3 Telegram Bot Configuration
- **User Bot:** Provides end-users with access tokens via `/token` command.
- **Admin Bot:** Provides administrative control with whitelisted Telegram IDs.

---

## 6. API Reference

### 6.1 Admin Panel Backend (FastAPI)

**Base URL:** `http://localhost:8000/api/v1`

#### Authentication
| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/auth/login` | Login, returns JWT |
| `POST` | `/auth/refresh` | Refresh JWT token |
| `POST` | `/auth/logout` | Logout |

#### Users
| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/users/` | List users |
| `GET` | `/users/{username}` | Get user details |
| `PATCH` | `/users/{username}` | Update user (speed, premium) |
| `POST` | `/users/` | Create user |
| `DELETE` | `/users/{username}` | Delete user |

#### Servers
| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/servers/` | List servers |
| `POST` | `/servers/` | Add server |
| `PATCH` | `/servers/{id}` | Update server |
| `DELETE` | `/servers/{id}` | Delete server |

#### Dashboard
| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/dashboard/highlights` | Statistics and highlights |

### 6.2 Telegram Bot Commands

#### User Bot
| Command | Description |
|---------|-------------|
| `/start` | Welcome message |
| `/token` | Generate access token |
| `/token_mac` | Legacy token command |

#### Admin Bot
| Command | Description |
|---------|-------------|
| `/start` | Show main menu |
| `/menu` | Show main menu |
| `/users` | List all users |
| `/user <username>` | User details |
| `/create <username> <speed> [premium]` | Create user |
| `/delete <username>` | Delete user |
| `/search <query>` | Search users |
| `/premium <username> <on\|off>` | Toggle premium |
| `/speed <username> <Mbps>` | Set speed limit |
| `/reset <username>` | Reset password |
| `/status` | Container status |
| `/logs <service>` | Service logs |
| `/restart <service>` | Restart service |
| `/backup` | Create backup |
| `/block <username>` | Block user |
| `/unblock <username>` | Unblock user |
| `/stats` | Security statistics |
| `/broadcast <message>` | Broadcast to all users |
| `/help` | Show help |

---

## 7. Core Components

### 7.1 VPN Server (`fptn/server`)
- **Protocol:** Reality, Rolling Tunnel.
- **Security:** Anti-probing, filter stack, SHA-256 password hashing (legacy).
- **Configuration:** JSON-based server and user lists.

### 7.2 Admin Backend (`fptn-admin/backend`)
- **Framework:** FastAPI with async SQLAlchemy.
- **Auth:** JWT with bcrypt password hashing.
- **Storage:** File-based (`users.list`, `servers.json`) for compatibility with C++ core.
- **Bot Integration:** Optional Telegram bot for notifications.

### 7.3 Admin Frontend (`fptn-admin/frontend`)
- **Framework:** React 18 with TypeScript.
- **Build:** Vite 5 with hot module replacement.
- **Styling:** Tailwind CSS 3.4 with custom theme tokens.
- **State:** React Context (`AuthContext`, `LayoutContext`).
- **Routing:** React Router with protected routes (`RequireAuth`).

### 7.4 Telegram Bots
- **User Bot (`sysadmin-tools/telegram-bot`):**
  - Generates Brotli-compressed access tokens.
  - Manages user registration and password resets.
  - Reads `users.list`, `servers.json`, `premium_servers.json`.

- **Admin Bot (`fptn-admin-bot/`):**
  - Full administrative control via Telegram.
  - Docker socket access for container management.
  - User management, monitoring, backup, security.

---

## 8. Usage Examples

### 8.1 Create a New User via Admin Bot
```
/create john_doe 50 premium
```
Output:
```
✅ Пользователь создан:
`john_doe`
Пароль: `aB3cD4eF`
Скорость: 50 Mbps
Премиум: Да
```

### 8.2 Generate Access Token (User Bot)
```
/token
```
Output:
```
🎉✨ Вы успешно зарегистрированы! 🎉

🌐 Клиент можно скачать с https://storage.googleapis.com/fptn.org/index.html

📋💾 Нажмите на токен ниже, чтобы скопировать и вставите его в приложение! ⬇️

`fptnb:eyJ...`
```

### 8.3 Monitor Server via Admin Bot
```
📊 Мониторинг
```
Output:
```
📊 Мониторинг сервера

⏱ Uptime: 14:30:22 up 10 days, ...

💻 Контейнеры:
docker-compose-fptn-server-1    Up 2 hours    0.0.0.0:443->443/tcp
fptn-admin-fptn-admin-backend-1 Up 54 minutes 0.0.0.0:8000->8000/tcp
...

💾 Диск:
Filesystem      Size  Used Avail Use% Mounted on
...
```

### 8.4 Block a User via Admin Bot
```
/block john_doe
```
Output:
```
🚫 `john_doe` заблокирован.
```

---

## 9. Operations & Maintenance

### 9.1 Backup
```bash
# Via admin bot
/backup

# Manual
tar -czf fptn-backup-$(date +%Y%m%d).tar.gz -C /opt/fptn/fptn/docker-compose fptn-server-data
```

### 9.2 Update
```bash
cd /opt/fptn
git pull
cd fptn/docker-compose && docker compose up -d --build
cd ../fptn-admin && docker compose up -d --build
```

### 9.3 Logs
```bash
# VPN server
docker logs docker-compose-fptn-server-1

# Admin backend
docker logs fptn-admin-fptn-admin-backend-1

# Admin frontend
docker logs fptn-admin-fptn-admin-frontend-1

# User bot
docker logs fptn-sysadmin-tools-telegram-bot-1

# Admin bot
docker logs fptn-admin-bot-telegram-admin-bot-1
```

### 9.4 Restart Services
```bash
docker restart <service_name>
```

---

## 10. Troubleshooting & FAQ

### Q: Bot shows "No such file or directory: 'docker'"
**A:** The bot container needs Docker CLI and socket mounted. Ensure `docker-compose.yml` includes:
```yaml
volumes:
  - /usr/bin/docker:/usr/bin/docker:ro
  - /var/run/docker.sock:/var/run/docker.sock
```

### Q: Frontend build fails with `npm audit` errors
**A:** The Dockerfile ignores high-severity audit warnings. For production, update dependencies:
```bash
cd fptn-admin/frontend
npm audit fix --force
```

### Q: Poetry lock fails with Python version mismatch
**A:** Ensure Python 3.13 is used. Generate lock file locally or in Docker:
```bash
docker run --rm -v $(pwd):/app -w /app python:3.13-slim bash -c "pip install poetry && poetry lock"
```

### Q: Admin bot shows 2150 blocked users
**A:** The bot was reading `blacklist.txt` (domain blacklist). Fixed by using `blocked_users.txt` for user blocking.

### Q: CORS errors in admin panel
**A:** Set `CORS_ORIGINS` in `.env` to your domain (not `*`).

### Q: JWT token not persisting
**A:** Browser `localStorage` is used by default. For better security, implement httpOnly Secure cookies.

---

## 11. Security Considerations

### Current Issues (from AUDIT.md)
| Priority | Issue | Status |
|----------|-------|--------|
| P0 | SHA-256 without salt for VPN passwords | Planned migration to Argon2id |
| P0 | CORS `*` in backend | Should restrict to specific domain |
| P0 | No rate-limit on `/auth/login` | Needs implementation |
| P0 | JWT in `localStorage` without `httpOnly` | Should use Secure cookies |
| P1 | `session.cpp` 1450 lines, cyclomatic 114 | Refactoring planned |
| P1 | `route_manager.cpp` 1533 lines, no tests | Needs unit tests |
| P2 | Frontend dependencies outdated (React 18, Vite 4) | Update planned |
| P2 | No security scanning in CI | Add Trivy/Grype |

### Best Practices
- Change default admin credentials immediately after installation.
- Use HTTPS with valid certificates in production.
- Restrict `ADMIN_IDS` in admin bot `.env`.
- Regularly update dependencies and scan for vulnerabilities.
- Enable firewall (`ufw`) and restrict SSH access.

---

## 12. Development

### Local Setup
```bash
# Clone repository
git clone https://github.com/ZDarow/FTPN.git
cd FTPN

# Backend
cd fptn-admin/backend
poetry install
poetry run uvicorn app.main:app --reload

# Frontend
cd fptn-admin/frontend
npm install
npm run dev

# Tests
cd fptn-admin/backend && pytest
cd fptn-admin/frontend && npx vitest run
```

### Code Style
- **Python:** Black, pylint, mypy strict mode.
- **TypeScript:** ESLint + Prettier (no trailing commas, no semicolons).
- **C++:** Follow existing conventions in `fptn/`.

### CI/CD
GitHub Actions run on push:
- Backend: `black --check`, `pylint`, `pytest`.
- Frontend: `npm run lint`, `tsc --noEmit`, `vitest run`, `npm run build`.

---

## 13. Changelog

### 0.4.4 (2026-09-05)
- Integrated `fptn-manager` as optional step.
- Updated deploy scripts (`install.sh`, `configure.sh`).
- Fixed admin bot Docker socket access.
- Added comprehensive admin bot with native menu.
- Fixed blacklist handling in admin bot.

### 0.4.3 (2026-09-04)
- Initial public release.
- VPN core with Reality protocol.
- Admin panel with user management.
- Telegram user bot.
- Docker-based deployment.

---

*Documentation generated automatically. For issues and contributions, visit https://github.com/ZDarow/FTPN.*
