#!/bin/bash
# mc-adduser.sh — Add a Minecraft username to whitelist and ops.
# Called via sudo by mc-dispatch.sh (ForceCommand for mc-ctrl SSH user).
#
# Online mode:  UUID is fetched from the Mojang API.
# Offline mode: UUID is derived from the username (OfflinePlayer algorithm).

USERNAME="$1"

if [ -z "$USERNAME" ]; then
    echo "Usage: ssh mc-ctrl@<host> -p <port> adduser <minecraft-username>"
    exit 1
fi

# Validate username — Minecraft allows letters, digits, underscore, 3–16 chars
if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9_]{3,16}$ ]]; then
    echo "ERROR: '$USERNAME' is not a valid Minecraft username."
    echo "       Only letters, digits and underscores are allowed (3–16 characters)."
    exit 1
fi

WHITELIST_FILE="/server/whitelist.json"
OPS_FILE="/server/ops.json"
PROPS_FILE="/server/data/cfg/server.properties"

# ── Determine UUID ────────────────────────────────────────────
ONLINE_MODE=$(grep "^online-mode=" "$PROPS_FILE" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')

if [ "$ONLINE_MODE" != "false" ]; then
    # Online mode — fetch real UUID from Mojang API
    echo "==> Looking up '$USERNAME' in Mojang API..."
    RESPONSE=$(curl -sf "https://api.mojang.com/users/profiles/minecraft/$USERNAME")
    if [ -z "$RESPONSE" ]; then
        echo "ERROR: No Mojang account found for '$USERNAME'."
        echo "       Check the spelling and try again."
        exit 1
    fi
    UUID_FLAT=$(echo "$RESPONSE" | jq -r '.id // empty')
    if [ -z "$UUID_FLAT" ]; then
        echo "ERROR: Unexpected response from Mojang API."
        exit 1
    fi
    UUID="${UUID_FLAT:0:8}-${UUID_FLAT:8:4}-${UUID_FLAT:12:4}-${UUID_FLAT:16:4}-${UUID_FLAT:20:12}"
else
    # Offline mode — derive UUID from "OfflinePlayer:<name>"
    echo "==> Offline mode — generating UUID for '$USERNAME'..."
    UUID=$(python3 - "$USERNAME" <<'PYEOF'
import sys, hashlib, uuid
name = sys.argv[1]
h = bytearray(hashlib.md5(("OfflinePlayer:" + name).encode("utf-8")).digest())
h[6] = (h[6] & 0x0f) | 0x30
h[8] = (h[8] & 0x3f) | 0x80
print(str(uuid.UUID(bytes=bytes(h))))
PYEOF
)
    if [ -z "$UUID" ]; then
        echo "ERROR: Could not generate offline UUID."
        exit 1
    fi
fi

echo "==> UUID: $UUID"

# ── Whitelist ─────────────────────────────────────────────────
[ -f "$WHITELIST_FILE" ] || echo "[]" > "$WHITELIST_FILE"
jq --arg name "$USERNAME" --arg uuid "$UUID" \
    'if any(.[]; .name == $name) then . else . + [{"uuid": $uuid, "name": $name}] end' \
    "$WHITELIST_FILE" > /tmp/mc-wl.tmp && mv /tmp/mc-wl.tmp "$WHITELIST_FILE"
chown root:mc-sftp "$WHITELIST_FILE" && chmod 664 "$WHITELIST_FILE"
echo "==> '$USERNAME' added to whitelist."

# ── Ops ───────────────────────────────────────────────────────
[ -f "$OPS_FILE" ] || echo "[]" > "$OPS_FILE"
jq --arg name "$USERNAME" --arg uuid "$UUID" \
    'if any(.[]; .name == $name) then . else . + [{"uuid": $uuid, "name": $name, "level": 4, "bypassesPlayerLimit": false}] end' \
    "$OPS_FILE" > /tmp/mc-ops.tmp && mv /tmp/mc-ops.tmp "$OPS_FILE"
chown root:mc-sftp "$OPS_FILE" && chmod 664 "$OPS_FILE"
echo "==> '$USERNAME' added to ops (level 4)."

# ── Live reload ───────────────────────────────────────────────
if pgrep -f "spigot-.*\.jar" > /dev/null 2>&1; then
    echo "whitelist reload" > /proc/1/fd/0 2>/dev/null || true
    echo "==> Whitelist reloaded — '$USERNAME' can connect immediately."
    echo "==> Operator permissions take effect after the next server restart."
else
    echo "==> Server is not running — changes take effect on next start."
fi

echo "==> Done. You may close this connection."
