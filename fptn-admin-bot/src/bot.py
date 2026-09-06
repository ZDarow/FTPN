#!/usr/bin/env python3
"""
FPTN Admin Bot — максимальное меню + серверная часть
=====================================================
Команды:
  /start          — главное меню
  /users          — список пользователей
  /create         — создать пользователя
  /token          — сгенерировать клиентский токен
  /server         — ресурсы сервера (CPU/RAM/Disk)
  /status         — статус контейнеров
  /logs           — логи сервиса
  /restart        — перезапуск сервиса
  /backup         — бэкапы: создать / список / восстановить
  /batch          — пакетные операции
  /block          — блокировка пользователя
  /stats          — статистика безопасности
  /broadcast      — рассылка
  /help           — справка
"""

import json
import os
import sys
import random
import string
import hashlib
import threading
import subprocess
import re
from pathlib import Path
from datetime import datetime

from loguru import logger
from telegram import Update, ReplyKeyboardMarkup, KeyboardButton, InlineKeyboardMarkup, InlineKeyboardButton
from telegram.constants import ParseMode
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    filters,
    CallbackQueryHandler,
    CallbackContext,
)

# ========== CONFIG ==========
TELEGRAM_API_TOKEN = os.getenv("TELEGRAM_API_TOKEN")
FPTN_WELCOME_MESSAGE_EN = os.getenv("FPTN_WELCOME_MESSAGE_EN", "")
FPTN_WELCOME_MESSAGE_RU = os.getenv("FPTN_WELCOME_MESSAGE_RU", "")
MAX_USER_SPEED_LIMIT = int(os.getenv("MAX_USER_SPEED_LIMIT", "100"))
SERVICE_NAME = os.getenv("SERVICE_NAME", "FPTN")
USERS_FILE = Path(os.getenv("USERS_FILE", "/etc/fptn/users.list"))
SERVERS_LIST_FILE = Path(os.getenv("SERVERS_LIST_FILE", "/etc/fptn/servers.json"))
PREMIUM_SERVERS_FILE = Path(os.getenv("PREMIUM_SERVERS_FILE", "/etc/fptn/premium_servers.json"))
SERVERS_CENSORED_LIST_FILE = Path(os.getenv("SERVERS_CENSORED_LIST_FILE", "/etc/fptn/servers_censored_zone.json"))
BLACKLIST_FILE = Path(os.getenv("BLACKLIST_FILE", "/etc/fptn/blocked_users.txt"))
BACKUP_DIR = Path(os.getenv("BACKUP_DIR", "/opt/fptn/backups"))
ADMIN_IDS = {int(x) for x in os.getenv("ADMIN_IDS", "").split(",") if x.strip().isdigit()}
ENABLE_BROTLI_COMPRESSION = os.getenv("ENABLE_BROTLI_COMPRESSION", "false").lower() == "true"

# ========== LOAD DATA ==========
def _load_json(path: Path, default=[]):
    if path.exists():
        try:
            with open(path, "r") as fp:
                return json.load(fp)
        except (json.JSONDecodeError, OSError):
            pass
    return default

PREMIUM_SERVERS = _load_json(PREMIUM_SERVERS_FILE)
SERVERS_LIST = _load_json(SERVERS_LIST_FILE)
SERVERS_CENSORED_LIST = _load_json(SERVERS_CENSORED_LIST_FILE)

if os.path.exists(BLACKLIST_FILE):
    with open(BLACKLIST_FILE, "r") as fp:
        BLACKLIST = [line.strip() for line in fp if line.strip()]
else:
    BLACKLIST = []


# ========== HELPERS ==========
def _msg(update: Update):
    """Вернуть Message из callback-query или обычного сообщения."""
    if update.callback_query and update.callback_query.message:
        return update.callback_query.message
    return update.message


def init_logger():
    logger.remove()
    log_file = Path(os.getenv("LOG_FILE", "/var/log/fptn_admin_bot.log"))
    log_file.parent.mkdir(parents=True, exist_ok=True)
    logger.add(str(log_file), level="INFO", format="{time} - {level} - {message}", rotation="1 MB")
    logger.add(sys.stdout, level="INFO", format="{time} - {level} - {message}")


def is_admin(user_id: int) -> bool:
    return user_id in ADMIN_IDS or len(ADMIN_IDS) == 0


def escape_markdown(text: str) -> str:
    return text.replace("_", "\\_").replace("*", "\\*").replace("`", "\\`").replace("[", "\\[")


# ========== KEYBOARDS ==========
def get_main_keyboard() -> ReplyKeyboardMarkup:
    return ReplyKeyboardMarkup(
        [
            [KeyboardButton("👥 Пользователи"), KeyboardButton("📊 Сервер")],
            [KeyboardButton("💾 Бэкапы"), KeyboardButton("🔑 Токены")],
            [KeyboardButton("⚙️ Настройки"), KeyboardButton("ℹ️ Помощь")],
        ],
        resize_keyboard=True,
    )


def get_users_inline_keyboard() -> InlineKeyboardMarkup:
    users = UserManager(USERS_FILE).load_users()
    buttons = []
    for username in users.keys():
        buttons.append([InlineKeyboardButton(f"👤 {username}", callback_data=f"user:{username}")])
    buttons.append([InlineKeyboardButton("➕ Создать пользователя", callback_data="action:create")])
    buttons.append([InlineKeyboardButton("⬅️ Назад", callback_data="menu:main")])
    return InlineKeyboardMarkup(buttons)


def get_user_actions_keyboard(username: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🔄 Сброс пароля", callback_data=f"reset:{username}")],
        [InlineKeyboardButton("⭐ Премиум", callback_data=f"premium:{username}")],
        [InlineKeyboardButton("🚀 Скорость", callback_data=f"speed:{username}")],
        [InlineKeyboardButton("🔑 Токен", callback_data=f"token:{username}")],
        [InlineKeyboardButton("🗑 Удалить", callback_data=f"delete:{username}")],
        [InlineKeyboardButton("⬅️ Назад", callback_data="menu:users")],
    ])


def get_services_keyboard() -> InlineKeyboardMarkup:
    services = [
        "docker-compose-fptn-server-1",
        "fptn-admin-fptn-admin-backend-1",
        "fptn-admin-fptn-admin-frontend-1",
        "fptn-admin-bot-telegram-admin-bot-1",
    ]
    buttons = []
    for service in services:
        buttons.append([
            InlineKeyboardButton(f"📋 {service}", callback_data=f"logs:{service}"),
            InlineKeyboardButton(f"🔄 {service}", callback_data=f"restart:{service}"),
        ])
    buttons.append([InlineKeyboardButton("⬅️ Назад", callback_data="menu:server")])
    return InlineKeyboardMarkup(buttons)


def get_server_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🔄 Обновить", callback_data="refresh:status")],
        [InlineKeyboardButton("📋 Логи", callback_data="menu:logs")],
        [InlineKeyboardButton("⬅️ Назад", callback_data="menu:main")],
    ])


def get_backup_keyboard() -> InlineKeyboardMarkup:
    backups = sorted(BACKUP_DIR.glob("fptn-backup-*.tar.gz"), reverse=True)
    buttons = []
    for b in backups[:5]:
        name = b.name
        size = b.stat().st_size / 1024 / 1024
        buttons.append([InlineKeyboardButton(
            f"📦 {name} ({size:.1f} MB)",
            callback_data=f"restore:{name}",
        )])
    if not buttons:
        buttons.append([InlineKeyboardButton("📭 Нет бэкапов", callback_data="noop")])
    buttons.append([InlineKeyboardButton("➕ Создать бэкап", callback_data="action:backup")])
    buttons.append([InlineKeyboardButton("⬅️ Назад", callback_data="menu:main")])
    return InlineKeyboardMarkup(buttons)


def get_token_keyboard() -> InlineKeyboardMarkup:
    users = UserManager(USERS_FILE).load_users()
    buttons = []
    for username in users.keys():
        buttons.append([InlineKeyboardButton(f"🔑 {username}", callback_data=f"token:{username}")])
    buttons.append([InlineKeyboardButton("⬅️ Назад", callback_data="menu:main")])
    return InlineKeyboardMarkup(buttons)


def get_settings_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🌐 Серверные настройки", callback_data="action:server_settings")],
        [InlineKeyboardButton("📢 Рассылка", callback_data="action:broadcast")],
        [InlineKeyboardButton("🔒 Блокировки", callback_data="menu:blocked")],
        [InlineKeyboardButton("⬅️ Назад", callback_data="menu:main")],
    ])


def get_blocked_keyboard() -> InlineKeyboardMarkup:
    buttons = []
    for user in BLACKLIST[:10]:
        buttons.append([InlineKeyboardButton(f"🚫 {user}", callback_data=f"unblock:{user}")])
    if not buttons:
        buttons.append([InlineKeyboardButton("✅ Нет заблокированных", callback_data="noop")])
    buttons.append([InlineKeyboardButton("⬅️ Назад", callback_data="menu:settings")])
    return InlineKeyboardMarkup(buttons)


# ========== USER MANAGER ==========
class UserManager:
    def __init__(self, users_file: Path):
        self.users_file = users_file
        self.user_data_lock = threading.Lock()

    def _generate_password(self, length=8) -> str:
        return "".join(random.choice(string.ascii_letters + string.digits) for _ in range(length))

    def _hash_password(self, password: str) -> str:
        sha256 = hashlib.sha256()
        sha256.update(password.encode("utf-8"))
        return sha256.hexdigest()

    def load_users(self) -> dict:
        users = {}
        if self.users_file.exists():
            with self.users_file.open("r") as file:
                for line in file:
                    parts = line.strip().split()
                    if len(parts) >= 3:
                        username = parts[0]
                        password = parts[1]
                        speed = parts[2]
                        is_premium = len(parts) > 3 and parts[3] == "1"
                        users[username] = {
                            "password": password,
                            "speed": speed,
                            "is_premium": is_premium,
                        }
        return users

    def save_users(self, users: dict):
        self.users_file.parent.mkdir(parents=True, exist_ok=True)
        with self.users_file.open("w") as file:
            for username, data in users.items():
                password = data["password"]
                speed = data["speed"]
                is_premium = "1" if data["is_premium"] is True else "0"
                file.write(f"{username} {password} {speed} {is_premium}\n")

    def get_user(self, username: str) -> dict | None:
        users = self.load_users()
        return users.get(username)

    def create_user(self, username: str, speed: str, premium: bool = False) -> tuple[bool, str]:
        users = self.load_users()
        if username in users:
            return False, "Пользователь уже существует"
        password = self._generate_password()
        hashed_password = self._hash_password(password)
        users[username] = {"password": hashed_password, "speed": speed, "is_premium": premium}
        self.save_users(users)
        return True, password

    def set_premium(self, username: str, premium: bool) -> bool:
        users = self.load_users()
        if username not in users:
            return False
        users[username]["is_premium"] = premium
        self.save_users(users)
        return True

    def set_speed(self, username: str, speed: str) -> bool:
        users = self.load_users()
        if username not in users:
            return False
        users[username]["speed"] = speed
        self.save_users(users)
        return True

    def reset_password(self, username: str) -> tuple[str, str | None]:
        users = self.load_users()
        if username not in users:
            return username, None
        new_password = self._generate_password()
        hashed_password = self._hash_password(new_password)
        current_speed = users[username]["speed"]
        current_premium = users[username].get("is_premium", False)
        users[username] = {"password": hashed_password, "speed": current_speed, "is_premium": current_premium}
        self.save_users(users)
        return username, new_password

    def delete_user(self, username: str) -> bool:
        users = self.load_users()
        if username not in users:
            return False
        del users[username]
        self.save_users(users)
        return True

    def search_users(self, query: str) -> dict:
        users = self.load_users()
        if not query:
            return users
        query = query.lower()
        return {k: v for k, v in users.items() if query in k.lower()}

    def batch_reset_passwords(self, usernames: list[str]) -> dict[str, str]:
        results = {}
        for username in usernames:
            _, new_pass = self.reset_password(username)
            results[username] = new_pass
        return results

    def batch_delete(self, usernames: list[str]) -> dict[str, bool]:
        results = {}
        for username in usernames:
            results[username] = self.delete_user(username)
        return results


user_manager = UserManager(USERS_FILE)


# ========== SERVER MONITORING ==========
def get_server_stats() -> dict:
    """CPU, RAM, Disk, Uptime."""
    stats = {}
    try:
        # CPU
        cpu_out = subprocess.run(["cat", "/proc/loadavg"], capture_output=True, text=True, check=True).stdout.strip()
        stats["cpu"] = cpu_out.split()[0] if cpu_out else "N/A"
    except Exception:
        stats["cpu"] = "N/A"

    try:
        # RAM
        mem_out = subprocess.run(["free", "-m"], capture_output=True, text=True, check=True).stdout
        lines = mem_out.strip().split("\n")
        if len(lines) >= 2:
            parts = lines[1].split()
            total, used, avail = parts[1], parts[2], parts[6] if len(parts) > 6 else parts[3]
            stats["ram"] = f"{used}MB / {total}MB (свободно: {avail}MB)"
        else:
            stats["ram"] = "N/A"
    except Exception:
        stats["ram"] = "N/A"

    try:
        # Disk
        df_out = subprocess.run(["df", "-h", "/"], capture_output=True, text=True, check=True).stdout
        lines = df_out.strip().split("\n")
        if len(lines) >= 2:
            parts = lines[1].split()
            stats["disk"] = f"{parts[2]} / {parts[1]} ({parts[4]})"
        else:
            stats["disk"] = "N/A"
    except Exception:
        stats["disk"] = "N/A"

    try:
        # Uptime
        uptime_out = subprocess.run(["uptime", "-p"], capture_output=True, text=True, check=True).stdout.strip()
        stats["uptime"] = uptime_out.replace("up ", "")
    except Exception:
        stats["uptime"] = "N/A"

    try:
        # Docker info
        docker_out = subprocess.run(
            ["docker", "info", "--format", "{{.Containers}} {{.Images}}"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        stats["docker"] = docker_out
    except Exception:
        stats["docker"] = "N/A"

    return stats


def get_container_stats() -> list[dict]:
    """Detailed container stats."""
    try:
        out = subprocess.run(
            ["docker", "stats", "--no-stream", "--format", "{{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        if not out:
            return []
        containers = []
        for line in out.split("\n"):
            parts = line.split("\t")
            if len(parts) >= 5:
                containers.append({
                    "name": parts[0],
                    "cpu": parts[1],
                    "mem": parts[2],
                    "net": parts[3],
                    "block": parts[4],
                })
        return containers
    except Exception:
        return []


# ========== TOKEN GENERATION ==========
def generate_client_token(username: str, password: str, server_ip: str, port: int = 443) -> str:
    """Generate FPTN client token."""
    import base64
    token_data = {
        "version": 1,
        "service_name": SERVICE_NAME,
        "username": username,
        "password": password,
        "servers": [{"name": SERVICE_NAME, "host": server_ip, "md5_fingerprint": "", "port": port}],
        "censored_zone_servers": [],
    }
    # Try to get server fingerprint
    try:
        cert_path = "/opt/fptn/fptn-server-data/server.crt"
        if os.path.exists(cert_path):
            import hashlib
            with open(cert_path, "rb") as f:
                cert_data = f.read()
                fp = hashlib.md5(cert_data).hexdigest()
                token_data["servers"][0]["md5_fingerprint"] = fp
    except Exception:
        pass

    json_str = json.dumps(token_data)
    encoded = base64.b64encode(json_str.encode()).decode()
    return f"fptn:{encoded}"


def get_server_ip() -> str:
    """Get server public IP."""
    try:
        return subprocess.run(
            ["curl", "-fsSL", "--max-time", "5", "https://api.ipify.org"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return "213.21.242.99"


# ========== BACKUP MANAGER ==========
def create_backup() -> tuple[bool, str]:
    """Create a backup tar.gz."""
    try:
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        backup_file = BACKUP_DIR / f"fptn-backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}.tar.gz"
        subprocess.run(
            ["tar", "-czf", str(backup_file), "-C", "/opt/fptn",
             "fptn/docker-compose", "fptn-server-data", "fptn-admin"],
            check=True,
        )
        return True, str(backup_file)
    except Exception as e:
        return False, str(e)


def list_backups() -> list[Path]:
    """List all backups sorted by date."""
    return sorted(BACKUP_DIR.glob("fptn-backup-*.tar.gz"), reverse=True)


def restore_backup(filename: str) -> tuple[bool, str]:
    """Restore a backup."""
    backup_path = BACKUP_DIR / filename
    if not backup_path.exists():
        return False, "Файл не найден"
    try:
        subprocess.run(["tar", "-xzf", str(backup_path), "-C", "/opt/fptn"], check=True)
        return True, "Восстановлено"
    except Exception as e:
        return False, str(e)


# ========== BROADCAST ==========
async def cmd_broadcast(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    if not context.args:
        await _msg(update).reply_text("Использование: `/broadcast <сообщение>`", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
        return

    message_text = " ".join(context.args)
    users = user_manager.load_users()
    sent = 0
    failed = 0

    for username in users:
        try:
            # Extract user ID from username (assuming format user<ID>)
            uid_str = re.sub(r"\D", "", username)
            if uid_str:
                await context.bot.send_message(chat_id=int(uid_str), text=message_text)
                sent += 1
        except Exception:
            failed += 1

    await _msg(update).reply_text(
        f"📢 Рассылка завершена:\n✅ Доставлено: {sent}\n❌ Не доставлено: {failed}",
        reply_markup=get_main_keyboard(),
    )


# ========== MAIN MENU ==========
async def start(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    context.user_data["menu_state"] = "main"
    welcome = FPTN_WELCOME_MESSAGE_EN or FPTN_WELCOME_MESSAGE_RU or "⚡ FPTN Admin Bot"
    await _msg(update).reply_text(
        welcome,
        parse_mode=ParseMode.MARKDOWN,
        disable_web_page_preview=True,
        reply_markup=get_main_keyboard(),
    )


async def cmd_menu(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return
    context.user_data["menu_state"] = "main"
    await _msg(update).reply_text("Главное меню:", reply_markup=get_main_keyboard())


# ========== USERS ==========
async def cmd_users(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return
    context.user_data["menu_state"] = "users"
    users = user_manager.load_users()
    if not users:
        await _msg(update).reply_text("Пользователи не найдены.", reply_markup=get_main_keyboard())
        return

    lines = [f"👥 **Пользователи ({len(users)}):**\n"]
    for username, data in users.items():
        premium = "⭐" if data.get("is_premium") else ""
        lines.append(f"  • `{username}` — {data['speed']} Mbps {premium}")
    await _msg(update).reply_text("\n".join(lines), parse_mode=ParseMode.MARKDOWN, reply_markup=get_users_inline_keyboard())


async def cmd_user_info(update: Update, context: CallbackContext, username: str) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    user = user_manager.get_user(username)
    if not user:
        await _msg(update).reply_text(f"Пользователь `{username}` не найден.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_users_inline_keyboard())
        return

    premium = "Да" if user.get("is_premium") else "Нет"
    text = f"👤 **{username}**\n🚀 Скорость: {user['speed']} Mbps\n⭐ Премиум: {premium}\n"
    await _msg(update).reply_text(text, parse_mode=ParseMode.MARKDOWN, reply_markup=get_user_actions_keyboard(username))


async def cmd_user_reset(update: Update, context: CallbackContext, username: str) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    _, new_password = user_manager.reset_password(username)
    if new_password is None:
        await _msg(update).reply_text(f"Пользователь `{username}` не найден.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_user_actions_keyboard(username))
        return

    await _msg(update).reply_text(
        f"🔑 Пароль для `{username}` сброшен.\nНовый пароль: `{new_password}`",
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=get_user_actions_keyboard(username),
    )


async def cmd_user_premium(update: Update, context: CallbackContext, username: str) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    user = user_manager.get_user(username)
    if not user:
        await _msg(update).reply_text(f"Пользователь `{username}` не найден.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_user_actions_keyboard(username))
        return

    new_premium = not user.get("is_premium", False)
    user_manager.set_premium(username, new_premium)
    await _msg(update).reply_text(
        f"⭐ Премиум для `{username}` установлен: {'Да' if new_premium else 'Нет'}",
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=get_user_actions_keyboard(username),
    )


async def cmd_user_speed(update: Update, context: CallbackContext, username: str, speed: str) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    if user_manager.set_speed(username, speed):
        await _msg(update).reply_text(f"🚀 Скорость для `{username}` установлена: {speed} Mbps", parse_mode=ParseMode.MARKDOWN, reply_markup=get_user_actions_keyboard(username))
    else:
        await _msg(update).reply_text(f"Пользователь `{username}` не найден.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_user_actions_keyboard(username))


async def cmd_user_delete(update: Update, context: CallbackContext, username: str) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    if user_manager.delete_user(username):
        await _msg(update).reply_text(f"🗑 Пользователь `{username}` удален.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_users_inline_keyboard())
    else:
        await _msg(update).reply_text(f"Пользователь `{username}` не найден.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_user_actions_keyboard(username))


# ========== CREATE USER ==========
async def cmd_create(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    if not context.args or len(context.args) < 2:
        await _msg(update).reply_text(
            "Использование: `/create <username> <speed> [premium]`\nПример: `/create user1 100 premium`",
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=get_main_keyboard(),
        )
        return

    username = context.args[0]
    speed = context.args[1]
    premium = len(context.args) > 2 and context.args[2].lower() == "premium"

    success, result = user_manager.create_user(username, speed, premium)
    if success:
        await _msg(update).reply_text(
            f"✅ Пользователь `{username}` создан.\n🚀 Скорость: {speed} Mbps\n⭐ Премиум: {'Да' if premium else 'Нет'}\n🔑 Пароль: `{result}`",
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=get_main_keyboard(),
        )
    else:
        await _msg(update).reply_text(f"❌ Не удалось создать пользователя: {result}", reply_markup=get_main_keyboard())


# ========== TOKEN ==========
async def cmd_token(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    if not context.args:
        await _msg(update).reply_text("Использование: `/token <username>`\nИли нажмите кнопку в меню.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_token_keyboard())
        return

    username = context.args[0]
    user = user_manager.get_user(username)
    if not user:
        await _msg(update).reply_text(f"Пользователь `{username}` не найден.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
        return

    server_ip = get_server_ip()
    token = generate_client_token(username, user["password"], server_ip)
    await _msg(update).reply_text(
        f"🔑 Токен для `{username}`:\n\n`{token}`",
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=get_main_keyboard(),
    )


# ========== SEARCH ==========
async def cmd_search(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    if not context.args:
        await _msg(update).reply_text("Использование: `/search <запрос>`", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
        return

    query = context.args[0]
    results = user_manager.search_users(query)
    if not results:
        await _msg(update).reply_text(f"Пользователи по запросу `{query}` не найдены.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
        return

    buttons = []
    for username in results.keys():
        buttons.append([InlineKeyboardButton(username, callback_data=f"user:{username}")])
    keyboard = InlineKeyboardMarkup(buttons)
    await _msg(update).reply_text(f"🔍 Результаты поиска по `{query}`:", parse_mode=ParseMode.MARKDOWN, reply_markup=keyboard)


# ========== SERVER ==========
async def cmd_status(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    stats = get_server_stats()
    containers = get_container_stats()

    response = "📊 **Сервер:**\n"
    response += f"🕐 Uptime: {stats.get('uptime', 'N/A')}\n"
    response += f"⚡ CPU: {stats.get('cpu', 'N/A')}\n"
    response += f"💾 RAM: {stats.get('ram', 'N/A')}\n"
    response += f"💿 Disk: {stats.get('disk', 'N/A')}\n\n"

    response += "📦 **Контейнеры:**\n"
    for c in containers:
        status_icon = "🟢" if "Up" in c.get("status", "") else "🔴"
        response += f"{status_icon} `{c['name']}` — {c['cpu']} CPU, {c['mem']}\n"

    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔄 Обновить", callback_data="refresh:status")],
        [InlineKeyboardButton("📋 Логи", callback_data="menu:logs")],
        [InlineKeyboardButton("⬅️ Назад", callback_data="menu:main")],
    ])
    await _msg(update).reply_text(response, parse_mode=ParseMode.MARKDOWN, reply_markup=keyboard)


async def cmd_logs(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    if not context.args:
        await _msg(update).reply_text("Выберите сервис:", reply_markup=get_services_keyboard())
        return

    service = context.args[0]
    await _send_logs(update, service)


async def _send_logs(update: Update, service: str) -> None:
    try:
        result = subprocess.run(
            ["docker", "logs", "--tail", "50", service],
            capture_output=True,
            text=True,
            check=True,
        )
        output = result.stdout + result.stderr
        if len(output) > 4000:
            output = output[-4000:]
        if update.callback_query:
            await update.callback_query.message.reply_text(f"```\n{output}\n```", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
            await update.callback_query.answer()
        else:
            await _msg(update).reply_text(f"```\n{output}\n```", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
    except Exception as e:
        if update.callback_query:
            await update.callback_query.message.reply_text(f"Не удалось получить логи для {service}: {e}", reply_markup=get_main_keyboard())
            await update.callback_query.answer()
        else:
            await _msg(update).reply_text(f"Не удалось получить логи для {service}: {e}", reply_markup=get_main_keyboard())


async def cmd_restart(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    if not context.args:
        await _msg(update).reply_text("Выберите сервис:", reply_markup=get_services_keyboard())
        return

    service = context.args[0]
    try:
        subprocess.run(["docker", "restart", service], check=True)
        await _msg(update).reply_text(f"✅ Сервис `{service}` перезапущен.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
    except Exception as e:
        await _msg(update).reply_text(f"❌ Не удалось перезапустить {service}: {e}", reply_markup=get_main_keyboard())


# ========== BACKUP ==========
async def cmd_backup(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    success, result = create_backup()
    if success:
        size = Path(result).stat().st_size / 1024 / 1024
        await _msg(update).reply_text(f"✅ Бэкап создан:\n`{Path(result).name}`\nРазмер: {size:.1f} MB", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
    else:
        await _msg(update).reply_text(f"❌ Не удалось создать бэкап: {result}", reply_markup=get_main_keyboard())


async def cmd_backup_list(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    backups = list_backups()
    if not backups:
        await _msg(update).reply_text("📭 Бэкапов нет.", reply_markup=get_main_keyboard())
        return

    lines = ["📦 **Бэкапы:**\n"]
    for b in backups[:5]:
        size = b.stat().st_size / 1024 / 1024
        lines.append(f"  • `{b.name}` — {size:.1f} MB")
    await _msg(update).reply_text("\n".join(lines), parse_mode=ParseMode.MARKDOWN, reply_markup=get_backup_keyboard())


# ========== BATCH OPERATIONS ==========
async def cmd_batch(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    if not context.args or context.args[0] not in ("reset", "delete"):
        await _msg(update).reply_text(
            "Использование:\n"
            "  `/batch reset` — сбросить все пароли\n"
            "  `/batch delete` — удалить всех пользователей",
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=get_main_keyboard(),
        )
        return

    action = context.args[0]
    users = user_manager.load_users()

    if action == "reset":
        results = user_manager.batch_reset_passwords(list(users.keys()))
        msg = "🔑 Пароли сброшены:\n" + "\n".join(f"  • `{u}`: `{p}`" for u, p in results.items())
    else:
        results = user_manager.batch_delete(list(users.keys()))
        msg = "🗑 Пользователи удалены:\n" + "\n".join(f"  • `{u}`: {'✅' if r else '❌'}" for u, r in results.items())

    await _msg(update).reply_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())


# ========== SECURITY ==========
async def cmd_block_user(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    if not context.args:
        await _msg(update).reply_text("Использование: `/block <username>`", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
        return

    username = context.args[0]
    if username not in BLACKLIST:
        BLACKLIST.append(username)
        with open(BLACKLIST_FILE, "w") as fp:
            fp.write("\n".join(BLACKLIST) + "\n")
        await _msg(update).reply_text(f"🚫 `{username}` заблокирован.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
    else:
        await _msg(update).reply_text(f"`{username}` уже в блокировке.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())


async def cmd_unblock_user(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    if not context.args:
        await _msg(update).reply_text("Использование: `/unblock <username>`", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
        return

    username = context.args[0]
    if username in BLACKLIST:
        BLACKLIST.remove(username)
        with open(BLACKLIST_FILE, "w") as fp:
            fp.write("\n".join(BLACKLIST) + "\n")
        await _msg(update).reply_text(f"✅ `{username}` разблокирован.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
    else:
        await _msg(update).reply_text(f"`{username}` не найден в блокировке.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())


async def cmd_security_stats(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    users = user_manager.load_users()
    blocked_count = len(BLACKLIST)
    premium_count = sum(1 for u in users.values() if u.get("is_premium"))

    stats = "📊 **Статистика безопасности:**\n\n"
    stats += f"👥 Пользователей: {len(users)}\n"
    stats += f"⭐ Премиум: {premium_count}\n"
    stats += f"🚫 Заблокировано: {blocked_count}\n"
    stats += f"🌐 Серверов: {len(SERVERS_LIST)}\n"

    await _msg(update).reply_text(stats, parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())


# ========== HELP ==========
async def cmd_help(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    help_text = """
⚡ **FPTN Admin Bot** ⚡

👥 **Пользователи:**
/start — главное меню
/users — список
/create <user> <speed> [premium] — создать
/token <user> — токен
/reset <user> — сброс пароля
/delete <user> — удалить
/premium <user> <on|off> — премиум
/speed <user> <Mbps> — скорость
/search <query> — поиск
/batch reset|delete — пакетно

⚙️ **Сервер:**
/server — ресурсы (CPU/RAM/Disk)
/status — контейнеры
/logs <service> — логи
/restart <service> — перезапуск

💾 **Бэкапы:**
/backup — создать
/backuplist — список

🔒 **Безопасность:**
/block <user> — блокировка
/unblock <user> — разблокировка
/stats — статистика

📢 **Другое:**
/broadcast <msg> — рассылка
/menu — меню
/help — справка
""".strip()
    await _msg(update).reply_text(help_text, parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())


# ========== CALLBACKS ==========
async def callback_handler(update: Update, context: CallbackContext) -> None:
    query = update.callback_query
    if not query:
        return

    if not is_admin(query.from_user.id):
        await query.answer("⛔ Access denied.", show_alert=True)
        return

    data = query.data or ""

    # User actions
    if data.startswith("user:"):
        username = data.split(":", 1)[1]
        context.user_data["selected_user"] = username
        await cmd_user_info(update, context, username)
        await query.answer()

    elif data.startswith("reset:"):
        username = data.split(":", 1)[1]
        await cmd_user_reset(update, context, username)
        await query.answer()

    elif data.startswith("premium:"):
        username = data.split(":", 1)[1]
        await cmd_user_premium(update, context, username)
        await query.answer()

    elif data.startswith("speed:"):
        username = data.split(":", 1)[1]
        context.user_data["menu_state"] = "speed_input"
        context.user_data["selected_user"] = username
        await query.message.reply_text(f"Введите новую скорость для `{username}` в Mbps:", parse_mode=ParseMode.MARKDOWN)
        await query.answer()

    elif data.startswith("token:"):
        username = data.split(":", 1)[1]
        context.args = [username]
        await cmd_token(update, context)
        await query.answer()

    elif data.startswith("delete:"):
        username = data.split(":", 1)[1]
        await cmd_user_delete(update, context, username)
        await query.answer()

    elif data.startswith("back:"):
        target = data.split(":", 1)[1]
        if target == "users":
            context.user_data["menu_state"] = "users"
            await query.message.reply_text("👥 Управление пользователями:", reply_markup=get_users_inline_keyboard())
        elif target == "server":
            await cmd_status(update, context)
        elif target == "main":
            context.user_data["menu_state"] = "main"
            await query.message.reply_text("⬅️ Главное меню:", reply_markup=get_main_keyboard())
        await query.answer()

    elif data.startswith("logs:"):
        service = data.split(":", 1)[1]
        await _send_logs(update, service)

    elif data.startswith("restart:"):
        service = data.split(":", 1)[1]
        try:
            subprocess.run(["docker", "restart", service], check=True)
            await query.message.reply_text(f"✅ Сервис `{service}` перезапущен.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
        except Exception as e:
            await query.message.reply_text(f"❌ Не удалось перезапустить {service}: {e}", reply_markup=get_main_keyboard())
        await query.answer()

    elif data.startswith("refresh:"):
        if data == "refresh:status":
            await cmd_status(update, context)
        await query.answer()

    elif data.startswith("menu:"):
        target = data.split(":", 1)[1]
        if target == "logs":
            await query.message.reply_text("Выберите сервис:", reply_markup=get_services_keyboard())
        elif target == "users":
            context.user_data["menu_state"] = "users"
            await query.message.reply_text("👥 Управление пользователями:", reply_markup=get_users_inline_keyboard())
        elif target == "server":
            await cmd_status(update, context)
        elif target == "main":
            context.user_data["menu_state"] = "main"
            await query.message.reply_text("⬅️ Главное меню:", reply_markup=get_main_keyboard())
        elif target == "backups":
            await query.message.reply_text("💾 Бэкапы:", reply_markup=get_backup_keyboard())
        elif target == "tokens":
            context.user_data["menu_state"] = "tokens"
            await query.message.reply_text("🔑 Токены:", reply_markup=get_token_keyboard())
        elif target == "settings":
            context.user_data["menu_state"] = "settings"
            await query.message.reply_text("⚙️ Настройки:", reply_markup=get_settings_keyboard())
        elif target == "blocked":
            context.user_data["menu_state"] = "blocked"
            await query.message.reply_text("🔒 Заблокированные:", reply_markup=get_blocked_keyboard())
        await query.answer()

    elif data.startswith("restore:"):
        filename = data.split(":", 1)[1]
        success, result = restore_backup(filename)
        if success:
            await query.message.reply_text(f"✅ Бэкап `{filename}` восстановлен.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
        else:
            await query.message.reply_text(f"❌ Ошибка восстановления: {result}", reply_markup=get_main_keyboard())
        await query.answer()

    elif data.startswith("action:"):
        action = data.split(":", 1)[1]
        if action == "create":
            context.user_data["menu_state"] = "create"
            await query.message.reply_text("Введите `/create <username> <speed> [premium]`", reply_markup=get_main_keyboard())
        elif action == "backup":
            success, result = create_backup()
            if success:
                size = Path(result).stat().st_size / 1024 / 1024
                await query.message.reply_text(f"✅ Бэкап: {Path(result).name} ({size:.1f} MB)", reply_markup=get_main_keyboard())
            else:
                await query.message.reply_text(f"❌ {result}", reply_markup=get_main_keyboard())
        elif action == "server_settings":
            stats = get_server_stats()
            msg = "🌐 **Сервер:**\n"
            msg += f"CPU: {stats.get('cpu', 'N/A')}\n"
            msg += f"RAM: {stats.get('ram', 'N/A')}\n"
            msg += f"Disk: {stats.get('disk', 'N/A')}\n"
            msg += f"Uptime: {stats.get('uptime', 'N/A')}\n"
            await query.message.reply_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=get_settings_keyboard())
        elif action == "broadcast":
            context.user_data["menu_state"] = "broadcast"
            await query.message.reply_text("Введите `/broadcast <сообщение>`", reply_markup=get_main_keyboard())
        elif action == "noop":
            await query.answer()
        await query.answer()

    else:
        await query.answer()


# ========== TEXT HANDLER ==========
async def text_handler(update: Update, context: CallbackContext) -> None:
    if not update.message or not update.message.text:
        return

    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    text = update.message.text.strip()
    state = context.user_data.get("menu_state", "main")

    if state == "speed_input":
        username = context.user_data.get("selected_user")
        if not username:
            await _msg(update).reply_text("Пользователь не выбран.", reply_markup=get_main_keyboard())
            context.user_data["menu_state"] = "main"
            return
        await cmd_user_speed(update, context, username, text)
        context.user_data["menu_state"] = "users"
        return

    if state == "create":
        parts = text.split()
        if len(parts) >= 2:
            context.args = parts
            await cmd_create(update, context)
        else:
            await _msg(update).reply_text("Формат: `<username> <speed> [premium]`", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())
        context.user_data["menu_state"] = "main"
        return

    if state == "broadcast":
        context.args = [text]
        await cmd_broadcast(update, context)
        context.user_data["menu_state"] = "main"
        return

    if state == "main":
        if text == "👥 Пользователи":
            await cmd_users(update, context)
        elif text == "📊 Сервер":
            await cmd_status(update, context)
        elif text == "💾 Бэкапы":
            await cmd_backup_list(update, context)
        elif text == "🔑 Токены":
            context.user_data["menu_state"] = "tokens"
            await _msg(update).reply_text("🔑 Выберите пользователя:", reply_markup=get_token_keyboard())
        elif text == "⚙️ Настройки":
            context.user_data["menu_state"] = "settings"
            await _msg(update).reply_text("⚙️ Настройки:", reply_markup=get_settings_keyboard())
        elif text == "ℹ️ Помощь":
            await cmd_help(update, context)
        else:
            await _msg(update).reply_text("Неизвестная команда. Используйте меню или /help", reply_markup=get_main_keyboard())


# ========== MAIN ==========
def main() -> None:
    if not TELEGRAM_API_TOKEN:
        logger.error("TELEGRAM_API_TOKEN is not set.")
        sys.exit(1)

    application = Application.builder().token(TELEGRAM_API_TOKEN).build()

    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("menu", cmd_menu))
    application.add_handler(CommandHandler("users", cmd_users))
    application.add_handler(CommandHandler("user", cmd_user_info))
    application.add_handler(CommandHandler("create", cmd_create))
    application.add_handler(CommandHandler("delete", cmd_user_delete))
    application.add_handler(CommandHandler("premium", cmd_user_premium))
    application.add_handler(CommandHandler("speed", cmd_user_speed))
    application.add_handler(CommandHandler("reset", cmd_user_reset))
    application.add_handler(CommandHandler("search", cmd_search))
    application.add_handler(CommandHandler("status", cmd_status))
    application.add_handler(CommandHandler("logs", cmd_logs))
    application.add_handler(CommandHandler("restart", cmd_restart))
    application.add_handler(CommandHandler("backup", cmd_backup))
    application.add_handler(CommandHandler("backuplist", cmd_backup_list))
    application.add_handler(CommandHandler("batch", cmd_batch))
    application.add_handler(CommandHandler("token", cmd_token))
    application.add_handler(CommandHandler("block", cmd_block_user))
    application.add_handler(CommandHandler("unblock", cmd_unblock_user))
    application.add_handler(CommandHandler("stats", cmd_security_stats))
    application.add_handler(CommandHandler("broadcast", cmd_broadcast))
    application.add_handler(CommandHandler("help", cmd_help))
    application.add_handler(CallbackQueryHandler(callback_handler))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))

    logger.info("Admin bot started and is polling for messages.")
    application.run_polling()


if __name__ == "__main__":
    init_logger()
    main()