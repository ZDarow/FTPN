"""Backup management for the FPTN Admin Bot."""

import subprocess
from pathlib import Path

from bot.config import BACKUP_DIR


def create_backup() -> tuple[bool, str]:
    """Create a backup tar.gz."""
    try:
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        backup_file = (
            BACKUP_DIR
            / f"fptn-backup-{__import__('datetime').datetime.now().strftime('%Y%m%d-%H%M%S')}.tar.gz"
        )
        subprocess.run(
            [
                "tar",
                "-czf",
                str(backup_file),
                "-C",
                "/opt/fptn",
                "fptn/docker-compose",
                "fptn-server-data",
                "fptn-admin",
            ],
            check=True,
        )
        return True, str(backup_file)
    except (subprocess.CalledProcessError, OSError) as e:
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
    except (subprocess.CalledProcessError, OSError) as e:
        return False, str(e)
