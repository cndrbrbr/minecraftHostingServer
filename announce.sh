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
# The message is sent as a server 'say' command (over RCON) to every running
# server listed in servers.txt. Servers that are not running are skipped.

cd "$(dirname "$0")"

if [ $# -eq 0 ]; then
    echo "Usage: ./announce.sh <message>"
    echo ""
    echo "Example: ./announce.sh \"Server maintenance in 5 minutes!\""
    exit 1
fi

MESSAGE="$*"

# Servers from servers.txt (written by setup.sh); fallback for old setups
if [ -f servers.txt ]; then
    mapfile -t ALL_SERVERS < servers.txt
else
    ALL_SERVERS=(lobby mc1 mc2 mc3 mc4 mc5)
fi
CONTAINERS=("${ALL_SERVERS[@]}")

sent=0
skipped=0

for NAME in "${CONTAINERS[@]}"; do
    if docker compose ps --status running "$NAME" 2>/dev/null | grep -q "$NAME"; then
        if docker compose exec -T "$NAME" python3 /mc-rcon.py say "[ADMIN] $MESSAGE" >/dev/null 2>&1; then
            echo "  ✓ $NAME"
            (( sent++ )) || true
        else
            echo "  – $NAME  (Minecraft not ready, stopped, or custom server)"
            (( skipped++ )) || true
        fi
    else
        echo "  – $NAME  (not running)"
        (( skipped++ )) || true
    fi
done

echo ""
echo "Message sent to $sent server(s), $skipped skipped."
