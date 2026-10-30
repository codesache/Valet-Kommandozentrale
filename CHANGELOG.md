# Changelog

Alle Änderungen an der Valet-Kommandozentrale. Versionen folgen
[Semantic Versioning](https://semver.org/lang/de/).

## [1.0.0] – 2026-10-30

Erste öffentliche Version.

### Enthalten
- Menü und Direktbefehle für Valet und Homebrew-MySQL: Status, Start, Stopp,
  Neustart
- Datenbanken anlegen und auflisten
- Umstieg von MAMP PRO: Datenbank aus MAMP in eine `.sql`-Datei exportieren
  und ins native MySQL importieren, optional mit passendem DB-Benutzer
- Hosts-Übersicht als Tabelle mit HTTPS-Status, Datenbank, PHP-Version und
  Pfad (`dev hosts:list`)
- Zertifikate ausstellen, erneuern und löschen sowie neue Hosts anlegen
  (`dev hosts`)
- Update-Prüfung für Valet, PHP, MySQL und Imagick
- `valet-precheck.sh` zur Prüfung der Umgebung vor der Installation
- Lokale Zugangsdaten in `dev.local.conf` (nicht im Repo)

[1.0.0]: https://github.com/codesache/Valet-Kommandozentrale/releases/tag/v1.0.0
