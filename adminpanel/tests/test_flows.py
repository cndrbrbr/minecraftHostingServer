"""End-to-end tests of the admin page with a fake server backend and mailer."""
import io
import re
import zipfile

import pytest
from fastapi.testclient import TestClient

from app import security as sec
from app.config import Server, Settings, load_servers
from app.db import DB
from app.main import create_app
from app.servers import Result, ServerControl, ServerError


class FakeMailer:
    def __init__(self):
        self.sent = []

    async def send_code(self, to, name, code):
        self.sent.append(("code", to, code))
        return True

    async def send_invite(self, to, name, link, server, role):
        self.sent.append(("invite", to, link))
        return True

    def last(self, kind, to):
        return [m for m in self.sent if m[0] == kind and m[1] == to][-1][2]


class FakeControl:
    def __init__(self):
        self.calls = []
        self.uploads = []
        self.installed = [{"file": "minecraft-prometheus-exporter.jar", "name": "PrometheusExporter",
                           "version": "3.1.2", "catalog_id": "prometheus", "locked": True}]

    async def status(self, server):
        return {"state": self.state, "type": "spigot", "version": "26.3", "players": [], "max_players": 20}

    async def plugins(self, server):
        return self.installed

    async def catalog(self, server):
        return {"version": "26.3", "plugins": [
            {"id": "viaversion", "name": "ViaVersion", "description": "x", "locked": False,
             "requires": [], "installed": False, "available": True,
             "category": "Andere Minecraft-Versionen", "status": "verified", "max": ""},
            {"id": "coreprotect", "name": "CoreProtect", "description": "y", "locked": False,
             "requires": [], "installed": False, "available": False,
             "category": "Bauen & Schützen", "status": "testing", "max": "26.2"},
            {"id": "worldguard", "name": "WorldGuard", "description": "z", "locked": False,
             "requires": ["worldedit"], "installed": False, "available": True,
             "category": "Bauen & Schützen", "status": "verified", "max": ""}]}

    async def players(self, server):
        return {"whitelist": ["Steve"], "ops": []}

    async def action(self, server, action):
        self.calls.append((server.name, action))
        return Result(True, "ok")

    async def install_plugin(self, server, plugin_id):
        self.calls.append((server.name, "install", plugin_id))
        return Result(True, "ok")

    async def remove_plugin(self, server, filename):
        self.calls.append((server.name, "remove", filename))
        return Result(True, "ok")

    async def player(self, server, action, name):
        if not re.match(r"^[A-Za-z0-9_]{3,16}$", name):
            raise ServerError("Ungültiger Spielername")
        self.calls.append((server.name, action, name))
        return Result(True, "ok")

    async def upload_plugin(self, server, filename, data):
        self.uploads.append((server.name, filename, len(data)))

    props = "motd=A Minecraft Server\ndifficulty=easy\nserver-port=25565\n"
    state = "running"
    saved = None

    async def properties(self, server):
        return self.props

    async def save_properties(self, server, content):
        self.saved = (server.name, content)
        return Result(True, "==> server.properties saved.")

    async def restore_properties(self, server):
        self.calls.append((server.name, "properties-restore"))
        return Result(True, "ok")


ORIGIN = "http://testserver"


@pytest.fixture
def env(tmp_path):
    settings = Settings(public_url=ORIGIN, data_dir=tmp_path, servers={
        "lobby": Server("lobby", "lobby", admin_only=True),
        "mc1": Server("mc1", "mc1", 2221, 25565), "mc2": Server("mc2", "mc2", 2222, 25566)})
    db = DB(tmp_path / "t.db")
    mailer, control = FakeMailer(), FakeControl()
    app = create_app(settings, db, control, mailer)
    return settings, db, mailer, control, app


def client(app):
    return TestClient(app, base_url=ORIGIN, follow_redirects=False)


def make_user(db, email, name, role, server=None, password="geheim123"):
    db.run("INSERT INTO users (email, name, role, server, password_hash, created_at) VALUES (?, ?, ?, ?, ?, 0)",
           email, name, role, server, sec.hash_password(password) if password else None)
    return db.one("SELECT id FROM users WHERE email = ?", email)["id"]


def csrf_of(html):
    return re.search(r'name="csrf" value="([^"]+)"', html).group(1)


def login(c, mailer, email, password="geheim123"):
    r = c.post("/login", data={"email": email, "password": password})
    assert r.status_code == 303 and r.headers["location"] == "/login/code", r.text
    page = c.get("/login/code").text
    r = c.post("/login/code", data={"code": mailer.last("code", email), "csrf": csrf_of(page)})
    assert r.status_code == 303 and r.headers["location"] == "/"
    return r


def test_login_needs_code(env):
    _, db, mailer, _, app = env
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    c = client(app)
    r = c.post("/login", data={"email": "kid@school.de", "password": "geheim123"})
    assert r.headers["location"] == "/login/code"
    # Without the code there is no access to the server page
    assert c.get("/server/mc1").headers["location"] == "/login"
    page = c.get("/login/code").text
    r = c.post("/login/code", data={"code": "000000" if mailer.last("code", "kid@school.de") != "000000" else "111111",
                                    "csrf": csrf_of(page)})
    assert r.status_code == 401
    login(client(app), mailer, "kid@school.de")


def test_wrong_password_and_unknown_user_look_the_same(env):
    _, db, _, _, app = env
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    c = client(app)
    a = c.post("/login", data={"email": "kid@school.de", "password": "falsch"})
    b = c.post("/login", data={"email": "nobody@school.de", "password": "falsch"})
    assert a.status_code == b.status_code == 401
    assert "stimmt nicht" in a.text and "stimmt nicht" in b.text


def test_code_attempts_are_limited(env):
    _, db, mailer, _, app = env
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    c = client(app)
    c.post("/login", data={"email": "kid@school.de", "password": "geheim123"})
    real = mailer.last("code", "kid@school.de")
    wrong = "123456" if real != "123456" else "654321"
    for _ in range(sec.CODE_MAX_ATTEMPTS - 1):
        page = c.get("/login/code").text
        assert c.post("/login/code", data={"code": wrong, "csrf": csrf_of(page)}).status_code == 401
    page = c.get("/login/code").text
    r = c.post("/login/code", data={"code": wrong, "csrf": csrf_of(page)})
    assert r.headers["location"] == "/login?info=code"
    # Even the right code no longer works — the login starts over
    r = c.post("/login/code", data={"code": real, "csrf": csrf_of(page)})
    assert r.headers["location"] == "/login"


def test_login_attempts_are_limited(env):
    _, db, _, _, app = env
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    c = client(app)
    for _ in range(sec.LIMIT_LOGIN_EMAIL[1]):
        c.post("/login", data={"email": "kid@school.de", "password": "falsch"})
    r = c.post("/login", data={"email": "kid@school.de", "password": "geheim123"})
    assert r.status_code == 429


def test_student_sees_only_own_server(env):
    _, db, mailer, control, app = env
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    c = client(app)
    login(c, mailer, "kid@school.de")
    assert c.get("/").headers["location"] == "/server/mc1"
    assert c.get("/server/mc1").status_code == 200
    assert c.get("/server/mc2").status_code == 403
    assert c.get("/admin").headers["location"] == "/"
    page = c.get("/server/mc1").text
    token = csrf_of(page)
    assert c.post("/server/mc2/power", data={"action": "stop", "csrf": token}).status_code == 403
    assert c.post("/admin/assign", data={"server": "mc2", "name": "x", "email": "x@y.de", "csrf": token}).status_code == 403
    r = c.post("/server/mc1/power", data={"action": "stop", "csrf": token})
    assert r.status_code == 303 and ("mc1", "stop") in control.calls


def test_csrf_and_origin_are_checked(env):
    _, db, mailer, control, app = env
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    c = client(app)
    login(c, mailer, "kid@school.de")
    assert c.post("/server/mc1/power", data={"action": "stop", "csrf": "wrong"}).status_code == 403
    token = csrf_of(c.get("/server/mc1").text)
    r = c.post("/server/mc1/power", data={"action": "stop", "csrf": token},
               headers={"Origin": "https://evil.example"})
    assert r.status_code == 403
    assert control.calls == []


def test_invite_flow_and_reuse(env):
    _, db, mailer, _, app = env
    make_user(db, "teacher@school.de", "Teacher", "admin")
    c = client(app)
    login(c, mailer, "teacher@school.de")
    token = csrf_of(c.get("/admin").text)
    r = c.post("/admin/assign", data={"server": "mc2", "name": "Neu", "email": "Neu@School.de", "csrf": token})
    assert r.status_code == 303
    link = mailer.last("invite", "neu@school.de")
    path = link.replace(ORIGIN, "")
    s = client(app)
    assert s.post(path, data={"password": "kurz", "confirm": "kurz"}).status_code == 400
    r = s.post(path, data={"password": "langesPasswort", "confirm": "langesPasswort"})
    assert r.headers["location"] == "/login?info=password"
    # The link works only once
    assert s.get(path).status_code == 404
    login(s, mailer, "neu@school.de", "langesPasswort")
    assert s.get("/").headers["location"] == "/server/mc2"


def test_release_ends_access_immediately(env):
    _, db, mailer, control, app = env
    make_user(db, "teacher@school.de", "Teacher", "admin")
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    kid = client(app)
    login(kid, mailer, "kid@school.de")
    assert kid.get("/server/mc1").status_code == 200
    t = client(app)
    login(t, mailer, "teacher@school.de")
    token = csrf_of(t.get("/admin").text)
    t.post("/admin/release", data={"server": "mc1", "wipe": "yes", "csrf": token})
    assert ("mc1", "wipe") in control.calls
    assert kid.get("/server/mc1").headers["location"] == "/login"


def test_reinvite_invalidates_password(env):
    _, db, mailer, _, app = env
    make_user(db, "teacher@school.de", "Teacher", "admin")
    kid_id = make_user(db, "kid@school.de", "Kid", "student", "mc1")
    t = client(app)
    login(t, mailer, "teacher@school.de")
    t.post(f"/admin/users/{kid_id}/reinvite", data={"csrf": csrf_of(t.get("/admin").text)})
    r = client(app).post("/login", data={"email": "kid@school.de", "password": "geheim123"})
    assert r.status_code == 401


def test_last_admin_and_self_cannot_be_deleted(env):
    _, db, mailer, _, app = env
    me = make_user(db, "teacher@school.de", "Teacher", "admin")
    t = client(app)
    login(t, mailer, "teacher@school.de")
    t.post(f"/admin/users/{me}/delete", data={"csrf": csrf_of(t.get("/admin").text)})
    assert db.one("SELECT id FROM users WHERE id = ?", me) is not None


def jar_bytes(name="MyPlugin", version="1.0"):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("plugin.yml", f"name: {name}\nversion: '{version}'\nmain: x.Y\n")
    return buf.getvalue()


def test_upload_checks_jar(env):
    _, db, mailer, control, app = env
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    c = client(app)
    login(c, mailer, "kid@school.de")
    token = csrf_of(c.get("/server/mc1").text)
    c.post("/server/mc1/plugins/upload", data={"csrf": token},
           files={"jar": ("evil.jar", b"not a zip", "application/java-archive")})
    assert control.uploads == []
    c.post("/server/mc1/plugins/upload", data={"csrf": token},
           files={"jar": ("../../x.jar", jar_bytes(), "application/java-archive")})
    assert control.uploads == [("mc1", "MyPlugin-1.0.jar", len(jar_bytes()))]
    # A locked plugin cannot be replaced by an upload
    c.post("/server/mc1/plugins/upload", data={"csrf": token},
           files={"jar": ("p.jar", jar_bytes("PrometheusExporter", "9"), "application/java-archive")})
    assert len(control.uploads) == 1


def test_invalid_player_name_is_rejected(env):
    _, db, mailer, control, app = env
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    c = client(app)
    login(c, mailer, "kid@school.de")
    token = csrf_of(c.get("/server/mc1").text)
    r = c.post("/server/mc1/players", data={"action": "op", "player": "x; rm -rf /", "csrf": token})
    assert r.status_code == 303
    assert all(call[1] != "op" for call in control.calls)


def test_session_cookie_flags(env):
    settings, db, mailer, _, app = env
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    r = client(app).post("/login", data={"email": "kid@school.de", "password": "geheim123"})
    cookie = r.headers["set-cookie"].lower()
    assert "httponly" in cookie and "samesite=lax" in cookie


def test_referrer_policy_keeps_origin_header(env):
    # Browsers send "Origin: null" on form posts when the page says no-referrer
    _, _, _, _, app = env
    r = client(app).get("/login")
    assert r.headers["referrer-policy"] == "same-origin"


def test_same_origin_post_is_accepted(env):
    _, db, mailer, _, app = env
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    r = client(app).post("/login", data={"email": "kid@school.de", "password": "geheim123"},
                         headers={"Origin": ORIGIN})
    assert r.status_code == 303


def test_properties_edit_and_restart(env):
    _, db, mailer, control, app = env
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    c = client(app)
    login(c, mailer, "kid@school.de")
    html = c.get("/server/mc1/properties").text
    assert "difficulty=easy" in html
    assert c.get("/server/mc2/properties").status_code == 403
    new = "motd=Mein Server\r\ndifficulty=hard\r\nserver-port=25565"
    control.state = "stopped"
    r = c.post("/server/mc1/properties", data={"content": new, "action": "restart", "csrf": csrf_of(html)})
    assert r.headers["location"] == "/server/mc1"
    assert control.saved == ("mc1", "motd=Mein Server\ndifficulty=hard\nserver-port=25565\n")
    assert ("mc1", "start") in control.calls          # stopped server → start, not restart
    row = db.one("SELECT detail FROM audit WHERE action = 'properties'")
    assert row["detail"] == "difficulty, motd"
    assert c.post("/server/mc2/properties", data={"content": new, "csrf": csrf_of(html)}).status_code == 403


def test_properties_size_limit(env):
    _, db, mailer, control, app = env
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    c = client(app)
    login(c, mailer, "kid@school.de")
    html = c.get("/server/mc1/properties").text
    c.post("/server/mc1/properties", data={"content": "a=" + "x" * 70000, "csrf": csrf_of(html)})
    assert control.saved is None


def test_properties_restore(env):
    _, db, mailer, control, app = env
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    c = client(app)
    login(c, mailer, "kid@school.de")
    html = c.get("/server/mc1/properties").text
    assert c.post("/server/mc2/properties/restore", data={"csrf": csrf_of(html)}).status_code == 403
    c.post("/server/mc1/properties/restore", data={"csrf": csrf_of(html)})
    assert ("mc1", "properties-restore") in control.calls


def test_catalog_groups_and_badges(env):
    _, db, mailer, _, app = env
    make_user(db, "kid@school.de", "Kid", "student", "mc1")
    c = client(app)
    login(c, mailer, "kid@school.de")
    html = c.get("/server/mc1").text
    assert 'class="catalog-scroll"' in html
    # Groups in the defined order, each once
    assert html.index("Andere Minecraft-Versionen") < html.index("Bauen &amp; Schützen")
    assert html.count('class="catalog-group"') == 2
    assert "Testphase" in html
    assert "läuft nur bis 26.2" in html
    assert "Installiert dazu: worldedit" in html


def test_jarcheck_handles_bom_and_crlf():
    from app.jarcheck import inspect_jar
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("plugin.yml", "﻿name: GroupManager\r\nversion: 3.2 (Phoenix)\r\nmain: x.Y\r\n".encode("utf-8"))
    assert inspect_jar(buf.getvalue()) == ("GroupManager", "3.2 (Phoenix)", "GroupManager-3.2Phoenix.jar")


def test_admin_only_server_cannot_be_assigned_or_wiped(env):
    _, db, mailer, control, app = env
    make_user(db, "teacher@school.de", "Teacher", "admin")
    t = client(app)
    login(t, mailer, "teacher@school.de")
    page = t.get("/admin").text
    assert "nur Admins" in page
    assert 'name="server" value="lobby"' not in page      # no assign/release form for the lobby
    token = csrf_of(page)
    t.post("/admin/assign", data={"server": "lobby", "name": "Kid", "email": "kid@school.de", "csrf": token})
    assert db.one("SELECT id FROM users WHERE email = ?", "kid@school.de") is None
    assert mailer.sent == [("code", "teacher@school.de", mailer.last("code", "teacher@school.de"))]
    t.post("/admin/release", data={"server": "lobby", "wipe": "yes", "csrf": token})
    assert ("lobby", "wipe") not in control.calls
    # The admin manages the lobby like any other server
    assert t.get("/server/lobby").status_code == 200
    token = csrf_of(t.get("/server/lobby").text)
    t.post("/server/lobby/power", data={"action": "restart", "csrf": token})
    assert ("lobby", "restart") in control.calls


def test_student_never_reaches_admin_only_server(env):
    _, db, mailer, control, app = env
    # Even if the database says so (e.g. set by hand), a student gets no access
    make_user(db, "kid@school.de", "Kid", "student", "lobby")
    c = client(app)
    login(c, mailer, "kid@school.de")
    assert c.get("/").status_code == 200                  # "no server yet" page, no redirect
    assert c.get("/server/lobby").status_code == 403
    assert c.get("/server/lobby/properties").status_code == 403
    # valid token of this session, so the 403 comes from the access check
    token = db.one("SELECT s.csrf FROM sessions s JOIN users u ON u.id = s.user_id "
                   "WHERE u.email = ? AND s.stage = 'full'", "kid@school.de")["csrf"]
    assert c.post("/server/lobby/power", data={"action": "stop", "csrf": token}).status_code == 403
    assert control.calls == []


def test_servers_json_admin_only(tmp_path):
    f = tmp_path / "servers.json"
    f.write_text('{"mode": "bungeecord", "servers": ['
                 '{"name": "lobby", "host": "lobby", "public_ssh_port": null, "public_mc_port": null, "admin_only": true},'
                 '{"name": "mc1", "host": "mc1", "public_ssh_port": 2221, "public_mc_port": null}]}')
    mode, servers = load_servers(f)
    assert mode == "bungeecord" and list(servers) == ["lobby", "mc1"]
    assert servers["lobby"].admin_only and not servers["mc1"].admin_only


def test_upload_path_is_relative_to_sftp_start_dir(tmp_path):
    """The jar is written to data/plugins/ relative to where SFTP starts, so the
    upload works with the standard chroot (/server, start dir /) and with a
    chroot one level up (start dir /server)."""
    opened, written = [], []

    class FakeFile:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def write(self, data): written.append(data)

    class FakeSFTP:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        def open(self, path, mode):
            opened.append((path, mode))
            return FakeFile()

    class FakeConn:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        def start_sftp_client(self): return FakeSFTP()

    class Control(ServerControl):
        async def _connect(self, server, user, key_name):
            assert (user, key_name) == ("mc-sftp", "sftp_key")
            return FakeConn()

    control = Control(Settings(data_dir=tmp_path), DB(tmp_path / "t.db"))
    import asyncio
    asyncio.run(control.upload_plugin(Server("mc1", "mc1"), "Test-1.0.jar", b"jar"))
    assert opened == [("data/plugins/Test-1.0.jar", "wb")]
    assert written == [b"jar"]
