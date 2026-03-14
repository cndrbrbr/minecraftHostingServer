# Minecraft Workshop Host — Admin Guide

This system runs **5 isolated Spigot Minecraft servers** on a single host, one per student, each in its own Docker container. Students connect to their server with FileZilla (file upload) and PuTTY (server restart). They cannot access each other's servers or do anything beyond those two actions.

Built on top of [javascriptMinecraftWorkshopServer](https://github.com/cndrbrbr/javascriptMinecraftWorkshopServer).

---

## How it works

```
Host machine
│
├── mc1  (container)  ── Minecraft port 25565 ── SSH port 2221  ── student 1
├── mc2  (container)  ── Minecraft port 25566 ── SSH port 2222  ── student 2
├── mc3  (container)  ── Minecraft port 25567 ── SSH port 2223  ── student 3
├── mc4  (container)  ── Minecraft port 25568 ── SSH port 2224  ── student 4
└── mc5  (container)  ── Minecraft port 25569 ── SSH port 2225  ── student 5
```

Each container runs Debian Trixie and contains:
- A Spigot Minecraft server with the script4kids plugin
- An SSH server with exactly two locked-down users:

| SSH user | Tool | Permission |
|----------|------|------------|
| `mc-sftp` | FileZilla | SFTP only, restricted to the server's data folder |
| `mc-ctrl` | PuTTY | Runs the server restart script — nothing else |

Students authenticate with SSH keys. No passwords, no shell, no way to reach other containers.

---

## Prerequisites

Install these on the host machine before you begin:

- **Docker** (version 20+) including **Docker Compose v2**
  ```bash
  docker --version          # should print Docker version 20+
  docker compose version    # should print v2.x.x
  ```
- **ssh-keygen** — available by default on Linux and macOS; on Windows install Git for Windows or WSL
- **git** — to clone this repository

Students on Windows will also need:
- **FileZilla** — https://filezilla-project.org
- **PuTTY** (includes PuTTYgen) — https://putty.org

---

## First-time setup

Do this once on the host machine, before any workshop.

### Step 1 — Clone the repository

```bash
git clone git@github.com:cndrbrbr/minecraftHostingServer.git mchost
cd mchost
```

### Step 2 — Configure memory

This script reads the host's total RAM, reserves 15 % (minimum 2 GB) for the OS and Docker, and splits the rest equally across the 5 servers. It writes the result into `docker-compose.yml` and generates the per-server start scripts.

```bash
chmod +x configure-memory.sh
./configure-memory.sh
```

Example output on a 16 GB machine:

```
╔══════════════════════════════════════════════════╗
║         Memory configuration                     ║
╠══════════════════════════════════════════════════╣
║  Total RAM          :  16384 MB                  ║
║  OS reservation     :   2458 MB                  ║
║  Available for MC   :  13926 MB                  ║
║  Per server (max)   :   2560 MB  (2560M)
║  Per server (min)   :   1280 MB  (1280M)
╚══════════════════════════════════════════════════╝

✓ docker-compose.yml updated  (MC_MEM_MIN=1280M  MC_MEM_MAX=2560M)
✓ start-mc1.sh generated
✓ start-mc2.sh generated
...
```

Re-run this script any time you move the setup to a different machine.

### Step 3 — Generate SSH keys

This creates two ed25519 key pairs per server (one for FileZilla, one for PuTTY) and writes the public keys into `.env` so docker-compose can inject them into the containers.

```bash
chmod +x setup-keys.sh
./setup-keys.sh
```

The keys are saved under `keys/`:

```
keys/
├── mc1/
│   ├── sftp_key        ← give this file to student 1  (FileZilla)
│   ├── sftp_key.pub
│   ├── ctrl_key        ← give this file to student 1  (PuTTY)
│   └── ctrl_key.pub
├── mc2/  ...
├── mc3/  ...
├── mc4/  ...
└── mc5/  ...
```

> **Never commit the private key files.** They are excluded by `.gitignore`.

### Step 4 — Build the image and start all servers

```bash
docker compose up -d
```

The **first run** takes 5–15 minutes because Docker builds the image (downloads packages, compiles the plugin). Every start after that is done in seconds.

What happens inside each container on boot:

```
1. SSH host keys are generated (once, stored on the volume)
2. SSH server starts            (~1 s)
3. Spigot JAR is built          (~5–10 min on first run only)
4. Minecraft server starts      (~30 s)
5. World is generated           (~1 min on first run only)
```

### Step 5 — Verify everything is running

```bash
docker compose ps
```

All five containers should show `running`:

```
NAME  STATUS         PORTS
mc1   Up 3 minutes   0.0.0.0:25565->25565/tcp, 0.0.0.0:2221->22/tcp
mc2   Up 3 minutes   0.0.0.0:25566->25565/tcp, 0.0.0.0:2222->22/tcp
mc3   Up 3 minutes   0.0.0.0:25567->25565/tcp, 0.0.0.0:2223->22/tcp
mc4   Up 3 minutes   0.0.0.0:25568->25565/tcp, 0.0.0.0:2224->22/tcp
mc5   Up 3 minutes   0.0.0.0:25569->25565/tcp, 0.0.0.0:2225->22/tcp
```

Check the logs to confirm the Minecraft server inside mc1 is ready:

```bash
docker compose logs -f mc1
```

The server is ready when you see this line:

```
[Server thread/INFO]: Done (12.345s)! For help, type "help"
```

Press `Ctrl+C` to stop following the log. Repeat for the other servers if needed.

### Step 6 — Distribute keys to students

Hand each student their two key files and their connection details. You can use the student guide template in `STUDENT.md` — fill in the host IP and SSH port before printing or sending it.

| Student | Key files | SSH port | Minecraft port |
|---------|-----------|----------|----------------|
| 1 | `keys/mc1/sftp_key`, `keys/mc1/ctrl_key` | 2221 | 25565 |
| 2 | `keys/mc2/sftp_key`, `keys/mc2/ctrl_key` | 2222 | 25566 |
| 3 | `keys/mc3/sftp_key`, `keys/mc3/ctrl_key` | 2223 | 25567 |
| 4 | `keys/mc4/sftp_key`, `keys/mc4/ctrl_key` | 2224 | 25568 |
| 5 | `keys/mc5/sftp_key`, `keys/mc5/ctrl_key` | 2225 | 25569 |

Replace `<HOST>` with the actual IP or hostname of the workshop machine:

| Student | FileZilla (SFTP) | PuTTY (SSH) | Minecraft client |
|---------|-----------------|-------------|-----------------|
| 1 | `sftp://<HOST>:2221` user `mc-sftp` | `<HOST>:2221` user `mc-ctrl` | `<HOST>:25565` |
| 2 | `sftp://<HOST>:2222` user `mc-sftp` | `<HOST>:2222` user `mc-ctrl` | `<HOST>:25566` |
| 3 | `sftp://<HOST>:2223` user `mc-sftp` | `<HOST>:2223` user `mc-ctrl` | `<HOST>:25567` |
| 4 | `sftp://<HOST>:2224` user `mc-sftp` | `<HOST>:2224` user `mc-ctrl` | `<HOST>:25568` |
| 5 | `sftp://<HOST>:2225` user `mc-sftp` | `<HOST>:2225` user `mc-ctrl` | `<HOST>:25569` |

---

## Day-of-workshop operations

All commands run from the `mchost/` directory on the host.

### Start all servers

```bash
docker compose up -d
```

### Start or restart a single server

Use the generated scripts — they pick up any configuration changes automatically:

```bash
./start-mc1.sh
./start-mc3.sh
```

### Restart only the Minecraft process inside a container

Use this when a student uploads new plugins and you want to restart the server without recreating the container:

```bash
./restart.sh 3     # restarts the Java process in mc3
```

The container stays up, SSH stays available. The server is back within ~10 seconds.

### Stop a single server

```bash
docker compose stop mc2
```

Start it again with `./start-mc2.sh`. World data is kept.

### Stop all servers

```bash
docker compose down
```

All containers are stopped and removed. World data, plugins, and configs survive in the named volumes (`mc1_data` … `mc5_data`).

To **wipe everything** including world data (fresh start):

```bash
docker compose down -v     # permanent — cannot be undone
```

### Watch the logs

```bash
docker compose logs -f mc1          # follow mc1
docker compose logs --tail=50 mc2   # last 50 lines of mc2
docker compose logs -f              # follow all servers at once
```

### Open a shell inside a container

```bash
docker compose exec mc1 bash
```

From here you can inspect files, read the Minecraft log, or manually run server commands. Exit with `Ctrl+D`.

Send a broadcast message to all players on mc1:

```bash
docker compose exec mc1 bash -c 'echo "say Workshop ends in 5 minutes!" > /proc/1/fd/0'
```

---

## Maintenance

### Update after a git pull

If you pull new code (plugin update, config change):

```bash
git pull
docker compose build
docker compose up -d
```

The Spigot JAR is cached on the volume and not rebuilt unless you also set `FORCE_BUILD: "true"` in `docker-compose.yml`.

### Force a Spigot version update

Edit `docker-compose.yml`, set `FORCE_BUILD: "true"` and optionally update `SPIGOT_VERSION` for the servers you want to update. Then:

```bash
docker compose up -d
```

Set `FORCE_BUILD` back to `"false"` after the build completes.

### Replace a student's lost key

```bash
# Generate a new SFTP key for student 3
ssh-keygen -t ed25519 -f keys/mc3/sftp_key -N '' -C "mc3-sftp"

# Open .env and replace MC3_SFTP_PUBKEY with the content of keys/mc3/sftp_key.pub
nano .env

# Restart the container to apply the new key
docker compose up -d --no-deps mc3
```

The new key is active immediately on next container start. Give the student the new `keys/mc3/sftp_key` file.

### Re-run memory configuration

If you move the host to a different machine or add RAM:

```bash
./configure-memory.sh
docker compose up -d
```

---

## Configuration reference

All values are set per service in `docker-compose.yml`. To change a setting for one server, edit that service block and run `docker compose up -d --no-deps mcN`.

| Variable | Set by | Description |
|----------|--------|-------------|
| `MC_PORT` | fixed `25565` | Internal Minecraft port (do not change) |
| `MC_MAXPLAYERS` | `docker-compose.yml` | Max players per server |
| `MC_MEM_MIN` | `configure-memory.sh` | JVM minimum heap |
| `MC_MEM_MAX` | `configure-memory.sh` | JVM maximum heap |
| `MC_LEVELNAME` | `docker-compose.yml` | World folder name |
| `SPIGOT_VERSION` | `docker-compose.yml` | Spigot version to build |
| `FORCE_BUILD` | `docker-compose.yml` | `true` to force Spigot rebuild on next start |
| `SFTP_PUBKEY` | `.env` (via `setup-keys.sh`) | Public key for the SFTP user |
| `CTRL_PUBKEY` | `.env` (via `setup-keys.sh`) | Public key for the control user |

---

## Security model

| Layer | What it does |
|-------|-------------|
| Docker container | Each student's server is fully isolated — no access to other containers or the host filesystem |
| SSH chroot | `mc-sftp` is locked into `/server`; cannot navigate outside the container's data directory |
| ForceCommand | `mc-ctrl` is unconditionally forced to run `/mc-start.sh`; no shell access is possible |
| sudo scope | `mc-ctrl` may only `sudo /mc-start.sh` — sudo for anything else is blocked |
| Key-only auth | Password login is disabled on all SSH users |
| No forwarding | TCP, X11, and agent forwarding are disabled |

> For a production deployment, restrict the host firewall so Minecraft ports are only reachable from the workshop network, and consider putting a TLS reverse proxy (e.g. Caddy) in front of any web-facing services.

---

## File structure

```
mchost/
├── docker-compose.yml      # 5 server services with port mappings and env vars
├── configure-memory.sh     # detect RAM → update docker-compose.yml → generate start scripts
├── setup-keys.sh           # generate ed25519 key pairs + write .env
├── restart.sh              # restart the MC process inside a running container
├── start-mc1.sh            # generated by configure-memory.sh ┐
├── start-mc2.sh            #                                  │
├── start-mc3.sh            #                                  ├ start/restart one server
├── start-mc4.sh            #                                  │
├── start-mc5.sh            #                                  ┘
├── .env                    # public SSH keys — written by setup-keys.sh
├── .env.example            # empty template
├── .gitignore              # excludes private keys, .env, start-mc*.sh
├── STUDENT.md              # printable student guide (fill in IP + port before sharing)
└── spigot/
    ├── Dockerfile          # debian:trixie-slim, openssh-server, two SSH users
    ├── entrypoint.sh       # generates SSH host keys → starts sshd → builds Spigot → runs MC
    ├── sshd_config         # ChrootDirectory for mc-sftp, ForceCommand for mc-ctrl
    ├── mc-start.sh         # the only command mc-ctrl can run (restarts Minecraft)
    ├── watch_copy.sh       # inotify helper: keeps server.properties in sync with volume
    ├── server.properties   # default server config (copied to volume on first run)
    ├── eula.txt            # eula=true
    └── whitelist.json      # empty by default; students can edit via FileZilla
```
