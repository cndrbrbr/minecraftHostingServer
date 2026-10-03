#!/bin/bash
set -e

DEFAULT_VERSION=${SPIGOT_VERSION:-26.3}

# ── Server type ──────────────────────────────────────────────
# spigot (default) — BuildTools compiles Spigot from source on the volume,
#                     as it always has.
# custom            — the "bring your own server" exception (e.g. Forge,
#                      Fabric, vanilla, a specific fork, …). Nothing is
#                      managed: the student uploads their own server files
#                      plus an executable /server/start.sh, and this script
#                      just runs it. version/restore are not available in
#                      this mode — see README.
SERVER_TYPE="${MC_SERVER_TYPE:-spigot}"
case "$SERVER_TYPE" in
    spigot|custom) ;;
    *)
        echo "==> WARNING: unknown MC_SERVER_TYPE '$SERVER_TYPE' — falling back to 'spigot'."
        SERVER_TYPE="spigot"
        ;;
esac

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

# Record the server type on the volume so mc-version.sh / mc-restore.sh /
# mc-adduser.sh (which run later via sudo, with a reset environment) can
# read it back without relying on env vars surviving sudo.
echo "$SERVER_TYPE" > /server/.servertype

if [ "$SERVER_TYPE" != "custom" ]; then
    # ── Volume directory structure (managed Spigot layout) ───────
    mkdir -p /server/data/cfg /server/data/plugins /server/data/worlds

    # ── Plugin: always update so image rebuilds take effect ──────
    cp /server-base/plugins/*.jar /server/data/plugins/

    # ── PrometheusExporter config: copy on first run only ────────
    mkdir -p /server/data/plugins/PrometheusExporter
    [ -f /server/data/plugins/PrometheusExporter/config.yml ] || \
        cp /server-base/plugins/PrometheusExporter/config.yml /server/data/plugins/PrometheusExporter/config.yml

    # ── Config: copy to volume on first run only ─────────────────
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

    # server.properties: online-mode abhängig von BungeeCord-Modus
    # Mit BungeeCord: online-mode=false (BungeeCord übernimmt die Authentifizierung)
    # Ohne BungeeCord: online-mode=true
    if [ "${MC_BUNGEECORD:-false}" = "true" ]; then
        sed -i 's/online-mode=true/online-mode=false/' /server/data/cfg/server.properties
    else
        sed -i 's/online-mode=false/online-mode=true/' /server/data/cfg/server.properties
    fi

    mkdir -p /server/bundler /server/logs /server/crash-reports
else
    # ── Custom mode: /server itself can't be made writable (see below), so
    # pre-create the entry point plus the directory names most server
    # software (Forge, Fabric, vanilla, …) expects at its root. If a
    # student's server needs another top-level name that doesn't exist yet,
    # the admin creates it once with:
    #   docker compose exec <name> mkdir /server/<dir>
    #   docker compose exec <name> chown mc-sftp:mc-sftp /server/<dir>
    if [ ! -f /server/start.sh ]; then
        cat > /server/start.sh <<'STARTSH'
#!/bin/bash
# Replace this with the command that launches your server, e.g.:
#   exec java -Xms1G -Xmx2G -jar server.jar --nogui
echo "start.sh has not been set up yet — edit it to launch your server."
exit 1
STARTSH
    fi
    chmod +x /server/start.sh
    mkdir -p /server/mods /server/config /server/libraries /server/world /server/logs /server/crash-reports
fi

[ -f /server/eula.txt ] || echo "eula=true" > /server/eula.txt

# Pre-create every root-level file a vanilla-format server (Spigot, and
# also Forge/vanilla for custom-type students) writes to on its own —
# /server itself can't be group-writable (see below), so any filename the
# server process wants to create fresh has to already exist.
[ -f /server/whitelist.json ]      || echo '[]' > /server/whitelist.json
[ -f /server/ops.json ]            || echo '[]' > /server/ops.json
[ -f /server/banned-players.json ] || echo '[]' > /server/banned-players.json
[ -f /server/banned-ips.json ]     || echo '[]' > /server/banned-ips.json
[ -f /server/usercache.json ]      || echo '[]' > /server/usercache.json
[ -f /server/help.yml ]            || touch /server/help.yml
[ -f /server/permissions.yml ]     || touch /server/permissions.yml

# ── Permissions ────────────────────────────────────────────────
# /server itself must stay root:root 755 — OpenSSH's ChrootDirectory
# refuses to start sshd otherwise. This is the one directory a student
# can never get write access to. Everything else under /server is
# handed over so students have full control of their own server.
chown root:root /server
chmod 755 /server
find /server -mindepth 1 -exec chown mc-sftp:mc-sftp {} +
# Host keys must stay root-owned and unreadable by anyone else.
chown root:root /server/ssh_host_ed25519_key /server/ssh_host_rsa_key
chmod 600 /server/ssh_host_ed25519_key /server/ssh_host_rsa_key

if [ "$SERVER_TYPE" != "custom" ]; then
    # ── watch_copy: push image config changes to volume at runtime
    /watch_copy.sh /server-base/server.properties /server/data/cfg/server.properties &
fi

# ── Start server with auto-restart loop ─────────────────────
# Exits only when /server/.shutdown exists (docker stop).
# A SIGTERM from mc-stop.sh causes a non-zero exit → paused (not restarted)
# when /server/.stopped is present. mc-start.sh removes .stopped to resume.
cd /server
echo "==> Minecraft server loop starting (type: ${SERVER_TYPE})..."

while true; do
    # Wait while the student has manually stopped the server
    while [ -f /server/.stopped ]; do
        sleep 2
    done

    if [ "$SERVER_TYPE" = "custom" ]; then
        if [ ! -f /server/start.sh ]; then
            echo "==> No /server/start.sh found. Upload your server files and an"
            echo "==> executable start.sh via SFTP, then run 'start' again. Waiting..."
            touch /server/.stopped
            continue
        fi
        chmod +x /server/start.sh
        echo "==> Starting custom server via /server/start.sh ..."
        runuser -u mc-sftp -- /server/start.sh &
        PID=$!
    else
        # Re-read version on every start so version changes take effect
        # without restarting the container
        VERSION=${DEFAULT_VERSION}
        if [ -f /server/.version ]; then
            VERSION=$(cat /server/.version | tr -d '[:space:]')
        fi
        SERVER_JAR="/server/spigot-${VERSION}.jar"

        # Build Spigot if this version is not cached on the volume yet
        if [ ! -f "$SERVER_JAR" ] || [ "${FORCE_BUILD:-false}" = "true" ]; then
            echo "==> Building Spigot ${VERSION} via BuildTools (this takes a few minutes)..."
            BUILD_DIR=$(mktemp -d)
            cd "$BUILD_DIR"
            if ! java -jar /buildtools/BuildTools.jar --rev "${VERSION}" --compile SPIGOT; then
                echo "==> ERROR: BuildTools failed for version ${VERSION}. Set a valid"
                echo "==> version with 'version <x.x.x>' and run 'start' again. Waiting..."
                cd /server
                rm -rf "$BUILD_DIR"
                touch /server/.stopped
                continue
            fi
            # BuildTools names the jar after the version it actually resolved
            # to (e.g. requesting "26.1" produces spigot-26.1.2.jar), which
            # doesn't always match what was requested — find whatever it
            # produced instead of assuming the exact filename.
            BUILT_JAR=$(ls "${BUILD_DIR}"/spigot-*.jar 2>/dev/null | head -n1)
            if [ -z "$BUILT_JAR" ]; then
                echo "==> ERROR: BuildTools did not produce a jar for version ${VERSION}."
                echo "==> Set a valid version with 'version <x.x.x>' and run 'start' again. Waiting..."
                cd /server
                rm -rf "$BUILD_DIR"
                touch /server/.stopped
                continue
            fi
            cp "$BUILT_JAR" "$SERVER_JAR"
            rm -rf "$BUILD_DIR"
            cd /server
        fi

        chown mc-sftp:mc-sftp "$SERVER_JAR"

        # ── script4kids (jsmn): pick the jar built for this version ──
        # A plugin built for a newer API than the server refuses to load, so
        # servers on 26.3+ get the 26.3 build and everything older the 1.21.11
        # build (which needs at least 1.21.11 itself).
        if [ "$(printf '%s\n%s\n' 26.3 "$VERSION" | sort -V | head -n1)" = "26.3" ]; then
            JSMN_MC=26.3
        else
            JSMN_MC=1.21.11
        fi
        rm -f /server/data/plugins/jsmn-*.jar
        cp /server-base/plugins-mc/"$JSMN_MC"/jsmn-*.jar /server/data/plugins/
        chown mc-sftp:mc-sftp /server/data/plugins/jsmn-*.jar

        echo "==> Starting Minecraft server ${VERSION}..."
        runuser -u mc-sftp -- java \
            -Xms${MC_MEM_MIN:-512M} \
            -Xmx${MC_MEM_MAX:-1G} \
            -Dpolyglot.engine.WarnInterpreterOnly=false \
            --add-opens=java.base/java.lang=ALL-UNNAMED \
            --add-opens=java.base/java.lang.invoke=ALL-UNNAMED \
            --add-opens=java.base/java.lang.ref=ALL-UNNAMED \
            --add-opens=java.base/java.nio=ALL-UNNAMED \
            --add-opens=java.base/java.util=ALL-UNNAMED \
            -jar "$SERVER_JAR" \
            --config        "./data/cfg/server.properties" \
            --bukkit-settings  "./data/cfg/bukkit.yml" \
            --spigot-settings  "./data/cfg/spigot.yml" \
            --commands-settings "./data/cfg/commands.yml" \
            --plugins       "./data/plugins" \
            --world-dir     "./data/worlds" \
            --level-name    "${MC_LEVELNAME:-world}" \
            --port          "${MC_PORT:-25565}" \
            nogui &
        PID=$!
    fi

    echo "$PID" > /server/.pid
    wait "$PID" || true
    rm -f /server/.pid

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
