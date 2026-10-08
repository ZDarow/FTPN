"""User management for the FPTN Admin Bot."""

import hashlib
import random
import string
import threading
from pathlib import Path


class UserManager:
    def __init__(self, users_file: Path):
        self.users_file = users_file
        self.user_data_lock = threading.Lock()

    def _generate_password(self, length: int = 8) -> str:
        return "".join(
            random.choice(string.ascii_letters + string.digits) for _ in range(length)
        )

    @staticmethod
    def _hash_password(password: str) -> str:
        sha256 = hashlib.sha256()
        sha256.update(password.encode("utf-8"))
        return sha256.hexdigest()

    def load_users(self) -> dict:
        users = {}
        if self.users_file.exists():
            with self.users_file.open("r", encoding="utf-8") as file:
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

    def save_users(self, users: dict) -> None:
        self.users_file.parent.mkdir(parents=True, exist_ok=True)
        with self.users_file.open("w", encoding="utf-8") as file:
            for username, data in users.items():
                password = data["password"]
                speed = data["speed"]
                is_premium = "1" if data["is_premium"] is True else "0"
                file.write(f"{username} {password} {speed} {is_premium}\n")

    def get_user(self, username: str) -> dict | None:
        users = self.load_users()
        return users.get(username)

    def create_user(
        self, username: str, speed: str, premium: bool = False
    ) -> tuple[bool, str]:
        users = self.load_users()
        if username in users:
            return False, "Пользователь уже существует"
        password = self._generate_password()
        hashed_password = self._hash_password(password)
        users[username] = {
            "password": hashed_password,
            "speed": speed,
            "is_premium": premium,
        }
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
        users[username] = {
            "password": hashed_password,
            "speed": current_speed,
            "is_premium": current_premium,
        }
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
