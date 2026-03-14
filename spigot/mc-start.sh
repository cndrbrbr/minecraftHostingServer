#!/bin/bash
# mc-start.sh — Restart the Minecraft server process.
# Called via: sudo /mc-start.sh (forced command for mc-ctrl SSH user)
# The entrypoint's restart loop detects the stopped process and relaunches it.

echo "==> Stopping Minecraft server..."
pkill -TERM -f "spigot-.*\.jar" 2>/dev/null || true
echo "==> Server will restart automatically in a few seconds."
echo "==> You may close this connection."
