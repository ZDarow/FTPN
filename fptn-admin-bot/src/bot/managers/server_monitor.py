"""Server monitoring and token generation for the FPTN Admin Bot."""

import base64
import hashlib
import logging
import subprocess
from pathlib import Path

from bot.config import (
    PREMIUM_SERVERS_FILE,
    SERVERS_CENSORED_LIST_FILE,
    SERVERS_LIST_FILE,
)

logger = logging.getLogger(__name__)


def get_server_stats() -> dict:
    """CPU, RAM, Disk, Uptime."""
    stats = {}
    try:
        cpu_out = subprocess.run(
            ["cat", "/proc/loadavg"], capture_output=True, text=True, check=True
        ).stdout.strip()
        stats["cpu"] = cpu_out.split()[0] if cpu_out else "N/A"
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        stats["cpu"] = "N/A"

    try:
        mem_out = subprocess.run(
            ["free", "-m"], capture_output=True, text=True, check=True
        ).stdout
        lines = mem_out.strip().split("\n")
        if len(lines) >= 2:
            parts = lines[1].split()
            total, used, avail = (
                parts[1],
                parts[2],
                parts[6] if len(parts) > 6 else parts[3],
            )
            stats["ram"] = f"{used}MB / {total}MB (свободно: {avail}MB)"
        else:
            stats["ram"] = "N/A"
    except (
        subprocess.CalledProcessError,
        FileNotFoundError,
        OSError,
        IndexError,
        ValueError,
    ):
        stats["ram"] = "N/A"

    try:
        df_out = subprocess.run(
            ["df", "-h", "/"], capture_output=True, text=True, check=True
        ).stdout
        lines = df_out.strip().split("\n")
        if len(lines) >= 2:
            parts = lines[1].split()
            stats["disk"] = f"{parts[2]} / {parts[1]} ({parts[4]})"
        else:
            stats["disk"] = "N/A"
    except (subprocess.CalledProcessError, FileNotFoundError, OSError, IndexError):
        stats["disk"] = "N/A"

    try:
        uptime_out = subprocess.run(
            ["uptime", "-p"], capture_output=True, text=True, check=True
        ).stdout.strip()
        stats["uptime"] = uptime_out.replace("up ", "")
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        stats["uptime"] = "N/A"

    try:
        docker_out = subprocess.run(
            ["docker", "info", "--format", "{{.Containers}} {{.Images}}"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        stats["docker"] = docker_out
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        stats["docker"] = "N/A"

    return stats


def get_container_stats() -> list[dict]:
    """Detailed container stats."""
    try:
        out = subprocess.run(
            [
                "docker",
                "stats",
                "--no-stream",
                "--format",
                "{{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}",
            ],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        if not out:
            return []
        containers = []
        for line in out.split("\n"):
            parts = line.split("\t")
            if len(parts) >= 5:
                containers.append(
                    {
                        "name": parts[0],
                        "cpu": parts[1],
                        "mem": parts[2],
                        "net": parts[3],
                        "block": parts[4],
                    }
                )
        return containers
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        return []


def generate_client_token(
    username: str, password: str, server_ip: str, port: int = 443
) -> str:
    """Generate FPTN client token."""
    if SERVERS_LIST_FILE.exists():
        try:
            __import__("json").loads(
                SERVERS_LIST_FILE.read_text(encoding="utf-8") or "[]"
            )
        except (__import__("json").JSONDecodeError, OSError):
            pass

    premium_servers = []
    if PREMIUM_SERVERS_FILE.exists():
        try:
            premium_servers = __import__("json").loads(
                PREMIUM_SERVERS_FILE.read_text(encoding="utf-8") or "[]"
            )
        except (__import__("json").JSONDecodeError, OSError):
            pass

    censored_zone_servers = []
    if SERVERS_CENSORED_LIST_FILE.exists():
        try:
            censored_zone_servers = __import__("json").loads(
                SERVERS_CENSORED_LIST_FILE.read_text(encoding="utf-8") or "[]"
            )
        except (__import__("json").JSONDecodeError, OSError):
            pass

    token_data = {
        "version": 1,
        "service_name": "FPTN",
        "username": username,
        "password": password,
        "servers": [
            {
                "id": "local",
                "name": "Local",
                "host": server_ip,
                "port": port,
                "sni": server_ip,
                "premium": False,
            }
        ],
        "premium_servers": premium_servers,
        "censored_zone_servers": censored_zone_servers,
    }

    # Try to get server fingerprint
    try:
        cert_path = "/opt/fptn/fptn-server-data/server.crt"
        if Path(cert_path).exists():
            with open(cert_path, "rb") as f:
                cert_data = f.read()
                fp = hashlib.md5(cert_data).hexdigest()
                token_data["servers"][0]["md5_fingerprint"] = fp
    except (OSError, ValueError) as e:
        logger.debug("Failed to read server certificate fingerprint: %s", e)

    json_str = __import__("json").dumps(token_data)
    encoded = base64.b64encode(json_str.encode()).decode()
    return f"fptn:{encoded}"


def get_server_ip() -> str:
    """Get server public IP."""
    try:
        return subprocess.run(
            ["curl", "-fsSL", "--max-time", "5", "https://api.ipify.org"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        return "213.21.242.99"
