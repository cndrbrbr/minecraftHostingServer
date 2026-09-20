#!/bin/bash
# mc-dispatch.sh — SSH ForceCommand dispatcher for mc-ctrl.
# Reads SSH_ORIGINAL_COMMAND to decide which action to run.
#
# Student usage from PuTTY / ssh client:
#   ssh mc-ctrl@<host> -p <port> start
#   ssh mc-ctrl@<host> -p <port> stop
#   ssh mc-ctrl@<host> -p <port> version <version>
#   ssh mc-ctrl@<host> -p <port> restore <YYYY-MM-DD|latest>
#   ssh mc-ctrl@<host> -p <port> adduser <minecraft-username>
#
# A student running custom software (MC_SERVER_TYPE=custom) only gets
# start/stop here — version/restore/adduser all assume the managed
# Spigot file layout, which custom-type students don't have.

SERVER_TYPE=$(cat /server/.servertype 2>/dev/null || true)
SERVER_TYPE="${SERVER_TYPE:-spigot}"

custom_denied() {
    echo "ERROR: this server is running custom software (MC_SERVER_TYPE=custom)."
    echo "       Only 'start' and 'stop' are available here — manage your"
    echo "       server files, version and backups directly via SFTP."
    exit 1
}

case "${SSH_ORIGINAL_COMMAND:-}" in
    start)
        exec sudo /mc-start.sh
        ;;
    stop)
        exec sudo /mc-stop.sh
        ;;
    version\ *)
        [ "$SERVER_TYPE" = "custom" ] && custom_denied
        VERSION="${SSH_ORIGINAL_COMMAND#version }"
        exec sudo /mc-version.sh "$VERSION"
        ;;
    restore\ *)
        [ "$SERVER_TYPE" = "custom" ] && custom_denied
        DATE="${SSH_ORIGINAL_COMMAND#restore }"
        exec sudo /mc-restore.sh "$DATE"
        ;;
    adduser\ *)
        [ "$SERVER_TYPE" = "custom" ] && custom_denied
        USERNAME="${SSH_ORIGINAL_COMMAND#adduser }"
        exec sudo /mc-adduser.sh "$USERNAME"
        ;;
    *)
        if [ "$SERVER_TYPE" = "custom" ]; then
            echo "Usage: ssh mc-ctrl@<host> -p <port> start"
            echo "       ssh mc-ctrl@<host> -p <port> stop"
        else
            echo "Usage: ssh mc-ctrl@<host> -p <port> start"
            echo "       ssh mc-ctrl@<host> -p <port> stop"
            echo "       ssh mc-ctrl@<host> -p <port> version <version>"
            echo "       ssh mc-ctrl@<host> -p <port> restore <YYYY-MM-DD|latest>"
            echo "       ssh mc-ctrl@<host> -p <port> adduser <minecraft-username>"
        fi
        exit 1
        ;;
esac
