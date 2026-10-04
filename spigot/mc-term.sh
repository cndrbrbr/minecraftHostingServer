#!/bin/bash
# mc-term.sh — Stop the running Minecraft server, but never hang forever.
# Called (as root) by entrypoint.sh, mc-stop.sh, mc-restart.sh, mc-restore.sh
# and mc-wipe.sh.
#
#   mc-term.sh [seconds]          SIGTERM (the server saves the world); a
#                                 detached watchdog SIGKILLs it if it is still
#                                 running after <seconds> (default 60).
#                                 Returns at once.
#   mc-term.sh --wait [seconds]   same, but returns only when it is gone.
#
# Some shutdowns deadlock (e.g. after plugins were removed while running);
# without the watchdog the server would stay "stopping" until someone kills it.
WAIT=false
[ "${1:-}" = "--wait" ] && { WAIT=true; shift; }
if [ "${1:-}" = "--watch" ]; then MODE=watch; T=$2; PID=$3; else MODE=term; T=${1:-60}; fi
[[ "$T" =~ ^[0-9]+$ ]] || T=60

alive() {
    # The server process itself (started by entrypoint.sh as mc-sftp), not a
    # zombie and not whatever a student might have written into .pid.
    [ -d "/proc/$1" ] && [ "$(stat -c %U "/proc/$1" 2>/dev/null)" = "mc-sftp" ] && \
        ! grep -q '^State:[[:space:]]*Z' "/proc/$1/status" 2>/dev/null
}

watch() {
    for _ in $(seq 1 "$T"); do
        alive "$PID" || return 0
        sleep 1
    done
    echo "==> Server did not stop within ${T}s — killing it (world as of the last save)." > /proc/1/fd/1 2>/dev/null
    kill -KILL "$PID" 2>/dev/null
    for _ in $(seq 1 10); do alive "$PID" || return 0; sleep 1; done
}

if [ "$MODE" = watch ]; then
    [[ "$PID" =~ ^[0-9]+$ ]] && watch
    exit 0
fi

PID=$(cat /server/.pid 2>/dev/null)
[[ "$PID" =~ ^[0-9]+$ ]] && alive "$PID" || exit 0
kill -TERM "$PID" 2>/dev/null || exit 0
if $WAIT; then
    watch
else
    setsid "$0" --watch "$T" "$PID" </dev/null >/dev/null 2>&1 &
fi
exit 0
