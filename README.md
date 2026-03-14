# Minecraft Workshop Host

Runs **5 isolated Spigot Minecraft servers** on a single host, each in its own Docker container. Every server gets individual SSH access so students can upload files with FileZilla and restart their server with PuTTY — and nothing else.

Built on top of [javascriptMinecraftWorkshopServer](https://github.com/cndrbrbr/javascriptMinecraftWorkshopServer).

---

## Architecture

```
Host machine
│
├── mc1  (container)  ── MC port 25565 ── SSH port 2221
├── mc2  (container)  ── MC port 25566 ── SSH port 2222
├── mc3  (container)  ── MC port 25567 ── SSH port 2223
├── mc4  (container)  ── MC port 25568 ── SSH port 2224
└── mc5  (container)  ── MC port 25569 ── SSH port 2225
```

Each container is an independent Debian Trixie environment with:
- A Spigot server (built via BuildTools on first start)
- The [script4kids](https://github.com/cndrbrbr/script4kids) plugin
- An SSH server with two locked-down users per container

### SSH users per container

| User | Tool | What they can do |
|------|------|-----------------|
| `mc-sftp` | FileZilla | SFTP only, chrooted to `/server`, lands in `/data/` |
| `mc-ctrl` | PuTTY | Runs `/mc-start.sh` only — restarts the MC server |

Both users authenticate exclusively with their individual SSH key. Password login is disabled. No shell, no forwarding, no escape.

---

## Prerequisites

- Docker + Docker Compose (v2)
- `ssh-keygen` available on the host
- (Windows students) PuTTYgen to convert keys to `.ppk`

---

## Setup

### 1. Generate SSH keys

```bash
chmod +x setup-keys.sh
./setup-keys.sh
```

This creates two ed25519 key pairs per server under `keys/mc{1-5}/`:

```
keys/
├── mc1/
│   ├── sftp_key      ← private key for FileZilla  (give to student)
│   ├── sftp_key.pub  ← public key                 (stays on server)
│   ├── ctrl_key      ← private key for PuTTY       (give to student)
│   └── ctrl_key.pub  ← public key                 (stays on server)
├── mc2/ ...
```

It also writes all public keys into `.env`, which docker-compose reads on startup.

> **Keep private keys safe.** Never commit them — they are in `.gitignore`.

### 2. Start all servers

```bash
docker compose up -d
```

On first start each container:
1. Starts the SSH server
2. Builds Spigot via BuildTools (takes ~5 minutes, cached on the volume)
3. Launches the Minecraft server

Subsequent starts skip the build step and are ready in seconds.

### 3. Distribute keys to students

Each student receives:
- The **host IP or domain** of the workshop machine
- Their **SSH port** (2221–2225)
- Their **`sftp_key`** file (FileZilla)
- Their **`ctrl_key`** file (PuTTY / PuTTYgen)

---

## Student instructions

### FileZilla — upload, edit, download files

1. Open FileZilla → **Edit → Settings → SFTP → Add key file** → select `sftp_key`
2. Connect:
   - Protocol: **SFTP**
   - Host: `<host IP>`
   - Port: `<your SSH port, e.g. 2221>`
   - Logon type: **Interactive**
   - User: `mc-sftp`
3. You land in `/data/` — this is your server's data directory:
   ```
   /data/
   ├── cfg/          ← server.properties, bukkit.yml, …
   ├── plugins/      ← drop .jar files here
   └── worlds/       ← world saves
   ```

### PuTTY — restart the server

1. Open PuTTYgen → **Load** `ctrl_key` → **Save private key** → save as `ctrl_key.ppk`
2. Open PuTTY → **Connection → SSH → Auth → Credentials** → browse to `ctrl_key.ppk`
3. Connect:
   - Host: `<host IP>`
   - Port: `<your SSH port, e.g. 2221>`
   - User: `mc-ctrl`
4. Click **Open** — the server restarts automatically. You can close the window.

> After uploading new plugins via FileZilla, use PuTTY to restart the server so they take effect.

---

## Admin operations

### Restart a single MC server process (without restarting the container)

```bash
./restart.sh 3        # restarts the Minecraft process inside mc3
```

The entrypoint's crash-restart loop detects the stopped process and relaunches it within ~5 seconds.

### Restart a whole container

```bash
docker compose restart mc3
```

### Rebuild the image (e.g. after a plugin update)

```bash
docker compose build
docker compose up -d
```

### Stop everything

```bash
docker compose down
```

Data is stored in named Docker volumes (`mc1_data` … `mc5_data`) and survives `down`.
To also delete all world data: `docker compose down -v`

### View server logs

```bash
docker compose logs -f mc1
```

### Open a server console (admin only)

```bash
docker compose exec mc1 bash
```

---

## Configuration

All environment variables are set per-service in `docker-compose.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `MC_PORT` | `25565` | Internal Minecraft port (do not change) |
| `MC_MAXPLAYERS` | `5` | Max players per server |
| `MC_MEM_MIN` | `512M` | JVM minimum heap |
| `MC_MEM_MAX` | `1G` | JVM maximum heap |
| `MC_LEVELNAME` | `world` | World folder name |
| `FORCE_BUILD` | `false` | Set `true` to force Spigot rebuild |
| `SPIGOT_VERSION` | `1.21.4` | Spigot version to build |
| `SFTP_PUBKEY` | *(from .env)* | Public key for the SFTP user |
| `CTRL_PUBKEY` | *(from .env)* | Public key for the control user |

To change settings for a specific server, edit the relevant service block in `docker-compose.yml` and run `docker compose up -d mc3` (only that service restarts).

---

## Security model

- **Container isolation:** each student's server is a separate container; students cannot reach each other's files or processes
- **SSH chroot:** the SFTP user (`mc-sftp`) is chrooted to `/server` and can only access that container's data
- **ForceCommand:** the control user (`mc-ctrl`) is unconditionally forced into `/mc-start.sh` — no shell is granted
- **sudo scope:** `mc-ctrl` may only `sudo /mc-start.sh`, nothing else
- **No passwords:** all SSH auth is key-only; password login is disabled
- **No forwarding:** TCP, X11, and agent forwarding are all disabled

> For a production deployment consider adding TLS termination (e.g. Caddy) in front of a web IDE and restricting the host firewall so MC ports are only reachable from the workshop network.

---

## File structure

```
mchost/
├── docker-compose.yml     # 5 server services
├── setup-keys.sh          # generate SSH keys + populate .env
├── restart.sh             # host-side MC process restart helper
├── .env.example           # template — copied to .env by setup-keys.sh
├── .gitignore             # excludes private keys and .env
└── spigot/
    ├── Dockerfile         # debian:trixie-slim, two SSH users, host keys
    ├── entrypoint.sh      # SSH init → Spigot build → MC restart loop
    ├── sshd_config        # chroot + ForceCommand configuration
    ├── mc-start.sh        # student restart script (PuTTY)
    ├── watch_copy.sh      # inotify helper: sync config changes to volume
    ├── server.properties  # default server config (copied on first run)
    ├── eula.txt           # eula=true
    └── whitelist.json     # empty by default; edit via FileZilla
```
