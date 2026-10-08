"""Telegram keyboards for the FPTN Admin Bot."""

from telegram import (
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    KeyboardButton,
    ReplyKeyboardMarkup,
)

from bot.config import BACKUP_DIR, USERS_FILE


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
    from bot.managers.user_manager import UserManager

    users = UserManager(USERS_FILE).load_users()
    buttons = []
    for username in users:
        buttons.append(
            [InlineKeyboardButton(f"👤 {username}", callback_data=f"user:{username}")]
        )
    buttons.append(
        [InlineKeyboardButton("➕ Создать пользователя", callback_data="action:create")]
    )
    buttons.append([InlineKeyboardButton("⬅️ Назад", callback_data="menu:main")])
    return InlineKeyboardMarkup(buttons)


def get_user_actions_keyboard(username: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "🔄 Сброс пароля", callback_data=f"reset:{username}"
                )
            ],
            [InlineKeyboardButton("⭐ Премиум", callback_data=f"premium:{username}")],
            [InlineKeyboardButton("🚀 Скорость", callback_data=f"speed:{username}")],
            [InlineKeyboardButton("🔑 Токен", callback_data=f"token:{username}")],
            [InlineKeyboardButton("🗑 Удалить", callback_data=f"delete:{username}")],
            [InlineKeyboardButton("⬅️ Назад", callback_data="menu:users")],
        ]
    )


def get_services_keyboard() -> InlineKeyboardMarkup:
    services = [
        "docker-compose-fptn-server-1",
        "fptn-admin-fptn-admin-backend-1",
        "fptn-admin-fptn-admin-frontend-1",
        "fptn-admin-bot-telegram-admin-bot-1",
    ]
    buttons = []
    for service in services:
        buttons.append(
            [
                InlineKeyboardButton(f"📋 {service}", callback_data=f"logs:{service}"),
                InlineKeyboardButton(
                    f"🔄 {service}", callback_data=f"restart:{service}"
                ),
            ]
        )
    buttons.append([InlineKeyboardButton("⬅️ Назад", callback_data="menu:server")])
    return InlineKeyboardMarkup(buttons)


def get_server_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [
            [InlineKeyboardButton("🔄 Обновить", callback_data="refresh:status")],
            [InlineKeyboardButton("📋 Логи", callback_data="menu:logs")],
            [InlineKeyboardButton("⬅️ Назад", callback_data="menu:main")],
        ]
    )


def get_backup_keyboard() -> InlineKeyboardMarkup:
    backups = sorted(BACKUP_DIR.glob("fptn-backup-*.tar.gz"), reverse=True)
    buttons = []
    for b in backups[:5]:
        name = b.name
        size = b.stat().st_size / 1024 / 1024
        buttons.append(
            [
                InlineKeyboardButton(
                    f"📦 {name} ({size:.1f} MB)",
                    callback_data=f"restore:{name}",
                )
            ]
        )
    if not buttons:
        buttons.append([InlineKeyboardButton("📭 Нет бэкапов", callback_data="noop")])
    buttons.append(
        [InlineKeyboardButton("➕ Создать бэкап", callback_data="action:backup")]
    )
    buttons.append([InlineKeyboardButton("⬅️ Назад", callback_data="menu:main")])
    return InlineKeyboardMarkup(buttons)


def get_token_keyboard() -> InlineKeyboardMarkup:
    from bot.managers.user_manager import UserManager

    users = UserManager(USERS_FILE).load_users()
    buttons = []
    for username in users:
        buttons.append(
            [InlineKeyboardButton(f"🔑 {username}", callback_data=f"token:{username}")]
        )
    buttons.append([InlineKeyboardButton("⬅️ Назад", callback_data="menu:main")])
    return InlineKeyboardMarkup(buttons)


def get_settings_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "🌐 Серверные настройки", callback_data="action:server_settings"
                )
            ],
            [InlineKeyboardButton("📢 Рассылка", callback_data="action:broadcast")],
            [InlineKeyboardButton("🔒 Блокировки", callback_data="menu:blocked")],
            [InlineKeyboardButton("⬅️ Назад", callback_data="menu:main")],
        ]
    )


def get_blocked_keyboard() -> InlineKeyboardMarkup:
    from bot.config import BLACKLIST_FILE

    buttons = []
    if BLACKLIST_FILE.exists():
        for user in BLACKLIST_FILE.read_text(encoding="utf-8").splitlines()[:10]:
            user = user.strip()
            if user:
                buttons.append(
                    [
                        InlineKeyboardButton(
                            f"🚫 {user}", callback_data=f"unblock:{user}"
                        )
                    ]
                )
    if not buttons:
        buttons.append(
            [InlineKeyboardButton("✅ Нет заблокированных", callback_data="noop")]
        )
    buttons.append([InlineKeyboardButton("⬅️ Назад", callback_data="menu:settings")])
    return InlineKeyboardMarkup(buttons)
