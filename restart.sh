#!/bin/bash
# restart.sh — Restart the Minecraft server process inside a container.
# Usage:  ./restart.sh <1-5>
#
# This kills the Java process; the entrypoint's restart loop relaunches it
# within ~5 seconds without touching the container itself.
# Use "docker compose restart mc<N>" to restart the whole container instead.

SERVER="${1:-}"
if [[ ! "$SERVER" =~ ^[1-5]$ ]]; then
    echo "Usage: $0 <1|2|3|4|5>"
    exit 1
fi

CONTAINER="mc${SERVER}"
echo "Restarting Minecraft server in ${CONTAINER}..."
docker compose exec -T "${CONTAINER}" \
    bash -c "pkill -TERM -f 'spigot-.*\.jar' 2>/dev/null && echo '==> Restart triggered.' || echo '==> Server was not running.'"
