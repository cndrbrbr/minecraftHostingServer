#!/bin/bash
# mc-adduser.sh — Add a Minecraft username to whitelist and ops.
# Called via sudo by mc-dispatch.sh (ForceCommand for mc-ctrl SSH user).
# Kept for the PuTTY 'adduser' command; the work is done by mc-players.sh.

USERNAME="$1"
if [ -z "$USERNAME" ]; then
    echo "Usage: ssh mc-ctrl@<host> -p <port> adduser <minecraft-username>"
    exit 1
fi

/mc-players.sh add "$USERNAME" || exit 1
/mc-players.sh op "$USERNAME" || exit 1
echo "==> Done. You may close this connection."
