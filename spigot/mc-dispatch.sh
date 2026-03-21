#!/bin/bash
# mc-dispatch.sh — SSH ForceCommand dispatcher for mc-ctrl.
# Reads SSH_ORIGINAL_COMMAND to decide which action to run.
#
# Student usage from PuTTY / ssh client:
#   ssh mc-ctrl@<host> -p <port> start
#   ssh mc-ctrl@<host> -p <port> stop

case "${SSH_ORIGINAL_COMMAND:-}" in
    start)
        exec sudo /mc-start.sh
        ;;
    stop)
        exec sudo /mc-stop.sh
        ;;
    *)
        echo "Usage: ssh mc-ctrl@<host> -p <port> start"
        echo "       ssh mc-ctrl@<host> -p <port> stop"
        exit 1
        ;;
esac
