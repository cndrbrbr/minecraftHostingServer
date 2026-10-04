#!/bin/bash
# mc-stop.sh — Stop the Minecraft server without auto-restart.
# Called via sudo by mc-dispatch.sh (ForceCommand for mc-ctrl SSH user).
# Creates the .stopped marker so the entrypoint loop waits instead of restarting.

touch /server/.stopped
/mc-term.sh
echo "==> Server stopped."
echo "==> Use the start command to bring it back up."
echo "==> You may close this connection."
