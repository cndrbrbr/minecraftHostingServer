#!/bin/bash
# mc-version.sh — Set the Spigot version for the next server start.
# Called via sudo by mc-dispatch.sh (ForceCommand for mc-ctrl SSH user).
# The new version takes effect after a stop + start.
# If the version has not been built before, BuildTools will compile it
# on the next start (this takes several minutes).

VERSION="$1"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "ERROR: Invalid version format '$VERSION'."
    echo "Usage: ssh mc-ctrl@<host> -p <port> version <version>"
    echo "Example: version 1.20.4"
    exit 1
fi

echo "$VERSION" > /server/.version
echo "==> Version set to $VERSION."
echo "==> Run 'stop' then 'start' to apply."
echo "==> If this version has not been used before, the first start"
echo "==> will take several minutes to compile it."
