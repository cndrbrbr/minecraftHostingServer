"""Sending login codes and invitations by e-mail (SMTP)."""
import asyncio
import logging
import smtplib
import ssl
from email.message import EmailMessage
from email.utils import formataddr, make_msgid

from .config import Settings

log = logging.getLogger("adminpanel.mail")

SIGNATURE = "\n\n-- \nMinecraft-Server · Adminseite\nDiese Mail wurde automatisch verschickt."


class Mailer:
    def __init__(self, settings: Settings):
        self.s = settings

    def _send_sync(self, to: str, subject: str, body: str) -> None:
        msg = EmailMessage()
        msg["From"] = formataddr(("Minecraft-Server", self.s.mail_from))
        msg["To"] = to
        msg["Subject"] = subject
        msg["Message-ID"] = make_msgid(domain=self.s.mail_from.split("@")[-1])
        msg.set_content(body + SIGNATURE)
        context = ssl.create_default_context()
        if self.s.smtp_tls == "ssl":
            smtp = smtplib.SMTP_SSL(self.s.smtp_host, self.s.smtp_port, timeout=20, context=context)
        else:
            smtp = smtplib.SMTP(self.s.smtp_host, self.s.smtp_port, timeout=20)
        with smtp:
            if self.s.smtp_tls == "starttls":
                smtp.starttls(context=context)
            if self.s.smtp_user and self.s.smtp_password:
                smtp.login(self.s.smtp_user, self.s.smtp_password)
            smtp.send_message(msg)

    async def send(self, to: str, subject: str, body: str) -> bool:
        if self.s.mail_test:
            log.warning("MAIL_TEST — mail to %s: %s\n%s", to, subject, body)
        try:
            await asyncio.to_thread(self._send_sync, to, subject, body)
            return True
        except Exception as exc:  # noqa: BLE001 — report any SMTP problem to the user
            log.error("sending mail to %s failed: %s", to, exc)
            return False

    async def send_code(self, to: str, name: str, code: str) -> bool:
        return await self.send(
            to, f"Dein Anmeldecode: {code}",
            f"Hallo {name},\n\n"
            f"dein Anmeldecode für die Minecraft-Adminseite lautet:\n\n    {code}\n\n"
            "Er gilt 10 Minuten. Wenn du dich gerade nicht anmelden wolltest, "
            "kannst du diese Mail ignorieren – ohne den Code kommt niemand in dein Konto.")

    async def send_invite(self, to: str, name: str, link: str, server: str | None, role: str) -> bool:
        what = (f"Du hast den Minecraft-Server {server} bekommen und kannst ihn ab jetzt "
                "über die Adminseite starten, stoppen und einrichten."
                if role == "student" and server else
                "Du hast einen Admin-Zugang für die Minecraft-Adminseite bekommen."
                if role == "admin" else
                "Du hast einen Zugang für die Minecraft-Adminseite bekommen.")
        return await self.send(
            to, "Einladung zur Minecraft-Adminseite",
            f"Hallo {name},\n\n{what}\n\n"
            f"Lege hier dein Passwort fest (der Link gilt 7 Tage und nur einmal):\n\n    {link}\n\n"
            "Danach meldest du dich mit deiner Mailadresse und deinem Passwort an. "
            "Zusätzlich bekommst du bei jeder Anmeldung einen Code an diese Mailadresse.")
