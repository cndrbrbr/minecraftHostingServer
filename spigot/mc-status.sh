#!/bin/bash
# mc-status.sh — Server state as JSON (for the admin page).
# Called via sudo by mc-dispatch.sh.
#
# state: stopped  — stopped by the student/admin (waiting for start)
#        building — BuildTools is compiling a new version
#        starting — Java process runs, server not ready yet
#        running  — server is up (players are listed)

type=$(cat /server/.servertype 2>/dev/null || echo spigot)
version=""
if [ "$type" != "custom" ]; then
    [ -f /server/.version ] && version=$(tr -d '[:space:]' < /server/.version)
    [ -z "$version" ] && version=$(tr -d '[:space:]' < /server/.default-version 2>/dev/null)
fi

players="[]"
max=0
if [ -f /server/.stopped ]; then
    state=stopped
elif [ -f /server/.pid ] && kill -0 "$(cat /server/.pid)" 2>/dev/null; then
    state=starting
    if [ "$type" != "custom" ] && out=$(python3 /mc-rcon.py list 2>/dev/null); then
        state=running
        # "There are 1 of a max of 20 players online: Steve"
        max=$(echo "$out" | sed -nE 's/.*max of ([0-9]+).*/\1/p')
        players=$(echo "$out" | sed -E 's/^[^:]*:[[:space:]]*//; s/§.//g' | tr ',' '\n' \
            | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -E '^[A-Za-z0-9_]{1,16}$' | jq -R . | jq -s -c .)
    elif [ "$type" = "custom" ]; then
        state=running
    fi
else
    state=building
fi

# Is the whitelist switched on? (white-list=true in server.properties)
whitelist=false
grep -q '^white-list=true' /server/data/cfg/server.properties 2>/dev/null && whitelist=true

jq -n -c --arg state "$state" --arg type "$type" --arg version "$version" \
    --argjson players "${players:-[]}" --argjson max "${max:-0}" --argjson whitelist "$whitelist" \
    '{state: $state, type: $type, version: $version, players: $players, max_players: $max, whitelist: $whitelist}'
