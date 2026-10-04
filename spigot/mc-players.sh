#!/bin/bash
# mc-players.sh — Whitelist and operator management.
# Called via sudo by mc-dispatch.sh (and mc-adduser.sh).
#
#   mc-players.sh list            whitelist and ops (JSON)
#   mc-players.sh add <name>      add to whitelist
#   mc-players.sh remove <name>   remove from whitelist and ops
#   mc-players.sh op <name>       give operator rights (level 4)
#   mc-players.sh deop <name>     take operator rights away
#
# Whitelist changes are written to whitelist.json and, if the server is
# running, applied immediately with "whitelist reload" over RCON.
# Op changes go through RCON while the server runs (it keeps ops in memory
# and would overwrite a file edit), and into ops.json while it is stopped.
set -uo pipefail

WHITELIST_FILE="/server/whitelist.json"
OPS_FILE="/server/ops.json"
PROPS_FILE="/server/data/cfg/server.properties"

die() { echo "ERROR: $*" >&2; exit 1; }

if [ "$(cat /server/.servertype 2>/dev/null)" = "custom" ]; then
    die "this server runs custom software — manage whitelist/ops via SFTP."
fi

exec 9>/server/.mc-players.lock
flock 9

[ -f "$WHITELIST_FILE" ] || echo "[]" > "$WHITELIST_FILE"
[ -f "$OPS_FILE" ] || echo "[]" > "$OPS_FILE"

running() { [ -f /server/.pid ] && kill -0 "$(cat /server/.pid)" 2>/dev/null; }
rcon() { python3 /mc-rcon.py "$@"; }

write_json() {  # <file> <jq filter> [jq args...] — atomic, keeps ownership
    local file="$1"; shift
    jq "$@" "$file" > "$file.tmp" || { rm -f "$file.tmp"; die "could not update $(basename "$file")."; }
    mv "$file.tmp" "$file"
    chown mc-sftp:mc-sftp "$file" && chmod 664 "$file"
}

valid_name() {
    [[ "$1" =~ ^[a-zA-Z0-9_]{3,16}$ ]] || die "'$1' is not a valid Minecraft username (letters, digits, _; 3–16 characters)."
}

# UUID as the server will see it: Mojang UUID in online mode,
# "OfflinePlayer:<name>" UUID in offline mode (e.g. behind BungeeCord).
lookup_uuid() {
    local name="$1" online response flat
    online=$(grep "^online-mode=" "$PROPS_FILE" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    if [ "$online" != "false" ]; then
        response=$(curl -sf --max-time 10 "https://api.mojang.com/users/profiles/minecraft/$name") || true
        [ -n "$response" ] || die "no Minecraft account found for '$name' — check the spelling."
        flat=$(echo "$response" | jq -r '.id // empty')
        [ -n "$flat" ] || die "unexpected response from the Mojang API."
        echo "${flat:0:8}-${flat:8:4}-${flat:12:4}-${flat:16:4}-${flat:20:12}"
    else
        python3 - "$name" <<'PYEOF'
import sys, hashlib, uuid
h = bytearray(hashlib.md5(("OfflinePlayer:" + sys.argv[1]).encode("utf-8")).digest())
h[6] = (h[6] & 0x0f) | 0x30
h[8] = (h[8] & 0x3f) | 0x80
print(str(uuid.UUID(bytes=bytes(h))))
PYEOF
    fi
}

do_deop() {
    local name="$1" out
    if running; then
        out=$(rcon deop "$name") || die "could not reach the server: $out"
        echo "==> $out"
    else
        write_json "$OPS_FILE" --arg n "$name" 'map(select((.name | ascii_downcase) != ($n | ascii_downcase)))'
        echo "==> '$name' is no longer an operator."
    fi
}

reload_whitelist() {
    if running && rcon whitelist reload >/dev/null; then
        echo "==> Applied immediately."
    else
        echo "==> Server is not running — takes effect on next start."
    fi
}

cmd="${1:-}"
name="${2:-}"
case "$cmd" in
    list)
        jq -n -c --slurpfile wl "$WHITELIST_FILE" --slurpfile ops "$OPS_FILE" \
            '{whitelist: [$wl[0][]? | .name] | sort_by(ascii_downcase),
              ops: [$ops[0][]? | .name] | sort_by(ascii_downcase)}'
        ;;

    add)
        valid_name "$name"
        if jq -e --arg n "$name" 'any(.[]; (.name | ascii_downcase) == ($n | ascii_downcase))' "$WHITELIST_FILE" >/dev/null; then
            echo "==> '$name' is already on the whitelist."
            exit 0
        fi
        uuid=$(lookup_uuid "$name") || exit 1
        write_json "$WHITELIST_FILE" --arg name "$name" --arg uuid "$uuid" '. + [{uuid: $uuid, name: $name}]'
        echo "==> '$name' added to the whitelist."
        reload_whitelist
        ;;

    remove)
        valid_name "$name"
        write_json "$WHITELIST_FILE" --arg n "$name" 'map(select((.name | ascii_downcase) != ($n | ascii_downcase)))'
        echo "==> '$name' removed from the whitelist."
        reload_whitelist
        # Removed players lose operator rights too (only if they had them)
        if jq -e --arg n "$name" 'any(.[]; (.name | ascii_downcase) == ($n | ascii_downcase))' "$OPS_FILE" >/dev/null; then
            do_deop "$name"
        fi
        ;;

    op)
        valid_name "$name"
        if running; then
            out=$(rcon op "$name") || die "could not reach the server: $out"
            echo "==> $out"
        else
            if jq -e --arg n "$name" 'any(.[]; (.name | ascii_downcase) == ($n | ascii_downcase))' "$OPS_FILE" >/dev/null; then
                echo "==> '$name' is already an operator."
                exit 0
            fi
            uuid=$(jq -r --arg n "$name" '.[] | select((.name | ascii_downcase) == ($n | ascii_downcase)) | .uuid' "$WHITELIST_FILE" | head -n1)
            [ -n "$uuid" ] || uuid=$(lookup_uuid "$name") || exit 1
            write_json "$OPS_FILE" --arg name "$name" --arg uuid "$uuid" \
                '. + [{uuid: $uuid, name: $name, level: 4, bypassesPlayerLimit: false}]'
            echo "==> '$name' is now an operator (takes effect on next start)."
        fi
        ;;

    deop)
        valid_name "$name"
        do_deop "$name"
        ;;

    *)
        echo "Usage: mc-players.sh list | add <name> | remove <name> | op <name> | deop <name>"
        exit 1
        ;;
esac
