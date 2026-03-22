#!/bin/bash
# mc-restore.sh — Restore a dated backup from the backup server.
# Called via sudo by mc-dispatch.sh (ForceCommand for mc-ctrl SSH user).
#
# Requires these env vars in docker-compose.yml:
#   BACKUP_URL  — base URL of the backup HTTP server
#                 e.g. http://source-host:8080
#   MC_NAME     — name of this server (mc1 … mc5)

DATE="$1"
BASE_URL="${BACKUP_URL:-}"
NAME="${MC_NAME:-}"

if [ -z "$BASE_URL" ]; then
    echo "ERROR: BACKUP_URL is not configured for this server."
    echo "       Ask your admin to set it in docker-compose.yml."
    exit 1
fi

if [ -z "$NAME" ]; then
    echo "ERROR: MC_NAME is not configured for this server."
    exit 1
fi

if [ -z "$DATE" ]; then
    echo "Usage: ssh mc-ctrl@<host> -p <port> restore <YYYY-MM-DD>"
    echo "       ssh mc-ctrl@<host> -p <port> restore latest"
    exit 1
fi

# Resolve "latest" to a concrete date
if [ "$DATE" = "latest" ]; then
    echo "==> Fetching latest backup date..."
    DATE=$(curl -sf "$BASE_URL/$NAME/latest.txt" | tr -d '[:space:]')
    if [ -z "$DATE" ]; then
        echo "ERROR: Could not fetch $BASE_URL/$NAME/latest.txt"
        exit 1
    fi
    echo "==> Latest backup: $DATE"
fi

# Validate date format
if [[ ! "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "ERROR: Invalid date '$DATE'. Use YYYY-MM-DD or 'latest'."
    exit 1
fi

echo "==> Restoring $NAME from backup $DATE..."
echo "==> Stopping server..."
touch /server/.stopped
pkill -TERM -f "spigot-.*\.jar" 2>/dev/null || true
sleep 3

# Download and extract cfg, plugins, worlds
for part in cfg plugins worlds; do
    URL="$BASE_URL/$NAME/${part}-${DATE}.zip"
    echo "==> Downloading $part..."
    if ! curl -sf "$URL" -o "/tmp/restore-${part}.zip"; then
        echo "ERROR: Could not download $URL"
        rm -f /tmp/restore-*.zip
        exit 1
    fi
    rm -rf "/server/data/$part"
    unzip -q "/tmp/restore-${part}.zip" -d "/server/data/"
    rm "/tmp/restore-${part}.zip"
    echo "    ✓ $part restored"
done

chown -R mc-sftp:mc-sftp /server/data

echo "==> Restore complete ($DATE)."
echo "==> Run 'start' to launch the server."
echo "==> You may close this connection."
