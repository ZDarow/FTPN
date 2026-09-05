FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/

ENV TELEGRAM_API_TOKEN=""
ENV ADMIN_IDS="0"
ENV USERS_FILE="/etc/fptn/users.list"
ENV SERVERS_LIST_FILE="/etc/fptn/servers.json"
ENV PREMIUM_SERVERS_FILE="/etc/fptn/premium_servers.json"
ENV SERVERS_CENSORED_LIST_FILE="/etc/fptn/servers_censored_zone.json"
ENV BLACKLIST_FILE="/etc/fptn/blocked_users.txt"
ENV LOG_FILE="/var/log/fptn_admin_bot.log"
ENV MAX_USER_SPEED_LIMIT="100"
ENV SERVICE_NAME="FPTN"
ENV ENABLE_BROTLI_COMPRESSION="false"

RUN mkdir -p /var/log /etc/fptn

CMD ["python", "src/bot.py"]
