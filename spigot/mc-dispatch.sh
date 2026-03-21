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
    version\ *)
        VERSION="${SSH_ORIGINAL_COMMAND#version }"
        exec sudo /mc-version.sh "$VERSION"
        ;;
    *)
        echo "Usage: ssh mc-ctrl@<host> -p <port> start"
        echo "       ssh mc-ctrl@<host> -p <port> stop"
        echo "       ssh mc-ctrl@<host> -p <port> version <version>"
        echo "Example: ssh mc-ctrl@<host> -p <port> version 1.20.4"
        exit 1
        ;;
esac
