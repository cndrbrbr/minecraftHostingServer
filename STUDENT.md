# Minecraft Workshop — Student Guide

Welcome to the JavaScript Minecraft Workshop! This guide explains how to upload files to your Minecraft server and how to restart it.

---

## Your connection details

Your teacher fills in this table for you before handing out this guide.

| | Address | Username |
|-|---------|----------|
| **FileZilla (SFTP)** | `sftp://____________________:________` | `mc-sftp` |
| **PuTTY (SSH restart)** | `____________________:________` | `mc-ctrl` |
| **Minecraft client** | `____________________:________` | your Minecraft name |

Your two key files:
- `sftp_key` — for FileZilla
- `ctrl_key` — for PuTTY (needs to be converted once, see below)

> **Your server is yours alone.** Other students have their own separate server and cannot access yours.

---

## Part 1 — FileZilla: upload, edit, and download files

FileZilla lets you transfer files between your computer and your Minecraft server over a secure connection.

### Install FileZilla

Download and install FileZilla from **https://filezilla-project.org** (choose "FileZilla Client").

### Step 1 — Convert the key with PuTTYgen (do this once)

FileZilla works most reliably with keys in the `.ppk` format. You convert your `sftp_key` file once using **PuTTYgen** (installed together with PuTTY).

1. Open **PuTTYgen** (search for it in the Start menu).
2. Click **Load**.
3. In the file browser, change the dropdown in the bottom-right corner from *"PuTTY Private Key Files (\*.ppk)"* to **All Files (\*.\*)**.
4. Navigate to your `sftp_key` file and click **Open**.
5. PuTTYgen shows *"Successfully imported foreign key"* — click **OK**.
6. Click **Save private key**.
7. When asked about a passphrase, click **Yes** (save without one).
8. Save the file as **`sftp_key.ppk`** in the same folder as the original `sftp_key`.

### Step 2 — Register the key in FileZilla (do this once)

1. Open FileZilla.
2. Open the settings:
   - Windows / Linux: **Edit → Settings**
   - macOS: **FileZilla → Preferences**
3. In the left panel click **Connection → SFTP**.
4. Click **Add key file…**
5. Navigate to your **`sftp_key.ppk`** file (the converted one) and click **Open**.
6. The key appears in the list. Click **OK**.

You only need to do this once. FileZilla remembers the key.

### Connect to your server

1. Look at the toolbar at the very top of the FileZilla window. Fill in these four fields:

   | Field | What to enter |
   |-------|---------------|
   | **Host** | `sftp://` followed by the host address — for example `sftp://192.168.1.100` |
   | **Username** | `mc-sftp` |
   | **Password** | *(leave completely empty)* |
   | **Port** | your SSH port (e.g. `2221`) |

2. Click **Quickconnect**.

3. The first time you connect, FileZilla shows a warning:
   *"The server's host key is unknown. Do you trust this host?"*
   Click **OK** (or **Trust / Always trust**). This warning will not appear again.

4. FileZilla connects and you see two panels. The **right panel** shows your server's files.

### Your server's file structure

After connecting you land directly in your server's data folder `/data/`:

```
/data/
├── cfg/          — configuration files (server.properties, bukkit.yml, …)
├── plugins/      — this is where you upload your plugin .jar files
└── worlds/       — world saves (don't delete these during the workshop)
```

### Upload a plugin file

1. In the **left panel** (your computer), navigate to the folder where your `.jar` file is saved.
2. In the **right panel** (your server), open the `plugins` folder by double-clicking it.
3. Drag the `.jar` file from the left panel into the right panel.
4. FileZilla shows the transfer in the queue at the bottom. Wait until it says *"Successful transfers"*.
5. **Restart your server** (see Part 2) so the new plugin is loaded.

### Edit a file on the server

1. In the right panel, navigate to the file you want to edit.
2. Right-click the file → **View/Edit**.
3. FileZilla opens the file in a text editor on your computer.
4. Make your changes and **save** the file (Ctrl+S).
5. FileZilla detects the change and asks *"Do you want to upload the file?"* — click **Yes**.
6. Restart your server if the file was a config file or plugin.

### Download a file from the server

1. In the right panel, navigate to the file you want to download.
2. Drag it from the right panel into the left panel (your computer).
   Or: right-click → **Download**.

---

## Part 2 — PuTTY: start, stop, change version, and add players

PuTTY lets you send commands to your server. The connection closes automatically after each command — you do not get a terminal or shell.

You can send four commands:

| Command | What it does |
|---------|-------------|
| `stop` | Stops the Minecraft server |
| `start` | Starts the Minecraft server again |
| `version 1.20.4` | Switches to a different Spigot version (takes effect after stop + start) |
| `adduser CoolPlayer99` | Adds a Minecraft player to your whitelist and makes them an operator |

### Install PuTTY

Download the **MSI installer** from **https://putty.org** and install it. PuTTY comes with PuTTYgen, which you need in the next step.

### Convert your key (do this once)

PuTTY uses a different key format than the `ctrl_key` file you received. You need to convert it once with **PuTTYgen**.

1. Open **PuTTYgen** (search for it in the Start menu).
2. Click the **Load** button.
3. In the file browser, find the dropdown in the bottom-right corner that says *"PuTTY Private Key Files (\*.ppk)"* and change it to **All Files (\*.\*)**.
4. Navigate to your `ctrl_key` file and click **Open**.
5. PuTTYgen shows: *"Successfully imported foreign key …"* — click **OK**.
6. Click **Save private key**.
7. PuTTYgen asks *"Are you sure you want to save this key without a passphrase?"* — click **Yes**.
8. Save the file as **`ctrl_key.ppk`** in the same folder as the original `ctrl_key`.

You only need to do this once.

### Save PuTTY sessions (do this once)

Save a separate session for each command so you can run them with two clicks.

**For each session, follow these steps — only the Session Name and Remote command differ:**

1. Open **PuTTY**.
2. In the left tree make sure **Session** is selected.
3. Fill in:
   - **Host Name:** the host address (e.g. `192.168.1.100`)
   - **Port:** your SSH port (e.g. `2221`)
   - **Connection type:** SSH
4. In the left tree go to **Connection → Data**.
5. In the **Auto-login username** field type `mc-ctrl`.
6. In the left tree go to **Connection → SSH**.
7. In the **Remote command** field type the command for this session (see table below).
8. In the left tree go to **Connection → SSH → Auth → Credentials**.
9. Next to *"Private key file for authentication"* click **Browse…** and open your `ctrl_key.ppk`.
10. In the left tree go back to **Session**.
11. Type the session name in the **Saved Sessions** field and click **Save**.

| Session name | Remote command |
|---|---|
| `mc-stop` | `stop` |
| `mc-start` | `start` |
| `mc-version-1.20.4` | `version 1.20.4` *(change the number as needed)* |
| `mc-adduser` | `adduser YourMinecraftName` *(change the name as needed)* |

### Stop the server

1. Open **PuTTY** and double-click **mc-stop**.
2. The first time, PuTTY shows a security warning — click **Accept**.
3. The terminal shows:
   ```
   ==> Server stopped.
   ==> Use the start command to bring it back up.
   ==> You may close this connection.
   ```
4. Close the window. Players can no longer connect to your server.

### Start the server

1. Open **PuTTY** and double-click **mc-start**.
2. The terminal shows:
   ```
   ==> Starting Minecraft server — it will be available in a few seconds.
   ==> You may close this connection.
   ```
3. Close the window. Wait about 30 seconds, then connect from Minecraft.

### Change the Spigot version

1. Open **PuTTY** and double-click the version session (e.g. `mc-version-1.20.4`).
2. The terminal shows:
   ```
   ==> Version set to 1.20.4.
   ==> Run 'stop' then 'start' to apply.
   ==> If this version has not been used before, the first start
   ==> will take several minutes to compile it.
   ```
3. Now run **mc-stop**, then **mc-start**.
4. If this is the first time that version is used, the server takes several minutes to start while it compiles. Wait for the Minecraft server to become reachable before connecting.

> To set a different version later, create a new PuTTY session with a different **Remote command** (e.g. `version 1.21.1`) and save it under a new name.

### Add a player to your server

Use this command to let a specific Minecraft player join your server and give them operator permissions.

1. Open **PuTTY** and double-click **mc-adduser**.
2. The terminal shows:
   ```
   ==> Looking up 'CoolPlayer99' in Mojang API...
   ==> UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ==> 'CoolPlayer99' added to whitelist.
   ==> 'CoolPlayer99' added to ops (level 4).
   ==> Whitelist reloaded — 'CoolPlayer99' can connect immediately.
   ==> Operator permissions take effect after the next server restart.
   ==> Done. You may close this connection.
   ```
3. Close the window. The player can now connect to your server.

> To add a different player, create a new PuTTY session with a different **Remote command** (e.g. `adduser AnotherPlayer`) and save it under a new name.

---

## Typical workflow during the workshop

1. Write or edit your script / plugin on your computer.
2. Open FileZilla → upload the `.jar` file to `/data/plugins/` (or edit config files in `/data/cfg/`).
3. Open PuTTY → run **mc-stop**, then **mc-start**.
4. Wait ~30 seconds, then connect to Minecraft and test your changes.
5. Repeat.

---

## Connect to your Minecraft server

Open **Minecraft Java Edition**, go to **Multiplayer → Add Server** and enter the address from your connection table above (the row labelled *Minecraft client*). It looks like:

```
192.168.1.100:25565
```

The server must be running before you can connect. If it just restarted, wait 10–15 seconds first.

---

## Troubleshooting

**FileZilla says "Connection refused" or times out**
- Check that the host address and port are correct.
- Make sure you typed `mc-sftp` as the username (not your own name).
- Ask your teacher whether the servers are running.

**FileZilla says "Authentication failed"**
- Make sure you converted `sftp_key` to `sftp_key.ppk` with PuTTYgen first, and loaded the `.ppk` file in Settings → Connection → SFTP.
- You may have the wrong key file — check that you are using `sftp_key.ppk` (not `ctrl_key` or `ctrl_key.ppk`).

**PuTTY says "Access denied"**
- Make sure the **Auto-login username** in the session is set to `mc-ctrl`.
- Make sure you loaded `ctrl_key.ppk` (the converted file, not `ctrl_key`).
- Check that the **Remote command** in the session is exactly `stop`, `start`, or `version 1.x.x`.

**PuTTY opens and closes immediately without showing any message**
- This is normal — it means the command ran successfully.
- If it happens for `start`, wait 30 seconds and try to connect from Minecraft.

**PuTTY shows "The server's host key is not cached"**
- Click **Accept** — this is normal on the first connection.

**I uploaded a plugin but it doesn't work**
- Did you restart the server after uploading? The server must restart to load new plugins.
- Check that the `.jar` file is in `/data/plugins/` and not in `/data/` by mistake.

**My Minecraft client can't connect to the server**
- Wait 10–15 seconds after restarting — the server needs time to come back up.
- Make sure you are using the correct port number for your server.
