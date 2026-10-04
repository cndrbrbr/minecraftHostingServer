"""Passwords, one-time codes/tokens, sessions and rate limiting."""
import hashlib
import hmac
import secrets
import time

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

from .db import DB

CODE_TTL = 10 * 60              # login code valid for 10 minutes
CODE_MAX_ATTEMPTS = 5           # wrong codes before the login starts over
INVITE_TTL = 7 * 24 * 3600      # invitation link valid for 7 days
SESSION_IDLE = 2 * 3600         # logged out after 2 h without activity
SESSION_MAX = 12 * 3600         # and after 12 h at the latest
PENDING_MAX = 15 * 60           # password ok, code not yet entered
MIN_PASSWORD = 8

# (kind, limit, window seconds)
LIMIT_LOGIN_EMAIL = ("login-fail-email", 10, 15 * 60)
LIMIT_LOGIN_IP = ("login-fail-ip", 30, 15 * 60)
LIMIT_CODE_MAIL = ("code-mail", 5, 15 * 60)

_ph = PasswordHasher()
# Verified against when the e-mail is unknown, so the response time doesn't
# reveal which addresses have an account.
_DUMMY_HASH = _ph.hash(secrets.token_urlsafe(16))


def sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def now() -> int:
    return int(time.time())


# ── passwords ─────────────────────────────────────────────────
def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(stored_hash: str | None, password: str) -> bool:
    try:
        return _ph.verify(stored_hash or _DUMMY_HASH, password) and stored_hash is not None
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def password_problem(password: str, confirm: str) -> str | None:
    if password != confirm:
        return "Die beiden Passwörter stimmen nicht überein."
    if len(password) < MIN_PASSWORD:
        return f"Das Passwort muss mindestens {MIN_PASSWORD} Zeichen lang sein."
    if len(password) > 200:
        return "Das Passwort ist zu lang."
    return None


# ── rate limiting ─────────────────────────────────────────────
def limited(db: DB, limit: tuple[str, int, int], key: str) -> bool:
    kind, count, window = limit
    row = db.one("SELECT COUNT(*) AS n FROM events WHERE kind = ? AND key = ? AND ts > ?",
                 kind, key.lower(), now() - window)
    return row["n"] >= count


def record(db: DB, limit: tuple[str, int, int], key: str) -> None:
    db.run("INSERT INTO events (kind, key, ts) VALUES (?, ?, ?)", limit[0], key.lower(), now())
    db.run("DELETE FROM events WHERE ts < ?", now() - 24 * 3600)


# ── invitation tokens ─────────────────────────────────────────
def create_invite(db: DB, user_id: int) -> str:
    """New invitation link token; earlier unused invitations become invalid."""
    db.run("DELETE FROM tokens WHERE user_id = ? AND purpose = 'invite'", user_id)
    token = secrets.token_urlsafe(32)
    db.run("INSERT INTO tokens (user_id, purpose, token_hash, expires_at) VALUES (?, 'invite', ?, ?)",
           user_id, sha256(token), now() + INVITE_TTL)
    return token


def find_invite(db: DB, token: str):
    return db.one(
        "SELECT t.id AS token_id, u.* FROM tokens t JOIN users u ON u.id = t.user_id "
        "WHERE t.token_hash = ? AND t.purpose = 'invite' AND t.used = 0 AND t.expires_at > ?",
        sha256(token), now())


def use_invite(db: DB, token_id: int) -> None:
    db.run("UPDATE tokens SET used = 1 WHERE id = ?", token_id)


# ── login codes ───────────────────────────────────────────────
def create_login_code(db: DB, user_id: int, session_hash: str) -> str:
    """6-digit code bound to one pending session; replaces earlier codes."""
    db.run("DELETE FROM tokens WHERE purpose = 'login' AND session_id = ?", session_hash)
    code = f"{secrets.randbelow(1_000_000):06d}"
    db.run("INSERT INTO tokens (user_id, purpose, token_hash, session_id, expires_at) VALUES (?, 'login', ?, ?, ?)",
           user_id, sha256(session_hash + ":" + code), session_hash, now() + CODE_TTL)
    return code


def check_login_code(db: DB, session_hash: str, code: str) -> str:
    """Returns 'ok', 'wrong' (try again) or 'expired' (start over)."""
    row = db.one("SELECT * FROM tokens WHERE purpose = 'login' AND session_id = ? AND used = 0",
                 session_hash)
    if row is None or row["expires_at"] <= now() or row["attempts"] >= CODE_MAX_ATTEMPTS:
        return "expired"
    code = "".join(ch for ch in code if ch.isdigit())
    if hmac.compare_digest(row["token_hash"], sha256(session_hash + ":" + code)):
        db.run("UPDATE tokens SET used = 1 WHERE id = ?", row["id"])
        return "ok"
    db.run("UPDATE tokens SET attempts = attempts + 1 WHERE id = ?", row["id"])
    return "expired" if row["attempts"] + 1 >= CODE_MAX_ATTEMPTS else "wrong"


# ── sessions ──────────────────────────────────────────────────
def create_session(db: DB, user_id: int, stage: str) -> tuple[str, str]:
    """Returns (cookie value, its hash). Only the hash is stored."""
    sid = secrets.token_urlsafe(32)
    h = sha256(sid)
    db.run("INSERT INTO sessions (id_hash, user_id, stage, csrf, created_at, last_seen) VALUES (?, ?, ?, ?, ?, ?)",
           h, user_id, stage, secrets.token_urlsafe(24), now(), now())
    return sid, h


def load_session(db: DB, sid: str | None):
    """Session row joined with its user, or None if missing/expired."""
    if not sid:
        return None
    h = sha256(sid)
    row = db.one(
        "SELECT s.id_hash, s.stage, s.csrf, s.flash, s.created_at, s.last_seen, "
        "u.id AS user_id, u.email, u.name, u.role, u.server "
        "FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.id_hash = ?", h)
    if row is None:
        return None
    t = now()
    max_age = PENDING_MAX if row["stage"] == "code" else SESSION_MAX
    if t - row["last_seen"] > SESSION_IDLE or t - row["created_at"] > max_age:
        db.run("DELETE FROM sessions WHERE id_hash = ?", h)
        return None
    db.run("UPDATE sessions SET last_seen = ? WHERE id_hash = ?", t, h)
    return row


def end_session(db: DB, session_hash: str) -> None:
    db.run("DELETE FROM sessions WHERE id_hash = ?", session_hash)
    db.run("DELETE FROM tokens WHERE purpose = 'login' AND session_id = ?", session_hash)


def end_user_sessions(db: DB, user_id: int) -> None:
    db.run("DELETE FROM sessions WHERE user_id = ?", user_id)


def set_flash(db: DB, session_hash: str, message: str, kind: str = "ok") -> None:
    db.run("UPDATE sessions SET flash = ? WHERE id_hash = ?", f"{kind}|{message}", session_hash)


def pop_flash(db: DB, session) -> tuple[str, str] | None:
    if not session or not session["flash"]:
        return None
    db.run("UPDATE sessions SET flash = NULL WHERE id_hash = ?", session["id_hash"])
    kind, _, message = session["flash"].partition("|")
    return kind, message
