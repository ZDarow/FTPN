from typing import Literal

from pydantic import BaseModel, Field, field_validator


class AdminLogin(BaseModel):
    username: str
    password: str


class AdminCreate(BaseModel):
    username: str = Field(min_length=1)
    password: str = Field(min_length=4)


class AdminOut(BaseModel):
    username: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    mustChangePassword: bool = False


class ChangePassword(BaseModel):
    currentPassword: str
    newPassword: str = Field(min_length=8)


class VpnUser(BaseModel):
    username: str
    blocked: bool
    premiumAccess: bool
    maxSpeed: int


class UsersPage(BaseModel):
    users: list[VpnUser]
    total: int


class UserUpdate(BaseModel):
    username: str | None = None
    maxSpeed: int | None = Field(default=None, ge=0)
    blocked: bool | None = None
    premiumAccess: bool | None = None

    @field_validator("username")
    @classmethod
    def _alnum(cls, value: str | None) -> str | None:
        if value is not None and not value.isalnum():
            raise ValueError("username must be alphanumeric")
        return value


class UserCreate(BaseModel):
    username: str
    password: str
    maxSpeed: int | None = Field(default=None, ge=0)
    premiumAccess: bool = False

    @field_validator("username")
    @classmethod
    def _alnum(cls, value: str) -> str:
        if not value.isalnum():
            raise ValueError("username must be alphanumeric")
        return value


class UserCreated(VpnUser):
    token: str


class UserToken(BaseModel):
    token: str


class Server(BaseModel):
    name: str
    host: str
    md5_fingerprint: str = ""
    port: int = 443
    ping: int = 0


class ServerCreate(Server):
    kind: Literal["regular", "premium", "censored"] = "regular"


class ServerUpdate(BaseModel):
    name: str | None = None
    host: str | None = None
    md5_fingerprint: str | None = None
    port: int | None = None
    ping: int | None = None


class ServersList(BaseModel):
    regular: list[Server]
    premium: list[Server]
    censoredZone: list[Server]


class Highlights(BaseModel):
    totalUsers: int
    premiumUsers: int
    blockedUsers: int


class BotSettingsOut(BaseModel):
    telegramToken: str
    botEnabled: bool
    botRunning: bool
    maxUserSpeedLimit: int
    serviceName: str
    welcomeMessageEn: str
    welcomeMessageRu: str


class BotSettingsUpdate(BaseModel):
    telegramToken: str | None = None
    maxUserSpeedLimit: int | None = Field(default=None, ge=0)
    serviceName: str | None = None
    welcomeMessageEn: str | None = None
    welcomeMessageRu: str | None = None


class BotEnabledUpdate(BaseModel):
    enabled: bool
