"""Settings from the environment (written by setup.sh into docker-compose.yml)."""
import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlparse


@dataclass(frozen=True)
class Server:
    name: str
    host: str
    public_ssh_port: int | None = None
    public_mc_port: int | None = None
    admin_only: bool = False        # e.g. the lobby: never assigned to a student


@dataclass
class Settings:
    public_url: str = "http://localhost:8000"
    admin_email: str = ""
    mail_from: str = "adminpage@test.local"
    smtp_host: str = "localhost"
    smtp_port: int = 25
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_tls: str = "none"          # starttls | ssl | none
    mail_test: bool = False
    data_dir: Path = Path("/data")
    keys_dir: Path = Path("/run/keys")
    mode: str = "standalone"
    servers: dict[str, Server] = field(default_factory=dict)

    @property
    def secure_cookies(self) -> bool:
        return self.public_url.startswith("https://")

    @property
    def origin(self) -> str:
        u = urlparse(self.public_url)
        return f"{u.scheme}://{u.netloc}"


def load_servers(path: Path) -> tuple[str, dict[str, Server]]:
    if not path.exists():
        return "standalone", {}
    data = json.loads(path.read_text(encoding="utf-8"))
    servers = {}
    for s in data.get("servers", []):
        servers[s["name"]] = Server(
            name=s["name"],
            host=s.get("host", s["name"]),
            public_ssh_port=s.get("public_ssh_port"),
            public_mc_port=s.get("public_mc_port"),
            admin_only=s.get("admin_only") is True,
        )
    return data.get("mode", "standalone"), servers


def load_settings() -> Settings:
    env = os.environ
    password = env.get("SMTP_PASSWORD", "")
    pw_file = env.get("SMTP_PASSWORD_FILE")
    if pw_file and Path(pw_file).exists():
        password = Path(pw_file).read_text(encoding="utf-8").strip()
    mode, servers = load_servers(Path(env.get("SERVERS_FILE", "/app/servers.json")))
    return Settings(
        public_url=env.get("PUBLIC_URL", "http://localhost:8000").rstrip("/"),
        admin_email=env.get("ADMIN_EMAIL", ""),
        mail_from=env.get("MAIL_FROM", "adminpage@test.local"),
        smtp_host=env.get("SMTP_HOST", "localhost"),
        smtp_port=int(env.get("SMTP_PORT", "25") or 25),
        smtp_user=env.get("SMTP_USER", ""),
        smtp_password=password,
        smtp_tls=env.get("SMTP_TLS", "none") or "none",
        mail_test=env.get("MAIL_TEST", "false").lower() == "true",
        data_dir=Path(env.get("DATA_DIR", "/data")),
        keys_dir=Path(env.get("KEYS_DIR", "/run/keys")),
        mode=mode,
        servers=servers,
    )
