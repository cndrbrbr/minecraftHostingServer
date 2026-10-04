#!/bin/bash
# mc-wipe.sh — Reset a server for the next student (admin only, via the admin page).
# Called via sudo by mc-dispatch.sh.
#
# Stops the server, moves the world and the plugin folder aside into
# data/backup-<timestamp>/ (nothing is deleted except backups older than the
# three newest), empties whitelist/ops and resets the Minecraft version to the
# default. Default plugins are installed again on the next start.
# The server stays stopped.
set -uo pipefail

if [ "$(cat /server/.servertype 2>/dev/null)" = "custom" ]; then
    echo "ERROR: custom servers cannot be reset here." >&2
    exit 1
fi

touch /server/.stopped
/mc-term.sh --wait

ts=$(date +%Y%m%d-%H%M%S)
backup="/server/data/backup-$ts"
mkdir -p "$backup"
[ -d /server/data/worlds ] && mv /server/data/worlds "$backup/worlds"
[ -d /server/data/plugins ] && mv /server/data/plugins "$backup/plugins"
cp /server/whitelist.json /server/ops.json "$backup/" 2>/dev/null || true
mkdir -p /server/data/worlds /server/data/plugins
echo '[]' > /server/whitelist.json
echo '[]' > /server/ops.json
rm -f /server/.version /server/.catalog-state.json /server/.catalog-defaults-done
chown -R mc-sftp:mc-sftp /server/data/worlds /server/data/plugins /server/whitelist.json /server/ops.json "$backup"

# Keep only the three newest backups
ls -1d /server/data/backup-* 2>/dev/null | sort -r | tail -n +4 | xargs -r rm -rf

echo "==> Server reset. Previous world and plugins saved in data/backup-$ts."
echo "==> The server is stopped; start it when the next student is ready."
