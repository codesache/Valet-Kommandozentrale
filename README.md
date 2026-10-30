# Valet-Kommandozentrale

Menügesteuerte Shell für die lokale Contao-Entwicklung auf macOS mit
[Laravel Valet](https://laravel.com/docs/valet) und nativem MySQL aus Homebrew.
Entstanden beim Umstieg von MAMP PRO auf Valet: Datenbanken aus MAMP
exportieren, ins native MySQL importieren, Hosts mit HTTPS versehen und den
Überblick behalten, welche Projekte schon umgestellt sind.

```
=== Valet-Kommandozentrale ===

Allgemein
  [ 1] Status anzeigen

Start / Stop
  [ 2] Starten (Valet und MySQL)
  [ 3] Stoppen
  [ 4] Alles neu starten
  [ 5] Nur Valet neu starten
  [ 6] Nur MySQL neu starten

Datenbank
  [ 7] Datenbank anlegen
  [ 8] Datenbanken auflisten
  [ 9] Datenbank aus MAMP exportieren (Datei)
  [10] Datenbank aus Datei importieren

Hosts
  [11] Hosts auflisten / Zertifikate verwalten

Sonstiges
  [12] Updates prüfen (Valet/PHP/MySQL/Imagick)
  [ 0] Beenden
```

## Enthalten

| Datei                    | Zweck                                                                  |
| ------------------------ | ---------------------------------------------------------------------- |
| `dev.sh`                 | Die Kommandozentrale: Menü und Direktbefehle                           |
| `valet-precheck.sh`      | Prüft die Umgebung vor der Valet-Installation, ändert nichts am System |
| `dev.local.conf.example` | Vorlage für lokale Zugangsdaten                                        |
| `CHANGELOG.md`           | Änderungen pro Version                                                 |

## Voraussetzungen

- macOS auf Apple Silicon oder Intel
- [Homebrew](https://brew.sh)
- PHP 8.3 oder 8.4 aus Homebrew
- Laravel Valet 4 (über Composer global installiert)
- MySQL aus Homebrew
- Bash 3.2 reicht, die macOS-Standardversion genügt

MAMP PRO wird nur für den Export alter Datenbanken gebraucht.

## Installation

```bash
git clone git@github.com:codesache/Valet-Kommandozentrale.git
cd Valet-Kommandozentrale

# Umgebung prüfen (Homebrew, PHP, Composer, Ports, MAMP, MySQL, Valet)
bash valet-precheck.sh

# Zugangsdaten anlegen
cp dev.local.conf.example dev.local.conf
chmod 600 dev.local.conf
```

Optional als Befehl `dev` überall verfügbar machen:

```bash
ln -s "$(pwd)/dev.sh" /opt/homebrew/bin/dev   # Intel-Mac: /usr/local/bin/dev
```

### Valet ohne Passwortabfrage

Start, Stopp und Zertifikate laufen über `sudo valet`. Damit nicht jedes Mal
das Passwort abgefragt wird, mit `sudo visudo -f /etc/sudoers.d/valet` diese
Zeilen eintragen (Pfad zu `valet` mit `which valet` prüfen):

```
Cmnd_Alias VALET = /Users/<benutzer>/.composer/vendor/bin/valet *
%admin ALL=(root) NOPASSWD:SETENV: VALET
```

`dev.sh status` meldet, wenn das noch fehlt.

## Konfiguration

`dev.sh` bringt Standardwerte mit: natives MySQL mit `root` ohne Passwort,
MAMP mit `root`/`root`. Abweichende Werte gehören in `dev.local.conf` neben
dem Skript:

```bash
MYSQL_PASS="geheim"
MAMP_PASS="root"
```

Die Datei steht in `.gitignore` und wird auch gefunden, wenn `dev.sh` über
einen Symlink aufgerufen wird.

## Benutzung

Ohne Parameter öffnet sich das Menü (Pfeiltasten oder Nummer eingeben).
Alle Funktionen gibt es auch als Direktbefehl:

| Befehl                            | Funktion                                                             |
| --------------------------------- | -------------------------------------------------------------------- |
| `dev status`                      | Status von Valet, MySQL und PHP                                      |
| `dev start` / `stop` / `restart`  | Valet und MySQL gemeinsam                                            |
| `dev valet:restart`               | nur Valet                                                            |
| `dev db:create [name]`            | Datenbank anlegen                                                    |
| `dev db:list`                     | Datenbanken auflisten                                                |
| `dev db:export-mamp [db]`         | Datenbank aus MAMP PRO in eine `.sql`-Datei exportieren              |
| `dev db:import-file [datei] [db]` | `.sql`-Datei ins native MySQL importieren                            |
| `dev hosts:list`                  | Hosts mit HTTPS- und Datenbank-Status                                |
| `dev hosts`                       | wie `hosts:list`, dazu Zertifikate ausstellen/löschen und neue Hosts |
| `dev check-updates`               | Valet, PHP, MySQL und Imagick auf Updates prüfen                     |

## Umstieg von MAMP PRO

MAMP und Valet laufen nicht gleichzeitig, beide wollen die Ports 80 und 443.
Der Umstieg läuft deshalb in zwei getrennten Schritten über eine Datei:

1. **Export** (`dev db:export-mamp`): startet bei Bedarf nur das MySQL von
   MAMP, ohne Apache, und schreibt die Datenbank in eine `.sql`-Datei. Der
   passende `mysqldump` der laufenden MAMP-Version wird automatisch gewählt.
2. **Import** (`dev db:import-file`): legt die Datenbank im nativen MySQL an,
   auf Wunsch mit einem gleichnamigen Benutzer, und gibt die fertige
   `DATABASE_URL` für die `.env.local` aus.

Danach in der Hosts-Übersicht mit `[s]` ein Zertifikat ausstellen. Ein Host
mit HTTPS gilt als umgestellt.

## Hosts-Übersicht

`dev hosts` listet alle verlinkten Valet-Sites und alle Contao-Projekte in den
geparkten Verzeichnissen als Tabelle:

```
┌─────┬───┬────────────────────────┬──────────┬──────────────────┬──────────────────────────────┐
│ Nr. │   │ URL                    │ PHP      │ DB (nativ)       │ Pfad                         │
├─────┼───┼────────────────────────┼──────────┼──────────────────┼──────────────────────────────┤
│   1 │ ✓ │ https://projekt-a.test │ Standard │ ✓ projekt-a      │ ~/Sites/projekt-a            │
├─────┼───┼────────────────────────┼──────────┼──────────────────┼──────────────────────────────┤
│   2 │ ✓ │ https://alt.test       │ Standard │ —                │ Projekt fehlt (Zertifikat …) │
╞═════╪═══╪════════════════════════╪══════════╪══════════════════╪══════════════════════════════╡
│   3 │ ✗ │ http://projekt-b.test  │ Standard │ ✗ projekt-b      │ ~/Sites/projekt-b            │
└─────┴───┴────────────────────────┴──────────┴──────────────────┴──────────────────────────────┘
```

- **✓ / ✗ vorne:** HTTPS-Zertifikat vorhanden oder nicht
- **DB (nativ):** Name aus `DATABASE_URL` in `.env.local` und ob es die
  Datenbank im nativen MySQL gibt
- **PHP:** eigene Version, wenn der Host per `valet isolate` festgelegt ist
- **Projekt fehlt:** Zertifikat ohne zugehöriges Projekt, kann gelöscht werden

Unter der Tabelle stehen die Aktionen: Zertifikat ausstellen oder erneuern,
Zertifikat löschen und neuen Host anlegen. Ein neuer Host bekommt bei Bedarf
einen `valet link` auf den `public/`-Ordner.

## Hinweise

- **Browser zeigen ein falsches Zertifikat (`CN=default`, MAMP PRO):** Der
  Apache von MAMP läuft noch und belegt Port 443 auf IPv6 (`::1`). Browser
  versuchen `.test`-Domains zuerst über IPv6 und landen dann bei MAMP statt
  bei Valet. MAMP PRO beenden.
- **Firefox akzeptiert das Zertifikat nicht:** In `about:config` den Wert
  `security.enterprise_roots.enabled` auf `true` setzen, damit Firefox die
  Valet-CA aus dem macOS-Schlüsselbund übernimmt.
- **Mehrere Domains für ein Contao-Projekt:** pro Domain einen Valet-Link auf
  denselben `public/`-Ordner anlegen und in Contao bei jedem Startpunkt die
  passende Domain eintragen (`tl_page.dns`).

## Zusammen mit der Contao-PfeilShell

Die Valet-Kommandozentrale kümmert sich um die Umgebung: Valet, MySQL,
Hosts und Zertifikate. Was innerhalb eines Contao-Projekts passiert, also
Cache leeren, Datenbank migrieren oder Backups anlegen, übernimmt die
[Contao-PfeilShell](https://github.com/codesache/Contao-PfeilShell) mit
`./contao.sh` im Projektordner.

## Lizenz

[MIT](LICENSE)

## Autor

Markus Schindler, [CodeSache](https://www.codesache.de): Webdesign und
Programmierung mit Contao
