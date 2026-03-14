#!/bin/bash
# configure-memory.sh — Detect host RAM, calculate equal JVM heap per server,
# update docker-compose.yml, and generate per-server start scripts.
#
# Run once after git clone, before "docker compose up":
#   chmod +x configure-memory.sh && ./configure-memory.sh
#
# Re-run any time you change the hardware or want to adjust the reservation.

set -e
cd "$(dirname "$0")"

NUM_SERVERS=5

# ── How much RAM to reserve for the OS, Docker daemon, SSH, etc. ─────────────
# Default: 2 GB or 15% of total RAM, whichever is larger.
TOTAL_MB=$(awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo)
RESERVE_15PCT=$(( TOTAL_MB * 15 / 100 ))
OS_RESERVE_MB=$(( RESERVE_15PCT > 2048 ? RESERVE_15PCT : 2048 ))

AVAILABLE_MB=$(( TOTAL_MB - OS_RESERVE_MB ))
PER_SERVER_MB=$(( AVAILABLE_MB / NUM_SERVERS ))

# Round down to the nearest 256 MB for clean values
PER_SERVER_MB=$(( (PER_SERVER_MB / 256) * 256 ))

if [ "$PER_SERVER_MB" -lt 512 ]; then
    echo "ERROR: Only ${PER_SERVER_MB} MB available per server after OS reservation."
    echo "       At least $(( OS_RESERVE_MB + 512 * NUM_SERVERS )) MB total RAM is recommended."
    exit 1
fi

# Min heap = 50% of max, floored at 256 MB
MIN_MB=$(( PER_SERVER_MB / 2 ))
[ "$MIN_MB" -lt 256 ] && MIN_MB=256
MIN_MB=$(( (MIN_MB / 256) * 256 ))

# ── Format helper (use G when evenly divisible, else M) ──────────────────────
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

# ── Print plan ────────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════╗"
echo "║         Memory configuration                     ║"
echo "╠══════════════════════════════════════════════════╣"
printf "║  Total RAM          : %6d MB                  ║\n" "$TOTAL_MB"
printf "║  OS reservation     : %6d MB                  ║\n" "$OS_RESERVE_MB"
printf "║  Available for MC   : %6d MB                  ║\n" "$AVAILABLE_MB"
printf "║  Per server (max)   : %6d MB  (%s)           \n"   "$PER_SERVER_MB" "$MEM_MAX"
printf "║  Per server (min)   : %6d MB  (%s)           \n"   "$MIN_MB"        "$MEM_MIN"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Update docker-compose.yml ─────────────────────────────────────────────────
sed -i \
    -e "s/MC_MEM_MIN: \"[^\"]*\"/MC_MEM_MIN: \"${MEM_MIN}\"/g" \
    -e "s/MC_MEM_MAX: \"[^\"]*\"/MC_MEM_MAX: \"${MEM_MAX}\"/g" \
    docker-compose.yml

echo "✓ docker-compose.yml updated  (MC_MEM_MIN=${MEM_MIN}  MC_MEM_MAX=${MEM_MAX})"

# ── Generate per-server start scripts ────────────────────────────────────────
MC_PORTS=(25565 25566 25567 25568 25569)
SSH_PORTS=(2221  2222  2223  2224  2225)

for i in 1 2 3 4 5; do
    idx=$(( i - 1 ))
    script="start-mc${i}.sh"
    cat > "$script" <<SCRIPT
#!/bin/bash
# start-mc${i}.sh — Start / restart Minecraft server ${i}
# Memory: max=${MEM_MAX} / min=${MEM_MIN}  (set by configure-memory.sh)
# MC port : ${MC_PORTS[$idx]}
# SSH port: ${SSH_PORTS[$idx]}
cd "\$(dirname "\$0")"
echo "==> (Re)starting mc${i}  [max=${MEM_MAX}, min=${MEM_MIN}]..."
docker compose up -d --no-deps mc${i}
echo "==> mc${i} is up."
echo "    Minecraft : <host>:${MC_PORTS[$idx]}"
echo "    SSH       : <host>:${SSH_PORTS[$idx]}"
SCRIPT
    chmod +x "$script"
    echo "✓ ${script} generated"
done

echo ""
echo "Next steps:"
echo "  1. Run ./setup-keys.sh   (if you haven't already)"
echo "  2. Run docker compose up -d"
echo "  Or start individual servers with ./start-mc1.sh … ./start-mc5.sh"
