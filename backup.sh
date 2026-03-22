#!/bin/bash
# backup.sh — Create dated backups of Minecraft server data volumes.
#
# Usage:
#   ./backup.sh          — back up all 5 servers
#   ./backup.sh 1        — back up mc1 only
#   ./backup.sh 1 3 5    — back up mc1, mc3, mc5
#
# Backups are written to ./backups/mc<N>/ as three zip files:
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
SERVERS="${@:-1 2 3 4 5}"

echo "==> Backup date: $DATE"
echo ""

for i in $SERVERS; do
    NAME="mc${i}"
    DIR="$BACKUP_DIR/$NAME"
    mkdir -p "$DIR"

    # Check container is running
    if ! docker compose ps --status running "$NAME" 2>/dev/null | grep -q "$NAME"; then
        echo "⚠  $NAME is not running — skipping."
        continue
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
done

echo "All backups written to $BACKUP_DIR"
echo ""
echo "To serve backups for restore commands, run:"
echo "  docker run -d --rm -p 8080:80 -v $BACKUP_DIR:/usr/share/nginx/html:ro nginx:alpine"
echo "  Then set BACKUP_URL=http://<this-host>:8080 in the destination docker-compose.yml"
