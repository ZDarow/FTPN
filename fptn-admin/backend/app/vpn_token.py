import base64
import json
import secrets
import string

import brotli


def generate_password(length: int = 12) -> str:
    return "".join(secrets.choice(string.ascii_letters) for _ in range(length))


def build_token(
    *,
    service_name: str,
    username: str,
    is_premium: bool,
    regular: list[dict],
    premium: list[dict],
    censored: list[dict],
) -> str:
    """Build the fptn access-token payload.

    NOTE: the payload intentionally contains no password or password hash.
    The VPN client authenticates against the C++ server using the password
    that was issued out-of-band (stored as a salted SHA-256 hash in
    ``users.list``).
    """
    servers = premium + regular if is_premium else regular
    data = {
        "version": 1,
        "service_name": service_name,
        "username": username,
        "servers": servers,
        "censored_zone_servers": censored,
    }
    return json.dumps(data, separators=(",", ":"))


def build_access_link(token: str, brotli_enabled: bool) -> str:
    if brotli_enabled:
        compressed = brotli.compress(
            token.encode("utf-8"),
            quality=11,
            lgwin=24,
            lgblock=24,
            mode=brotli.MODE_TEXT,
        )
        return "fptnb:" + base64.b64encode(compressed).decode("utf-8").replace("=", "")
    return "fptn:" + base64.b64encode(token.encode("utf-8")).decode("utf-8").replace("=", "")
