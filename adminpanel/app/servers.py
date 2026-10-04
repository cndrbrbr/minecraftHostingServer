"""Controlling the Minecraft servers over their SSH control path.

The admin page holds the per-server control key (mc-ctrl, restricted to
mc-dispatch.sh) and SFTP key (mc-sftp, chrooted to /server) — exactly what a
student has for PuTTY and FileZilla. It never talks to Docker.
"""
import asyncio
import json
import logging
import re
from dataclasses import dataclass

import asyncssh

from .config import Server, Settings
from .db import DB

log = logging.getLogger("adminpanel.servers")

PLAYER_RE = re.compile(r"^[A-Za-z0-9_]{3,16}$")
PLUGIN_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
JAR_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*\.jar$")


class ServerError(Exception):
    pass


@dataclass
class Result:
    ok: bool
    output: str


class ServerControl:
    def __init__(self, settings: Settings, db: DB):
        self.s = settings
        self.db = db

    async def _connect(self, server: Server, user: str, key_name: str):
        key = self.s.keys_dir / server.name / key_name
        if not key.exists():
            raise ServerError(f"Schlüssel für {server.name} fehlt.")
        try:
            conn = await asyncio.wait_for(asyncssh.connect(
                server.host, port=22, username=user, client_keys=[str(key)],
                known_hosts=None, agent_path=None), timeout=10)
        except (OSError, asyncssh.Error, asyncio.TimeoutError) as exc:
            raise ServerError(f"{server.name} ist nicht erreichbar.") from exc
        # Trust on first use: the host key of each server is pinned
        host_key = conn.get_server_host_key()
        fingerprint = host_key.get_fingerprint() if host_key else ""
        row = self.db.one("SELECT key FROM hostkeys WHERE server = ?", server.name)
        if row is None:
            self.db.run("INSERT INTO hostkeys (server, key) VALUES (?, ?)", server.name, fingerprint)
        elif row["key"] != fingerprint:
            conn.close()
            log.error("host key of %s changed: %s != %s", server.name, fingerprint, row["key"])
            raise ServerError(f"Der Schlüssel von {server.name} hat sich geändert – "
                              "aus Sicherheitsgründen wird die Verbindung abgelehnt (siehe README).")
        return conn

    async def run(self, server: Server, command: str, timeout: float = 60) -> Result:
        conn = await self._connect(server, "mc-ctrl", "ctrl_key")
        async with conn:
            try:
                proc = await asyncio.wait_for(conn.run(command, check=False), timeout=timeout)
            except asyncio.TimeoutError as exc:
                raise ServerError(f"{server.name} antwortet nicht.") from exc
        out = ((proc.stdout or "") + (proc.stderr or "")).strip()
        return Result(proc.exit_status == 0, out)

    async def run_json(self, server: Server, command: str):
        res = await self.run(server, command)
        if not res.ok:
            raise ServerError(res.output or f"{command} fehlgeschlagen.")
        try:
            return json.loads(res.output.splitlines()[-1])
        except (ValueError, IndexError) as exc:
            raise ServerError(f"Unerwartete Antwort von {server.name}.") from exc

    # ── convenience wrappers (arguments are validated here AND in the container) ──
    async def status(self, server: Server) -> dict:
        return await self.run_json(server, "status")

    async def plugins(self, server: Server) -> list:
        return await self.run_json(server, "plugins")

    async def catalog(self, server: Server) -> dict:
        return await self.run_json(server, "catalog")

    async def players(self, server: Server) -> dict:
        return await self.run_json(server, "players")

    async def action(self, server: Server, action: str) -> Result:
        if action not in {"start", "stop", "restart", "wipe"}:
            raise ServerError("Unbekannte Aktion.")
        return await self.run(server, action, timeout=120)

    async def install_plugin(self, server: Server, plugin_id: str) -> Result:
        if not PLUGIN_ID_RE.match(plugin_id):
            raise ServerError("Ungültiges Plugin.")
        return await self.run(server, f"plugin-install {plugin_id}")

    async def remove_plugin(self, server: Server, filename: str) -> Result:
        if not JAR_RE.match(filename):
            raise ServerError("Ungültiger Dateiname.")
        return await self.run(server, f"plugin-remove {filename}")

    async def player(self, server: Server, action: str, name: str) -> Result:
        if action not in {"player-add", "player-remove", "op", "deop"}:
            raise ServerError("Unbekannte Aktion.")
        if not PLAYER_RE.match(name):
            raise ServerError("Ungültiger Spielername (3–16 Zeichen: Buchstaben, Ziffern, _).")
        return await self.run(server, f"{action} {name}")

    async def upload_plugin(self, server: Server, filename: str, data: bytes) -> None:
        if not JAR_RE.match(filename):
            raise ServerError("Ungültiger Dateiname.")
        conn = await self._connect(server, "mc-sftp", "sftp_key")
        async with conn:
            async with conn.start_sftp_client() as sftp:
                async with sftp.open(f"/data/plugins/{filename}", "wb") as f:
                    await f.write(data)
