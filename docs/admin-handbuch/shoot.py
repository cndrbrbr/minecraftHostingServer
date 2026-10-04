"""Screenshots for admin-handbuch.md (docs/admin-handbuch/*.png).

Runs against a separate demo admin page so no real account or mail is used:
  docker run -d --name demo-mail --network <project>_workshop axllent/mailpit
  docker run -d --name demo-admin --network <project>_workshop -e PUBLIC_URL=http://demo-admin:8000 \
      -e MAIL_FROM=adminseite@schule.example -e SMTP_HOST=demo-mail -e SMTP_PORT=1025 -e SMTP_TLS=none \
      -e MAIL_TEST=true -v demo-admin-data:/data -v $PWD/keys:/keys:ro -v $PWD/servers.json:/app/servers.json:ro \
      <project>-adminpanel
  docker exec demo-admin adminctl invite-admin lehrer@schule.example "Frau Beispiel"
  docker run --rm --network <project>_workshop -v $PWD/docs/admin-handbuch:/out -v $PWD/docs/admin-handbuch/shoot.py:/shoot.py:ro \
      mcr.microsoft.com/playwright/python:v1.63.0-noble sh -c "pip install -q playwright==1.63.0; python /shoot.py"
The student gets mc2 — use a server without real player names on it.
"""
import json
import re
import time
import urllib.request

from playwright.sync_api import sync_playwright

BASE = "http://demo-admin:8000"
MAIL = "http://demo-mail:8025"
OUT = "/out"


def mails():
    return json.load(urllib.request.urlopen(MAIL + "/api/v1/messages"))["messages"]


def matching(to, subject_part):
    return [m for m in mails() if any(a["Address"] == to for a in m["To"]) and subject_part in m["Subject"]]


def count(to, subject_part):
    return len(matching(to, subject_part))


def last_mail(to, subject_part, before=0):
    """Newest matching mail, waiting until there are more than `before`."""
    for _ in range(60):
        found = matching(to, subject_part)       # Mailpit lists newest first
        if len(found) > before:
            m = found[0]
            msg = json.load(urllib.request.urlopen(f"{MAIL}/api/v1/message/{m['ID']}"))
            return m["ID"], msg["Text"]
        time.sleep(0.5)
    raise SystemExit(f"no mail '{subject_part}' for {to}")


def shot(page, name, selector=None, full=False):
    path = f"{OUT}/{name}.png"
    if selector:
        page.locator(selector).first.screenshot(path=path)
    else:
        page.screenshot(path=path, full_page=full)
    print("  ✓", name)


def login(page, email, password):
    page.goto(BASE + "/login")
    page.fill("input[name=email]", email)
    page.fill("input[name=password]", password)
    n = count(email, "Anmeldecode")
    page.click("button.primary")
    page.wait_for_url("**/login/code")
    _, text = last_mail(email, "Anmeldecode", n)
    code = re.search(r"\b(\d{6})\b", text).group(1)
    return code


with sync_playwright() as pw:
    browser = pw.chromium.launch(args=["--lang=de-DE"])
    ctx = browser.new_context(viewport={"width": 1180, "height": 820}, device_scale_factor=1, locale="de-DE")
    page = ctx.new_page()

    # ── Lehrkraft: Einladung annehmen ──
    print("Lehrkraft")
    mail_id, text = last_mail("lehrer@schule.example", "Einladung")
    page.goto(f"{MAIL}/view/{mail_id}")
    page.wait_for_timeout(1500)
    shot(page, "01-einladungsmail")
    link = re.search(r"http://\S+/invite/\S+", text).group(0)
    page.goto(link)
    page.fill("input[name=password]", "LehrerPasswort1")
    page.fill("input[name=confirm]", "LehrerPasswort1")
    shot(page, "02-passwort-festlegen")
    page.click("button.primary")
    page.wait_for_url("**/login?info=password")

    # ── Anmelden mit Code ──
    page.fill("input[name=email]", "lehrer@schule.example")
    page.fill("input[name=password]", "LehrerPasswort1")
    shot(page, "03-anmelden")
    n = count("lehrer@schule.example", "Anmeldecode")
    page.click("button.primary")
    page.wait_for_url("**/login/code")
    mail_id, text = last_mail("lehrer@schule.example", "Anmeldecode", n)
    code = re.search(r"\b(\d{6})\b", text).group(1)
    page.fill("input[name=code]", code)
    shot(page, "04-code-eingeben")
    page.click("button.primary")
    page.wait_for_url("**/admin")
    page.wait_for_timeout(500)
    shot(page, "05-uebersicht")

    # ── Server vergeben ──
    page.locator("tr", has_text="mc2").locator("summary", has_text="Vergeben").click()
    form = page.locator("tr", has_text="mc2").locator("form[action='/admin/assign']")
    form.locator("input[name=name]").fill("Max Muster")
    form.locator("input[name=email]").fill("max@schule.example")
    shot(page, "06-server-vergeben", "section.card >> nth=0")
    form.locator("button").click()
    page.wait_for_url("**/admin")
    shot(page, "07-server-vergeben-fertig", "section.card >> nth=0")

    # ── Schüler: Einladung, Anmeldung, eigener Server ──
    print("Schüler")
    kid = ctx.browser.new_context(viewport={"width": 1180, "height": 820}, device_scale_factor=1, locale="de-DE")
    kp = kid.new_page()
    mail_id, text = last_mail("max@schule.example", "Einladung")
    kp.goto(f"{MAIL}/view/{mail_id}")
    kp.wait_for_timeout(1500)
    shot(kp, "19-schueler-einladungsmail")
    kp.goto(re.search(r"http://\S+/invite/\S+", text).group(0))
    kp.fill("input[name=password]", "SchuelerPasswort1")
    kp.fill("input[name=confirm]", "SchuelerPasswort1")
    shot(kp, "20-schueler-passwort", "section.card")
    kp.click("button.primary")
    kp.wait_for_url("**/login?info=password")
    kp.fill("input[name=email]", "max@schule.example")
    kp.fill("input[name=password]", "SchuelerPasswort1")
    shot(kp, "21-schueler-anmelden", "section.card")
    n = count("max@schule.example", "Anmeldecode")
    kp.click("button.primary")
    kp.wait_for_url("**/login/code")
    _, text = last_mail("max@schule.example", "Anmeldecode", n)
    kp.fill("input[name=code]", re.search(r"\b(\d{6})\b", text).group(1))
    shot(kp, "22-schueler-code", "section.card")
    kp.click("button.primary")
    kp.wait_for_url("**/server/mc2")
    shot(kp, "08-schueler-server", "section.card >> nth=0")

    # Plugins: Liste + Katalog
    shot(kp, "09-plugins", "section.card >> nth=1")
    kp.locator(".catalog-scroll").evaluate("el => el.scrollTop = 420")
    kp.wait_for_timeout(300)
    shot(kp, "10-katalog-gescrollt", ".catalog-scroll")
    item = kp.locator(".catalog .item", has_text="CaveCompass")
    if item.count():
        item.locator("button").click()
        kp.wait_for_url("**/server/mc2")
        shot(kp, "11-plugin-installiert", "p.flash")

    # Spieler
    for action, player in (("player-add", "Notch"), ("player-add", "jeb_")):
        f = kp.locator("form[action='/server/mc2/players']:has(input[value='player-add'])")
        f.locator("input[name=player]").fill(player)
        f.locator("button").click()
        kp.wait_for_url("**/server/mc2")
    kp.locator("tr", has_text="jeb_").locator("button", has_text="Zum Operator machen").click()
    kp.wait_for_url("**/server/mc2")
    shot(kp, "12-spieler", "section.card >> nth=2")

    # Einstellungen
    kp.goto(BASE + "/server/mc2/properties")
    shot(kp, "13-einstellungen", "section.card >> nth=0")
    shot(kp, "14-einstellungen-hilfe", "section.card >> nth=1")

    # ── Lehrkraft: Zugänge, Freigeben, Protokoll ──
    print("Lehrkraft (Verwaltung)")
    page.goto(BASE + "/admin")
    page.locator("tr", has_text="max@schule.example").first.locator("summary", has_text="Freigeben").click()
    shot(page, "15-freigeben", "section.card >> nth=0")
    page.goto(BASE + "/admin")
    page.locator("section.card").nth(1).locator("tr", has_text="Max Muster").locator("summary").click()
    shot(page, "16-zugaenge", "section.card >> nth=1")
    shot(page, "17-letzte-aktionen", "section.card >> nth=2")

    # Lehrkraft sieht jeden Server
    page.goto(BASE + "/server/mc1")
    shot(page, "18-lehrkraft-server", "section.card >> nth=0")

    browser.close()
print("fertig")
