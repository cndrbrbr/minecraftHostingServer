# Minecraft Workshop Host — Admin Guide

This system runs **isolated Spigot Minecraft servers** (5 by default, any number from 1 to 30) on a single host, one per student, each in its own Docker container. Students manage their server on the **admin page** — a web page with e-mail login code where they start/stop it, install or upload plugins and manage players — or with FileZilla (files) and PuTTY (start/stop). They cannot access each other's servers.

Built on top of [javascriptMinecraftWorkshopServer](https://github.com/cndrbrbr/javascriptMinecraftWorkshopServer).

## Contents

- [How it works](#how-it-works)
  - [Standalone mode](#standalone-mode)
  - [BungeeCord mode](#bungeecord-mode)
  - [SSH access](#ssh-access-both-modes)
  - [Server software: Spigot, or a student's own (custom)](#server-software-spigot-or-a-students-own-custom)
- [Prerequisites](#prerequisites)
- [First-time setup](#first-time-setup)
  - [Step 1 — Clone the repository](#step-1--clone-the-repository)
  - [Step 2 — Run setup.sh](#step-2--run-setupsh)
  - [Step 3 — SSH keys](#step-3--ssh-keys)
  - [Step 4 — Build the image and start all servers](#step-4--build-the-image-and-start-all-servers)
  - [Step 5 — Verify everything is running](#step-5--verify-everything-is-running)
  - [Step 6 — Distribute keys to students](#step-6--distribute-keys-to-students)
  - [Step 7 — First login on the admin page](#step-7--first-login-on-the-admin-page)
- [Admin page](#admin-page)
  - [What students and teachers can do](#what-students-and-teachers-can-do)
  - [Login with e-mail code](#login-with-e-mail-code)
  - [Assigning and releasing servers](#assigning-and-releasing-servers)
  - [HTTPS](#https)
  - [Sending mail](#sending-mail)
  - [Mail test mode](#mail-test-mode)
  - [adminctl](#adminctl)
  - [How the admin page talks to the servers](#how-the-admin-page-talks-to-the-servers)
  - [Troubleshooting](#troubleshooting-admin-page)
- [Plugin catalog](#plugin-catalog)
- [Day-of-workshop operations](#day-of-workshop-operations)
  - [Start all servers](#start-all-servers)
  - [Start or restart a single server](#start-or-restart-a-single-server)
  - [Student server control](#student-server-control-start--stop--version--restore--adduser)
  - [Broadcast a message to all players](#broadcast-a-message-to-all-players)
  - [Restart only the Minecraft process](#restart-only-the-minecraft-process-inside-a-container-admin-shortcut)
  - [In-game server switching (BungeeCord)](#in-game-server-switching-bungeecord-mode)
  - [Stop a single server](#stop-a-single-server)
  - [Stop all servers](#stop-all-servers)
  - [Watch the logs](#watch-the-logs)
  - [Open the Minecraft server console](#open-the-minecraft-server-console)
  - [Open a shell inside a container](#open-a-shell-inside-a-container)
- [Maintenance](#maintenance)
  - [Update after a git pull](#update-after-a-git-pull)
  - [Force a Spigot version update](#force-a-spigot-version-update)
  - [Replace a student's lost key](#replace-a-students-lost-key)
  - [Switch deployment mode or number of servers](#switch-deployment-mode-or-number-of-servers)
  - [Re-run memory configuration](#re-run-memory-configuration)
- [Configuration reference](#configuration-reference)
  - [Changing max players](#changing-max-players)
- [Backup and restore](#backup-and-restore)
  - [Creating backups](#creating-backups-source-server)
  - [Serving backups over HTTP](#serving-backups-over-http)
  - [Configuring the destination server](#configuring-the-destination-server)
  - [Restoring a backup](#restoring-a-backup-student-or-admin)
  - [Automating backups with cron](#automating-backups-with-cron)
- [BungeeCord internals](#bungeecord-internals)
  - [Authentication flow](#authentication-flow)
  - [Network isolation](#network-isolation)
  - [Server addresses and container restarts](#server-addresses-and-container-restarts)
  - [Lobby](#lobby)
- [Firewall (iptables)](#firewall-iptables)
- [Security model](#security-model)
- [File structure](#file-structure)

Two deployment modes are available — choose when running `setup.sh`:

| Mode | When to use |
|------|-------------|
| **standalone** | Simple setup — each server has its own Minecraft port (25565, 25566, …; up to 10 servers). Students connect to different ports. |
| **bungeecord** | Network setup — a BungeeCord proxy and lobby sit in front. All players connect on a single port (25565) and are routed to their server. |

---

## How it works

The diagrams show the default of 5 servers; `setup.sh --servers N` creates `mc1` … `mcN` with the same port scheme (SSH `2220+N`, Prometheus `9940+N`, standalone Minecraft `25564+N`).

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

Players use `/server mc1` … `/server mcN` in-game to switch from the lobby to a student server.

With the admin page enabled, two or three more containers run next to the servers: `adminpanel` (the web page), plus `caddy` (HTTPS) or `mailpit` (mail test mode) depending on the options — see [Admin page](#admin-page).

---

### SSH access (both modes)

Each container runs Debian Trixie and contains:
- A Minecraft server — Spigot by default, with the script4kids plugin (JavaScript engine powered by GraalVM CE JDK); see [Server software](#server-software-spigot-or-a-students-own-custom) for the custom (e.g. Forge) alternative
- An SSH server with exactly two locked-down users:

| SSH user | Tool | Permission |
|----------|------|------------|
| `mc-sftp` | FileZilla | SFTP only, chrooted to the student's own server root — full access to all of their own files, no access to other students |
| `mc-ctrl` | PuTTY / ssh, admin page | Runs `start`, `stop`, `version <x.x.x>`, `restore <date\|latest>`, `adduser <minecraft-name>` and the [admin page commands](#how-the-admin-page-talks-to-the-servers) — nothing else |

Students authenticate with SSH keys. No passwords, no shell, no way to reach other containers.

Every student's SFTP session opens directly at their server's root directory
(`/server`), not just the `data/` subfolder — students have full read/write
access to their entire server (jar files, logs, whitelist, configs,
everything) except the `/server` directory entry itself, which OpenSSH
requires to stay `root:root` for the chroot to work at all.

---

### Server software: Spigot, or a student's own (custom)

Each student server has an `MC_SERVER_TYPE` setting in `docker-compose.yml`:

| `MC_SERVER_TYPE` | What happens |
|---|---|
| `spigot` *(default)* | BuildTools compiles the requested `SPIGOT_VERSION` on the volume, as today. |
| `custom` | **The exception case** — for a student who wants different server software entirely (Forge, Fabric, vanilla, a specific fork, …). Nothing is managed for them: they upload their own server files plus an executable `start.sh` via SFTP, and the container just runs it. |

(Paper was considered as a lighter-weight third option but was dropped: its
"Paperclip" launcher needs to create several directories — `cache`,
`libraries`, `versions`, `config`, and possibly more in future releases —
directly in the server root, which conflicts with keeping that root locked
down. `custom` covers the same need without that fragility.)

To mark a student as an exception, edit their service block in
`docker-compose.yml`:

```yaml
mc3:
  environment:
    MC_SERVER_TYPE: "custom"
```

Then `docker compose up -d --no-deps mc3`.

**What the custom student needs to do:**

1. Connect with FileZilla as usual — they now land at their full server root.
   A placeholder `start.sh` and the common mod-loader folders (`mods/`,
   `config/`, `libraries/`, `world/`, `logs/`, `crash-reports/`) already
   exist there so they have somewhere to upload into — `/server` itself
   can't accept brand-new top-level names (see the exception above), only
   existing names can be written to.
2. Upload their server into those folders (e.g. a Forge installer's output:
   the server jar, its `libraries/`, `mods/`, etc.).
3. Edit `start.sh` so it launches their server in the foreground, listening
   on port `25565` (the value of `MC_PORT`). This is the one integration
   point the workshop host requires — everything else about the server
   layout is up to them.
4. Run `start` from PuTTY as usual.

If their server needs a top-level name that isn't pre-created (rare), the
admin adds it once from the host:

```bash
docker compose exec mc3 mkdir /server/<name>
docker compose exec mc3 chown mc-sftp:mc-sftp /server/<name>
```

**What's different for a custom-type student (the marked exception):**

- Only `start` and `stop` are available. `version`, `restore`, and `adduser`
  all refuse to run — they assume the managed Spigot file layout, which
  custom-type students don't have. The student manages their own files,
  version, backups, and whitelist/ops directly over SFTP.
- `./backup.sh` skips them automatically (no `data/` folder to zip) and says
  so.
- No script4kids plugin, no Prometheus exporter, no automatic EULA/whitelist
  seeding beyond `eula.txt` — plugins are a Bukkit/Spigot-only concept.

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

### Step 2 — Run setup.sh

`setup.sh` does the whole configuration in one go:

- reads the host's total RAM, reserves 15 % (minimum 2 GB) for the OS and Docker (plus 512 MB for BungeeCord and 384 MB for the admin page), and splits the rest equally across the servers,
- generates the SSH keys for every server (existing keys are kept),
- writes `docker-compose.yml`, `servers.json`, `servers.txt`, `bungee/config.yml` (BungeeCord mode), `Caddyfile` (own HTTPS) and the `start-*.sh` scripts,
- stores all settings in `.env`, so a later re-run only needs the options that change.

Everything is given on the command line (missing required values are asked interactively when run in a terminal):

```bash
./setup.sh --bungeecord \
           --servers 5 \
           --domain admin.meckminecraft.de \
           --admin-email teacher@example.de \
           --mail-from tech@screenpaper.de \
           --smtp-host mx2fed.netcup.net --smtp-port 465 --smtp-tls ssl
```

The SMTP password is then asked for with a hidden prompt (see [Sending mail](#sending-mail)).

| Option | Default | Meaning |
|---|---|---|
| `--standalone` / `--bungeecord` | asked | Deployment mode |
| `--servers N` | `5` | Number of student servers (1–30; standalone up to 10) |
| `--no-adminpanel` | – | Setup without admin page (as before) |
| `--domain HOST` | – | Address of the admin page, e.g. `admin.meckminecraft.de` (required for the admin page) |
| `--admin-email MAIL` | – | First admin; receives the first invitation |
| `--mail-from MAIL` | – | Sender of login codes and invitations |
| `--smtp-host HOST` | – | SMTP server |
| `--smtp-port PORT` | `587` | SMTP port |
| `--smtp-user USER` | `--mail-from` | SMTP login |
| `--smtp-tls starttls\|ssl\|none` | `starttls` (`ssl` on port 465) | SMTP encryption |
| `--smtp-password-file FILE` | – | Read the SMTP password from a file instead of the prompt (or set `$SMTP_PASSWORD`) |
| `--proxy own\|caddy-proxy\|none` | `own` | HTTPS for the admin page — see [HTTPS](#https) |
| `--admin-port PORT` | `8080` | Host port of the admin page with `--proxy none` |
| `--mail-test` | – | Don't send real mail; show all mails in Mailpit — see [Mail test mode](#mail-test-mode) |

Example output on a 16 GB machine:

```
╔══════════════════════════════════════════════════╗
║         Hosting server configuration             ║
╠══════════════════════════════════════════════════╣
║  Mode               : bungeecord                 ║
║  Student servers    : 5                          ║
║  Admin page         : admin.meckminecraft.de     ║
║  Total RAM          :  16384 MB                  ║
║  OS reservation     :   2457 MB                  ║
║  BungeeCord         :    512 MB                  ║
║  Admin page         :    384 MB                  ║
║  Per server (max)   :   2048 MB  (2G   )         ║
║  Per server (min)   :   1024 MB  (1G   )         ║
╚══════════════════════════════════════════════════╝
```

Re-run `setup.sh` any time you move the setup to a different machine, change the mode or the number of servers. `configure-memory.sh` and `setup-keys.sh` still exist and simply run `setup.sh`.

### Step 3 — SSH keys

`setup.sh` creates two ed25519 key pairs per server (one for FileZilla, one for PuTTY) and writes the public keys into `.env` so docker-compose can inject them into the containers. The admin page uses the same keys (read-only).

The keys are saved under `keys/`:

```
keys/
├── mc1/
│   ├── sftp_key        ← give this file to student 1  (FileZilla)
│   ├── sftp_key.pub
│   ├── ctrl_key        ← give this file to student 1  (PuTTY)
│   └── ctrl_key.pub
├── mc2/  ...
├── mcN/  ...
└── lobby/              ← BungeeCord mode only: for the admin page — never give these out
```

In BungeeCord mode the lobby gets a key pair too, so the admin page can manage it. The lobby has no public SSH port, so these keys only work from inside the `workshop` network (i.e. from the admin page).

> **The `keys/` folder is not part of the repository** (excluded by `.gitignore`) — keep it, together with `.env` and `secrets/`, only on the host and in your backups. Missing `.pub` files are recreated from the private keys by `setup.sh`.

### Step 4 — Build the image and start all servers

```bash
docker compose up -d --build
```

The **first run** takes 5–15 minutes because Docker builds the images (downloads packages, pulls GraalVM CE JDK, downloads all plugins of the [plugin catalog](#plugin-catalog)). Every start after that is done in seconds.

> **Why GraalVM CE JDK?** The script4kids plugin runs student JavaScript via the GraalVM polyglot engine, which requires GraalVM's JDK — standard OpenJDK cannot initialize the JS engine. The container base is still Debian Trixie; GraalVM replaces only the JDK.

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

With the admin page there is also `adminpanel` and, depending on the options, `caddy` or `mailpit`.

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

With the admin page most students won't need the keys at all — hand them out only to students who want FileZilla/PuTTY.

### Step 7 — First login on the admin page

Send yourself the first invitation (to the address given with `--admin-email`):

```bash
docker compose exec adminpanel adminctl invite-admin
```

Open the link in the mail, set your password, then log in at `https://<domain>` with your e-mail address, password and the code that arrives by mail. On the overview page you assign servers to students — see [Assigning and releasing servers](#assigning-and-releasing-servers).

---

## Admin page

A web page where students manage their own server and teachers manage all of them. **How to use it (German, with screenshots): [admin-handbuch.md](admin-handbuch.md) for teachers, [schueler-handbuch.md](schueler-handbuch.md) for students.** It runs in the `adminpanel` container (Python/FastAPI, SQLite) and is set up by `setup.sh` (see [Step 2](#step-2--run-setupsh)).

### What students and teachers can do

**Students** see only the server assigned to them:

| Area | Actions |
|---|---|
| Status | running / starting / being built / stopped, Minecraft version, players online; **start**, **stop**, **restart** |
| Plugins | list of installed plugins, **remove**; **install** from the [plugin catalog](#plugin-catalog) (the build matching the server's Minecraft version is picked automatically); **upload** an own plugin `.jar` (max. 64 MB, must contain a `plugin.yml`; a plugin with the same name is replaced) |
| Players | **add/remove** players on the whitelist, **give/take operator** rights — applied immediately via RCON, no restart needed |
| Settings | **edit `server.properties`** in the browser, with a short explanation of the common keys; *Speichern und neu starten* saves and (re)starts the server in one step; *rückgängig* goes back to the previous version |

Plugin and settings changes take effect after a restart (the page says so). In `server.properties` the keys the setup depends on — `server-port`, `online-mode`, `enable-rcon`, `rcon.port`, `rcon.password`, `broadcast-rcon-to-ops` — always keep their values; a file without any other setting (e.g. an interrupted upload) is refused, and the previous file is kept as `server.properties.bak`. The PrometheusExporter is shown as a required plugin and cannot be removed (it feeds the monitoring).

**Teachers (admins)** additionally see:

- an overview of all servers with status, version, player count and assigned student,
- **assign** a free server to a student (name + e-mail; an invitation is sent),
- **release** a server — the student loses access immediately; optionally **reset** it (see below),
- all accounts: **send a new invitation** (the old password stops working — this is how "forgot password" works), **delete an account** (name and e-mail are removed, also from the action log), **add further admins**,
- the last 40 actions (who did what on which server),
- in BungeeCord mode the **lobby** as the first server in the list, marked *nur Admins*: it can be managed like every other server but never assigned to a student (see [Lobby](#lobby)).

Every admin can do everything a student can, on every server. Servers with `MC_SERVER_TYPE=custom` only offer start/stop/restart.

### Login with e-mail code

1. E-mail address + password.
2. A 6-digit code is sent to that address — valid 10 minutes, at most 5 attempts, then the login starts over.

- Sessions end after 2 hours without activity and after 12 hours at the latest; releasing a server or deleting/re-inviting an account ends the sessions of that user immediately.
- Passwords are stored as Argon2 hashes; codes, invitation links and session ids only as SHA-256 hashes.
- Failed logins are limited (10 per e-mail address / 30 per IP in 15 minutes), so are code mails (5 per account in 15 minutes).
- "Forgot password" deliberately goes through the teacher (new invitation) — a reset link by mail would make access to the mailbox alone enough, and the second factor would be worthless.
- Only name, e-mail address, assigned server and the password hash are stored, in `adminpanel_data` (not in the repository).

### Assigning and releasing servers

**Assign:** on the overview, *Vergeben …* next to a free server → name + e-mail → the student gets an invitation mail, sets their own password (link valid 7 days, single use) and can log in. An existing account without a server can be assigned again by its e-mail address.

The lobby has no *Vergeben …* — it is admin-only (`"admin_only": true` in `servers.json`). Even if the database were edited by hand, a student never gets access to an admin-only server.

**Release:** *Freigeben …* next to an assigned server. With *Server zurücksetzen* checked, the server is also reset for the next student:

- the server is stopped,
- world and plugin folder are moved to `data/backup-<timestamp>/` on the server's volume (the three newest backups are kept, older ones are deleted),
- whitelist and ops are emptied, the Minecraft version goes back to the default,
- the default plugins are installed again on the next start; the server stays stopped until someone starts it.

### HTTPS

| `--proxy` | What happens |
|---|---|
| `own` (default) | A `caddy` container gets a Let's Encrypt certificate for `--domain`. Ports 80 and 443 must be reachable and the DNS name must point to the host. |
| `caddy-proxy` | The admin page joins the external Docker network `proxy` of the shared [caddy-proxy](https://github.com/cndrbrbr/caddy-proxy) stack; add the block printed by `setup.sh` to that stack's Caddyfile and reload it. |
| `none` | Plain HTTP on `--admin-port` (default 8080). Only for tests or a trusted LAN — passwords and codes travel unencrypted. |

The page refuses cross-site form posts (origin check plus a CSRF token in every form), sets `HttpOnly`/`SameSite` cookies (`Secure` with HTTPS), forbids framing and runs without JavaScript.

### Sending mail

Codes and invitations are sent through an existing mailbox via SMTP. Sending through the provider keeps the mails out of spam folders (the domain's SPF record only allows the provider's servers).

**netcup webhosting** (e.g. `tech@screenpaper.de`): use the mail server's own host name from the WCP, not the domain alias — the TLS certificate is issued for the host name, and the page verifies it. Only SMTP with SSL/TLS on port 465 is offered:

```bash
./setup.sh --mail-from tech@screenpaper.de --smtp-host mx2fed.netcup.net --smtp-port 465 --smtp-tls ssl
```

netcup blocks an IP address for a while after a few failed SMTP logins — if the server suddenly stops answering on all ports, wait before trying again.

The SMTP password is **not** passed on the command line (it would end up in the shell history and the process list). `setup.sh` asks for it with a hidden prompt, or reads it from `--smtp-password-file` or `$SMTP_PASSWORD`, and stores it in `secrets/smtp_password` (mode 600, excluded from git), which is mounted read-only into the admin page.

To change it later: `./setup.sh --smtp-password-file /path/to/file` (or delete `secrets/smtp_password` and re-run `./setup.sh` in a terminal), then `docker compose up -d adminpanel`.

### Mail test mode

With `--mail-test`, no real mail is sent: a `mailpit` container catches every mail and shows it at `http://<host>:8025`. Combined with `--proxy none` this is a complete local test setup:

```bash
./setup.sh --standalone --servers 2 --domain 192.168.1.49 --proxy none --mail-test --admin-email you@example.de
docker compose up -d --build
docker compose exec adminpanel adminctl invite-admin
# open http://192.168.1.49:8025 (mails) and http://192.168.1.49:8080 (admin page)
```

`--domain` must be the address you open in the browser (the page refuses form posts from other origins). Switch back to real mail with `./setup.sh --no-mail-test --mail-from … --smtp-host …`.

### adminctl

Command line tasks inside the admin page container:

```bash
docker compose exec adminpanel adminctl invite-admin [email] [name]   # create admin (default: ADMIN_EMAIL) and send an invitation
docker compose exec adminpanel adminctl list                          # list all accounts
docker compose exec adminpanel adminctl forget-hostkey mc3            # accept a server's new SSH host key (see below)
```

`invite-admin` also prints the invitation link, in case the mail does not arrive.

### How the admin page talks to the servers

The admin page has **no access to the Docker socket**. It controls each server exactly like a student does: over SSH with the server's `ctrl_key` (user `mc-ctrl`, forced into `mc-dispatch.sh`) and `sftp_key` (user `mc-sftp`, chrooted to `/server`, used for plugin uploads). The keys are mounted read-only from `keys/` and copied to a private directory for the unprivileged `app` user at container start. A flaw in the admin page therefore gives no more access than a student already has with PuTTY and FileZilla.

`mc-dispatch.sh` accepts these commands in addition to the PuTTY ones (JSON output where noted); every argument is validated again inside the container:

| Command | Script | Purpose |
|---|---|---|
| `status` | `mc-status.sh` | state, version, players online (JSON) |
| `restart` | `mc-restart.sh` | restart, or start if stopped |
| `plugins`, `catalog` | `mc-plugins.sh` | installed / installable plugins (JSON) |
| `plugin-install <id>`, `plugin-remove <file.jar>` | `mc-plugins.sh` | install from the catalog / remove |
| `players` | `mc-players.sh` | whitelist and ops (JSON) |
| `player-add`, `player-remove`, `op`, `deop <name>` | `mc-players.sh` | whitelist and operator rights |
| `wipe` | `mc-wipe.sh` | reset for the next student (see above) |
| `properties-get`, `properties-set`, `properties-restore` | `mc-properties.sh` | read / replace (content on stdin) / undo `server.properties` |

Whitelist and operator changes take effect immediately through **RCON**: `entrypoint.sh` enables it on every server with a random password kept on the volume (`/server/.rcon-password`); port 25575 is not published. `announce.sh` uses the same path.

The SSH host key of each server is pinned on first contact (trust on first use). If a server's volume is recreated, its host key changes and the admin page refuses the connection until you run `adminctl forget-hostkey <server>`.

### Troubleshooting (admin page)

| Problem | Solution |
|---|---|
| "Die Mail … konnte nicht verschickt werden" | Check `docker compose logs adminpanel`; usually a wrong SMTP password or port. Test with `adminctl invite-admin` (prints the error and the link). |
| Code mail does not arrive | Spam folder; at most 5 codes per 15 minutes. |
| Student forgot the password | Overview → account → *Neue Einladung schicken*. |
| A server shows "nicht erreichbar" | The container is down or still starting — `docker compose ps`, `docker compose logs mcN`. |
| "Der Schlüssel von mcN hat sich geändert" | The server's volume was recreated: `docker compose exec adminpanel adminctl forget-hostkey mcN`. |
| "Forbidden (origin)" on every form | The page is opened under a different address than `--domain`; re-run `setup.sh --domain <address>`. |

---

## Plugin catalog

`spigot/plugin-catalog.json` lists the plugins students can install from the admin page (or with `ssh … plugin-install <id>`). It is based on [plugin-list.md](plugin-list.md); every entry was load-tested on Spigot 26.3 and 1.21.11 (both on Java 25, as in the containers). On the admin page the catalog is grouped and scrolls in its own box; plugins marked *testing* in plugin-list.md show a *Testphase* badge.

| Group | Plugins (id) | 1.21.11 | 26.3 |
|---|---|:-:|:-:|
| Unsere Plugins | `script4kids` (**default**), `cavecompass`, `geomaptools` | ✓ | ✓ |
| Andere Minecraft-Versionen | `viaversion`, `viabackwards` (installs ViaVersion) | ✓ | ✓ |
| Welten & Portale | `multiverse-core`, `multiverse-portals`, `multiverse-netherportals`, `multiverse-inventories`, `multiverse-signportals` (each installs Multiverse-Core), `voidgen`ᵗ, `advanced-portals`ᵗ | ✓ | ✓ |
| Bauen & Schützen | `worldedit` (beta), `blocklocker` | ✓ | ✓ |
| | `worldguard` (installs WorldEdit), `protectionstones`ᵗ (installs WorldGuard + WorldEdit) | – (needs 26.2+) | ✓ |
| | `coreprotect`ᵗ | ✓ | – (refuses 26.3; `max: 26.2`) |
| Spiele | `bedwars`ᵗ (Screaming BedWars) | ✓ | ✓ |
| Technik | `protocollib` (development build), `orebfuscator` (installs ProtocolLib), `vault`ᵗ, `groupmanager`ᵗ | ✓ | ✓ |
| | `prometheus` (PrometheusExporter) — **required**, cannot be removed | ✓ | ✓ |

ᵗ *testing* in plugin-list.md — the plugin loads, but has seen little use on these versions.

Not in the catalog: **Vivecraft Spigot Extension** 1.3.15-1 (crashes on Spigot 26.3 with `NoClassDefFoundError` — apparently Paper-only), **ZNPCs** and **LifeSteal SMP** (downloads only on SpigotMC, which can't be fetched automatically; LifeSteal also needs Helix), **Prometheus4Spigot** (no release yet). The "not recommended" plugins of plugin-list.md are left out as well.

`protocollib` points to ProtocolLib's rolling `dev-build` release, so every image build takes the current development build (plugin-list.md recommends it for 26.3); all other entries are pinned to a version.

Each plugin has one download per Minecraft version where needed (`variants`: the key is the lowest Minecraft version the jar is for; `*` = all versions). All jars are downloaded **when the image is built**, so the servers need no internet access to install plugins.

Before every server start, `mc-plugins.sh sync` installs the default plugins on a fresh server, makes sure the required ones are present, and switches every installed catalog plugin to the jar for the server's current Minecraft version — so `version 1.21.11` / `version 26.3` keeps the plugins working. Plugins students remove stay removed.

**To update a plugin or add one:** edit `spigot/plugin-catalog.json` (fields are explained at the top of the file; `max` limits a plugin to versions up to the given one, `category` and `status` control the admin page), then `docker compose build && docker compose up -d`. Servers pick up the new jar on their next start. Downloads must be direct links (GitHub releases, Modrinth CDN) — SpigotMC pages cannot be downloaded by the build.

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

The default version is **26.3** (`SPIGOT_VERSION`); servers whose student never ran `version` use it.
The image contains the script4kids plugin built for 1.21.11 and for 26.3 (release tags
`v<version>-mc<minecraft>`, version set by `JSMN_VERSION` in `spigot/Dockerfile`); before every start
the matching one is copied to `data/plugins/` — the 26.3 build for 26.3 and newer, the 1.21.11 build
for anything older. script4kids needs at least 1.21.11.

> **Worlds only go forward.** Starting a world with a newer version converts it; an older version can
> no longer load it afterwards (the server fails with `No key dimensions … No key seed` and keeps
> restarting). To go back to an older version, `restore` a backup made with that version or start
> with an empty `data/worlds/`.

**How restore works:** `restore <date|latest>` downloads backup zips from the configured `BACKUP_URL`, stops the server, extracts cfg/plugins/worlds, then waits. The student runs `start` to bring the server back up. See the [Backup and restore](#backup-and-restore) section for setup.

**How adduser works:** `adduser <minecraft-username>` looks up the player's UUID from the Mojang API (or derives it for offline mode), then adds the player to both `whitelist.json` and `ops.json` (operator level 4). If the server is running, the whitelist is reloaded immediately so the player can connect without a restart. Op permissions take effect after the next server restart.

### Broadcast a message to all players

Use `announce.sh` to warn players across all running servers before doing maintenance:

```bash
./announce.sh "Server maintenance in 5 minutes — please save your work!"
./announce.sh "I am restarting mc3 now."
```

The message appears in-game as `[ADMIN] <your text>`. Containers that are not running are automatically skipped.

### Restart only the Minecraft process inside a container (admin shortcut)

```bash
docker compose exec mc3 bash -c 'rm -f /server/.stopped; [ -f /server/.pid ] && kill -TERM "$(cat /server/.pid)"; true'
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

The Spigot JAR is cached on the volume and not rebuilt unless you also set `FORCE_BUILD: "true"` in `docker-compose.yml`. The admin page is rebuilt by the same commands; its accounts are kept in the `adminpanel_data` volume.

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

### Switch deployment mode or number of servers

Re-run `setup.sh` with the new options, then restart everything:

```bash
./setup.sh --standalone          # or --bungeecord, and/or --servers N
docker compose down
docker compose up -d --build
```

World data is preserved in volumes. BungeeCord volumes (`bungee_data`, `lobby_data`) are created fresh if they did not exist. BungeeCord picks up the new server list automatically unless `config.yml` on its volume was edited by hand (then it logs a warning and keeps your version).

When you reduce the number of servers, the volumes of the removed servers are kept; `setup.sh` lists them so you can back them up and delete them with `docker volume rm`. Students assigned to a removed server should be released on the admin page first.

### Re-run memory configuration

If you move the host to a different machine or add RAM:

```bash
./setup.sh
docker compose up -d
```

---

## Configuration reference

All values are set per service in `docker-compose.yml`. To change a setting for one server, edit that service block and run `docker compose up -d --no-deps mcN`.

| Variable | Set by | Description |
|----------|--------|-------------|
| `MC_PORT` | fixed `25565` | Internal Minecraft port (do not change) |
| `MC_NAME` | `docker-compose.yml` | Container name used to locate backups (`mc1` … `mc5`, `lobby`) |
| `MC_MEM_MIN` | `setup.sh` | JVM minimum heap |
| `MC_MEM_MAX` | `setup.sh` | JVM maximum heap |
| `MC_LEVELNAME` | `docker-compose.yml` | World folder name |
| `MC_BUNGEECORD` | `docker-compose.yml` | `true` to enable BungeeCord IP forwarding in spigot.yml |
| `MC_SERVER_TYPE` | `docker-compose.yml` | `spigot` (default) or `custom` — see [Server software](#server-software-spigot-or-a-students-own-custom) |
| `SPIGOT_VERSION` | `docker-compose.yml` | Default Spigot version to build, `26.3` if unset (ignored for `custom`; can be overridden per-server by the student via `version` command) |
| `FORCE_BUILD` | `docker-compose.yml` | `true` to force a Spigot rebuild on next start (ignored for `custom`) |
| `BACKUP_URL` | `docker-compose.yml` | Base URL of the backup HTTP server — required for the `restore` command |
| `SFTP_PUBKEY` | `.env` (via `setup.sh`) | Public key for the SFTP user |
| `CTRL_PUBKEY` | `.env` (via `setup.sh`) | Public key for the control user |

Admin page (`adminpanel` service, all written by `setup.sh`):

| Variable | Description |
|----------|-------------|
| `PUBLIC_URL` | Address of the page, used in mail links and for the origin check |
| `ADMIN_EMAIL` | First admin (`adminctl invite-admin` without arguments) |
| `MAIL_FROM`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_TLS` | Mail sending |
| `SMTP_PASSWORD_FILE` | `/run/secrets/smtp_password` (from `secrets/smtp_password`) |
| `MAIL_TEST` | `true` in mail test mode |

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

### Server addresses and container restarts

BungeeCord resolves the server names (`lobby:25565`, `mc1:25565`, …) only once, at startup. When Docker recreates a server container, it can get a different IP address — the proxy then keeps sending players to the old address, which may now belong to another server (symptom: players get "You are not whitelisted" or end up on the wrong world, and the lobby log shows no login at all). Therefore:

- `docker compose up -d` and `docker compose restart <server>` restart the proxy automatically (`depends_on` with `restart: true` in the generated `docker-compose.yml`).
- The `start-lobby.sh` / `start-mcN.sh` scripts restart the proxy when they had to recreate the container.
- After `docker compose up -d --no-deps <server>` by hand, run `docker compose restart bungee` yourself.

All players are disconnected for a few seconds while the proxy restarts.

### Lobby

The lobby server uses the same Spigot image as the student servers. It is admin-managed only: `setup.sh` gives it its own key pair (`keys/lobby/`, `LOBBY_SFTP_PUBKEY` / `LOBBY_CTRL_PUBKEY` in `.env`), but publishes **no SSH port** for it — only the admin page reaches it, over the `workshop` network. On the admin page it appears as *nur Admins*: admins can start/stop it, manage its plugins, players and `server.properties`, but it cannot be assigned to a student or reset. World data is stored in the `lobby_data` volume.

---

## Firewall (iptables)

Docker-published Ports umgehen die `INPUT`-Chain. Regeln für Docker-Container gehören in die `DOCKER-USER`-Chain — sie greifen nach dem DNAT, bevor das Paket den Container erreicht.

```bash
# Platzhalter ersetzen:
MONITORING_IP="<IP_DES_MINECRAFTDASH_SERVERS>"   # z. B. 10.0.0.5

# ── Prometheus Exporter (container-intern: 9940) ─────────────
# Nur der Monitoring-Server darf die Metriken abrufen.
# Gilt für alle Server gleichzeitig, da sie alle intern auf 9940 lauschen.
iptables -A DOCKER-USER -p tcp --dport 9940 -s "$MONITORING_IP" -j ACCEPT
iptables -A DOCKER-USER -p tcp --dport 9940 -j DROP

# ── Adminseite ───────────────────────────────────────────────
# --proxy own: 80 und 443 müssen öffentlich erreichbar sein (Let's Encrypt).
# --proxy none: Port 8080 (bzw. --admin-port) nur aus dem Schulnetz erlauben:
# iptables -A DOCKER-USER -p tcp --dport 8000 -s <WORKSHOP_NETZ>/24 -j ACCEPT
# iptables -A DOCKER-USER -p tcp --dport 8000 -j DROP
# (DOCKER-USER sieht den Container-Port 8000, nicht den Host-Port.)

# ── Minecraft (container-intern: 25565) ──────────────────────
# Öffentlich erreichbar — keine Einschränkung nötig.
# Optional: nur bestimmtes Netz erlauben:
# iptables -A DOCKER-USER -p tcp --dport 25565 -s <WORKSHOP_NETZ>/24 -j ACCEPT
# iptables -A DOCKER-USER -p tcp --dport 25565 -j DROP
```

> **Regeln dauerhaft speichern** (Debian/Ubuntu):
> ```bash
> apt install iptables-persistent
> netfilter-persistent save
> ```

> **Regeln prüfen:**
> ```bash
> iptables -L DOCKER-USER -n --line-numbers
> ```

> **Einzelne Regel entfernen** (Zeilennummer aus obigem Befehl):
> ```bash
> iptables -D DOCKER-USER <nummer>
> ```

---

## Security model

| Layer | What it does |
|-------|-------------|
| Docker container | Each student's server is fully isolated — no access to other containers or the host filesystem |
| Docker network (BungeeCord mode) | Backend servers are unreachable from outside the internal `workshop` network |
| SSH chroot | `mc-sftp` is locked into `/server` (their own server's root) and cannot navigate outside it or reach any other student's container. Within `/server` they have full read/write access to their own files — the one exception is the `/server` directory entry itself, which OpenSSH requires to stay `root:root` for the chroot to work |
| ForceCommand | `mc-ctrl` is unconditionally forced to run `/mc-dispatch.sh`; no shell access is possible |
| sudo scope | `mc-ctrl` may only sudo the control scripts (`mc-start/stop/version/restore/adduser/status/restart/plugins/players/wipe/properties.sh`), each of which validates its arguments — sudo for anything else is blocked |
| Key-only auth | Password login is disabled on all SSH users |
| No forwarding | TCP, X11, and agent forwarding are disabled |
| RCON | Enabled per server for the admin page, random password on the volume, port 25575 not published |
| Admin page | Password + e-mail code; no Docker socket — controls servers only through the SSH paths above; runs as an unprivileged user; see [Admin page](#admin-page) |

> For a production deployment, restrict the host firewall so Minecraft ports are only reachable from the workshop network, and run the admin page only behind HTTPS (`--proxy own` or `caddy-proxy`).

> A plugin uploaded by a student is arbitrary Java code running inside that student's container — the same as uploading it with FileZilla. Container isolation and the per-server RCON password keep it away from other servers.

---

## File structure

```
mchost/
├── setup.sh                        # first-time setup / re-configuration (mode, servers, admin page, RAM, keys)
├── configure-memory.sh             # old name — runs setup.sh
├── setup-keys.sh                   # old name — runs setup.sh
├── docker-compose.yml              # generated by setup.sh
├── servers.json / servers.txt      # generated: server list for the admin page / for announce.sh, backup.sh
├── Caddyfile                       # generated with --proxy own
├── secrets/smtp_password           # SMTP password (mode 600, excluded from git)
├── announce.sh                     # broadcast a message to all players (via RCON)
├── backup.sh                       # create dated backups of server data volumes
├── backup-server/
│   └── docker-compose.yml          # nginx:alpine that serves backup zips over HTTP (port 8080)
├── start-mc1.sh … start-mcN.sh     # generated — start/restart one server
├── start-bungee.sh, start-lobby.sh # generated in bungeecord mode
├── backups/                        # backup archives (excluded from git)
├── .env                            # settings + public SSH keys — written by setup.sh
├── .env.example                    # empty template
├── plugin-list.md                  # further plugins for Minecraft 26.3
├── STUDENT.md                      # student guide (admin page, FileZilla, PuTTY)
├── LICENSE                         # Apache 2.0
├── adminpanel/
│   ├── Dockerfile                  # python:3.12-slim, unprivileged user
│   ├── entrypoint.sh               # copies the SSH keys for the app user, drops root, starts uvicorn
│   ├── adminctl                    # command line tool (invite-admin, list, forget-hostkey)
│   ├── app/                        # FastAPI app: main.py (pages), security.py (login, codes, sessions),
│   │                               #   servers.py (SSH/SFTP), mailer.py, db.py, templates/, static/
│   └── tests/                      # pytest: login, permissions, CSRF, invitations, uploads
├── bungee/
│   ├── Dockerfile                  # debian:trixie-slim + openjdk + BungeeCord.jar
│   ├── entrypoint.sh               # syncs config.yml to the volume, starts BungeeCord
│   ├── config.base.yml             # template; the server list is filled in by setup.sh
│   └── config.yml                  # generated by setup.sh (online_mode, ip_forward, servers, listener)
└── spigot/
    ├── Dockerfile                  # debian:trixie-slim, GraalVM JDK, openssh-server, two SSH users, plugin catalog
    ├── entrypoint.sh               # SSH host keys → sshd → RCON → plugin sync → builds/runs MC per MC_SERVER_TYPE
    ├── plugin-catalog.json         # installable plugins (see Plugin catalog)
    ├── fetch-catalog.sh            # downloads the catalog jars at image build time
    ├── sshd_config                 # ChrootDirectory for mc-sftp (full server root), ForceCommand for mc-ctrl
    ├── mc-dispatch.sh              # SSH ForceCommand dispatcher (PuTTY and admin page commands)
    ├── mc-start.sh / mc-stop.sh    # .stopped marker → entrypoint loop starts / pauses the server
    ├── mc-restart.sh               # restart (or start)
    ├── mc-status.sh                # state, version, players (JSON)
    ├── mc-version.sh               # writes requested version to /server/.version (spigot type only)
    ├── mc-restore.sh               # fetches backup zips by date, extracts to volume
    ├── mc-plugins.sh               # list/catalog/install/remove plugins, version sync before each start
    ├── mc-players.sh               # whitelist and operators (RCON while running)
    ├── mc-adduser.sh               # PuTTY shortcut: whitelist + op via mc-players.sh
    ├── mc-wipe.sh                  # reset for the next student
    ├── mc-properties.sh            # read/replace/undo server.properties (protected keys kept)
    ├── mc-rcon.py                  # minimal RCON client
    ├── watch_copy.sh               # keeps server.properties in sync with volume
    ├── server.properties           # default server config (copied to volume on first run)
    ├── spigot.yml                  # bungeecord: false by default (set via MC_BUNGEECORD env var)
    ├── minecraft-prometheus-exporter.jar  # PrometheusExporter 3.1.2 (catalog: file:)
    ├── eula.txt                    # eula=true
    └── whitelist.json              # empty by default
```
