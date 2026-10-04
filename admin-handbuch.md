# Handbuch für Lehrkräfte: Die Adminseite der Minecraft-Server

Auf der **Adminseite** vergeben Sie Minecraft-Server an Ihre Schülerinnen und Schüler und behalten den Überblick. Die Schülerinnen und Schüler verwalten ihren eigenen Server dort selbst – ganz ohne PuTTY und FileZilla.

- Das Handbuch für die Schülerinnen und Schüler: **[schueler-handbuch.md](schueler-handbuch.md)** – geben Sie ihnen am besten diesen Link.
- Die Einrichtung auf dem Server (Installation, Mailversand, HTTPS) steht in der [README](README.md#admin-page).

## Inhalt

- [Auf einen Blick](#auf-einen-blick)
- [Erster Zugang](#erster-zugang)
- [Anmelden](#anmelden)
- [Die Übersicht](#die-übersicht)
- [Einen Server vergeben](#einen-server-vergeben)
- [Einen Server freigeben und zurücksetzen](#einen-server-freigeben-und-zurücksetzen)
- [Zugänge verwalten](#zugänge-verwalten)
- [Letzte Aktionen](#letzte-aktionen)
- [Einen Server selbst bedienen – auch die Lobby](#einen-server-selbst-bedienen--auch-die-lobby)
- [Tipps für den Workshop](#tipps-für-den-workshop)
- [Häufige Fragen](#häufige-fragen)

---

## Auf einen Blick

| | Schülerin / Schüler | Lehrkraft (Admin) |
|---|---|---|
| Sieht | nur den eigenen Server | alle Server und alle Zugänge |
| Server starten, stoppen, neu starten | ✓ | ✓ (jeden Server) |
| Plugins installieren, hochladen, entfernen | ✓ | ✓ |
| Spieler hinzufügen, Operatoren festlegen | ✓ | ✓ |
| Einstellungen (`server.properties`) ändern | ✓ | ✓ |
| Server vergeben, freigeben, zurücksetzen | – | ✓ |
| Zugänge einladen und löschen | – | ✓ |

**Anmeldung in zwei Schritten:** Mailadresse und Passwort, danach ein 6-stelliger **Code**, der bei jeder Anmeldung an die Mailadresse geschickt wird. Wer nur das Passwort kennt, kommt also nicht hinein. Jede Schülerin und jeder Schüler braucht deshalb eine **Mailadresse mit Postfach**, z. B. die Schul-Mailadresse.

---

## Erster Zugang

Den allerersten Admin-Zugang legt die Person an, die den Server betreibt (`adminctl invite-admin`, siehe README). Weitere Lehrkräfte laden Sie später selbst ein ([Zugänge verwalten](#zugänge-verwalten)).

Sie bekommen eine Mail **„Einladung zur Minecraft-Adminseite“**:

![Einladungsmail mit Link zum Festlegen des Passworts](docs/admin-handbuch/01-einladungsmail.png)

Der Link gilt **7 Tage** und **nur einmal**. Er öffnet eine Seite, auf der Sie Ihr Passwort festlegen (mindestens 8 Zeichen – bitte nicht das Passwort Ihres Mailkontos):

![Passwort festlegen](docs/admin-handbuch/02-passwort-festlegen.png)

## Anmelden

1. Mailadresse und Passwort eingeben, **Weiter** klicken.

   ![Anmeldeseite mit Mailadresse und Passwort](docs/admin-handbuch/03-anmelden.png)

2. In Ihrem Postfach liegt jetzt eine Mail **„Dein Anmeldecode: …“**. Den 6-stelligen Code eingeben und **Anmelden** klicken.

   ![Code aus der Mail eingeben](docs/admin-handbuch/04-code-eingeben.png)

- Der Code gilt **10 Minuten**. Nach 5 falschen Versuchen beginnt die Anmeldung von vorn.
- Keine Mail bekommen? Spam-Ordner prüfen oder **Neuen Code schicken** anklicken.
- Nach **2 Stunden** ohne Aktivität (spätestens nach 12 Stunden) werden Sie automatisch abgemeldet. Auf gemeinsam genutzten Rechnern bitte immer **Abmelden** (oben rechts).

## Die Übersicht

Nach der Anmeldung sehen Sie die **Übersicht**:

![Übersicht mit allen Servern, Zugängen und letzten Aktionen](docs/admin-handbuch/05-uebersicht.png)

- **Alle Server** – Zustand, Minecraft-Version, Spieler online und wem der Server gehört. Ein Klick auf den Servernamen öffnet ihn.
- **Zugänge** – alle Lehrkräfte und Schüler mit Rolle, Server und Status („aktiv“ oder „Einladung offen“).
- **Letzte Aktionen** – wer wann was getan hat.

Mit **Aktualisieren** holen Sie den neuesten Stand der Server.

| Zustand | Bedeutung |
|---|---|
| läuft | Der Server ist an, man kann sich verbinden. |
| startet … | Der Server fährt gerade hoch (etwa 30 Sekunden). |
| wird gebaut … | Eine neue Minecraft-Version wird erstellt – das kann einige Minuten dauern. |
| gestoppt | Der Server wurde ausgeschaltet und wartet auf „Starten“. |
| nicht erreichbar | Der Container läuft nicht oder antwortet nicht – siehe [Häufige Fragen](#häufige-fragen). |

## Einen Server vergeben

1. Neben einem **freien** Server auf **Vergeben …** klicken.
2. **Name** und **Mailadresse** der Schülerin oder des Schülers eingeben.
3. **Vergeben und einladen** klicken.

![Formular zum Vergeben eines Servers](docs/admin-handbuch/06-server-vergeben.png)

Die Schülerin oder der Schüler bekommt sofort eine Einladungsmail und legt damit ein eigenes Passwort fest – Sie müssen sich keine Passwörter ausdenken oder verteilen. Bis dahin steht in der Übersicht „Einladung offen“:

![Server ist vergeben, Einladung offen](docs/admin-handbuch/07-server-vergeben-fertig.png)

Jede Person kann höchstens **einen** Server haben. Hat jemand schon einen Zugang ohne Server (z. B. aus dem letzten Workshop), wird er mit derselben Mailadresse wieder verwendet.

## Einen Server freigeben und zurücksetzen

Wenn ein Workshop zu Ende ist oder ein Server an jemand anderen gehen soll: neben dem Server auf **Freigeben …** klicken.

![Server freigeben, optional zurücksetzen](docs/admin-handbuch/15-freigeben.png)

- **Ohne Häkchen:** Die Schülerin oder der Schüler verliert **sofort** den Zugang (auch wenn gerade jemand angemeldet ist). Welt, Plugins und Spielerliste bleiben, wie sie sind.
- **Mit Häkchen „Server zurücksetzen“:** zusätzlich wird der Server für die nächste Person vorbereitet:
  - der Server wird gestoppt (nach dem Speichern der Welt),
  - Welt und Plugins werden in einen Backup-Ordner auf dem Server verschoben – nicht gelöscht; die drei neuesten Backups bleiben erhalten,
  - Spielerliste und Operatoren werden geleert, die Minecraft-Version geht auf den Standard zurück,
  - beim nächsten Start werden die Standard-Plugins neu installiert.

Danach ist der Server wieder **frei** und kann neu vergeben werden.

## Zugänge verwalten

In der Tabelle **Zugänge** finden Sie bei jeder Person unter **Mehr …**:

![Zugänge mit den Möglichkeiten „Neue Einladung“ und „Zugang löschen“](docs/admin-handbuch/16-zugaenge.png)

- **Neue Einladung schicken** – so funktioniert „Passwort vergessen“: Das alte Passwort wird sofort ungültig, und die Person legt mit dem Link in der neuen Mail ein neues fest. (Ein „Passwort vergessen“-Link per Mail fehlt absichtlich: Dann würde der Zugriff auf das Postfach allein genügen, und der zweite Schritt der Anmeldung wäre wertlos.)
- **Zugang löschen** – Name und Mailadresse werden vollständig entfernt, auch aus den letzten Aktionen. Gedacht für das Ende eines Schuljahrs oder wenn jemand nicht mehr teilnimmt.

Mit **Weiteren Admin hinzufügen …** laden Sie andere Lehrkräfte ein. Den eigenen Zugang und den letzten Admin-Zugang kann man nicht löschen.

## Letzte Aktionen

Hier steht, wer wann was gemacht hat – hilfreich, wenn ein Server plötzlich anders aussieht:

![Liste der letzten Aktionen](docs/admin-handbuch/17-letzte-aktionen.png)

## Einen Server selbst bedienen – auch die Lobby

Sie können **jeden** Server öffnen (Klick auf den Namen in der Übersicht) und dort alles tun, was auch die Schülerinnen und Schüler können. Oben steht, wem der Server gehört:

![Ein Server aus Sicht der Lehrkraft](docs/admin-handbuch/18-lehrkraft-server.png)

Wie Starten, Stoppen, Plugins, Spielerliste und Einstellungen funktionieren, erklärt das **[Schüler-Handbuch](schueler-handbuch.md#dein-server-starten-stoppen-neu-starten)** Schritt für Schritt.

Im **BungeeCord-Modus** erscheint zusätzlich die **Lobby** – der Server, auf dem alle Spieler zuerst landen. Sie ist mit „nur Admins“ gekennzeichnet: Sie kann nicht vergeben und nicht zurückgesetzt werden, Sie können sie aber starten, stoppen und Plugins und Einstellungen ändern.

---

## Tipps für den Workshop

- **Vorher vergeben:** Vergeben Sie die Server ein paar Tage vor dem Workshop. Dann haben alle ihr Passwort schon festgelegt, und Probleme mit Mailadressen fallen rechtzeitig auf („Einladung offen“ in der Übersicht).
- **Spielerliste einschalten:** Bei einem neuen Server ist die Spielerliste **ausgeschaltet** – jeder, der die Adresse kennt, darf mitspielen. Die Serverseite zeigt dann einen roten Hinweis. Wer nur Freunde zulassen will, trägt sich und die Freunde ein und setzt in den Einstellungen `white-list=true` (siehe [Schüler-Handbuch](schueler-handbuch.md#spieler-und-operatoren)).
- **Ältere Minecraft-Versionen:** Haben Schülerinnen und Schüler noch eine ältere Minecraft-Version, hilft das Plugin **ViaBackwards** aus dem Katalog; bei neueren Versionen **ViaVersion**.
- **Nach dem Workshop:** Server mit „Server zurücksetzen“ freigeben. Am Ende des Schuljahrs die Zugänge der Schülerinnen und Schüler löschen – so werden keine Mailadressen länger als nötig gespeichert.

---

## Häufige Fragen

**Bei mir oder bei Schülern kommen keine Mails an.**
Spam-Ordner prüfen. Kommt bei niemandem etwas an, stimmt der Mailversand nicht – Bescheid geben an die Person, die den Server betreibt (`docker compose logs adminpanel` zeigt den Fehler; `adminctl invite-admin` gibt den Einladungslink zur Not auch direkt aus).

**Eine Schülerin hat ihr Passwort vergessen.**
*Zugänge → Mehr … → Neue Einladung schicken.*

**„Zu viele Fehlversuche. Bitte warte 15 Minuten.“**
Nach zu vielen falschen Passwörtern wird die Anmeldung für diese Mailadresse kurz gesperrt. Nach 15 Minuten geht es wieder.

**Ein Server ist „nicht erreichbar“.**
Kurz warten und **Aktualisieren** – nach einem Neustart dauert es etwas. Bleibt es dabei, muss die Person, die den Server betreibt, nachsehen (`docker compose ps`, `docker compose logs mcN`).

**Ein Server lässt sich nicht stoppen.**
Normalerweise speichert der Server und ist nach wenigen Sekunden aus. Hängt das Herunterfahren (das kann z. B. passieren, wenn Plugins im laufenden Betrieb entfernt wurden), wird er nach **60 Sekunden** automatisch beendet – mit dem zuletzt gespeicherten Stand der Welt.

**Die Welt eines zurückgesetzten Servers wird noch gebraucht.**
Sie liegt im Backup-Ordner des Servers (`data/backup-<Datum>/`). Die Person, die den Server betreibt, kann sie zurückholen – solange sie zu den drei neuesten Backups gehört.
