#!/bin/bash
set -e

# Copy default config on first start only.
# Admins can then edit /bungee/config.yml on the volume directly.
[ -f /bungee/config.yml ] || cp /bungee-base/config.yml /bungee/config.yml

cd /bungee
echo "==> Starting BungeeCord..."
exec java \
    -Xms128M \
    -Xmx${BUNGEE_MEM_MAX:-512M} \
    -jar BungeeCord.jar
