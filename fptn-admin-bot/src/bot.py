import json
import os
import sys
import random
import string
import hashlib
import threading
import subprocess
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
ADMIN_IDS = {int(x) for x in os.getenv("ADMIN_IDS", "").split(",") if x.strip().isdigit()}
ENABLE_BROTLI_COMPRESSION = os.getenv("ENABLE_BROTLI_COMPRESSION", "false").lower() == "true"

if os.path.exists(PREMIUM_SERVERS_FILE):
    with open(PREMIUM_SERVERS_FILE, "r") as fp:
        PREMIUM_SERVERS = json.load(fp)
else:
    PREMIUM_SERVERS = []

if SERVERS_LIST_FILE.exists():
    with open(SERVERS_LIST_FILE, "r") as fp:
        SERVERS_LIST = json.load(fp)
else:
    SERVERS_LIST = []

if os.path.exists(SERVERS_CENSORED_LIST_FILE):
    with open(SERVERS_CENSORED_LIST_FILE, "r") as fp:
        SERVERS_CENSORED_LIST = json.load(fp)
else:
    SERVERS_CENSORED_LIST = []

if os.path.exists(BLACKLIST_FILE):
    with open(BLACKLIST_FILE, "r") as fp:
        BLACKLIST = [line.strip() for line in fp if line.strip()]
else:
    BLACKLIST = []


def _msg(update: Update):
    """Вернуть Message из callback-query или обычного сообщения."""
    if update.callback_query and update.callback_query.message:
        return update.callback_query.message
    return update.message


def init_logger():
    logger.remove()
    log_file = Path(os.getenv("LOG_FILE", "/var/log/fptn_admin_bot.log"))
    log_file.parent.mkdir(parents=True, exist_ok=True)
    logger.add(
        str(log_file),
        level="INFO",
        format="{time} - {level} - {message}",
        rotation="1 MB",
    )
    logger.add(sys.stdout, level="INFO", format="{time} - {level} - {message}")


def is_admin(user_id: int) -> bool:
    return user_id in ADMIN_IDS or len(ADMIN_IDS) == 0


class UserManager:
    def __init__(self, users_file: Path):
        self.users_file = users_file
        self.user_data_lock = threading.Lock()

    def _generate_password(self, length=8) -> str:
        return "".join(random.choice(string.ascii_letters) for _ in range(length))

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


user_manager = UserManager(USERS_FILE)


def escape_markdown(text: str) -> str:
    return text.replace("_", "\\_").replace("*", "\\*").replace("`", "\\`").replace("[", "\\[")


def get_main_keyboard() -> ReplyKeyboardMarkup:
    return ReplyKeyboardMarkup(
        [
            [KeyboardButton("👥 Пользователи"), KeyboardButton("📊 Статус")],
            [KeyboardButton("🔄 Обновить"), KeyboardButton("ℹ️ Помощь")],
        ],
        resize_keyboard=True,
    )


def get_users_inline_keyboard() -> InlineKeyboardMarkup:
    users = user_manager.load_users()
    buttons = []
    for username in users.keys():
        buttons.append([InlineKeyboardButton(username, callback_data=f"user:{username}")])
    return InlineKeyboardMarkup(buttons)


def get_user_actions_keyboard(username: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🔄 Сбросить пароль", callback_data=f"reset:{username}")],
        [InlineKeyboardButton("⭐ Премиум", callback_data=f"premium:{username}")],
        [InlineKeyboardButton("🚀 Скорость", callback_data=f"speed:{username}")],
        [InlineKeyboardButton("🗑 Удалить", callback_data=f"delete:{username}")],
        [InlineKeyboardButton("⬅️ Назад", callback_data="back:users")],
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
            InlineKeyboardButton(f"🔄 {service}", callback_data=f"restart:{service}")
        ])
    return InlineKeyboardMarkup(buttons)


# ========== MAIN MENU ==========
async def start(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    context.user_data["menu_state"] = "main"
    welcome = FPTN_WELCOME_MESSAGE_EN or FPTN_WELCOME_MESSAGE_RU
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
    await _msg(update).reply_text("👥 Выберите пользователя:", reply_markup=get_users_inline_keyboard())


async def cmd_user_info(update: Update, context: CallbackContext, username: str) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    user = user_manager.get_user(username)
    if not user:
        await _msg(update).reply_text(f"Пользователь `{username}` не найден.", parse_mode=ParseMode.MARKDOWN, reply_markup=get_users_inline_keyboard())
        return

    premium = "Да" if user.get("is_premium") else "Нет"
    text = (
        f"👤 **{username}**\n"
        f"🚀 Скорость: {user['speed']} Mbps\n"
        f"⭐ Премиум: {premium}\n"
    )
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
            f"✅ Пользователь `{username}` создан.\n"
            f"🚀 Скорость: {speed} Mbps\n"
            f"⭐ Премиум: {'Да' if premium else 'Нет'}\n"
            f"🔑 Пароль: `{result}`",
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=get_main_keyboard(),
        )
    else:
        await _msg(update).reply_text(f"❌ Не удалось создать пользователя: {result}", reply_markup=get_main_keyboard())


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

    try:
        containers = subprocess.run(
            ["docker", "ps", "--format", "{{.Names}}\t{{.Status}}\t{{.Ports}}"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip().split("\n")

        if not containers or containers == [""]:
            await _msg(update).reply_text("Контейнеры не найдены.", reply_markup=get_main_keyboard())
            return

        response = "📊 **Статус сервисов:**\n\n"
        for line in containers:
            parts = line.split("\t")
            if len(parts) >= 2:
                name, status = parts[0], parts[1]
                ports = parts[2] if len(parts) > 2 else ""
                response += f"`{name}`\nСтатус: {status}\n"
                if ports:
                    response += f"Порты: {ports}\n"
                response += "\n"

        keyboard = InlineKeyboardMarkup([
            [InlineKeyboardButton("🔄 Обновить", callback_data="refresh:status")],
            [InlineKeyboardButton("📋 Логи", callback_data="menu:logs")],
        ])
        await _msg(update).reply_text(response, parse_mode=ParseMode.MARKDOWN, reply_markup=keyboard)
    except Exception as e:
        await _msg(update).reply_text(f"Не удалось получить статус: {e}", reply_markup=get_main_keyboard())


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
        # callback queries have no .message, use .callback_query.message instead
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


async def cmd_backup(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    try:
        backup_dir = Path("/opt/fptn/backups")
        backup_dir.mkdir(parents=True, exist_ok=True)
        backup_file = backup_dir / f"fptn-backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}.tar.gz"

        subprocess.run(
            ["tar", "-czf", str(backup_file), "-C", "/opt/fptn/fptn/docker-compose", "fptn-server-data"],
            check=True,
        )

        await _msg(update).reply_text(
            f"✅ Бэкап создан:\n`{backup_file.name}`\nРазмер: {backup_file.stat().st_size / 1024:.1f} KB",
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=get_main_keyboard(),
        )
    except Exception as e:
        await _msg(update).reply_text(f"❌ Не удалось создать бэкап: {e}", reply_markup=get_main_keyboard())


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

    stats = "📊 **Статистика безопасности**\n\n"
    stats += f"👥 Пользователей: {len(users)}\n"
    stats += f"⭐ Премиум: {premium_count}\n"
    stats += f"🚫 Заблокировано: {blocked_count}\n"
    stats += f"🌐 Серверов: {len(SERVERS_LIST)}\n"

    await _msg(update).reply_text(stats, parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_keyboard())


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

    for username, data in users.items():
        try:
            user_id = int(username.replace("user", ""))
            await context.bot.send_message(chat_id=user_id, text=message_text)
            sent += 1
        except Exception:
            failed += 1

    await _msg(update).reply_text(
        f"📢 Рассылка завершена:\n✅ Доставлено: {sent}\n❌ Не доставлено: {failed}",
        reply_markup=get_main_keyboard(),
    )


# ========== HELP ==========
async def cmd_help(update: Update, context: CallbackContext) -> None:
    if not is_admin(update.effective_user.id):
        await _msg(update).reply_text("⛔ Access denied.")
        return

    help_text = """
⚡ **FPTN Admin Bot** ⚡

👥 **Пользователи:**
/users - список
/user <username> - информация
/create <username> <speed> [premium] - создать
/delete <username> - удалить
/premium <username> <on|off> - премиум
/speed <username> <Mbps> - скорость
/reset <username> - сброс пароля
/search <query> - поиск

⚙️ **Сервер:**
/status - статус
/logs <service> - логи
/restart <service> - перезапуск
/backup - бэкап

🔒 **Безопасность:**
/block <username> - блокировка
/unblock <username> - разблокировка
/stats - статистика

📢 **Другое:**
/broadcast <msg> - рассылка
/menu - меню
/help - справка
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
    elif data.startswith("delete:"):
        username = data.split(":", 1)[1]
        await cmd_user_delete(update, context, username)
        await query.answer()
    elif data.startswith("back:"):
        target = data.split(":", 1)[1]
        if target == "users":
            context.user_data["menu_state"] = "users"
            await query.message.reply_text("👥 Управление пользователями:", reply_markup=get_users_inline_keyboard())
        await query.answer()
    elif data.startswith("logs:"):
        service = data.split(":", 1)[1]
        await _send_logs(update, service)
        await query.answer()
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
        if data == "menu:logs":
            await query.message.reply_text("Выберите сервис:", reply_markup=get_services_keyboard())
        elif data == "menu:users":
            await cmd_users(update, context)
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

    if state == "main":
        if text == "👥 Пользователи":
            await cmd_users(update, context)
        elif text == "📊 Статус":
            await cmd_status(update, context)
        elif text == "🔄 Обновить":
            await cmd_status(update, context)
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
