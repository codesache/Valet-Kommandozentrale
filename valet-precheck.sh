#!/usr/bin/env bash
#
# valet-precheck.sh
# Prüft die Umgebung vor der Valet+Contao-5-Installation.
# Funktioniert auf Apple Silicon (M-Chip) und Intel-Macs, mit zsh oder bash.
# Nur Diagnose – ändert nichts am System.
#
# Aufruf:  bash valet-precheck.sh
#

set -u

# Farben
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

OK="${GREEN}✓${NC}"
WARN="${YELLOW}!${NC}"
FAIL="${RED}✗${NC}"
INFO="${BLUE}i${NC}"

ISSUES=0
WARNINGS=0

section() {
    echo ""
    echo -e "${BOLD}── $1 ──${NC}"
}

fail() { echo -e "  $FAIL $1"; ISSUES=$((ISSUES+1)); }
warn() { echo -e "  $WARN $1"; WARNINGS=$((WARNINGS+1)); }
ok()   { echo -e "  $OK $1"; }
info() { echo -e "  $INFO $1"; }

echo ""
echo -e "${BOLD}Valet + Contao 5 – Umgebungsprüfung${NC}"
echo "$(date '+%Y-%m-%d %H:%M:%S')"

# ─────────────────────────────────────────────────────────────
section "System"
MACOS_VERSION=$(sw_vers -productVersion)
ARCH=$(uname -m)
info "macOS $MACOS_VERSION ($ARCH)"

if [[ "$ARCH" == "arm64" ]]; then
    BREW_PREFIX="/opt/homebrew"
    info "Apple Silicon erkannt → Homebrew unter $BREW_PREFIX"
else
    BREW_PREFIX="/usr/local"
    info "Intel-Mac erkannt → Homebrew unter $BREW_PREFIX"
fi

# ─────────────────────────────────────────────────────────────
section "Homebrew"
if command -v brew &>/dev/null; then
    BREW_VERSION=$(brew --version | head -1)
    ok "$BREW_VERSION"
    BREW_ACTUAL_PREFIX=$(brew --prefix)
    if [[ "$BREW_ACTUAL_PREFIX" != "$BREW_PREFIX" ]]; then
        warn "brew --prefix ($BREW_ACTUAL_PREFIX) weicht vom Standard ab"
        BREW_PREFIX="$BREW_ACTUAL_PREFIX"
    fi
else
    fail "Homebrew nicht installiert"
    echo "     → Installation: https://brew.sh"
fi

# ─────────────────────────────────────────────────────────────
section "Aktive Shell & PATH"
CURRENT_SHELL=$(basename "${SHELL:-/bin/bash}")
info "Aktive Login-Shell: $CURRENT_SHELL"

if [[ "$CURRENT_SHELL" == "zsh" ]]; then
    SHELL_RC="$HOME/.zshrc"
    SHELL_PROFILE="$HOME/.zprofile"
    PROFILE_FILES=("$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv")
else
    SHELL_RC="$HOME/.bash_profile"
    SHELL_PROFILE="$HOME/.profile"
    PROFILE_FILES=("$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile")
fi

echo -e "  ${INFO} PATH-Reihenfolge:"
echo "$PATH" | tr ':' '\n' | head -6 | sed 's/^/     /'

# MAMP im PATH?
if echo "$PATH" | grep -q "MAMP"; then
    fail "MAMP steht im PATH – überschreibt Homebrew-PHP"
    echo "     → In $SHELL_RC und $SHELL_PROFILE prüfen und entfernen"
fi

# MAMP-Aliase in Profile-Dateien? (ignoriert Kommentarzeilen)
for f in "${PROFILE_FILES[@]}"; do
    if [[ -f "$f" ]]; then
        if grep -v '^[[:space:]]*#' "$f" 2>/dev/null | grep -q "MAMP"; then
            fail "MAMP-Einträge in $f gefunden"
            echo "     → Datei bearbeiten und MAMP-Zeilen entfernen:"
            echo "        grep -n MAMP $f"
        fi
    fi
done

# Prüfen ob PHP@X.Y im PATH gepinnt ist (empfohlen)
if echo "$PATH" | grep -qE "opt/php@[0-9]"; then
    ok "PHP-Version im PATH explizit gepinnt (empfohlen)"
elif echo "$PATH" | grep -q "opt/php/bin"; then
    warn "PATH nutzt generisches 'opt/php' – wechselt beim brew link"
    echo "     → Besser explizit auf 'opt/php@8.4/bin' pinnen"
fi

# ─────────────────────────────────────────────────────────────
section "PHP"
if command -v php &>/dev/null; then
    PHP_BIN=$(which php)
    PHP_VER=$(php -r 'echo PHP_VERSION;')
    PHP_MAJOR_MINOR=$(echo "$PHP_VER" | cut -d. -f1,2)
    ok "aktive CLI: $PHP_BIN"
    ok "Version: PHP $PHP_VER"

    if [[ "$PHP_BIN" == *"MAMP"* ]]; then
        fail "Aktive PHP-Binary kommt aus MAMP!"
    fi

    # Contao-5-Kompatibilität
    case "$PHP_MAJOR_MINOR" in
        8.2|8.3|8.4)
            ok "PHP $PHP_MAJOR_MINOR ist Contao-5-kompatibel"
            ;;
        8.5)
            warn "PHP 8.5 ist offiziell noch nicht Contao-5-supported"
            echo "     → Für tägliche Arbeit auf 8.4 wechseln"
            ;;
        *)
            fail "PHP $PHP_MAJOR_MINOR ist nicht Contao-5-kompatibel"
            ;;
    esac

    # Installierte PHP-Versionen via Homebrew (auch aus Taps wie shivammathur/php)
    if command -v brew &>/dev/null; then
        INSTALLED_PHPS=$(brew list --formula --full-name 2>/dev/null | grep -E "(^|/)php(@[0-9]+\.[0-9]+)?$")
        if [[ -n "$INSTALLED_PHPS" ]]; then
            echo -e "  $INFO installierte Homebrew-PHPs:"
            echo "$INSTALLED_PHPS" | sed 's/^/     /'
        else
            warn "Kein PHP via Homebrew installiert"
            echo "     → brew install php@8.4"
        fi
    fi

    # Wichtige Extensions
    echo -e "  $INFO benötigte Extensions:"
    for ext in mysqli pdo_mysql intl mbstring gd imagick zip curl xml dom fileinfo; do
        if php -m 2>/dev/null | grep -qi "^$ext$"; then
            echo -e "     $OK $ext"
        else
            if [[ "$ext" == "imagick" ]]; then
                echo -e "     $WARN $ext (empfohlen für bessere Bildqualität)"
                WARNINGS=$((WARNINGS+1))
            else
                echo -e "     $FAIL $ext"
                ISSUES=$((ISSUES+1))
            fi
        fi
    done

    # PHP.ini kritische Werte
    echo -e "  $INFO php.ini-Werte (relevant für Contao Manager):"
    PHP_INI=$(php --ini | grep "Loaded" | awk -F: '{print $2}' | xargs)
    echo "     Datei: $PHP_INI"

    check_ini() {
        local key="$1"
        local expected="$2"
        local actual
        actual=$(php -r "echo ini_get('$key');")
        if [[ "$actual" == "$expected" ]]; then
            echo -e "     $OK $key = $actual"
        else
            echo -e "     $WARN $key = $actual (empfohlen: $expected)"
            WARNINGS=$((WARNINGS+1))
        fi
    }
    check_ini "memory_limit" "512M"
    check_ini "max_execution_time" "0"
    check_ini "default_socket_timeout" "600"
    check_ini "post_max_size" "512M"
    check_ini "upload_max_filesize" "512M"
    echo -e "     $INFO 'default_socket_timeout' bei niedrigem Wert (60) → Composer-Cloud-Timeout möglich"
else
    fail "PHP nicht im PATH"
fi

# ─────────────────────────────────────────────────────────────
section "Composer"
if command -v composer &>/dev/null; then
    COMPOSER_BIN=$(which composer)
    COMPOSER_VER=$(composer --version 2>/dev/null | head -1)
    ok "$COMPOSER_BIN"
    ok "$COMPOSER_VER"
    if [[ "$COMPOSER_BIN" == *"MAMP"* ]]; then
        fail "Composer kommt aus MAMP – bitte via 'brew install composer' ersetzen"
    fi
else
    fail "Composer nicht installiert"
    echo "     → brew install composer"
fi

# ─────────────────────────────────────────────────────────────
section "Ports & laufende Server"

check_port() {
    local port="$1"
    local desc="$2"
    local listener
    listener=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $1}' | sort -u | tr '\n' ' ')
    if [[ -z "$listener" ]]; then
        info "Port $port ($desc): frei"
    else
        if echo "$listener" | grep -qE "nginx"; then
            ok "Port $port ($desc): nginx (vermutlich Valet)"
        elif echo "$listener" | grep -qE "httpd|apache"; then
            fail "Port $port ($desc): Apache/httpd blockiert Valet"
            echo "     → MAMP stoppen: MAMP-App öffnen → Stop Servers"
            echo "     → oder: sudo apachectl stop"
        elif echo "$listener" | grep -qE "mysqld"; then
            ok "Port $port ($desc): mysqld läuft"
        else
            warn "Port $port ($desc) belegt von: $listener"
        fi
    fi
}

check_port 80 "HTTP"
check_port 443 "HTTPS"
check_port 3306 "MySQL"

# ─────────────────────────────────────────────────────────────
section "MAMP-Status"
MAMP_FOUND=0
for mamp_path in "/Applications/MAMP" "/Applications/MAMP PRO.app"; do
    if [[ -d "$mamp_path" ]]; then
        MAMP_FOUND=1
        warn "MAMP installiert: $mamp_path"
    fi
done

if [[ $MAMP_FOUND -eq 1 ]]; then
    # Läuft der MAMP-Autostart?
    if pgrep -f "MAMP" &>/dev/null; then
        info "MAMP-Prozesse laufen aktuell"
    fi
    # Läuft Apache im Hintergrund?
    if pgrep -x httpd &>/dev/null; then
        fail "httpd (Apache) läuft im Hintergrund"
        echo "     → MAMP-App öffnen und 'Stop Servers' klicken"
        echo "     → In MAMP-Preferences Autostart deaktivieren"
    fi
    # MAMP-Autostart-LaunchAgents?
    MAMP_AGENTS=$(find "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons -maxdepth 1 \( -name "*mamp*" -o -name "*MAMP*" \) 2>/dev/null)
    if [[ -n "$MAMP_AGENTS" ]]; then
        warn "MAMP LaunchAgents/Daemons gefunden:"
        echo "$MAMP_AGENTS" | sed 's/^/        /'
    fi
    echo "     Hinweis: MAMP kann installiert bleiben, muss aber gestoppt sein wenn Valet läuft."
else
    ok "MAMP nicht installiert"
fi

# ─────────────────────────────────────────────────────────────
section "MySQL / MariaDB (nativ via Homebrew)"
if command -v brew &>/dev/null; then
    NATIVE_DB=$(brew list --formula 2>/dev/null | grep -iE "^(mysql|mariadb|mysql-client)$")
    if [[ -n "$NATIVE_DB" ]]; then
        echo -e "  $INFO installiert:"
        echo "$NATIVE_DB" | sed 's/^/     /'
        # Service-Status
        DB_STATUS=$(brew services list 2>/dev/null | grep -iE "^(mysql|mariadb)" | awk '{print $1" → "$2}')
        if [[ -n "$DB_STATUS" ]]; then
            echo -e "  $INFO Service-Status:"
            echo "$DB_STATUS" | sed 's/^/     /'
        fi
    else
        info "Kein natives MySQL/MariaDB via Homebrew installiert"
        echo "     → brew install mysql"
    fi
fi

# ─────────────────────────────────────────────────────────────
section "Valet"
if command -v valet &>/dev/null; then
    VALET_BIN=$(which valet)
    VALET_VER=$(valet --version 2>/dev/null | head -1)
    ok "$VALET_VER"
    ok "$VALET_BIN"

    # DNS-Test .test
    if ping -c 1 -W 1 foobar.test &>/dev/null; then
        ok ".test-TLD wird auf 127.0.0.1 aufgelöst"
    else
        warn ".test-Domain reagiert nicht"
        echo "     → valet install"
    fi

    # Custom Contao Manager Driver?
    if [[ -f "$HOME/.config/valet/Drivers/ContaoManagerValetDriver.php" ]]; then
        ok "Custom ContaoManagerValetDriver.php installiert"
    else
        warn "ContaoManagerValetDriver.php fehlt in ~/.config/valet/Drivers/"
        echo "     → nötig, damit contao-manager.phar.php im Installationsmodus routet"
    fi

    # Alter SampleValetDriver?
    if [[ -f "$HOME/.config/valet/Drivers/SampleValetDriver.php" ]]; then
        warn "Alter SampleValetDriver.php gefunden (Valet-3-Altlast)"
        echo "     → rm ~/.config/valet/Drivers/SampleValetDriver.php"
    fi
else
    fail "Valet nicht installiert"
    echo "     → composer global require laravel/valet && valet install"
    if ! echo "$PATH" | grep -q ".composer/vendor/bin\|composer/vendor/bin"; then
        echo "     → Composer-global-Bin fehlt im PATH – nach Install ergänzen:"
        echo "        echo 'export PATH=\"\$HOME/.composer/vendor/bin:\$PATH\"' >> $SHELL_RC"
    fi
fi

# ─────────────────────────────────────────────────────────────
section "Projektverzeichnis"
if [[ -d "$HOME/Daten/htdocs" ]]; then
    ok "~/Daten/htdocs existiert"
else
    warn "~/Daten/htdocs fehlt (auf altem Rechner Standard)"
    echo "     → mkdir -p ~/Daten/htdocs"
fi

# Manager-Vorlage
if [[ -f "$HOME/Daten/tools/contao-manager.phar.php" ]]; then
    ok "Manager-Vorlage unter ~/Daten/tools/contao-manager.phar.php vorhanden"
else
    info "Manager-Vorlage unter ~/Daten/tools/ fehlt (optional, aber praktisch)"
fi

# ─────────────────────────────────────────────────────────────
section "Zusammenfassung"
echo ""
if [[ $ISSUES -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}Alles bereit für die Contao-Installation.${NC}"
elif [[ $ISSUES -eq 0 ]]; then
    echo -e "${YELLOW}${BOLD}$WARNINGS Warnung(en), keine kritischen Fehler.${NC}"
    echo "Installation grundsätzlich möglich, aber Empfehlungen oben durchgehen."
else
    echo -e "${RED}${BOLD}$ISSUES kritische(r) Fehler, $WARNINGS Warnung(en).${NC}"
    echo "Bitte zuerst die kritischen Punkte beheben."
fi
echo ""

exit $ISSUES
