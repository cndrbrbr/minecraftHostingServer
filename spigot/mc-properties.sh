#!/bin/bash
# mc-properties.sh — Read or replace server.properties (admin page).
# Called via sudo by mc-dispatch.sh.
#
#   mc-properties.sh get   print server.properties
#   mc-properties.sh set   replace it with the content on stdin
#
# Lines must be "key=value", comments (#…) or empty; at most 64 KB.
# Keys the hosting setup depends on are protected: their current values are
# kept whatever the new content says (reported as "kept: <key>").
# Minecraft reads the file only when the server starts.
set -uo pipefail

PROPS=/server/data/cfg/server.properties
MAX=65536
PROTECTED="server-port enable-rcon rcon.port rcon.password broadcast-rcon-to-ops online-mode"

die() { echo "ERROR: $*" >&2; exit 1; }

[ "$(cat /server/.servertype 2>/dev/null)" = "custom" ] && die "this server runs custom software — edit its files via SFTP."
[ -f "$PROPS" ] || die "server.properties does not exist yet — start the server once."

exec 9>/server/.mc-properties.lock
flock 9

case "${1:-}" in
    get)
        cat "$PROPS"
        ;;

    set)
        tmp=$(mktemp)
        trap 'rm -f "$tmp" "$tmp.new" "$tmp.kept"' EXIT
        head -c $(( MAX + 1 )) | tr -d '\r' > "$tmp"
        [ "$(wc -c < "$tmp")" -le "$MAX" ] || die "the file is too large (at most 64 KB)."

        # Validate: key=value, comment or empty line
        bad=$(awk '!/^[[:space:]]*(#|$)/ && !/^[A-Za-z0-9._-]+=/ { print NR; exit }' "$tmp")
        [ -z "$bad" ] || die "line $bad is not of the form name=value."

        # Protected keys keep their current value
        awk -v protected="$PROTECTED" -v oldfile="$PROPS" '
            BEGIN {
                n = split(protected, p, " ")
                for (i = 1; i <= n; i++) isprot[p[i]] = 1
                while ((getline line < oldfile) > 0) {
                    if (line ~ /^[A-Za-z0-9._-]+=/) {
                        k = substr(line, 1, index(line, "=") - 1)
                        if (k in isprot) old[k] = line
                    }
                }
            }
            /^[A-Za-z0-9._-]+=/ {
                k = substr($0, 1, index($0, "=") - 1)
                if (k in isprot) {
                    seen[k] = 1
                    if (k in old) {
                        if ($0 != old[k]) print "kept: " k > "/dev/stderr"
                        print old[k]
                    }
                    else print "kept: " k > "/dev/stderr"
                    next
                }
            }
            { print }
            END {
                for (k in old) if (!(k in seen)) { print old[k]; print "kept: " k > "/dev/stderr" }
            }' "$tmp" > "$tmp.new" 2> "$tmp.kept" || die "could not process the file."

        mv "$tmp.new" "$PROPS"
        chown mc-sftp:mc-sftp "$PROPS"
        chmod 664 "$PROPS"
        echo "==> server.properties saved."
        if [ -s "$tmp.kept" ]; then
            echo "==> Protected settings unchanged: $(sed 's/^kept: //' "$tmp.kept" | sort -u | paste -sd, -)"
        fi
        rm -f "$tmp.kept"
        echo "==> Changes take effect when the server (re)starts."
        ;;

    *)
        echo "Usage: mc-properties.sh get | set  (new content on stdin)"
        exit 1
        ;;
esac
