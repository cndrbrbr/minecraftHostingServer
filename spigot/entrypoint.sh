#!/bin/bash
set -e

DEFAULT_SPIGOT_VERSION=${SPIGOT_VERSION:-1.21.11}

# ── SSH host keys ────────────────────────────────────────────
# Stored on the volume so the fingerprint is stable across restarts
# and unique per container (each server has its own volume).
if [ ! -f /server/ssh_host_ed25519_key ]; then
    ssh-keygen -t ed25519 -f /server/ssh_host_ed25519_key -N '' -q
    ssh-keygen -t rsa -b 4096 -f /server/ssh_host_rsa_key -N '' -q
fi
# Always enforce correct ownership/permissions — sshd refuses to start otherwise
chown root:root /server/ssh_host_ed25519_key /server/ssh_host_rsa_key
chmod 600 /server/ssh_host_ed25519_key /server/ssh_host_rsa_key

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


# ── Volume directory structure ────────────────────────────────
mkdir -p /server/data/cfg /server/data/plugins /server/data/worlds

# ── Plugin: always update so image rebuilds take effect ──────
cp /server-base/plugins/*.jar /server/data/plugins/

# ── Config: copy to volume on first run only ─────────────────
[ -f /server/eula.txt ]                       || echo "eula=true" > /server/eula.txt
[ -f /server/data/cfg/server.properties ]     || cp /server-base/server.properties /server/data/cfg/server.properties
[ -f /server/whitelist.json ]                 || cp /server-base/whitelist.json /server/whitelist.json

# spigot.yml: copy on first run, then patch bungeecord flag from env
if [ ! -f /server/data/cfg/spigot.yml ]; then
    cp /server-base/spigot.yml /server/data/cfg/spigot.yml
fi
if [ "${MC_BUNGEECORD:-false}" = "true" ]; then
    sed -i 's/bungeecord: false/bungeecord: true/' /server/data/cfg/spigot.yml
else
    sed -i 's/bungeecord: true/bungeecord: false/' /server/data/cfg/spigot.yml
fi

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
# /server/ is root:root 755 (SSH chroot requirement) so mc-sftp cannot create
# new files there. Pre-create every file Spigot writes to its working dir so
# the Java process (mc-sftp) can open them for writing.
[ -f /server/ops.json ]            || echo '[]' > /server/ops.json
[ -f /server/banned-players.json ] || echo '[]' > /server/banned-players.json
[ -f /server/banned-ips.json ]     || echo '[]' > /server/banned-ips.json
[ -f /server/usercache.json ]      || echo '[]' > /server/usercache.json
[ -f /server/help.yml ]            || touch /server/help.yml
[ -f /server/permissions.yml ]     || touch /server/permissions.yml
chown root:mc-sftp \
    /server/whitelist.json /server/ops.json \
    /server/banned-players.json /server/banned-ips.json \
    /server/usercache.json /server/help.yml /server/permissions.yml
chmod 664 \
    /server/whitelist.json /server/ops.json \
    /server/banned-players.json /server/banned-ips.json \
    /server/usercache.json /server/help.yml /server/permissions.yml
# Spigot also needs to write into logs/ and crash-reports/
mkdir -p /server/logs /server/crash-reports
chown root:mc-sftp /server/logs /server/crash-reports
chmod 775 /server/logs /server/crash-reports

# ── watch_copy: push image config changes to volume at runtime
/watch_copy.sh /server-base/server.properties /server/data/cfg/server.properties &

# ── Start server with auto-restart loop ─────────────────────
# Exits only when /server/.shutdown exists (docker stop).
# A SIGTERM from mc-stop.sh causes a non-zero exit → paused (not restarted)
# when /server/.stopped is present. mc-start.sh removes .stopped to resume.
cd /server
echo "==> Minecraft server loop starting..."

while true; do
    # Wait while the student has manually stopped the server
    while [ -f /server/.stopped ]; do
        sleep 2
    done

    # Re-read version on every start so version changes take effect
    # without restarting the container
    SPIGOT_VERSION=${DEFAULT_SPIGOT_VERSION}
    if [ -f /server/.version ]; then
        SPIGOT_VERSION=$(cat /server/.version | tr -d '[:space:]')
    fi
    SPIGOT_JAR="/server/spigot-${SPIGOT_VERSION}.jar"

    # Build Spigot if this version is not cached on the volume yet
    if [ ! -f "$SPIGOT_JAR" ] || [ "${FORCE_BUILD:-false}" = "true" ]; then
        echo "==> Building Spigot ${SPIGOT_VERSION} via BuildTools (this takes a few minutes)..."
        BUILD_DIR=$(mktemp -d)
        cd "$BUILD_DIR"
        java -jar /buildtools/BuildTools.jar --rev "${SPIGOT_VERSION}" --compile SPIGOT
        cp "${BUILD_DIR}/spigot-${SPIGOT_VERSION}.jar" "$SPIGOT_JAR"
        rm -rf "$BUILD_DIR"
        cd /server
    fi

    echo "==> Starting Minecraft server ${SPIGOT_VERSION}..."
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
