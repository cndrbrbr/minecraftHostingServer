#!/bin/bash
# setup.sh — First-time setup and re-configuration of the hosting server.
#
# Chooses the deployment mode and number of servers, sizes the JVM heaps from
# the host RAM, generates SSH keys, and writes docker-compose.yml,
# servers.json / servers.txt, bungee/config.yml and the start-*.sh scripts.
# Optionally sets up the admin page (web UI with e-mail login code).
#
# Usage:
#   ./setup.sh --bungeecord --servers 5 \
#              --domain admin.example.de --admin-email teacher@example.de \
#              --mail-from tech@example.de --smtp-host mail.example.de
#
# Options:
#   --standalone | --bungeecord   deployment mode (asked interactively if missing)
#   --servers N                   number of student servers (default 5)
#   --no-adminpanel               no admin page (setup as before)
#   --domain HOST                 address of the admin page, e.g. admin.example.de
#   --admin-email MAIL            first admin; gets the first invitation
#   --mail-from MAIL              sender of login codes and invitations
#   --smtp-host HOST              SMTP server, e.g. mail.example.de
#   --smtp-port PORT              default 587
#   --smtp-user USER              default: --mail-from
#   --smtp-tls starttls|ssl|none  default starttls (ssl if port 465)
#   --smtp-password-file FILE     read the SMTP password from FILE
#                                 (otherwise $SMTP_PASSWORD or a hidden prompt)
#   --proxy own|caddy-proxy|none  HTTPS: own Caddy (default), the shared
#                                 caddy-proxy stack, or none (plain HTTP on --admin-port)
#   --admin-port PORT             host port for --proxy none (default 8080)
#   --mail-test                   don't send real mail: run Mailpit and show all
#                                 mails at http://<host>:8025 (for testing)
#
# Settings are stored in .env; on a re-run only changed options need to be
# given. Existing SSH keys and the SMTP password are kept.
#
# The SMTP password is never taken from the command line (it would end up in
# the shell history and the process list).

set -euo pipefail
cd "$(dirname "$0")"

die() { echo "ERROR: $*" >&2; exit 1; }

touch .env
chmod 600 .env
env_get() { grep -E "^$1=" .env | tail -n1 | cut -d= -f2- || true; }
env_set() {
    K="$1" V="$2" awk 'BEGIN { k = ENVIRON["K"]; v = ENVIRON["V"]; done = 0 }
        index($0, k "=") == 1 { print k "=" v; done = 1; next } { print }
        END { if (!done) print k "=" v }' .env > .env.tmp
    mv .env.tmp .env
    chmod 600 .env
}

# ── Defaults: previous run (.env), then built-in ──────────────
MODE=$(env_get SETUP_MODE)
SERVERS=$(env_get SETUP_SERVERS); SERVERS=${SERVERS:-5}
ADMINPANEL=$(env_get SETUP_ADMINPANEL); ADMINPANEL=${ADMINPANEL:-true}
DOMAIN=$(env_get ADMIN_DOMAIN)
ADMIN_EMAIL=$(env_get ADMIN_EMAIL)
MAIL_FROM=$(env_get MAIL_FROM)
SMTP_HOST=$(env_get SMTP_HOST)
SMTP_PORT=$(env_get SMTP_PORT); SMTP_PORT=${SMTP_PORT:-587}
SMTP_USER=$(env_get SMTP_USER)
SMTP_TLS=$(env_get SMTP_TLS)
PROXY=$(env_get SETUP_PROXY); PROXY=${PROXY:-own}
ADMIN_PORT=$(env_get ADMIN_PORT); ADMIN_PORT=${ADMIN_PORT:-8080}
MAIL_TEST=$(env_get SETUP_MAIL_TEST); MAIL_TEST=${MAIL_TEST:-false}
PASSWORD_FILE=""

# ── Command line ──────────────────────────────────────────────
need_arg() { [ $# -ge 2 ] && [ -n "$2" ] || die "$1 needs a value."; }
while [ $# -gt 0 ]; do
    case "$1" in
        --standalone)          MODE=standalone ;;
        --bungeecord)          MODE=bungeecord ;;
        --servers)             need_arg "$@"; SERVERS="$2"; shift ;;
        --no-adminpanel)       ADMINPANEL=false ;;
        --adminpanel)          ADMINPANEL=true ;;
        --domain)              need_arg "$@"; DOMAIN="$2"; ADMINPANEL=true; shift ;;
        --admin-email)         need_arg "$@"; ADMIN_EMAIL="$2"; shift ;;
        --mail-from)           need_arg "$@"; MAIL_FROM="$2"; shift ;;
        --smtp-host)           need_arg "$@"; SMTP_HOST="$2"; shift ;;
        --smtp-port)           need_arg "$@"; SMTP_PORT="$2"; shift ;;
        --smtp-user)           need_arg "$@"; SMTP_USER="$2"; shift ;;
        --smtp-tls)            need_arg "$@"; SMTP_TLS="$2"; shift ;;
        --smtp-password-file)  need_arg "$@"; PASSWORD_FILE="$2"; shift ;;
        --smtp-password)       die "the SMTP password must not be given on the command line — use --smtp-password-file, \$SMTP_PASSWORD or the prompt." ;;
        --proxy)               need_arg "$@"; PROXY="$2"; shift ;;
        --admin-port)          need_arg "$@"; ADMIN_PORT="$2"; shift ;;
        --mail-test)           MAIL_TEST=true ;;
        --no-mail-test)        MAIL_TEST=false ;;
        -h|--help)             sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)                     die "unknown option '$1' (see --help)." ;;
    esac
    shift
done

INTERACTIVE=false
[ -t 0 ] && INTERACTIVE=true
ask() {  # <variable> <prompt>
    $INTERACTIVE || return 0
    local value
    read -rp "$2: " value
    printf -v "$1" '%s' "$value"
}

if [ -z "$MODE" ]; then
    $INTERACTIVE || die "deployment mode missing: --standalone or --bungeecord."
    echo "Select deployment mode:"
    echo "  1) standalone   — servers on direct ports 25565…, no proxy"
    echo "  2) bungeecord   — BungeeCord proxy + lobby + servers (single port 25565)"
    read -rp "Mode [1/2]: " CHOICE
    case "$CHOICE" in
        1) MODE=standalone ;;
        2) MODE=bungeecord ;;
        *) die "invalid choice." ;;
    esac
fi

[[ "$SERVERS" =~ ^[0-9]+$ ]] && [ "$SERVERS" -ge 1 ] && [ "$SERVERS" -le 30 ] || die "--servers must be 1–30."
[ "$MODE" = standalone ] && [ "$SERVERS" -gt 10 ] && die "standalone mode supports up to 10 servers (ports 25565–25574); use --bungeecord for more."

if [ "$ADMINPANEL" = true ]; then
    [ -n "$DOMAIN" ] || ask DOMAIN "Address of the admin page (e.g. admin.example.de)"
    [ -n "$ADMIN_EMAIL" ] || ask ADMIN_EMAIL "E-mail address of the first admin"
    if [ "$MAIL_TEST" != true ]; then
        [ -n "$MAIL_FROM" ] || ask MAIL_FROM "Sender address for mails (e.g. tech@example.de)"
        [ -n "$SMTP_HOST" ] || ask SMTP_HOST "SMTP server (e.g. mail.example.de)"
    fi
    missing=()
    [ -n "$DOMAIN" ] || missing+=(--domain)
    [ -n "$ADMIN_EMAIL" ] || missing+=(--admin-email)
    if [ "$MAIL_TEST" != true ]; then
        [ -n "$MAIL_FROM" ] || missing+=(--mail-from)
        [ -n "$SMTP_HOST" ] || missing+=(--smtp-host)
    fi
    [ ${#missing[@]} -eq 0 ] || die "missing for the admin page: ${missing[*]} (or use --no-adminpanel)."

    [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die "--domain must be a host name like admin.example.de."
    [[ "$ADMIN_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || die "--admin-email is not an e-mail address."
    case "$PROXY" in own|caddy-proxy|none) ;; *) die "--proxy must be own, caddy-proxy or none." ;; esac
    [[ "$ADMIN_PORT" =~ ^[0-9]+$ ]] || die "--admin-port must be a number."

    if [ "$MAIL_TEST" = true ]; then
        MAIL_FROM=${MAIL_FROM:-adminpage@test.local}
        SMTP_HOST=mailpit; SMTP_PORT=1025; SMTP_USER=""; SMTP_TLS=none
    else
        SMTP_USER=${SMTP_USER:-$MAIL_FROM}
        if [ -z "$SMTP_TLS" ]; then
            if [ "$SMTP_PORT" = 465 ]; then SMTP_TLS=ssl; else SMTP_TLS=starttls; fi
        fi
        case "$SMTP_TLS" in starttls|ssl|none) ;; *) die "--smtp-tls must be starttls, ssl or none." ;; esac

        # SMTP password → secrets/smtp_password (mounted into the admin page)
        mkdir -p secrets && chmod 700 secrets
        if [ -n "$PASSWORD_FILE" ]; then
            [ -r "$PASSWORD_FILE" ] || die "cannot read $PASSWORD_FILE."
            head -n1 "$PASSWORD_FILE" | tr -d '\r\n' > secrets/smtp_password
        elif [ -n "${SMTP_PASSWORD:-}" ]; then
            printf '%s' "$SMTP_PASSWORD" > secrets/smtp_password
        elif [ ! -s secrets/smtp_password ]; then
            $INTERACTIVE || die "SMTP password missing: use --smtp-password-file or \$SMTP_PASSWORD."
            read -rsp "SMTP password for $SMTP_USER: " pw; echo
            printf '%s' "$pw" > secrets/smtp_password
            unset pw
        fi
        chmod 600 secrets/smtp_password
    fi
fi

# ── RAM calculation ───────────────────────────────────────────
if [ "$MODE" = bungeecord ]; then
    NUM_JVMS=$(( SERVERS + 1 ))   # lobby + mc1…mcN
    BUNGEE_RESERVE_MB=512
else
    NUM_JVMS=$SERVERS
    BUNGEE_RESERVE_MB=0
fi
PANEL_RESERVE_MB=0
[ "$ADMINPANEL" = true ] && PANEL_RESERVE_MB=384   # admin page + Caddy/Mailpit

TOTAL_MB=$(awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo)
RESERVE_15PCT=$(( TOTAL_MB * 15 / 100 ))
OS_RESERVE_MB=$(( RESERVE_15PCT > 2048 ? RESERVE_15PCT : 2048 ))
AVAILABLE_MB=$(( TOTAL_MB - OS_RESERVE_MB - BUNGEE_RESERVE_MB - PANEL_RESERVE_MB ))
PER_SERVER_MB=$(( AVAILABLE_MB / NUM_JVMS ))
PER_SERVER_MB=$(( (PER_SERVER_MB / 256) * 256 ))
if [ "$PER_SERVER_MB" -lt 512 ]; then
    die "only ${PER_SERVER_MB} MB per server left after reservations — use fewer servers (at least $(( OS_RESERVE_MB + BUNGEE_RESERVE_MB + PANEL_RESERVE_MB + 512 * NUM_JVMS )) MB RAM needed for $SERVERS)."
fi
MIN_MB=$(( PER_SERVER_MB / 2 )); [ "$MIN_MB" -lt 256 ] && MIN_MB=256
MIN_MB=$(( (MIN_MB / 256) * 256 ))
fmt() { local mb=$1; if [ $(( mb % 1024 )) -eq 0 ]; then echo "$(( mb / 1024 ))G"; else echo "${mb}M"; fi; }
MEM_MAX=$(fmt "$PER_SERVER_MB")
MEM_MIN=$(fmt "$MIN_MB")

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║         Hosting server configuration             ║"
echo "╠══════════════════════════════════════════════════╣"
printf "║  Mode               : %-26s ║\n" "$MODE"
printf "║  Student servers    : %-26s ║\n" "$SERVERS"
printf "║  Admin page         : %-26s ║\n" "$([ "$ADMINPANEL" = true ] && echo "$DOMAIN" || echo off)"
printf "║  Total RAM          : %6d MB                  ║\n" "$TOTAL_MB"
printf "║  OS reservation     : %6d MB                  ║\n" "$OS_RESERVE_MB"
[ "$BUNGEE_RESERVE_MB" -gt 0 ] && printf "║  BungeeCord         : %6d MB                  ║\n" "$BUNGEE_RESERVE_MB"
[ "$PANEL_RESERVE_MB" -gt 0 ] && printf "║  Admin page         : %6d MB                  ║\n" "$PANEL_RESERVE_MB"
printf "║  Per server (max)   : %6d MB  (%-5s)         ║\n" "$PER_SERVER_MB" "$MEM_MAX"
printf "║  Per server (min)   : %6d MB  (%-5s)         ║\n" "$MIN_MB" "$MEM_MIN"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── SSH keys ──────────────────────────────────────────────────
mkdir -p keys
for i in $(seq 1 "$SERVERS"); do
    dir="keys/mc${i}"
    mkdir -p "$dir"
    [ -f "$dir/sftp_key" ] || { ssh-keygen -q -t ed25519 -f "$dir/sftp_key" -N '' -C "mc${i}-sftp"; echo "✓ SFTP key for mc${i} generated"; }
    [ -f "$dir/ctrl_key" ] || { ssh-keygen -q -t ed25519 -f "$dir/ctrl_key" -N '' -C "mc${i}-ctrl"; echo "✓ control key for mc${i} generated"; }
    env_set "MC${i}_SFTP_PUBKEY" "$(cat "$dir/sftp_key.pub")"
    env_set "MC${i}_CTRL_PUBKEY" "$(cat "$dir/ctrl_key.pub")"
done

# ── Store settings ────────────────────────────────────────────
env_set SETUP_MODE "$MODE"
env_set SETUP_SERVERS "$SERVERS"
env_set SETUP_ADMINPANEL "$ADMINPANEL"
if [ "$ADMINPANEL" = true ]; then
    env_set ADMIN_DOMAIN "$DOMAIN"
    env_set ADMIN_EMAIL "$ADMIN_EMAIL"
    env_set MAIL_FROM "$MAIL_FROM"
    env_set SMTP_HOST "$SMTP_HOST"
    env_set SMTP_PORT "$SMTP_PORT"
    env_set SMTP_USER "$SMTP_USER"
    env_set SMTP_TLS "$SMTP_TLS"
    env_set SETUP_PROXY "$PROXY"
    env_set ADMIN_PORT "$ADMIN_PORT"
    env_set SETUP_MAIL_TEST "$MAIL_TEST"
fi

# ── servers.json / servers.txt ────────────────────────────────
{
    echo "{"
    echo "  \"mode\": \"$MODE\","
    echo "  \"servers\": ["
    for i in $(seq 1 "$SERVERS"); do
        mc_port=null; [ "$MODE" = standalone ] && mc_port=$(( 25564 + i ))
        sep=","; [ "$i" -eq "$SERVERS" ] && sep=""
        echo "    {\"name\": \"mc${i}\", \"host\": \"mc${i}\", \"public_ssh_port\": $(( 2220 + i )), \"public_mc_port\": ${mc_port}}${sep}"
    done
    echo "  ]"
    echo "}"
} > servers.json
{
    [ "$MODE" = bungeecord ] && echo lobby
    for i in $(seq 1 "$SERVERS"); do echo "mc${i}"; done
} > servers.txt
echo "✓ servers.json / servers.txt written"

# ── docker-compose.yml ────────────────────────────────────────
emit_server() {  # <i>
    local i=$1
    cat <<YAML

  mc${i}:
    build: ./spigot
    container_name: mc${i}
    restart: unless-stopped
    stdin_open: true
    tty: true
    ports:
YAML
    [ "$MODE" = standalone ] && echo "      - \"$(( 25564 + i )):25565\"   # Minecraft — student ${i}"
    cat <<YAML
      - "$(( 2220 + i )):22"       # SSH (FileZilla + PuTTY) — student ${i}
      - "$(( 9940 + i )):9940"     # Prometheus exporter — student ${i}
    environment:
      MC_NAME: mc${i}
      MC_LEVELNAME: world
      MC_PORT: "25565"
YAML
    [ "$MODE" = bungeecord ] && echo "      MC_BUNGEECORD: \"true\""
    cat <<YAML
      MC_MEM_MIN: "${MEM_MIN}"
      MC_MEM_MAX: "${MEM_MAX}"
      FORCE_BUILD: "false"
      MC_SERVER_TYPE: "spigot"
      BACKUP_URL: ""
      SFTP_PUBKEY: "\${MC${i}_SFTP_PUBKEY}"
      CTRL_PUBKEY: "\${MC${i}_CTRL_PUBKEY}"
    volumes:
      - mc${i}_data:/server
    networks:
      - workshop
YAML
}

{
    echo "# Generated by setup.sh — re-run it instead of editing by hand"
    echo "# (mode: ${MODE}, servers: ${SERVERS}, admin page: ${ADMINPANEL})."
    echo "services:"
    if [ "$MODE" = bungeecord ]; then
        cat <<YAML

  # ── BungeeCord proxy: single public entry point for all players ──
  bungee:
    build: ./bungee
    container_name: bungee
    restart: unless-stopped
    stdin_open: true
    tty: true
    ports:
      - "25565:25565"   # only public Minecraft port
    environment:
      BUNGEE_MEM_MAX: "512M"
    volumes:
      - bungee_data:/bungee
    networks:
      - workshop

  # ── Lobby: players land here first (admin-managed, no SSH) ──
  lobby:
    build: ./spigot
    container_name: lobby
    restart: unless-stopped
    stdin_open: true
    tty: true
    ports:
      - "9940:9940"     # Prometheus exporter — lobby
    environment:
      MC_LEVELNAME: world
      MC_MAXPLAYERS: "30"
      MC_PORT: "25565"
      MC_BUNGEECORD: "true"
      MC_MEM_MIN: "${MEM_MIN}"
      MC_MEM_MAX: "${MEM_MAX}"
      FORCE_BUILD: "false"
      MC_SERVER_TYPE: "spigot"
      SFTP_PUBKEY: ""
      CTRL_PUBKEY: ""
    volumes:
      - lobby_data:/server
    networks:
      - workshop
YAML
    fi
    echo ""
    echo "  # ── Student servers ──"
    for i in $(seq 1 "$SERVERS"); do emit_server "$i"; done

    if [ "$ADMINPANEL" = true ]; then
        if [ "$PROXY" = none ]; then
            public_url="http://${DOMAIN}:${ADMIN_PORT}"
        else
            public_url="https://${DOMAIN}"
        fi
        cat <<YAML

  # ── Admin page: start/stop, plugins and players per server ──
  # Talks to the servers only over their SSH control path (no Docker socket).
  adminpanel:
    build: ./adminpanel
    container_name: adminpanel
    restart: unless-stopped
    environment:
      PUBLIC_URL: "${public_url}"
      ADMIN_EMAIL: "\${ADMIN_EMAIL}"
      MAIL_FROM: "\${MAIL_FROM}"
      SMTP_HOST: "\${SMTP_HOST}"
      SMTP_PORT: "\${SMTP_PORT}"
      SMTP_USER: "\${SMTP_USER}"
      SMTP_TLS: "\${SMTP_TLS}"
YAML
        [ "$MAIL_TEST" = true ] || echo "      SMTP_PASSWORD_FILE: /run/secrets/smtp_password"
        [ "$MAIL_TEST" = true ] && echo "      MAIL_TEST: \"true\""
        if [ "$PROXY" = none ]; then
            echo "    ports:"
            echo "      - \"${ADMIN_PORT}:8000\""
        fi
        cat <<YAML
    volumes:
      - adminpanel_data:/data
      - ./keys:/keys:ro
      - ./servers.json:/app/servers.json:ro
YAML
        [ "$MAIL_TEST" = true ] || echo "      - ./secrets/smtp_password:/run/secrets/smtp_password:ro"
        echo "    networks:"
        echo "      - workshop"
        [ "$PROXY" = caddy-proxy ] && echo "      - proxy"

        if [ "$PROXY" = own ]; then
            cat <<YAML

  # ── HTTPS for the admin page (Let's Encrypt) ──
  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - workshop
YAML
        fi
        if [ "$MAIL_TEST" = true ]; then
            cat <<YAML

  # ── Mail test mode: catches all mails, web UI on port 8025 ──
  mailpit:
    image: axllent/mailpit
    container_name: mailpit
    restart: unless-stopped
    ports:
      - "8025:8025"
    networks:
      - workshop
YAML
        fi
    fi

    echo ""
    echo "volumes:"
    [ "$MODE" = bungeecord ] && { echo "  bungee_data:"; echo "  lobby_data:"; }
    for i in $(seq 1 "$SERVERS"); do echo "  mc${i}_data:"; done
    if [ "$ADMINPANEL" = true ]; then
        echo "  adminpanel_data:"
        [ "$PROXY" = own ] && { echo "  caddy_data:"; echo "  caddy_config:"; }
    fi
    echo ""
    echo "networks:"
    echo "  workshop:"
    echo "    driver: bridge"
    if [ "$ADMINPANEL" = true ] && [ "$PROXY" = caddy-proxy ]; then
        echo "  proxy:"
        echo "    external: true"
    fi
} > docker-compose.yml
echo "✓ docker-compose.yml written (${MODE}, ${SERVERS} servers, MC_MEM_MIN=${MEM_MIN}, MC_MEM_MAX=${MEM_MAX})"

if [ "$ADMINPANEL" = true ] && [ "$PROXY" = own ]; then
    cat > Caddyfile <<CADDY
# Generated by setup.sh — HTTPS for the admin page.
${DOMAIN} {
    reverse_proxy adminpanel:8000
}
CADDY
    echo "✓ Caddyfile written"
fi

# ── BungeeCord server list ────────────────────────────────────
if [ "$MODE" = bungeecord ]; then
    {
        sed -n '1,/^servers:/p' bungee/config.base.yml
        echo "  lobby:"
        echo "    motd: '&6JavaScript Minecraft Workshop &7— Lobby'"
        echo "    address: lobby:25565"
        echo "    restricted: false"
        for i in $(seq 1 "$SERVERS"); do
            echo "  mc${i}:"
            echo "    motd: '&aWorkshop Server ${i}'"
            echo "    address: mc${i}:25565"
            echo "    restricted: false"
        done
        echo ""
        sed -n '/^listeners:/,$p' bungee/config.base.yml
    } > bungee/config.yml
    echo "✓ bungee/config.yml written (lobby + mc1…mc${SERVERS})"
fi

# ── Start scripts ─────────────────────────────────────────────
rm -f start-mc*.sh start-bungee.sh start-lobby.sh
if [ "$MODE" = bungeecord ]; then
    for svc in bungee lobby; do
        cat > "start-${svc}.sh" <<SCRIPT
#!/bin/bash
# start-${svc}.sh — Start / restart ${svc}  (generated by setup.sh)
cd "\$(dirname "\$0")"
docker compose up -d --no-deps ${svc}
SCRIPT
        chmod +x "start-${svc}.sh"
    done
fi
for i in $(seq 1 "$SERVERS"); do
    if [ "$MODE" = bungeecord ]; then
        mc_line="echo \"    Connect via BungeeCord on port 25565, then /server mc${i}\""
    else
        mc_line="echo \"    Minecraft : <host>:$(( 25564 + i ))\""
    fi
    cat > "start-mc${i}.sh" <<SCRIPT
#!/bin/bash
# start-mc${i}.sh — Start / restart Minecraft server ${i}
# Memory: max=${MEM_MAX} / min=${MEM_MIN}  (generated by setup.sh)
cd "\$(dirname "\$0")"
echo "==> (Re)starting mc${i}  [max=${MEM_MAX}, min=${MEM_MIN}]..."
docker compose up -d --no-deps mc${i}
${mc_line}
echo "    SSH : <host>:$(( 2220 + i ))"
SCRIPT
    chmod +x "start-mc${i}.sh"
done
echo "✓ start scripts generated"

# ── Leftovers from a larger setup ─────────────────────────────
if command -v docker >/dev/null 2>&1; then
    project=$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')
    for v in $(docker volume ls -q 2>/dev/null | grep -E "^${project}_mc[0-9]+_data$" || true); do
        n=${v#"${project}"_mc}; n=${n%_data}
        if [ "$n" -gt "$SERVERS" ]; then
            echo "NOTE: volume $v (server mc$n) still exists but mc$n is no longer configured."
            echo "      Back it up if needed, then remove it with: docker volume rm $v"
        fi
    done
fi

echo ""
echo "Next steps:"
echo "  docker compose up -d --build"
if [ "$ADMINPANEL" = true ]; then
    case "$PROXY" in
        own)         echo "  Point the DNS name ${DOMAIN} to this host (ports 80 and 443 must be reachable)." ;;
        caddy-proxy) echo "  Add to the Caddyfile of the caddy-proxy stack and reload it:"
                     echo "      ${DOMAIN} {"
                     echo "          reverse_proxy adminpanel:8000"
                     echo "      }" ;;
        none)        echo "  The admin page runs on http://${DOMAIN}:${ADMIN_PORT} (plain HTTP — only for tests or a trusted LAN)." ;;
    esac
    echo "  Then send the first invitation to ${ADMIN_EMAIL}:"
    echo "      docker compose exec adminpanel adminctl invite-admin"
    [ "$MAIL_TEST" = true ] && echo "  Mail test mode: all mails appear at http://${DOMAIN}:8025"
fi
