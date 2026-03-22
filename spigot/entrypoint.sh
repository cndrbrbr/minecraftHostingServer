#!/bin/bash
set -e

SPIGOT_VERSION=${SPIGOT_VERSION:-1.21.11}
# Allow student to override version via /server/.version (set by mc-version.sh)
if [ -f /server/.version ]; then
    SPIGOT_VERSION=$(cat /server/.version | tr -d '[:space:]')
fi
SPIGOT_JAR="/server/spigot-${SPIGOT_VERSION}.jar"

# ── SSH host keys ────────────────────────────────────────────
# Stored on the volume so the fingerprint is stable across restarts
# and unique per container (each server has its own volume).
if [ ! -f /server/ssh_host_ed25519_key ]; then
    ssh-keygen -t ed25519 -f /server/ssh_host_ed25519_key -N '' -q
    ssh-keygen -t rsa -b 4096 -f /server/ssh_host_rsa_key -N '' -q
    chmod 600 /server/ssh_host_ed25519_key /server/ssh_host_rsa_key
fi

# ── Authorized keys from environment ─────────────────────────
# Written every start so key rotations take effect immediately
if [ -n "${SFTP_PUBKEY}" ]; then
    echo "${SFTP_PUBKEY}" > /home/mc-sftp/.ssh/authorized_keys
    chown mc-sftp:mc-sftp /home/mc-sftp/.ssh/authorized_keys
    chmod 600 /home/mc-sftp/.ssh/authorized_keys
fi

if [ -n "${CTRL_PUBKEY}" ]; then
    echo "${CTRL_PUBKEY}" > /home/mc-ctrl/.ssh/authorized_keys
    chown mc-ctrl:mc-ctrl /home/mc-ctrl/.ssh/authorized_keys
    chmod 600 /home/mc-ctrl/.ssh/authorized_keys
fi

# ── Start SSH server ──────────────────────────────────────────
mkdir -p /run/sshd
/usr/sbin/sshd
echo "==> SSH server started"

# ── Build Spigot if not on volume ────────────────────────────
if [ ! -f "$SPIGOT_JAR" ] || [ "${FORCE_BUILD:-false}" = "true" ]; then
    echo "==> Building Spigot ${SPIGOT_VERSION} via BuildTools (this takes a few minutes)..."
    BUILD_DIR=$(mktemp -d)
    cd "$BUILD_DIR"
    java -jar /buildtools/BuildTools.jar --rev "${SPIGOT_VERSION}" --compile SPIGOT
    cp "${BUILD_DIR}/spigot-${SPIGOT_VERSION}.jar" "$SPIGOT_JAR"
    rm -rf "$BUILD_DIR"
fi

# ── Volume directory structure ────────────────────────────────
mkdir -p /server/data/cfg /server/data/plugins /server/data/worlds

# ── Plugin: always update so image rebuilds take effect ──────
cp /server-base/plugins/*.jar /server/data/plugins/

# ── Config: copy to volume on first run only ─────────────────
[ -f /server/eula.txt ]                       || echo "eula=true" > /server/eula.txt
[ -f /server/data/cfg/server.properties ]     || cp /server-base/server.properties /server/data/cfg/server.properties
[ -f /server/data/cfg/spigot.yml ]            || cp /server-base/spigot.yml /server/data/cfg/spigot.yml
[ -f /server/whitelist.json ]                 || cp /server-base/whitelist.json /server/whitelist.json

# ── Permissions for ChrootDirectory ──────────────────────────
# /server must be root:root 755 (sshd ChrootDirectory requirement)
chown root:root /server
chmod 755 /server
# Students write to /server/data via SFTP
chown -R mc-sftp:mc-sftp /server/data
# Spigot unpacks itself into /server/bundler — must be writable by mc-sftp
mkdir -p /server/bundler
chown -R mc-sftp:mc-sftp /server/bundler
chmod -R u+rwX,go+rX /server/data

# ── watch_copy: push image config changes to volume at runtime
/watch_copy.sh /server-base/server.properties /server/data/cfg/server.properties &

# ── Start server with auto-restart loop ─────────────────────
# Exits only when /server/.shutdown exists (docker stop).
# A SIGTERM from mc-stop.sh causes a non-zero exit → paused (not restarted)
# when /server/.stopped is present. mc-start.sh removes .stopped to resume.
cd /server
echo "==> Starting Minecraft server ${SPIGOT_VERSION}..."

while true; do
    # Wait while the student has manually stopped the server
    while [ -f /server/.stopped ]; do
        sleep 2
    done

    runuser -u mc-sftp -- java \
        -Xms${MC_MEM_MIN:-512M} \
        -Xmx${MC_MEM_MAX:-1G} \
        --add-opens=java.base/java.lang=ALL-UNNAMED \
        --add-opens=java.base/java.lang.invoke=ALL-UNNAMED \
        --add-opens=java.base/java.lang.ref=ALL-UNNAMED \
        --add-opens=java.base/java.nio=ALL-UNNAMED \
        --add-opens=java.base/java.util=ALL-UNNAMED \
        -jar "$SPIGOT_JAR" \
        --config        "./data/cfg/server.properties" \
        --bukkit-settings  "./data/cfg/bukkit.yml" \
        --spigot-settings  "./data/cfg/spigot.yml" \
        --commands-settings "./data/cfg/commands.yml" \
        --plugins       "./data/plugins" \
        --world-dir     "./data/worlds" \
        --level-name    "${MC_LEVELNAME:-world}" \
        --max-players   "${MC_MAXPLAYERS:-20}" \
        --port          "${MC_PORT:-25565}" \
        nogui || true

    # Graceful shutdown requested by docker stop (SIGTERM to PID 1)
    if [ -f /server/.shutdown ]; then
        echo "==> Shutdown requested — exiting."
        exit 0
    fi

    # Student manually stopped the server — pause until start is called
    if [ -f /server/.stopped ]; then
        echo "==> Server stopped by student — waiting for start command..."
        continue
    fi

    echo "==> Server stopped — restarting in 5 seconds..."
    sleep 5
done
