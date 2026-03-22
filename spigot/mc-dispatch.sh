#!/bin/bash
# mc-dispatch.sh — SSH ForceCommand dispatcher for mc-ctrl.
# Reads SSH_ORIGINAL_COMMAND to decide which action to run.
#
# Student usage from PuTTY / ssh client:
#   ssh mc-ctrl@<host> -p <port> start
#   ssh mc-ctrl@<host> -p <port> stop
#   ssh mc-ctrl@<host> -p <port> version <version>
#   ssh mc-ctrl@<host> -p <port> restore <YYYY-MM-DD|latest>

case "${SSH_ORIGINAL_COMMAND:-}" in
    start)
        exec sudo /mc-start.sh
        ;;
    stop)
        exec sudo /mc-stop.sh
        ;;
    version\ *)
        VERSION="${SSH_ORIGINAL_COMMAND#version }"
        exec sudo /mc-version.sh "$VERSION"
        ;;
    restore\ *)
        DATE="${SSH_ORIGINAL_COMMAND#restore }"
        exec sudo /mc-restore.sh "$DATE"
        ;;
    *)
        echo "Usage: ssh mc-ctrl@<host> -p <port> start"
        echo "       ssh mc-ctrl@<host> -p <port> stop"
        echo "       ssh mc-ctrl@<host> -p <port> version <version>"
        echo "       ssh mc-ctrl@<host> -p <port> restore <YYYY-MM-DD|latest>"
        exit 1
        ;;
esac
