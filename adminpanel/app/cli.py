"""adminctl — command line tasks inside the adminpanel container.

  adminctl invite-admin [email] [name]   create the admin (default: $ADMIN_EMAIL)
                                         if needed and send an invitation
  adminctl list                          list all accounts
  adminctl forget-hostkey <server>       accept a server's new SSH host key
                                         (after its volume was recreated)
"""
import asyncio
import sys

from . import security as sec
from .config import load_settings
from .db import DB
from .mailer import Mailer


def main(argv: list[str]) -> int:
    settings = load_settings()
    db = DB(settings.data_dir / "adminpanel.db")
    cmd = argv[0] if argv else ""

    if cmd == "invite-admin":
        email = (argv[1] if len(argv) > 1 else settings.admin_email).strip().lower()
        name = argv[2] if len(argv) > 2 else "Admin"
        if not email:
            print("No e-mail given and ADMIN_EMAIL is not set.")
            return 1
        user = db.one("SELECT * FROM users WHERE email = ?", email)
        if user is None:
            cur = db.run("INSERT INTO users (email, name, role, created_at) VALUES (?, ?, 'admin', ?)",
                         email, name, sec.now())
            user_id = cur.lastrowid
            print(f"Admin account {email} created.")
        elif user["role"] != "admin":
            print(f"{email} already exists as a student account.")
            return 1
        else:
            user_id = user["id"]
        token = sec.create_invite(db, user_id)
        link = f"{settings.public_url}/invite/{token}"
        db.audit("adminctl", None, "invite admin", email)
        sent = asyncio.run(Mailer(settings).send_invite(email, name, link, None, "admin"))
        print("Invitation sent." if sent else "Sending the invitation FAILED — check the SMTP settings.")
        print(f"Invitation link (valid 7 days, single use):\n  {link}")
        return 0 if sent else 1

    if cmd == "list":
        for u in db.all("SELECT * FROM users ORDER BY role, name"):
            state = "active" if u["password_hash"] else "invited"
            print(f"{u['role']:8} {u['server'] or '-':6} {state:8} {u['name']} <{u['email']}>")
        return 0

    if cmd == "forget-hostkey" and len(argv) > 1:
        db.run("DELETE FROM hostkeys WHERE server = ?", argv[1])
        print(f"Host key of {argv[1]} forgotten; the next connection pins the new one.")
        return 0

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
