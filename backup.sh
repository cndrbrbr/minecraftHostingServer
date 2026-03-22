#!/bin/bash
# backup.sh — Create dated backups of Minecraft server data volumes.
#
# Usage:
#   ./backup.sh              — back up lobby (if running) + all 5 servers
#   ./backup.sh 1            — back up mc1 only
#   ./backup.sh 1 3 5        — back up mc1, mc3, mc5
#   ./backup.sh lobby        — back up lobby only
#   ./backup.sh lobby 1 2    — back up lobby + mc1 + mc2
#
# Backups are written to ./backups/<name>/ as three zip files:
#   cfg-YYYY-MM-DD.zip
#   plugins-YYYY-MM-DD.zip
#   worlds-YYYY-MM-DD.zip
#
# A latest.txt file is updated with the most recent backup date.
# Serve the ./backups/ directory over HTTP so restore commands can reach it.

set -e
cd "$(dirname "$0")"

DATE=$(date +%Y-%m-%d)
BACKUP_DIR="$(pwd)/backups"

# Build list of containers to back up
if [ $# -eq 0 ]; then
    # No arguments — back up lobby if running, then all mc servers
    CONTAINERS=()
    if docker compose ps --status running lobby 2>/dev/null | grep -q lobby; then
        CONTAINERS+=(lobby)
    fi
    CONTAINERS+=(mc1 mc2 mc3 mc4 mc5)
else
    # Arguments given — convert numbers to mc<N>, pass "lobby" as-is
    CONTAINERS=()
    for arg in "$@"; do
        if [ "$arg" = "lobby" ]; then
            CONTAINERS+=(lobby)
        else
            CONTAINERS+=("mc${arg}")
        fi
    done
fi

echo "==> Backup date: $DATE"
echo ""

backup_container() {
    local NAME="$1"
    local DIR="$BACKUP_DIR/$NAME"
    mkdir -p "$DIR"

    if ! docker compose ps --status running "$NAME" 2>/dev/null | grep -q "$NAME"; then
        echo "⚠  $NAME is not running — skipping."
        return
    fi

    echo "==> Backing up $NAME..."
    for part in cfg plugins worlds; do
        echo -n "    $part ... "
        docker compose exec -T "$NAME" \
            bash -c "cd /server/data && zip -qr /tmp/mc-backup-${part}.zip ${part}"
        docker cp "$NAME:/tmp/mc-backup-${part}.zip" "$DIR/${part}-${DATE}.zip"
        docker compose exec -T "$NAME" rm -f "/tmp/mc-backup-${part}.zip"
        echo "done  →  $DIR/${part}-${DATE}.zip"
    done

    echo "$DATE" > "$DIR/latest.txt"
    echo "==> $NAME complete."
    echo ""
}

for NAME in "${CONTAINERS[@]}"; do
    backup_container "$NAME"
done

echo "All backups written to $BACKUP_DIR"
echo ""
echo "To serve backups for restore commands, run:"
echo "  docker run -d --name mc-backup-server -p 8080:80 -v $BACKUP_DIR:/usr/share/nginx/html:ro nginx:alpine"
echo "  Then set BACKUP_URL=http://<this-host>:8080 in the destination docker-compose.yml"
