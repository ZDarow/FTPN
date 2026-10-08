"""FPTN Admin Bot configuration from environment variables."""

import os
from pathlib import Path

TELEGRAM_API_TOKEN = os.getenv("TELEGRAM_API_TOKEN", "")
FPTN_WELCOME_MESSAGE_EN = os.getenv("FPTN_WELCOME_MESSAGE_EN", "")
FPTN_WELCOME_MESSAGE_RU = os.getenv("FPTN_WELCOME_MESSAGE_RU", "")
MAX_USER_SPEED_LIMIT = int(os.getenv("MAX_USER_SPEED_LIMIT", "100"))
SERVICE_NAME = os.getenv("SERVICE_NAME", "FPTN")
USERS_FILE = Path(os.getenv("USERS_FILE", "/etc/fptn/users.list"))
SERVERS_LIST_FILE = Path(os.getenv("SERVERS_LIST_FILE", "/etc/fptn/servers.json"))
PREMIUM_SERVERS_FILE = Path(
    os.getenv("PREMIUM_SERVERS_FILE", "/etc/fptn/premium_servers.json")
)
SERVERS_CENSORED_LIST_FILE = Path(
    os.getenv("SERVERS_CENSORED_LIST_FILE", "/etc/fptn/servers_censored_zone.json")
)
BLACKLIST_FILE = Path(os.getenv("BLACKLIST_FILE", "/etc/fptn/blocked_users.txt"))
BACKUP_DIR = Path(os.getenv("BACKUP_DIR", "/opt/fptn/backups"))
ADMIN_IDS = {
    int(x) for x in os.getenv("ADMIN_IDS", "").split(",") if x.strip().isdigit()
}
ENABLE_BROTLI_COMPRESSION = (
    os.getenv("ENABLE_BROTLI_COMPRESSION", "false").lower() == "true"
)
