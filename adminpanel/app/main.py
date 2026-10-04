"""Admin page for the Minecraft hosting server.

Students: start/stop their own server, install or upload plugins, manage
whitelist and operators. Admins (teachers): everything for every server,
plus assigning servers to students and resetting them.

Login: e-mail + password, then a 6-digit code sent to that e-mail address.
"""
import asyncio
import logging
import re
from datetime import datetime
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

from fastapi import FastAPI, Form, Request, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from . import security as sec
from .config import Settings, load_settings
from .db import DB
from .jarcheck import MAX_SIZE, JarError, inspect_jar
from .mailer import Mailer
from .servers import ServerControl, ServerError

log = logging.getLogger("adminpanel")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

COOKIE = "mcadmin"
MAX_PROPERTIES = 64 * 1024
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
STATE_LABELS = {
    "running": ("läuft", "ok"),
    "starting": ("startet …", "busy"),
    "building": ("wird gebaut …", "busy"),
    "stopped": ("gestoppt", "off"),
    "unreachable": ("nicht erreichbar", "err"),
}


def create_app(settings: Settings | None = None, db: DB | None = None,
               control: ServerControl | None = None, mailer: Mailer | None = None) -> FastAPI:
    settings = settings or load_settings()
    db = db or DB(settings.data_dir / "adminpanel.db")
    control = control or ServerControl(settings, db)
    mailer = mailer or Mailer(settings)

    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
    app.state.settings, app.state.db, app.state.control, app.state.mailer = settings, db, control, mailer
    base = __file__.rsplit("/", 1)[0]
    app.mount("/static", StaticFiles(directory=f"{base}/static"), name="static")
    templates = Jinja2Templates(directory=f"{base}/templates")
    templates.env.globals["state_labels"] = STATE_LABELS
    tz = ZoneInfo("Europe/Berlin")
    templates.env.filters["datetime"] = lambda ts: datetime.fromtimestamp(ts, tz).strftime("%d.%m. %H:%M")

    # ── helpers ───────────────────────────────────────────────
    def client_ip(request: Request) -> str:
        fwd = request.headers.get("x-forwarded-for", "")
        return fwd.split(",")[0].strip() if fwd else (request.client.host if request.client else "?")

    def redirect(url: str) -> RedirectResponse:
        return RedirectResponse(url, status_code=303)

    def set_cookie(resp: Response, value: str) -> None:
        resp.set_cookie(COOKIE, value, httponly=True, samesite="lax",
                        secure=settings.secure_cookies, max_age=sec.SESSION_MAX, path="/")

    def page(request: Request, template: str, session=None, status_code: int = 200, **ctx) -> HTMLResponse:
        ctx.update(request=request, session=session, flash=sec.pop_flash(db, session),
                   servers=settings.servers, mode=settings.mode)
        resp = templates.TemplateResponse(request, template, ctx, status_code=status_code)
        resp.headers["Cache-Control"] = "no-store"
        return resp

    def flash_redirect(session, url: str, message: str, kind: str = "ok") -> RedirectResponse:
        sec.set_flash(db, session["id_hash"], message, kind)
        return redirect(url)

    def current(request: Request, stage: str = "full"):
        s = sec.load_session(db, request.cookies.get(COOKIE))
        if s is None or s["stage"] != stage:
            return None
        return s

    def can_access(session, server_name: str) -> bool:
        return server_name in settings.servers and (
            session["role"] == "admin" or session["server"] == server_name)

    def actor(session) -> str:
        return f"{session['name']} <{session['email']}>"

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        # Cross-site POSTs are refused (in addition to the CSRF token per form)
        if request.method == "POST":
            origin = request.headers.get("origin")
            if origin and origin != settings.origin:
                expected_host = urlparse(settings.public_url).netloc
                if urlparse(origin).netloc != expected_host:
                    return Response("Forbidden (origin)", status_code=403)
        resp = await call_next(request)
        resp.headers.setdefault("X-Frame-Options", "DENY")
        resp.headers.setdefault("X-Content-Type-Options", "nosniff")
        # same-origin, not no-referrer: with no-referrer browsers send "Origin: null"
        # on form posts, which the origin check above would refuse.
        resp.headers.setdefault("Referrer-Policy", "same-origin")
        resp.headers.setdefault("Content-Security-Policy",
                                "default-src 'self'; style-src 'self'; img-src 'self' data:; "
                                "form-action 'self'; frame-ancestors 'none'")
        return resp

    def csrf_ok(session, token: str) -> bool:
        return session is not None and sec.hmac.compare_digest(session["csrf"], token or "")

    # ── login ─────────────────────────────────────────────────
    @app.get("/login")
    async def login_form(request: Request):
        if current(request):
            return redirect("/")
        return page(request, "login.html", info=request.query_params.get("info"))

    @app.post("/login")
    async def login(request: Request, email: str = Form(""), password: str = Form("")):
        email = email.strip().lower()
        ip = client_ip(request)
        if sec.limited(db, sec.LIMIT_LOGIN_EMAIL, email) or sec.limited(db, sec.LIMIT_LOGIN_IP, ip):
            return page(request, "login.html", status_code=429, email=email,
                        error="Zu viele Fehlversuche. Bitte warte 15 Minuten.")
        user = db.one("SELECT * FROM users WHERE email = ?", email)
        if not sec.verify_password(user["password_hash"] if user else None, password):
            sec.record(db, sec.LIMIT_LOGIN_EMAIL, email)
            sec.record(db, sec.LIMIT_LOGIN_IP, ip)
            return page(request, "login.html", status_code=401, email=email,
                        error="Mailadresse oder Passwort stimmt nicht.")
        if sec.limited(db, sec.LIMIT_CODE_MAIL, str(user["id"])):
            return page(request, "login.html", status_code=429, email=email,
                        error="Es wurden gerade zu viele Codes verschickt. Bitte warte 15 Minuten.")
        sid, h = sec.create_session(db, user["id"], "code")
        code = sec.create_login_code(db, user["id"], h)
        sec.record(db, sec.LIMIT_CODE_MAIL, str(user["id"]))
        if not await mailer.send_code(user["email"], user["name"], code):
            sec.end_session(db, h)
            return page(request, "login.html", status_code=502, email=email,
                        error="Die Mail mit dem Code konnte nicht verschickt werden. Bitte sag deiner Lehrkraft Bescheid.")
        resp = redirect("/login/code")
        set_cookie(resp, sid)
        return resp

    @app.get("/login/code")
    async def code_form(request: Request):
        s = current(request, "code")
        if s is None:
            return redirect("/login")
        return page(request, "code.html", s, email=s["email"])

    @app.post("/login/code")
    async def code_check(request: Request, code: str = Form(""), csrf: str = Form("")):
        s = current(request, "code")
        if s is None or not csrf_ok(s, csrf):
            return redirect("/login")
        result = sec.check_login_code(db, s["id_hash"], code)
        if result == "wrong":
            return page(request, "code.html", s, status_code=401, email=s["email"],
                        error="Der Code stimmt nicht. Versuch es noch einmal.")
        if result == "expired":
            sec.end_session(db, s["id_hash"])
            return redirect("/login?info=code")
        # Fresh session id after login (no session fixation)
        sec.end_session(db, s["id_hash"])
        sid, _ = sec.create_session(db, s["user_id"], "full")
        db.audit(actor(s), None, "login")
        resp = redirect("/")
        set_cookie(resp, sid)
        return resp

    @app.post("/login/code/resend")
    async def code_resend(request: Request, csrf: str = Form("")):
        s = current(request, "code")
        if s is None or not csrf_ok(s, csrf):
            return redirect("/login")
        if sec.limited(db, sec.LIMIT_CODE_MAIL, str(s["user_id"])):
            return page(request, "code.html", s, status_code=429, email=s["email"],
                        error="Es wurden gerade zu viele Codes verschickt. Bitte warte 15 Minuten.")
        code = sec.create_login_code(db, s["user_id"], s["id_hash"])
        sec.record(db, sec.LIMIT_CODE_MAIL, str(s["user_id"]))
        sent = await mailer.send_code(s["email"], s["name"], code)
        return page(request, "code.html", s, email=s["email"],
                    info="Ein neuer Code ist unterwegs." if sent else None,
                    error=None if sent else "Die Mail konnte nicht verschickt werden.")

    @app.post("/logout")
    async def logout(request: Request):
        s = sec.load_session(db, request.cookies.get(COOKIE))
        if s:
            sec.end_session(db, s["id_hash"])
        resp = redirect("/login")
        resp.delete_cookie(COOKIE, path="/")
        return resp

    # ── invitation: set own password ──────────────────────────
    @app.get("/invite/{token}")
    async def invite_form(request: Request, token: str):
        row = sec.find_invite(db, token)
        if row is None:
            return page(request, "message.html", status_code=404, title="Link ungültig",
                        text="Dieser Einladungslink ist abgelaufen oder wurde schon benutzt. "
                             "Bitte deine Lehrkraft um eine neue Einladung.")
        return page(request, "invite.html", name=row["name"], email=row["email"], token=token)

    @app.post("/invite/{token}")
    async def invite_set(request: Request, token: str, password: str = Form(""), confirm: str = Form("")):
        row = sec.find_invite(db, token)
        if row is None:
            return redirect(f"/invite/{token}")
        problem = sec.password_problem(password, confirm)
        if problem:
            return page(request, "invite.html", status_code=400, name=row["name"],
                        email=row["email"], token=token, error=problem)
        db.run("UPDATE users SET password_hash = ? WHERE id = ?", sec.hash_password(password), row["id"])
        sec.use_invite(db, row["token_id"])
        sec.end_user_sessions(db, row["id"])
        db.audit(f"{row['name']} <{row['email']}>", None, "password set")
        return redirect("/login?info=password")

    # ── start page ────────────────────────────────────────────
    @app.get("/")
    async def home(request: Request):
        s = current(request)
        if s is None:
            return redirect("/login")
        if s["role"] == "admin":
            return redirect("/admin")
        if s["server"] and s["server"] in settings.servers:
            return redirect(f"/server/{s['server']}")
        return page(request, "message.html", s, title="Noch kein Server",
                    text="Dir ist im Moment kein Minecraft-Server zugeordnet. "
                         "Deine Lehrkraft kann dir einen Server geben.")

    # ── one server ────────────────────────────────────────────
    async def safe(coro, default):
        try:
            return await coro, None
        except ServerError as exc:
            return default, str(exc)

    @app.get("/server/{name}")
    async def server_page(request: Request, name: str):
        s = current(request)
        if s is None:
            return redirect("/login")
        if not can_access(s, name):
            return page(request, "message.html", s, status_code=403, title="Kein Zugriff",
                        text="Das ist nicht dein Server.")
        server = settings.servers[name]
        (status, err), (plugins, _), (catalog, _), (players, _) = await asyncio.gather(
            safe(control.status(server), {"state": "unreachable"}),
            safe(control.plugins(server), []),
            safe(control.catalog(server), {"version": "", "plugins": []}),
            safe(control.players(server), {"whitelist": [], "ops": []}),
        )
        owner = db.one("SELECT name, email FROM users WHERE server = ?", name)
        return page(request, "server.html", s, server=server, status=status, error=err,
                    plugins=plugins, catalog=catalog, players=players, owner=owner,
                    max_upload_mb=MAX_SIZE // (1024 * 1024))

    async def server_action(request: Request, name: str, csrf: str, run, success: str, audit_action: str,
                            detail: str = ""):
        s = current(request)
        if s is None:
            return redirect("/login")
        if not can_access(s, name) or not csrf_ok(s, csrf):
            return Response("Forbidden", status_code=403)
        try:
            res = await run(settings.servers[name])
        except ServerError as exc:
            return flash_redirect(s, f"/server/{name}", str(exc), "err")
        db.audit(actor(s), name, audit_action, detail)
        if res is not None and not res.ok:
            return flash_redirect(s, f"/server/{name}", res.output or "Das hat nicht geklappt.", "err")
        return flash_redirect(s, f"/server/{name}", success)

    @app.post("/server/{name}/power")
    async def power(request: Request, name: str, action: str = Form(""), csrf: str = Form("")):
        messages = {"start": "Der Server startet. Das dauert etwa eine halbe Minute.",
                    "stop": "Der Server wurde gestoppt.",
                    "restart": "Der Server startet neu. Das dauert etwa eine halbe Minute."}
        if action not in messages:
            return Response("Bad request", status_code=400)
        return await server_action(request, name, csrf, lambda srv: control.action(srv, action),
                                   messages[action], action)

    @app.post("/server/{name}/plugins/install")
    async def plugin_install(request: Request, name: str, plugin: str = Form(""), csrf: str = Form("")):
        return await server_action(
            request, name, csrf, lambda srv: control.install_plugin(srv, plugin),
            "Plugin installiert. Starte den Server neu, damit es aktiv wird.", "plugin install", plugin)

    @app.post("/server/{name}/plugins/remove")
    async def plugin_remove(request: Request, name: str, file: str = Form(""), csrf: str = Form("")):
        return await server_action(
            request, name, csrf, lambda srv: control.remove_plugin(srv, file),
            "Plugin entfernt. Starte den Server neu, damit es nicht mehr geladen wird.", "plugin remove", file)

    @app.post("/server/{name}/plugins/upload")
    async def plugin_upload(request: Request, name: str, jar: UploadFile, csrf: str = Form("")):
        s = current(request)
        if s is None:
            return redirect("/login")
        if not can_access(s, name) or not csrf_ok(s, csrf):
            return Response("Forbidden", status_code=403)
        data = await jar.read(MAX_SIZE + 1)
        try:
            plugin_name, version, filename = inspect_jar(data)
        except JarError as exc:
            return flash_redirect(s, f"/server/{name}", str(exc), "err")
        server = settings.servers[name]
        try:
            installed = await control.plugins(server)
            for p in installed:
                if p["name"].lower() == plugin_name.lower():
                    if p.get("locked"):
                        return flash_redirect(s, f"/server/{name}",
                                              f"{plugin_name} ist ein Pflicht-Plugin und kann nicht ersetzt werden.", "err")
                    if p["file"] != filename:
                        res = await control.remove_plugin(server, p["file"])
                        if not res.ok:
                            return flash_redirect(s, f"/server/{name}", res.output, "err")
            await control.upload_plugin(server, filename, data)
        except ServerError as exc:
            return flash_redirect(s, f"/server/{name}", str(exc), "err")
        except Exception:  # noqa: BLE001
            log.exception("upload to %s failed", name)
            return flash_redirect(s, f"/server/{name}", "Das Hochladen hat nicht geklappt.", "err")
        db.audit(actor(s), name, "plugin upload", f"{filename} ({len(data)} bytes)")
        return flash_redirect(s, f"/server/{name}",
                              f"{plugin_name} {version} hochgeladen. Starte den Server neu, damit es aktiv wird.")

    @app.post("/server/{name}/players")
    async def players_action(request: Request, name: str, action: str = Form(""),
                             player: str = Form(""), csrf: str = Form("")):
        texts = {"player-add": f"{player} darf jetzt auf den Server.",
                 "player-remove": f"{player} wurde entfernt.",
                 "op": f"{player} ist jetzt Operator.",
                 "deop": f"{player} ist kein Operator mehr."}
        if action not in texts:
            return Response("Bad request", status_code=400)
        player = player.strip()
        return await server_action(request, name, csrf, lambda srv: control.player(srv, action, player),
                                   texts[action], action, player)

    # ── server.properties ─────────────────────────────────────
    def parse_properties(text: str) -> dict[str, str]:
        out = {}
        for line in text.splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                key, _, value = line.partition("=")
                out[key.strip()] = value
        return out

    @app.get("/server/{name}/properties")
    async def properties_page(request: Request, name: str):
        s = current(request)
        if s is None:
            return redirect("/login")
        if not can_access(s, name):
            return page(request, "message.html", s, status_code=403, title="Kein Zugriff",
                        text="Das ist nicht dein Server.")
        server = settings.servers[name]
        (content, err), (status, _) = await asyncio.gather(
            safe(control.properties(server), ""),
            safe(control.status(server), {"state": "unreachable"}))
        return page(request, "properties.html", s, server=server, content=content, error=err,
                    status=status, max_kb=MAX_PROPERTIES // 1024)

    @app.post("/server/{name}/properties/restore")
    async def properties_restore(request: Request, name: str, csrf: str = Form("")):
        return await server_action(
            request, name, csrf, lambda srv: control.restore_properties(srv),
            "Die vorherige Fassung von server.properties ist wiederhergestellt. "
            "Sie gilt ab dem nächsten Start.", "properties restore")

    @app.post("/server/{name}/properties")
    async def properties_save(request: Request, name: str, content: str = Form(""),
                              action: str = Form("save"), csrf: str = Form("")):
        s = current(request)
        if s is None:
            return redirect("/login")
        if not can_access(s, name) or not csrf_ok(s, csrf):
            return Response("Forbidden", status_code=403)
        url = f"/server/{name}/properties"
        content = content.replace("\r\n", "\n")
        if len(content.encode("utf-8")) > MAX_PROPERTIES:
            return flash_redirect(s, url, "Die Datei ist zu groß.", "err")
        if not content.endswith("\n"):
            content += "\n"
        server = settings.servers[name]
        try:
            old = parse_properties(await control.properties(server))
            res = await control.save_properties(server, content)
            if not res.ok:
                return flash_redirect(s, url, res.output or "Speichern hat nicht geklappt.", "err")
            new = parse_properties(content)
            changed = sorted(k for k in set(old) | set(new) if old.get(k) != new.get(k))
            db.audit(actor(s), name, "properties", ", ".join(changed)[:300])
            message = "server.properties gespeichert."
            kept = re.search(r"Protected settings unchanged: (.+)", res.output)
            if kept:
                message += f" Diese geschützten Einträge bleiben unverändert: {kept.group(1)}."
            if action == "restart":
                status = await control.status(server)
                power = "start" if status.get("state") == "stopped" else "restart"
                await control.action(server, power)
                db.audit(actor(s), name, power)
                message += " Der Server startet jetzt mit den neuen Einstellungen."
                return flash_redirect(s, f"/server/{name}", message)
            message += " Die Änderungen gelten ab dem nächsten Start."
        except ServerError as exc:
            return flash_redirect(s, url, str(exc), "err")
        return flash_redirect(s, url, message)

    # ── admin ─────────────────────────────────────────────────
    def admin_session(request: Request):
        s = current(request)
        return s if s is not None and s["role"] == "admin" else None

    @app.get("/admin")
    async def admin_page(request: Request):
        s = admin_session(request)
        if s is None:
            return redirect("/login" if current(request) is None else "/")
        names = list(settings.servers)
        statuses = await asyncio.gather(*(safe(control.status(settings.servers[n]), {"state": "unreachable"})
                                          for n in names))
        users = db.all("SELECT id, email, name, role, server, password_hash IS NOT NULL AS active "
                       "FROM users ORDER BY role, name COLLATE NOCASE")
        owners = {u["server"]: u for u in users if u["server"]}
        rows = [{"server": settings.servers[n], "status": st, "error": err, "owner": owners.get(n)}
                for n, (st, err) in zip(names, statuses)]
        audit = db.all("SELECT * FROM audit ORDER BY id DESC LIMIT 40")
        return page(request, "admin.html", s, rows=rows, users=users, audit=audit)

    async def invite(user_id: int) -> bool:
        user = db.one("SELECT * FROM users WHERE id = ?", user_id)
        token = sec.create_invite(db, user_id)
        link = f"{settings.public_url}/invite/{token}"
        if settings.mail_test:
            log.warning("MAIL_TEST — invitation link for %s: %s", user["email"], link)
        return await mailer.send_invite(user["email"], user["name"], link, user["server"], user["role"])

    def admin_post(request: Request, csrf: str):
        s = admin_session(request)
        if s is None or not csrf_ok(s, csrf):
            return None
        return s

    @app.post("/admin/assign")
    async def admin_assign(request: Request, server: str = Form(""), name: str = Form(""),
                           email: str = Form(""), csrf: str = Form("")):
        s = admin_post(request, csrf)
        if s is None:
            return Response("Forbidden", status_code=403)
        name, email = name.strip()[:80], email.strip().lower()
        if server not in settings.servers:
            return flash_redirect(s, "/admin", "Unbekannter Server.", "err")
        if not name or not EMAIL_RE.match(email):
            return flash_redirect(s, "/admin", "Bitte Name und eine gültige Mailadresse eingeben.", "err")
        if db.one("SELECT id FROM users WHERE server = ?", server):
            return flash_redirect(s, "/admin", f"{server} ist schon vergeben – zuerst freigeben.", "err")
        user = db.one("SELECT * FROM users WHERE email = ?", email)
        if user and user["role"] == "admin":
            return flash_redirect(s, "/admin", "Diese Mailadresse gehört zu einem Admin.", "err")
        if user and user["server"]:
            return flash_redirect(s, "/admin", f"{user['name']} hat schon {user['server']}.", "err")
        if user:
            db.run("UPDATE users SET server = ?, name = ? WHERE id = ?", server, name, user["id"])
            user_id = user["id"]
            needs_invite = user["password_hash"] is None
        else:
            cur = db.run("INSERT INTO users (email, name, role, server, created_at) VALUES (?, ?, 'student', ?, ?)",
                         email, name, server, sec.now())
            user_id = cur.lastrowid
            needs_invite = True
        db.audit(actor(s), server, "assign", f"{name} <{email}>")
        if needs_invite:
            sent = await invite(user_id)
            if not sent:
                return flash_redirect(s, "/admin", f"{server} ist {name} zugeordnet, aber die Einladungsmail "
                                                   "konnte nicht verschickt werden.", "err")
            return flash_redirect(s, "/admin", f"{server} ist jetzt {name} zugeordnet. Die Einladung ist verschickt.")
        return flash_redirect(s, "/admin", f"{server} ist jetzt {name} zugeordnet (Zugang besteht schon).")

    @app.post("/admin/release")
    async def admin_release(request: Request, server: str = Form(""), wipe: str = Form(""),
                            csrf: str = Form("")):
        s = admin_post(request, csrf)
        if s is None:
            return Response("Forbidden", status_code=403)
        if server not in settings.servers:
            return flash_redirect(s, "/admin", "Unbekannter Server.", "err")
        user = db.one("SELECT * FROM users WHERE server = ?", server)
        if user:
            db.run("UPDATE users SET server = NULL WHERE id = ?", user["id"])
            sec.end_user_sessions(db, user["id"])
        msg = f"{server} ist freigegeben."
        if wipe == "yes":
            try:
                res = await control.action(settings.servers[server], "wipe")
            except ServerError as exc:
                return flash_redirect(s, "/admin", f"{msg} Zurücksetzen fehlgeschlagen: {exc}", "err")
            if not res.ok:
                return flash_redirect(s, "/admin", f"{msg} Zurücksetzen fehlgeschlagen: {res.output}", "err")
            msg += " Welt und Plugins wurden zurückgesetzt (alte Welt liegt im Backup-Ordner des Servers)."
        db.audit(actor(s), server, "release" + (" + wipe" if wipe == "yes" else ""),
                 f"{user['name']} <{user['email']}>" if user else "")
        return flash_redirect(s, "/admin", msg)

    @app.post("/admin/users/add-admin")
    async def admin_add_admin(request: Request, name: str = Form(""), email: str = Form(""),
                              csrf: str = Form("")):
        s = admin_post(request, csrf)
        if s is None:
            return Response("Forbidden", status_code=403)
        name, email = name.strip()[:80], email.strip().lower()
        if not name or not EMAIL_RE.match(email):
            return flash_redirect(s, "/admin", "Bitte Name und eine gültige Mailadresse eingeben.", "err")
        if db.one("SELECT id FROM users WHERE email = ?", email):
            return flash_redirect(s, "/admin", "Diese Mailadresse hat schon einen Zugang.", "err")
        cur = db.run("INSERT INTO users (email, name, role, created_at) VALUES (?, ?, 'admin', ?)",
                     email, name, sec.now())
        db.audit(actor(s), None, "add admin", f"{name} <{email}>")
        sent = await invite(cur.lastrowid)
        return flash_redirect(s, "/admin", f"Admin {name} angelegt." +
                              (" Die Einladung ist verschickt." if sent else " Die Mail konnte nicht verschickt werden."),
                              "ok" if sent else "err")

    @app.post("/admin/users/{user_id}/reinvite")
    async def admin_reinvite(request: Request, user_id: int, csrf: str = Form("")):
        s = admin_post(request, csrf)
        if s is None:
            return Response("Forbidden", status_code=403)
        user = db.one("SELECT * FROM users WHERE id = ?", user_id)
        if user is None:
            return flash_redirect(s, "/admin", "Unbekannter Zugang.", "err")
        if user["id"] == s["user_id"]:
            return flash_redirect(s, "/admin", "Du kannst dich nicht selbst neu einladen.", "err")
        # The old password stops working: "forgot password" goes through the teacher
        db.run("UPDATE users SET password_hash = NULL WHERE id = ?", user_id)
        sec.end_user_sessions(db, user_id)
        db.audit(actor(s), user["server"], "reinvite", f"{user['name']} <{user['email']}>")
        sent = await invite(user_id)
        return flash_redirect(s, "/admin", f"Neue Einladung an {user['name']} verschickt – das alte Passwort gilt nicht mehr."
                              if sent else "Die Mail konnte nicht verschickt werden.", "ok" if sent else "err")

    @app.post("/admin/users/{user_id}/delete")
    async def admin_delete(request: Request, user_id: int, csrf: str = Form("")):
        s = admin_post(request, csrf)
        if s is None:
            return Response("Forbidden", status_code=403)
        user = db.one("SELECT * FROM users WHERE id = ?", user_id)
        if user is None:
            return flash_redirect(s, "/admin", "Unbekannter Zugang.", "err")
        if user["id"] == s["user_id"]:
            return flash_redirect(s, "/admin", "Du kannst deinen eigenen Zugang nicht löschen.", "err")
        if user["role"] == "admin" and db.one("SELECT COUNT(*) AS n FROM users WHERE role = 'admin'")["n"] <= 1:
            return flash_redirect(s, "/admin", "Der letzte Admin kann nicht gelöscht werden.", "err")
        db.run("DELETE FROM users WHERE id = ?", user_id)
        # The audit log keeps no personal data of deleted users
        db.run("UPDATE audit SET actor = '(gelöscht)' WHERE actor = ?", f"{user['name']} <{user['email']}>")
        db.run("UPDATE audit SET detail = '(gelöscht)' WHERE detail = ?", f"{user['name']} <{user['email']}>")
        db.audit(actor(s), user["server"], "delete user", "")
        return flash_redirect(s, "/admin", f"Der Zugang von {user['name']} wurde gelöscht.")

    return app


app = None


def get_app() -> FastAPI:  # uvicorn factory
    global app
    if app is None:
        app = create_app()
    return app
