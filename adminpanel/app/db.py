"""SQLite storage: users, one-time tokens, sessions, rate-limit events, audit log.

Only what the admin page needs is stored: name, e-mail, assigned server and
an Argon2 password hash. Codes, invitation tokens and session ids are stored
as SHA-256 hashes only.
"""
import sqlite3
import time
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE COLLATE NOCASE,
    name          TEXT NOT NULL,
    role          TEXT NOT NULL CHECK (role IN ('admin', 'student')),
    server        TEXT UNIQUE,
    password_hash TEXT,
    created_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS tokens (
    id          INTEGER PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    purpose     TEXT NOT NULL CHECK (purpose IN ('invite', 'login')),
    token_hash  TEXT NOT NULL,
    session_id  TEXT,
    expires_at  INTEGER NOT NULL,
    attempts    INTEGER NOT NULL DEFAULT 0,
    used        INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS tokens_hash ON tokens(token_hash);
CREATE TABLE IF NOT EXISTS sessions (
    id_hash     TEXT PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    stage       TEXT NOT NULL CHECK (stage IN ('code', 'full')),
    csrf        TEXT NOT NULL,
    flash       TEXT,
    created_at  INTEGER NOT NULL,
    last_seen   INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS events (
    id    INTEGER PRIMARY KEY,
    kind  TEXT NOT NULL,
    key   TEXT NOT NULL,
    ts    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS events_kind_key ON events(kind, key, ts);
CREATE TABLE IF NOT EXISTS hostkeys (
    server  TEXT PRIMARY KEY,
    key     TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS audit (
    id      INTEGER PRIMARY KEY,
    ts      INTEGER NOT NULL,
    actor   TEXT NOT NULL,
    server  TEXT,
    action  TEXT NOT NULL,
    detail  TEXT
);
"""


class DB:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(str(path), check_same_thread=False, isolation_level=None)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA foreign_keys = ON")
        self.conn.execute("PRAGMA journal_mode = WAL")
        self.conn.executescript(SCHEMA)

    def one(self, sql, *args):
        return self.conn.execute(sql, args).fetchone()

    def all(self, sql, *args):
        return self.conn.execute(sql, args).fetchall()

    def run(self, sql, *args):
        return self.conn.execute(sql, args)

    # ── audit log ──
    def audit(self, actor: str, server: str | None, action: str, detail: str = ""):
        self.run(
            "INSERT INTO audit (ts, actor, server, action, detail) VALUES (?, ?, ?, ?, ?)",
            int(time.time()), actor, server, action, detail[:300],
        )
        # keep the log small
        self.run("DELETE FROM audit WHERE id NOT IN (SELECT id FROM audit ORDER BY id DESC LIMIT 1000)")
