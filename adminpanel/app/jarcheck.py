"""Checks an uploaded plugin jar before it is copied to a server."""
import io
import re
import zipfile

MAX_SIZE = 64 * 1024 * 1024
NAME_RE = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")


class JarError(ValueError):
    pass


def _field(yml: str, key: str) -> str:
    m = re.search(rf"^{key}:\s*(.+?)\s*$", yml, re.MULTILINE)
    if not m:
        return ""
    return m.group(1).strip().strip("'\"")


def inspect_jar(data: bytes) -> tuple[str, str, str]:
    """Returns (plugin name, version, safe file name) or raises JarError."""
    if len(data) > MAX_SIZE:
        raise JarError("Die Datei ist zu groß (höchstens 64 MB).")
    try:
        zf = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as exc:
        raise JarError("Das ist keine gültige .jar-Datei.") from exc
    with zf:
        try:
            # utf-8-sig drops a BOM; CRLF line ends are handled by the regex
            yml = zf.read("plugin.yml").decode("utf-8-sig", "replace").replace("\r", "")
        except KeyError as exc:
            raise JarError("In der Datei fehlt die plugin.yml – das ist kein Spigot-Plugin.") from exc
    name = _field(yml, "name")
    version = _field(yml, "version")
    if not NAME_RE.match(name):
        raise JarError("Die plugin.yml enthält keinen gültigen Plugin-Namen.")
    safe_version = re.sub(r"[^A-Za-z0-9_.+-]", "", version)[:32]
    filename = f"{name}-{safe_version}.jar" if safe_version else f"{name}.jar"
    return name, version, filename
