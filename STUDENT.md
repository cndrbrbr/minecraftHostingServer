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

> **Your server is yours alone.** Other students have their own separate server and cannot access yours.

---

## Part 1 — FileZilla: upload, edit, and download files

FileZilla lets you transfer files between your computer and your Minecraft server over a secure connection.

### Install FileZilla

Download and install FileZilla from **https://filezilla-project.org** (choose "FileZilla Client").

### Register your key (do this once)

FileZilla needs to know about your `sftp_key` file before it can connect.

1. Open FileZilla.
2. Open the settings:
   - Windows / Linux: **Edit → Settings**
   - macOS: **FileZilla → Preferences**
3. In the left panel click **Connection**, then **SFTP**.
4. Click the **Add key file…** button on the right.
5. A file browser opens. Navigate to your `sftp_key` file and click **Open**.
   - If FileZilla asks *"This file is not in a format supported by FileZilla. Convert it?"* — click **Yes**. Save the converted file in the same folder as the original.
6. The key now appears in the list. Click **OK** to close Settings.

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

## Part 2 — PuTTY: restart your server

PuTTY lets you send a restart command to your server. The connection closes automatically — you do not get a terminal or shell.

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

### Save a PuTTY session (do this once)

Setting up the connection once and saving it means you can reconnect with two clicks next time.

1. Open **PuTTY**.
2. In the left tree, make sure **Session** is selected (it is by default).
3. Fill in:
   - **Host Name:** the host address (e.g. `192.168.1.100`)
   - **Port:** your SSH port (e.g. `2221`)
   - **Connection type:** SSH
4. In the left tree go to **Connection → SSH → Auth → Credentials**.
5. Next to *"Private key file for authentication"* click **Browse…**.
6. Navigate to your `ctrl_key.ppk` file and click **Open**.
7. In the left tree go back to **Session**.
8. In the **Saved Sessions** field type a name, for example `mc-workshop`.
9. Click **Save**.

### Restart the server

1. Open **PuTTY**.
2. In the **Saved Sessions** list, double-click **mc-workshop** (or select it and click **Open**).
3. The first time you connect, PuTTY shows a security warning about the host key — click **Accept**.
4. A small terminal window appears. Type `mc-ctrl` and press **Enter** as the username.

   > On some setups PuTTY fills the username automatically. If it does, you skip the typing step.

5. The terminal shows:

   ```
   ==> Stopping Minecraft server...
   ==> Server will restart automatically in a few seconds.
   ==> You may close this connection.
   ```

6. You can close the PuTTY window. Your server restarts within about 10 seconds.

---

## Typical workflow during the workshop

1. Write or edit your script / plugin on your computer.
2. Open FileZilla → upload the `.jar` file to `/data/plugins/` (or edit config files in `/data/cfg/`).
3. Open PuTTY → restart the server.
4. Wait ~10 seconds, then connect to Minecraft and test your changes.
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
- Make sure the key was registered correctly in Settings → Connection → SFTP.
- You may have the wrong key file — check that you are using `sftp_key` (not `ctrl_key`).

**PuTTY says "Access denied"**
- Type the username exactly: `mc-ctrl` (all lowercase, hyphen between mc and ctrl).
- Make sure you loaded `ctrl_key.ppk` (the converted file, not `ctrl_key`).

**PuTTY shows "The server's host key is not cached"**
- Click **Accept** — this is normal on the first connection.

**I uploaded a plugin but it doesn't work**
- Did you restart the server after uploading? The server must restart to load new plugins.
- Check that the `.jar` file is in `/data/plugins/` and not in `/data/` by mistake.

**My Minecraft client can't connect to the server**
- Wait 10–15 seconds after restarting — the server needs time to come back up.
- Make sure you are using the correct port number for your server.
