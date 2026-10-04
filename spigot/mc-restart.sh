#!/bin/bash
# mc-restart.sh — Restart the Minecraft server (or start it if stopped).
# Called via sudo by mc-dispatch.sh. Killing the Java process without the
# .stopped marker makes the entrypoint loop start it again after 5 seconds.

if [ -f /server/.stopped ]; then
    exec /mc-start.sh
fi
if [ -f /server/.pid ] && kill -0 "$(cat /server/.pid)" 2>/dev/null && /mc-term.sh; then
    echo "==> Server is restarting — it will be back in about 30 seconds."
else
    echo "==> Server is not running yet (it may still be starting)."
fi
