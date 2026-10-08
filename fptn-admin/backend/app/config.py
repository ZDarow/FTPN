from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import field_validator


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    users_file: Path = Path("/etc/fptn/users.list")
    admins_file: Path = Path("/etc/fptn/admins.json")

    servers_file: Path = Path("/etc/fptn/servers.json")
    premium_servers_file: Path = Path("/etc/fptn/premium_servers.json")
    censored_servers_file: Path = Path("/etc/fptn/servers_censored_zone.json")

    enable_brotli_compression: bool = False

    telegram_token: str = ""
    bot_enabled: bool = False
    max_user_speed_limit: int = 30
    service_name: str = "fptn"
    welcome_message_en: str = ""
    welcome_message_ru: str = ""
    bot_settings_file: Path = Path("/etc/fptn/bot_settings.json")

    jwt_secret_file: Path = Path("/etc/fptn/jwt_secret")
    jwt_algorithm: str = "HS256"
    jwt_ttl_minutes: int = 60

    admin_login: str | None = None
    admin_password: str | None = None

    cors_origins: str = ""

    api_prefix: str = "/api/v1"

    @field_validator("cors_origins")
    @classmethod
    def _validate_cors_origins(cls, value: str) -> str:
        if not value.strip():
            return ""
        origins = [o.strip() for o in value.split(",") if o.strip()]
        for origin in origins:
            if not origin.startswith(("http://", "https://")):
                raise ValueError(f"Invalid CORS origin: {origin}")
        return ",".join(origins)

    @field_validator("jwt_algorithm")
    @classmethod
    def _validate_jwt_algorithm(cls, value: str) -> str:
        supported = {"HS256", "HS384", "HS512"}
        if value not in supported:
            raise ValueError(f"Unsupported JWT algorithm: {value}")
        return value

    @field_validator("jwt_ttl_minutes")
    @classmethod
    def _validate_jwt_ttl(cls, value: int) -> int:
        if value <= 0 or value > 1440:
            raise ValueError("jwt_ttl_minutes must be between 1 and 1440")
        return value

    @field_validator("max_user_speed_limit")
    @classmethod
    def _validate_speed_limit(cls, value: int) -> int:
        if value <= 0:
            raise ValueError("max_user_speed_limit must be positive")
        return value

    @field_validator("admin_login")
    @classmethod
    def _validate_admin_login(cls, value: str | None) -> str | None:
        if value is not None and not value.strip():
            raise ValueError("admin_login must not be empty")
        return value

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


settings = Settings()
