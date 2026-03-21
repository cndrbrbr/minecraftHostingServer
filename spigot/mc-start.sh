#!/bin/bash
# mc-start.sh — Start the Minecraft server after it has been stopped.
# Called via sudo by mc-dispatch.sh (ForceCommand for mc-ctrl SSH user).
# Removes the .stopped marker so the entrypoint loop launches the server.

if ! [ -f /server/.stopped ]; then
    echo "==> Server is already running."
    exit 0
fi

rm -f /server/.stopped
echo "==> Starting Minecraft server — it will be available in a few seconds."
echo "==> You may close this connection."
