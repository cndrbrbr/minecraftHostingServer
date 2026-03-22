# Minecraft Workshop Host — Admin Guide

This system runs **5 isolated Spigot Minecraft servers** on a single host, one per student, each in its own Docker container. Students connect to their server with FileZilla (file upload) and PuTTY (server restart). They cannot access each other's servers or do anything beyond those two actions.

Built on top of [javascriptMinecraftWorkshopServer](https://github.com/cndrbrbr/javascriptMinecraftWorkshopServer).

Two deployment modes are available — choose when running `configure-memory.sh`:

| Mode | When to use |
|------|-------------|
| **standalone** | Simple setup — each server has its own Minecraft port (25565–25569). Students connect to different ports. |
| **bungeecord** | Network setup — a BungeeCord proxy and lobby sit in front. All players connect on a single port (25565) and are routed to their server. |

---

## How it works

### Standalone mode

```
Host machine
│
├── mc1  (container)  ── Minecraft 25565 ── SSH 2221  ── student 1
├── mc2  (container)  ── Minecraft 25566 ── SSH 2222  ── student 2
├── mc3  (container)  ── Minecraft 25567 ── SSH 2223  ── student 3
├── mc4  (container)  ── Minecraft 25568 ── SSH 2224  ── student 4
└── mc5  (container)  ── Minecraft 25569 ── SSH 2225  ── student 5
```

### BungeeCord mode

```
Host machine
│
└── bungee  (container)  ── Minecraft 25565 ── public entry point
    │
    ├── lobby  (container, internal)  ── players land here first
    ├── mc1    (container, internal)  ── SSH 2221  ── student 1
    ├── mc2    (container, internal)  ── SSH 2222  ── student 2
    ├── mc3    (container, internal)  ── SSH 2223  ── student 3
    ├── mc4    (container, internal)  ── SSH 2224  ── student 4
    └── mc5    (container, internal)  ── SSH 2225  ── student 5
```

All containers communicate on an internal Docker bridge network (`workshop`). Student servers have no externally reachable Minecraft port — only the BungeeCord proxy is exposed.

Players use `/server mc1` … `/server mc5` in-game to switch from the lobby to a student server.

---

### SSH access (both modes)

Each container runs Debian Trixie and contains:
- A Spigot Minecraft server with the script4kids plugin
- An SSH server with exactly two locked-down users:

| SSH user | Tool | Permission |
|----------|------|------------|
| `mc-sftp` | FileZilla | SFTP only, restricted to the server's data folder |
| `mc-ctrl` | PuTTY / ssh | Runs `start`, `stop`, `version <x.x.x>`, `restore <date\|latest>`, or `adduser <minecraft-name>` — nothing else |

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

### Step 2 — Configure memory and choose deployment mode

This script reads the host's total RAM, reserves 15 % (minimum 2 GB) for the OS and Docker, and splits the rest equally across the servers. It writes a `docker-compose.yml` from the appropriate template and generates per-server start scripts.

**Choose your mode at the command line:**

```bash
chmod +x configure-memory.sh

./configure-memory.sh --standalone    # 5 servers, direct Minecraft ports 25565–25569
./configure-memory.sh --bungeecord    # BungeeCord proxy + lobby + 5 servers, single port 25565
./configure-memory.sh                 # interactive prompt if no flag given
```

Example output on a 16 GB machine (standalone):

```
╔══════════════════════════════════════════════════╗
║         Memory configuration                     ║
╠══════════════════════════════════════════════════╣
║  Mode               : standalone                 ║
║  Total RAM          :  16384 MB                  ║
║  OS reservation     :   2458 MB                  ║
║  Available for MC   :  13926 MB  (5 servers)
║  Per server (max)   :   2560 MB  (2560M)
║  Per server (min)   :   1280 MB  (1280M)
╚══════════════════════════════════════════════════╝

✓ docker-compose.yml written from docker-compose.standalone.yml
✓ Memory values updated  (MC_MEM_MIN=1280M  MC_MEM_MAX=2560M)
✓ start-mc1.sh generated
✓ start-mc2.sh generated
...
```

In BungeeCord mode the output also shows:
```
║  BungeeCord         :    512 MB  (fixed)
```
and generates `start-bungee.sh` and `start-lobby.sh` in addition to the mc scripts.

Re-run this script any time you move the setup to a different machine or change the mode.

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

**Standalone mode** — all five mc containers should show `running`:

```
NAME  STATUS         PORTS
mc1   Up 3 minutes   0.0.0.0:25565->25565/tcp, 0.0.0.0:2221->22/tcp
mc2   Up 3 minutes   0.0.0.0:25566->25565/tcp, 0.0.0.0:2222->22/tcp
mc3   Up 3 minutes   0.0.0.0:25567->25565/tcp, 0.0.0.0:2223->22/tcp
mc4   Up 3 minutes   0.0.0.0:25568->25565/tcp, 0.0.0.0:2224->22/tcp
mc5   Up 3 minutes   0.0.0.0:25569->25565/tcp, 0.0.0.0:2225->22/tcp
```

**BungeeCord mode** — bungee, lobby, and all five mc containers should show `running`:

```
NAME   STATUS         PORTS
bungee Up 3 minutes   0.0.0.0:25565->25565/tcp
lobby  Up 3 minutes
mc1    Up 3 minutes   0.0.0.0:2221->22/tcp
mc2    Up 3 minutes   0.0.0.0:2222->22/tcp
mc3    Up 3 minutes   0.0.0.0:2223->22/tcp
mc4    Up 3 minutes   0.0.0.0:2224->22/tcp
mc5    Up 3 minutes   0.0.0.0:2225->22/tcp
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

| Student | Key files | SSH port |
|---------|-----------|----------|
| 1 | `keys/mc1/sftp_key`, `keys/mc1/ctrl_key` | 2221 |
| 2 | `keys/mc2/sftp_key`, `keys/mc2/ctrl_key` | 2222 |
| 3 | `keys/mc3/sftp_key`, `keys/mc3/ctrl_key` | 2223 |
| 4 | `keys/mc4/sftp_key`, `keys/mc4/ctrl_key` | 2224 |
| 5 | `keys/mc5/sftp_key`, `keys/mc5/ctrl_key` | 2225 |

Replace `<HOST>` with the actual IP or hostname of the workshop machine.

**Standalone mode connection details:**

| Student | FileZilla (SFTP) | PuTTY (SSH) | Minecraft client |
|---------|-----------------|-------------|-----------------|
| 1 | `sftp://<HOST>:2221` user `mc-sftp` | `<HOST>:2221` user `mc-ctrl` | `<HOST>:25565` |
| 2 | `sftp://<HOST>:2222` user `mc-sftp` | `<HOST>:2222` user `mc-ctrl` | `<HOST>:25566` |
| 3 | `sftp://<HOST>:2223` user `mc-sftp` | `<HOST>:2223` user `mc-ctrl` | `<HOST>:25567` |
| 4 | `sftp://<HOST>:2224` user `mc-sftp` | `<HOST>:2224` user `mc-ctrl` | `<HOST>:25568` |
| 5 | `sftp://<HOST>:2225` user `mc-sftp` | `<HOST>:2225` user `mc-ctrl` | `<HOST>:25569` |

**BungeeCord mode connection details:**

All players connect to Minecraft on the same address. After joining they land in the lobby and use `/server mc1` … `/server mc5` to reach their server.

| Student | FileZilla (SFTP) | PuTTY (SSH) | Minecraft client |
|---------|-----------------|-------------|-----------------|
| 1 | `sftp://<HOST>:2221` user `mc-sftp` | `<HOST>:2221` user `mc-ctrl` | `<HOST>:25565` |
| 2 | `sftp://<HOST>:2222` user `mc-sftp` | `<HOST>:2222` user `mc-ctrl` | `<HOST>:25565` |
| 3 | `sftp://<HOST>:2223` user `mc-sftp` | `<HOST>:2223` user `mc-ctrl` | `<HOST>:25565` |
| 4 | `sftp://<HOST>:2224` user `mc-sftp` | `<HOST>:2224` user `mc-ctrl` | `<HOST>:25565` |
| 5 | `sftp://<HOST>:2225` user `mc-sftp` | `<HOST>:2225` user `mc-ctrl` | `<HOST>:25565` |

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

In BungeeCord mode, there are also:

```bash
./start-bungee.sh    # restart the BungeeCord proxy
./start-lobby.sh     # restart the lobby server
```

### Student server control (start / stop / version / restore / adduser)

Students control their own Minecraft process via SSH using their `ctrl_key`. The container and SSH stay up at all times — only the Java process inside is affected.

```bash
# From the host (admin):
ssh -i keys/mc3/ctrl_key -p 2223 mc-ctrl@localhost stop
ssh -i keys/mc3/ctrl_key -p 2223 mc-ctrl@localhost start
ssh -i keys/mc3/ctrl_key -p 2223 mc-ctrl@localhost version 1.20.4
ssh -i keys/mc3/ctrl_key -p 2223 mc-ctrl@localhost restore latest
ssh -i keys/mc3/ctrl_key -p 2223 mc-ctrl@localhost restore 2026-03-22
ssh -i keys/mc3/ctrl_key -p 2223 mc-ctrl@localhost adduser CoolPlayer99
```

Students do the same from their own machine using PuTTY (see `STUDENT.md`).

**How versioning works:** `version <x.x.x>` writes the requested version to the container volume. The change takes effect after the next `stop` + `start`. If that version has never been built before, BuildTools compiles it on first start (5–10 minutes). Subsequent starts with the same version are instant because the JAR is cached on the volume.

**How restore works:** `restore <date|latest>` downloads backup zips from the configured `BACKUP_URL`, stops the server, extracts cfg/plugins/worlds, then waits. The student runs `start` to bring the server back up. See the [Backup and restore](#backup-and-restore) section for setup.

**How adduser works:** `adduser <minecraft-username>` looks up the player's UUID from the Mojang API (or derives it for offline mode), then adds the player to both `whitelist.json` and `ops.json` (operator level 4). If the server is running, the whitelist is reloaded immediately so the player can connect without a restart. Op permissions take effect after the next server restart.

### Restart only the Minecraft process inside a container (admin shortcut)

```bash
docker compose exec mc3 bash -c 'rm -f /server/.stopped && pkill -TERM -f "spigot-.*\.jar" 2>/dev/null; true'
```

The container stays up, SSH stays available. The server is back within ~10 seconds.

### In-game server switching (BungeeCord mode)

Players can switch servers using the `/server` command from any server:

```
/server lobby   ← return to lobby
/server mc1     ← go to student 1's server
/server mc2     ← go to student 2's server
...
```

### Stop a single server

```bash
docker compose stop mc2
```

Start it again with `./start-mc2.sh`. World data is kept.

### Stop all servers

```bash
docker compose down
```

All containers are stopped and removed. World data, plugins, and configs survive in the named volumes (`mc1_data` … `mc5_data`, plus `bungee_data` and `lobby_data` in BungeeCord mode).

To **wipe everything** including world data (fresh start):

```bash
docker compose down -v     # permanent — cannot be undone
```

### Watch the logs

```bash
docker compose logs -f mc1          # follow mc1
docker compose logs --tail=50 mc2   # last 50 lines of mc2
docker compose logs -f              # follow all servers at once
docker compose logs -f bungee       # BungeeCord proxy log (bungeecord mode)
```

### Open the Minecraft server console

Use `docker attach` to connect directly to the Minecraft console of a running container. You can type server commands (e.g. `say`, `op`, `kick`) interactively.

```bash
docker attach mc1
```

You will see the live server log and can type commands immediately.

**Important — detach without stopping the server:**

Press **`Ctrl+P`** then **`Ctrl+Q`** to detach and leave the server running.

> Do **not** press `Ctrl+C` — that sends SIGINT to the Java process and stops the server.

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

### Switch deployment mode

Re-run `configure-memory.sh` with the new mode flag, then restart everything:

```bash
./configure-memory.sh --standalone    # or --bungeecord
docker compose down
docker compose up -d
```

World data is preserved in volumes. BungeeCord volumes (`bungee_data`, `lobby_data`) are created fresh if they did not exist.

### Re-run memory configuration

If you move the host to a different machine or add RAM:

```bash
./configure-memory.sh --standalone    # or --bungeecord
docker compose up -d
```

---

## Configuration reference

All values are set per service in `docker-compose.yml`. To change a setting for one server, edit that service block and run `docker compose up -d --no-deps mcN`.

| Variable | Set by | Description |
|----------|--------|-------------|
| `MC_PORT` | fixed `25565` | Internal Minecraft port (do not change) |
| `MC_NAME` | `docker-compose.yml` | Container name used to locate backups (`mc1` … `mc5`, `lobby`) |
| `MC_MEM_MIN` | `configure-memory.sh` | JVM minimum heap |
| `MC_MEM_MAX` | `configure-memory.sh` | JVM maximum heap |
| `MC_LEVELNAME` | `docker-compose.yml` | World folder name |
| `MC_BUNGEECORD` | `docker-compose.yml` | `true` to enable BungeeCord IP forwarding in spigot.yml |
| `SPIGOT_VERSION` | `docker-compose.yml` | Default Spigot version to build (can be overridden per-server by the student via `version` command) |
| `FORCE_BUILD` | `docker-compose.yml` | `true` to force Spigot rebuild on next start |
| `BACKUP_URL` | `docker-compose.yml` | Base URL of the backup HTTP server — required for the `restore` command |
| `SFTP_PUBKEY` | `.env` (via `setup-keys.sh`) | Public key for the SFTP user |
| `CTRL_PUBKEY` | `.env` (via `setup-keys.sh`) | Public key for the control user |

### Changing max players

`max-players` is **not** controlled by an environment variable. It is read directly from `server.properties` on the volume. The image default is **20**.

To change it for a specific server, edit `data/cfg/server.properties` via FileZilla and set `max-players=<N>`, then restart the server. Students can do this themselves.

To change the default for all fresh servers, edit `spigot/server.properties` in the repository and rebuild the image.

---

## Backup and restore

The backup system lets you snapshot each server's data (config, plugins, worlds) as dated zip files. Those zips are served over HTTP so any server can fetch and restore them by date or with the keyword `latest`.

### Creating backups (source server)

Run `backup.sh` on the host from the repository directory:

```bash
./backup.sh              # lobby (if running) + mc1–mc5
./backup.sh 1            # mc1 only
./backup.sh lobby 1 2    # lobby + mc1 + mc2
```

Backups are written to `./backups/<name>/`:

```
backups/
├── mc1/
│   ├── cfg-2026-03-22.zip
│   ├── plugins-2026-03-22.zip
│   ├── worlds-2026-03-22.zip
│   └── latest.txt          ← contains "2026-03-22"
├── mc2/  ...
└── lobby/  ...
```

> The `backups/` directory is excluded from git.

### Serving backups over HTTP

The restore command inside each container fetches zips via HTTP. A ready-made Compose file is in `backup-server/`:

```bash
cd backup-server
docker compose up -d
```

The backups are now reachable at `http://<source-host>:8080`. The server also shows a directory listing in the browser so you can browse available backups.

> **Does the backup server need a TLS certificate?**
> No — for a LAN / workshop setup plain HTTP on port 8080 is fine. If the server must be reachable over the public internet, put a TLS reverse proxy (e.g. Caddy with automatic Let's Encrypt) in front and point `BACKUP_URL` at the HTTPS address.

### Configuring the destination server

In `docker-compose.yml` on the destination server, set `BACKUP_URL` and confirm `MC_NAME` for each service:

```yaml
environment:
  MC_NAME: mc1
  BACKUP_URL: "http://<source-host>:8080"
```

Apply the change without rebuilding:

```bash
docker compose up -d --no-deps mc1
```

### Restoring a backup (student or admin)

Via PuTTY (student):
```
restore latest
restore 2026-03-22
```

Via SSH (admin):
```bash
ssh -i keys/mc1/ctrl_key -p 2221 mc-ctrl@localhost restore latest
ssh -i keys/mc1/ctrl_key -p 2221 mc-ctrl@localhost restore 2026-03-22
```

The restore process:
1. Stops the Minecraft server
2. Downloads `cfg`, `plugins`, and `worlds` zips from the backup server
3. Extracts them, replacing the current data
4. Waits — the student then runs `start` to bring the server back up

> **Note:** `restore` replaces all three data directories. Any changes made after the backup date will be lost.

### Automating backups with cron

To back up all servers automatically every night at 02:00:

```bash
crontab -e
```

Add:
```
0 2 * * * cd /path/to/mchost && ./backup.sh >> /var/log/mc-backup.log 2>&1
```

---

## BungeeCord internals

This section explains the technical choices for the BungeeCord setup.

### Authentication flow

- BungeeCord (`online_mode: true`) handles Mojang authentication centrally.
- Backend servers (lobby, mc1–mc5) run with `online-mode=false` in `server.properties` — they trust the UUID forwarded by BungeeCord.
- `ip_forward: true` is set in BungeeCord's `config.yml` so real Mojang UUIDs are passed through. This means whitelists and permissions on backend servers work correctly.
- `bungeecord: true` is set in `spigot.yml` on all backend servers to accept the forwarded connection data. This is applied automatically at container start via the `MC_BUNGEECORD=true` env var in `docker-compose.bungeecord.yml`.

### Network isolation

Backend servers are only reachable from within the `workshop` Docker bridge network. Only the BungeeCord container's port 25565 is bound to the host. Students cannot bypass the proxy.

### Lobby

The lobby server uses the same Spigot image as the student servers. It has no SSH keys set (`SFTP_PUBKEY` and `CTRL_PUBKEY` are empty) — it is admin-managed only. World data is stored in the `lobby_data` volume.

---

## Security model

| Layer | What it does |
|-------|-------------|
| Docker container | Each student's server is fully isolated — no access to other containers or the host filesystem |
| Docker network (BungeeCord mode) | Backend servers are unreachable from outside the internal `workshop` network |
| SSH chroot | `mc-sftp` is locked into `/server`; cannot navigate outside the container's data directory |
| ForceCommand | `mc-ctrl` is unconditionally forced to run `/mc-dispatch.sh`; no shell access is possible |
| sudo scope | `mc-ctrl` may only `sudo /mc-start.sh`, `sudo /mc-stop.sh`, `sudo /mc-version.sh`, `sudo /mc-restore.sh`, `sudo /mc-adduser.sh` — sudo for anything else is blocked |
| Key-only auth | Password login is disabled on all SSH users |
| No forwarding | TCP, X11, and agent forwarding are disabled |

> For a production deployment, restrict the host firewall so Minecraft ports are only reachable from the workshop network, and consider putting a TLS reverse proxy (e.g. Caddy) in front of any web-facing services.

---

## File structure

```
mchost/
├── docker-compose.yml              # written by configure-memory.sh from a template
├── docker-compose.standalone.yml   # template: 5 servers, direct MC ports 25565–25569
├── docker-compose.bungeecord.yml   # template: bungee + lobby + 5 servers, single port
├── configure-memory.sh             # detect RAM → write docker-compose.yml → generate start scripts
├── setup-keys.sh                   # generate ed25519 key pairs + write .env
├── backup.sh                       # create dated backups of server data volumes
├── backup-server/
│   └── docker-compose.yml          # nginx:alpine that serves backup zips over HTTP (port 8080)
├── start-mc1.sh                    # generated by configure-memory.sh ┐
├── start-mc2.sh                    #                                  │
├── start-mc3.sh                    #                                  ├ start/restart one server
├── start-mc4.sh                    #                                  │
├── start-mc5.sh                    #                                  ┘
├── start-bungee.sh                 # generated in bungeecord mode — restart BungeeCord proxy
├── start-lobby.sh                  # generated in bungeecord mode — restart lobby server
├── backups/                        # backup archives (excluded from git)
│   ├── mc1/  cfg-DATE.zip, plugins-DATE.zip, worlds-DATE.zip, latest.txt
│   └── ...
├── .env                            # public SSH keys — written by setup-keys.sh
├── .env.example                    # empty template
├── .gitignore                      # excludes private keys, .env, start-mc*.sh, backups/
├── LICENSE                         # Apache 2.0
├── STUDENT.md                      # printable student guide (fill in IP + port before sharing)
├── bungee/
│   ├── Dockerfile                  # debian:trixie-slim + openjdk + BungeeCord.jar
│   ├── entrypoint.sh               # copies config on first run, starts BungeeCord
│   └── config.yml                  # online_mode, ip_forward, server list, listener
└── spigot/
    ├── Dockerfile                  # debian:trixie-slim, openssh-server, two SSH users
    ├── entrypoint.sh               # generates SSH host keys → starts sshd → builds Spigot → runs MC
    ├── sshd_config                 # ChrootDirectory for mc-sftp, ForceCommand for mc-ctrl
    ├── mc-dispatch.sh              # SSH ForceCommand dispatcher — routes start/stop/version/restore/adduser
    ├── mc-start.sh                 # removes .stopped marker → entrypoint loop launches the server
    ├── mc-stop.sh                  # creates .stopped marker + kills Java → server stays down
    ├── mc-version.sh               # writes requested version to /server/.version on the volume
    ├── mc-restore.sh               # fetches backup zips by date, extracts to volume
    ├── mc-adduser.sh               # adds a Minecraft username to whitelist.json and ops.json
    ├── watch_copy.sh               # inotify helper: keeps server.properties in sync with volume
    ├── server.properties           # default server config (copied to volume on first run)
    ├── spigot.yml                  # bungeecord: false by default (set via MC_BUNGEECORD env var)
    ├── eula.txt                    # eula=true
    └── whitelist.json              # empty by default; students can edit via FileZilla
```
