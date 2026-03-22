#!/bin/bash
# announce.sh — Broadcast a message to all players on all running servers.
#
# Usage:
#   ./announce.sh <message>
#
# Examples:
#   ./announce.sh "Server maintenance in 5 minutes — please save your work!"
#   ./announce.sh "I am restarting mc3 now."
#
# The message is sent as a server 'say' command to every running container
# (lobby + mc1–mc5). Containers that are not running are silently skipped.

cd "$(dirname "$0")"

if [ $# -eq 0 ]; then
    echo "Usage: ./announce.sh <message>"
    echo ""
    echo "Example: ./announce.sh \"Server maintenance in 5 minutes!\""
    exit 1
fi

MESSAGE="$*"

CONTAINERS=(lobby mc1 mc2 mc3 mc4 mc5)

sent=0
skipped=0

for NAME in "${CONTAINERS[@]}"; do
    if docker compose ps --status running "$NAME" 2>/dev/null | grep -q "$NAME"; then
        docker compose exec -T "$NAME" \
            bash -c "echo 'say [ADMIN] $MESSAGE' > /proc/1/fd/0" 2>/dev/null
        echo "  ✓ $NAME"
        (( sent++ )) || true
    else
        echo "  – $NAME  (not running)"
        (( skipped++ )) || true
    fi
done

echo ""
echo "Message sent to $sent server(s), $skipped skipped."
