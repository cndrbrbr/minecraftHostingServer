#!/bin/bash
# configure-memory.sh — First-time setup: choose deployment mode,
# detect host RAM, size JVM heaps, write docker-compose.yml,
# and generate per-server start scripts.
#
# Usage:
#   ./configure-memory.sh --standalone    # 5 servers, direct ports, no proxy
#   ./configure-memory.sh --bungeecord    # BungeeCord proxy + lobby + 5 servers
#   ./configure-memory.sh                 # interactive prompt

set -e
cd "$(dirname "$0")"

# ── Parse mode ────────────────────────────────────────────────
MODE=""
for arg in "$@"; do
    case "$arg" in
        --standalone)  MODE="standalone" ;;
        --bungeecord)  MODE="bungeecord" ;;
    esac
done

if [ -z "$MODE" ]; then
    echo "Select deployment mode:"
    echo "  1) standalone   — 5 servers on direct ports 25565–25569, no proxy"
    echo "  2) bungeecord   — BungeeCord proxy + lobby + 5 servers (single port 25565)"
    echo ""
    read -rp "Mode [1/2]: " CHOICE
    case "$CHOICE" in
        1) MODE="standalone" ;;
        2) MODE="bungeecord" ;;
        *) echo "Invalid choice. Use 1 or 2."; exit 1 ;;
    esac
fi

# ── Mode-specific settings ────────────────────────────────────
if [ "$MODE" = "bungeecord" ]; then
    NUM_SERVERS=6          # lobby + mc1–mc5
    BUNGEE_RESERVE_MB=512  # fixed for BungeeCord proxy
    COMPOSE_TPL="docker-compose.bungeecord.yml"
else
    NUM_SERVERS=5          # mc1–mc5 only
    BUNGEE_RESERVE_MB=0
    COMPOSE_TPL="docker-compose.standalone.yml"
fi

# ── RAM calculation ───────────────────────────────────────────
TOTAL_MB=$(awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo)
RESERVE_15PCT=$(( TOTAL_MB * 15 / 100 ))
OS_RESERVE_MB=$(( RESERVE_15PCT > 2048 ? RESERVE_15PCT : 2048 ))
AVAILABLE_MB=$(( TOTAL_MB - OS_RESERVE_MB - BUNGEE_RESERVE_MB ))
PER_SERVER_MB=$(( AVAILABLE_MB / NUM_SERVERS ))

# Round down to the nearest 256 MB
PER_SERVER_MB=$(( (PER_SERVER_MB / 256) * 256 ))

if [ "$PER_SERVER_MB" -lt 512 ]; then
    echo "ERROR: Only ${PER_SERVER_MB} MB available per server after OS reservation."
    echo "       At least $(( OS_RESERVE_MB + BUNGEE_RESERVE_MB + 512 * NUM_SERVERS )) MB total RAM is recommended."
    exit 1
fi

MIN_MB=$(( PER_SERVER_MB / 2 ))
[ "$MIN_MB" -lt 256 ] && MIN_MB=256
MIN_MB=$(( (MIN_MB / 256) * 256 ))

fmt() {
    local mb=$1
    if [ $(( mb % 1024 )) -eq 0 ] && [ "$mb" -ge 1024 ]; then
        echo "$(( mb / 1024 ))G"
    else
        echo "${mb}M"
    fi
}

MEM_MAX=$(fmt "$PER_SERVER_MB")
MEM_MIN=$(fmt "$MIN_MB")

# ── Print plan ────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║         Memory configuration                     ║"
echo "╠══════════════════════════════════════════════════╣"
printf "║  Mode               : %-26s ║\n" "$MODE"
printf "║  Total RAM          : %6d MB                  ║\n" "$TOTAL_MB"
printf "║  OS reservation     : %6d MB                  ║\n" "$OS_RESERVE_MB"
[ "$BUNGEE_RESERVE_MB" -gt 0 ] && \
printf "║  BungeeCord         : %6d MB  (fixed)         ║\n" "$BUNGEE_RESERVE_MB"
printf "║  Available for MC   : %6d MB  (%d servers)    ║\n" "$AVAILABLE_MB" "$NUM_SERVERS"
printf "║  Per server (max)   : %6d MB  (%s)           \n"   "$PER_SERVER_MB" "$MEM_MAX"
printf "║  Per server (min)   : %6d MB  (%s)           \n"   "$MIN_MB"        "$MEM_MIN"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Write docker-compose.yml from the chosen template ────────
cp "$COMPOSE_TPL" docker-compose.yml
sed -i \
    -e "s/MC_MEM_MIN: \"[^\"]*\"/MC_MEM_MIN: \"${MEM_MIN}\"/g" \
    -e "s/MC_MEM_MAX: \"[^\"]*\"/MC_MEM_MAX: \"${MEM_MAX}\"/g" \
    docker-compose.yml

echo "✓ docker-compose.yml written from ${COMPOSE_TPL}"
echo "✓ Memory values updated  (MC_MEM_MIN=${MEM_MIN}  MC_MEM_MAX=${MEM_MAX})"
echo ""

# ── Generate per-server start scripts ────────────────────────
SSH_PORTS=(2221 2222 2223 2224 2225)
MC_PORTS=(25565 25566 25567 25568 25569)

if [ "$MODE" = "bungeecord" ]; then
    cat > "start-bungee.sh" <<SCRIPT
#!/bin/bash
# start-bungee.sh — Start / restart the BungeeCord proxy
cd "\$(dirname "\$0")"
echo "==> (Re)starting BungeeCord proxy..."
docker compose up -d --no-deps bungee
echo "==> BungeeCord is up on port 25565."
SCRIPT
    chmod +x "start-bungee.sh"
    echo "✓ start-bungee.sh generated"

    cat > "start-lobby.sh" <<SCRIPT
#!/bin/bash
# start-lobby.sh — Start / restart the lobby server
# Memory: max=${MEM_MAX} / min=${MEM_MIN}
cd "\$(dirname "\$0")"
echo "==> (Re)starting lobby  [max=${MEM_MAX}, min=${MEM_MIN}]..."
docker compose up -d --no-deps lobby
echo "==> lobby is up."
SCRIPT
    chmod +x "start-lobby.sh"
    echo "✓ start-lobby.sh generated"
else
    rm -f start-bungee.sh start-lobby.sh
fi

for i in 1 2 3 4 5; do
    idx=$(( i - 1 ))
    script="start-mc${i}.sh"
    if [ "$MODE" = "bungeecord" ]; then
        MC_LINE="echo \"    Connect via BungeeCord on port 25565\""
    else
        MC_LINE="echo \"    Minecraft : <host>:${MC_PORTS[$idx]}\""
    fi
    cat > "$script" <<SCRIPT
#!/bin/bash
# start-mc${i}.sh — Start / restart Minecraft server ${i}
# Memory: max=${MEM_MAX} / min=${MEM_MIN}  (set by configure-memory.sh)
# SSH port: ${SSH_PORTS[$idx]}
cd "\$(dirname "\$0")"
echo "==> (Re)starting mc${i}  [max=${MEM_MAX}, min=${MEM_MIN}]..."
docker compose up -d --no-deps mc${i}
echo "==> mc${i} is up."
${MC_LINE}
echo "    SSH : <host>:${SSH_PORTS[$idx]}"
SCRIPT
    chmod +x "$script"
    echo "✓ ${script} generated"
done

echo ""
echo "Mode: ${MODE}"
echo "Next steps:"
echo "  1. ./setup-keys.sh         (generate SSH keys for students)"
echo "  2. docker compose up -d    (start everything)"
