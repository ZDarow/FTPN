from __future__ import annotations

import fcntl
import json
import os
import tempfile
from contextlib import contextmanager
from pathlib import Path

from pydantic import BaseModel, Field, ValidationError


class ServerExists(Exception):
    def __init__(self, name: str):
        self.name = name
        super().__init__(name)


class ServerNotFound(Exception):
    def __init__(self, name: str):
        self.name = name
        super().__init__(name)


class ServerModel(BaseModel):
    name: str = Field(min_length=1)
    host: str = Field(min_length=1)
    md5_fingerprint: str = ""
    port: int = Field(ge=1, le=65535)
    ping: int = 0


class ServerStore:
    def __init__(self, regular_file: Path, premium_file: Path, censored_file: Path):
        self._files = {
            "regular": Path(regular_file),
            "premium": Path(premium_file),
            "censored": Path(censored_file),
        }
        for path in self._files.values():
            path.parent.mkdir(parents=True, exist_ok=True)

    def _read(self, kind: str) -> list[dict]:
        path = self._files[kind]
        if not path.exists():
            return []
        try:
            raw = json.loads(path.read_text(encoding="utf-8") or "[]")
        except json.JSONDecodeError:
            return []
        if not isinstance(raw, list):
            return []
        result = []
        for item in raw:
            try:
                result.append(ServerModel(**item).model_dump())
            except ValidationError:
                continue
        return result

    def _write(self, kind: str, servers: list[dict]) -> None:
        path = self._files[kind]
        directory = path.parent
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=f".{kind}.", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(servers, f, indent=4, ensure_ascii=False)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, path)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)

    @contextmanager
    def _locked(self, kind: str):
        lock_path = str(self._files[kind]) + ".lock"
        with open(lock_path, "w", encoding="utf-8") as lf:
            fcntl.flock(lf, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lf, fcntl.LOCK_UN)

    def list(self) -> dict[str, list[dict]]:
        return {kind: self._read(kind) for kind in self._files}

    def add(self, kind: str, server: dict) -> dict:
        with self._locked(kind):
            servers = self._read(kind)
            validated = ServerModel(**server).model_dump()
            if any(s.get("name") == validated["name"] for s in servers):
                raise ServerExists(validated["name"])
            servers.append(validated)
            self._write(kind, servers)
            return validated

    def delete(self, kind: str, name: str) -> None:
        with self._locked(kind):
            servers = self._read(kind)
            remaining = [s for s in servers if s.get("name") != name]
            if len(remaining) == len(servers):
                raise ServerNotFound(name)
            self._write(kind, remaining)

    def update(
        self,
        kind: str,
        name: str,
        *,
        new_name: str | None,
        host: str | None,
        md5_fingerprint: str | None,
        port: int | None,
        ping: int | None,
    ) -> dict:
        with self._locked(kind):
            servers = self._read(kind)
            server = next((s for s in servers if s.get("name") == name), None)
            if server is None:
                raise ServerNotFound(name)

            update_data = dict(server.items())
            if new_name and new_name != name:
                if any(s.get("name") == new_name for s in servers):
                    raise ServerExists(new_name)
                update_data["name"] = new_name
            if host is not None:
                update_data["host"] = host
            if md5_fingerprint is not None:
                update_data["md5_fingerprint"] = md5_fingerprint
            if port is not None:
                update_data["port"] = port
            if ping is not None:
                update_data["ping"] = ping

            validated = ServerModel(**update_data).model_dump()
            idx = next(i for i, s in enumerate(servers) if s.get("name") == name)
            servers[idx] = validated
            self._write(kind, servers)
            return validated
