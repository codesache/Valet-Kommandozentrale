#!/usr/bin/env bash
#
# dev.sh – Valet + MySQL Management für Contao-Entwicklung
# Läuft auf Intel-Macs und Apple Silicon, mit Bash 3.2+ (macOS-Standard).
#
# Aufruf:
#   dev.sh                → interaktives Menü
#   dev.sh status         → Statusübersicht
#   dev.sh start          → Valet + MySQL starten
#   dev.sh stop           → beides stoppen
#   dev.sh restart        → beides neu starten
#   dev.sh db:create      → neue Datenbank anlegen (fragt Namen ab)
#   dev.sh db:list        → alle Datenbanken auflisten
#   dev.sh db:export-mamp → Datenbank aus laufendem MAMP PRO in .sql-Datei exportieren
#   dev.sh db:import-file → .sql-Datei ins native MySQL importieren (Umstieg auf Valet)
#   dev.sh hosts:list     → Hosts mit HTTPS-/DB-Status (✓ HTTPS = auf Valet umgestellt)
#   dev.sh hosts          → wie hosts:list, plus Zertifikat ausstellen/löschen, neuer Host
#   dev.sh valet:restart  → nur Valet
#   dev.sh check-updates  → Valet/PHP/MySQL/Imagick auf Updates prüfen (einzeln: valet:check-update,
#                           php:check-update, mysql:check-update, imagick:check-update)
#

set -u

# ─── Farben ───
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Homebrew-Prefix erkennen (Intel vs. Apple Silicon) ───
if [[ "$(uname -m)" == "arm64" ]]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

# MySQL-Zugang (Standard bei MySQL/Homebrew: root ohne Passwort)
MYSQL_HOST="127.0.0.1"
MYSQL_PORT="3306"
MYSQL_USER="root"
MYSQL_PASS=""

# MAMP PRO MySQL-Zugang (für den Umstieg auf Valet: alte Projekt-DBs importieren)
MAMP_SOCK="/Applications/MAMP/tmp/mysql/mysql.sock"
MAMP_USER="root"
MAMP_PASS="root"

# ─── Lokale Zugangsdaten (nicht im Repo): dev.local.conf neben dem Skript
#     überschreibt die Werte oben. Symlinks auflösen (Aufruf z.B. über
#     /opt/homebrew/bin/dev), Bash 3.2 kennt kein "readlink -f" ───
SCRIPT_PATH="$0"
while [[ -L "$SCRIPT_PATH" ]]; do
    link_target="$(readlink "$SCRIPT_PATH")"
    [[ "$link_target" == /* ]] || link_target="$(dirname "$SCRIPT_PATH")/$link_target"
    SCRIPT_PATH="$link_target"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/dev.local.conf" ]] && source "$SCRIPT_DIR/dev.local.conf"

# ─── Ausgabe-Helper ───
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; }
warn()  { echo -e "  ${YELLOW}!${NC} $1"; }
info()  { echo -e "  ${BLUE}i${NC} $1"; }
title() { echo ""; echo -e "${BOLD}── $1 ──${NC}"; }

# ─── Ja/Nein-Prompt, Bash-3.2-kompatibel ───
confirm_yes() {
    local prompt="$1"
    local reply
    read -rp "  $prompt [j/N]: " reply
    case "$reply" in
        j|J|y|Y|ja|JA|Ja|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

# ─── Nach einer Menü-Aktion auf Leertaste warten, bevor ui_menu_arrows
#     den Screen löscht (sonst verschwindet die Ausgabe sofort wieder –
#     gleiches Problem wie in contao.sh, dort mit ui_pause gelöst) ───
ui_pause() {
    [ -t 0 ] || return 0
    echo ""
    printf "Weiter mit der Leertaste ... "
    local key=""
    while [ "$key" != " " ]; do
        IFS= read -n 1 -s -r key
    done
    echo ""
}

# ─── Pfeiltasten-Menü (übernommen aus Contao-PfeilShell/_contao-lib.sh,
#     ui_menu/ui_menu_plain/ui_menu_arrows – dort Referenz &
#     ausführliche Doku; dialog/whiptail-Zweig hier bewusst weggelassen) ───

# Echte ANSI-C-Escapes (nicht die literalen \033-Strings oben, die nur mit
# "echo -e" funktionieren) – nötig, weil ui_menu_arrows den Bildschirm in
# eine Variable baut und mit "printf '%s'" ausgibt, ohne -e-Interpretation.
if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
    C_RESET=""
    C_ORANGE=""
    C_SELECT=""
    C_GREY=""
    C_BLACK=""
    C_GREEN=""
    C_RED=""
    C_BG_GREEN=""
    C_BG_ORANGE=""
    C_BG_GREY=""
    C_BORDER=""
    C_BG_WHITE=""
else
    C_RESET=$'\033[0m'
    C_ORANGE=$'\033[1;38;2;244;124;0m'
    C_SELECT=$'\033[1;38;2;29;112;183m'
    C_GREY=$'\033[2m'
    C_BLACK=$'\033[0;30m'
    C_GREEN=$'\033[0;32m'
    C_RED=$'\033[0;31m'
    C_BG_GREEN=$'\033[1;30;48;2;80;200;120m'
    C_BG_ORANGE=$'\033[1;30;48;2;244;124;0m'
    C_BG_GREY=$'\033[1;37;48;2;60;60;60m'
    C_BORDER=$'\033[38;2;150;150;150m'
    C_BG_WHITE=$'\033[48;2;255;255;255m'
fi

UI_HINT_SHOWN=""
UI_MENU_TAGS=()
UI_MENU_DESCS=()

# ─── Pfad-Zeile zur Orientierung (wie CONTAO_SH_PATH_LINE in contao.sh) –
#     zeigt, aus welchem Projektordner "dev" aufgerufen wurde ───
UI_PATH_LINE="Pfad: $PWD"

# ui_menu TITLE PROMPT [tag1 desc1 ...] – "#" desc = Gruppen-Header,
# Tag "0" = Beenden/Zurück (Pfeil-links-Kurzbefehl). Ergebnis auf stdout,
# leer bei Abbruch/ESC.
ui_menu() {
    local title="$1" prompt="$2"
    shift 2

    UI_MENU_TAGS=()
    UI_MENU_DESCS=()
    local args=("$@")
    local n=${#args[@]}
    local idx=0
    while [ $idx -lt "$n" ]; do
        UI_MENU_TAGS+=("${args[$idx]}")
        UI_MENU_DESCS+=("${args[$((idx+1))]}")
        idx=$((idx+2))
    done

    # stdout zeigt bei Aufruf per "choice=$(ui_menu ...)" nie auf ein
    # Terminal – deshalb hier bewusst stderr (fd 2) prüfen, nicht stdout.
    if [ -t 0 ] && [ -t 2 ]; then
        ui_menu_arrows "$title" "$prompt"
        return $?
    fi

    ui_menu_plain "$title" "$prompt"
}

# Nummern-Fallback ohne Pfeiltasten (Pipes/Automatisierung/Tests).
ui_menu_plain() {
    local title="$1" prompt="$2"

    {
        echo ""
        echo "${C_ORANGE}=== $title ===${C_RESET}"
        [ -n "$prompt" ] && echo "$prompt"
    } >&2
    local k first=1
    for k in "${!UI_MENU_TAGS[@]}"; do
        if [ "${UI_MENU_TAGS[$k]}" = "#" ]; then
            echo "" >&2
            echo "${C_ORANGE}${UI_MENU_DESCS[$k]}${C_RESET}" >&2
        elif [ "${UI_MENU_TAGS[$k]}" = "0" ]; then
            [ $first -eq 1 ] && echo "" >&2
            printf "  ${C_ORANGE}[%2s] %s${C_RESET}\n" "${UI_MENU_TAGS[$k]}" "${UI_MENU_DESCS[$k]}" >&2
        else
            [ $first -eq 1 ] && echo "" >&2
            printf "  [%2s] %s\n" "${UI_MENU_TAGS[$k]}" "${UI_MENU_DESCS[$k]}" >&2
        fi
        first=0
    done
    echo "" >&2
    read -r -p "Auswahl: " choice
    [ -z "$choice" ] && return 1

    for k in "${!UI_MENU_TAGS[@]}"; do
        if [ "${UI_MENU_TAGS[$k]}" != "#" ] && [ "$choice" = "${UI_MENU_TAGS[$k]}" ]; then
            echo "${UI_MENU_TAGS[$k]}"
            return 0
        fi
    done

    echo "Ungültige Auswahl: $choice" >&2
    return 1
}

# Baut einen Kasten (graue Rahmenlinie, weißer Hintergrund innen) um Titel +
# optionalen Untertitel – Breite richtet sich nach der längeren der beiden
# Zeilen. Ausgabe über stdout, vom Aufrufer per "box="$(...)"" eingefangen.
_ui_box() {
    local title="$1" subtitle="$2"
    local w=${#title}
    [ ${#subtitle} -gt "$w" ] && w=${#subtitle}
    local inner=$((w + 2))

    local bar="" i
    for ((i = 0; i < inner; i++)); do bar+="─"; done

    local title_pad=$((w - ${#title}))
    local sub_pad=$((w - ${#subtitle}))
    local tsp="" ssp="" j
    for ((j = 0; j < title_pad; j++)); do tsp+=" "; done
    for ((j = 0; j < sub_pad; j++)); do ssp+=" "; done

    printf '%s' "${C_BORDER}┌${bar}┐${C_RESET}"$'\n'
    printf '%s' "${C_BORDER}│${C_RESET}${C_BG_WHITE}${C_BLACK} ${title}${tsp} ${C_RESET}${C_BORDER}│${C_RESET}"$'\n'
    if [ -n "$subtitle" ]; then
        printf '%s' "${C_BORDER}│${C_RESET}${C_BG_WHITE}${C_BLACK} ${subtitle}${ssp} ${C_RESET}${C_BORDER}│${C_RESET}"$'\n'
    fi
    printf '%s' "${C_BORDER}└${bar}┘${C_RESET}"$'\n'
}

# Pfeiltasten-Menü für ein echtes Terminal. Siehe Contao-PfeilShell/_contao-lib.sh
# für die ausführliche Doku (Bedienung, Escape-Sequenzen, flackerfreies Zeichnen).
ui_menu_arrows() {
    local title="$1" prompt="$2"

    local -a selectable=()
    local k
    for k in "${!UI_MENU_TAGS[@]}"; do
        [ "${UI_MENU_TAGS[$k]}" != "#" ] && selectable+=("$k")
    done
    [ ${#selectable[@]} -eq 0 ] && return 1

    local zero_idx="" m2
    for m2 in "${!UI_MENU_TAGS[@]}"; do
        if [ "${UI_MENU_TAGS[$m2]}" = "0" ]; then
            zero_idx="$m2"
            break
        fi
    done

    local cur=0 redraw=1 key esc numbuf="" frame first_draw=1

    printf '\033[?25l' >&2

    while true; do
        if [ "$redraw" = "1" ]; then
            frame=$'\033[H\033[2J\033[3J'
            frame="${frame}${UI_LOGO_BLOCK:-}"
            frame="${frame}"$'\n'"$(_ui_box "$title" "$prompt")"$'\n'
            [ -n "${UI_PATH_LINE:-}" ] && frame="${frame}${UI_PATH_LINE}"$'\n'
            [ -n "${UI_STATUS_LINE:-}" ] && frame="${frame}${UI_STATUS_LINE}"$'\n'
            if [ "$UI_HINT_SHOWN" != "1" ]; then
                frame="${frame}"$'\n'"${C_GREY}(Pfeiltasten hoch/runter, rechts/Enter bestätigt, links = zurück - oder Zahl + Enter)${C_RESET}"$'\n'
                UI_HINT_SHOWN=1
            fi
            local m line
            for m in "${!UI_MENU_TAGS[@]}"; do
                if [ "${UI_MENU_TAGS[$m]}" = "#" ]; then
                    frame="${frame}"$'\n'"${C_ORANGE}${UI_MENU_DESCS[$m]}${C_RESET}"$'\n'
                    continue
                fi
                line="$(printf "[%2s] %s" "${UI_MENU_TAGS[$m]}" "${UI_MENU_DESCS[$m]}")"
                if [ "$m" = "${selectable[$cur]}" ]; then
                    frame="${frame}${C_SELECT} > ${line}${C_RESET}"$'\n'
                elif [ "${UI_MENU_TAGS[$m]}" = "0" ]; then
                    frame="${frame}   ${C_ORANGE}${line}${C_RESET}"$'\n'
                else
                    frame="${frame}   ${line}"$'\n'
                fi
            done
            frame="${frame}"$'\n'
            [ -n "$numbuf" ] && frame="${frame}Auswahl: ${numbuf}"$'\n'
            printf '%s' "$frame" >&2
            redraw=0
            first_draw=0
        fi

        IFS= read -rsn1 key
        case "$key" in
            $'\x1b')
                IFS= read -rsn2 -t 1 esc
                case "$esc" in
                    '[A')
                        cur=$(( (cur - 1 + ${#selectable[@]}) % ${#selectable[@]} ))
                        redraw=1
                        ;;
                    '[B')
                        cur=$(( (cur + 1) % ${#selectable[@]} ))
                        redraw=1
                        ;;
                    '[C')
                        printf '\033[?25h' >&2
                        echo "${UI_MENU_TAGS[${selectable[$cur]}]}"
                        return 0
                        ;;
                    '[D')
                        if [ -n "$zero_idx" ]; then
                            printf '\033[?25h' >&2
                            echo "0"
                            return 0
                        fi
                        ;;
                    '')
                        printf '\033[?25h' >&2
                        return 1
                        ;;
                esac
                ;;
            "")
                printf '\033[?25h' >&2
                if [ -n "$numbuf" ]; then
                    for k in "${!UI_MENU_TAGS[@]}"; do
                        if [ "${UI_MENU_TAGS[$k]}" != "#" ] && [ "$numbuf" = "${UI_MENU_TAGS[$k]}" ]; then
                            echo "${UI_MENU_TAGS[$k]}"
                            return 0
                        fi
                    done
                    echo "Ungültige Auswahl: $numbuf" >&2
                    return 1
                fi
                echo "${UI_MENU_TAGS[${selectable[$cur]}]}"
                return 0
                ;;
            [0-9.])
                numbuf="$numbuf$key"
                redraw=1
                ;;
        esac
    done
}

# ─── MySQL-Command mit optionalem Passwort ───
mysql_cmd() {
    if [[ -z "$MYSQL_PASS" ]]; then
        mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" "$@"
    else
        mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASS" "$@"
    fi
}

# ─── MySQL-Server-Version für DATABASE_URL ermitteln ───
mysql_server_version() {
    local ver
    ver=$(mysql_cmd -Ne "SELECT VERSION();" 2>/dev/null | head -1 | cut -d'-' -f1)
    if [[ -z "$ver" ]]; then
        echo "8.0.0"   # Fallback
    else
        echo "$ver"
    fi
}

# ─── Prüfen was aktuell läuft ───
mysql_running() {
    lsof -nP -iTCP:3306 -sTCP:LISTEN 2>/dev/null | grep -q mysqld
}

valet_running() {
    lsof -nP -iTCP:80 -sTCP:LISTEN 2>/dev/null | grep -q nginx
}

# ─── Statuszeile fürs Menü (wie CONTAO_SH_STATUS_LINE in contao.sh) – pro
#     Menü-Durchlauf neu berechnet, nicht bei jedem Pfeiltasten-Redraw, damit
#     die Navigation nicht durch lsof/php-Aufrufe ausgebremst wird ───
ui_build_status_line() {
    local valet_col mysql_col php_col php_ver

    if valet_running; then valet_col="$C_BG_GREEN"; else valet_col="$C_BG_ORANGE"; fi
    if mysql_running; then mysql_col="$C_BG_GREEN"; else mysql_col="$C_BG_ORANGE"; fi

    php_col="$C_BG_GREY"
    php_ver="?"
    if command -v php >/dev/null 2>&1; then
        php_ver=$(php -r 'echo PHP_VERSION;' 2>/dev/null)
        [[ -z "$php_ver" ]] && php_ver="?"
    fi

    UI_STATUS_LINE="${valet_col} Valet $(valet_running && echo läuft || echo gestoppt) ${C_RESET}${mysql_col} MySQL $(mysql_running && echo läuft || echo gestoppt) ${C_RESET}${php_col} PHP ${php_ver} ${C_RESET}"
}

# ─── Prüft ob Valet ohne Passwort-Abfrage läuft, sonst Hinweis mit korrektem Pfad ───
check_valet_sudo() {
    local valet_bin
    valet_bin=$(command -v valet 2>/dev/null)
    if [[ -z "$valet_bin" ]]; then
        return
    fi
    if ! sudo -n "$valet_bin" --version >/dev/null 2>&1; then
        warn "sudo verlangt noch ein Passwort für Valet"
        info "Fix: sudo visudo -f /etc/sudoers.d/valet   und folgende Zeilen einfügen:"
        echo "     Cmnd_Alias VALET = $valet_bin *"
        echo "     %admin ALL=(root) NOPASSWD:SETENV: VALET"
        echo ""
    fi
}

# ─── MySQL-Service über Homebrew finden ───
mysql_service() {
    # Bevorzugt mysql, sonst mariadb
    if brew list --formula 2>/dev/null | grep -qE "^mysql$"; then
        echo "mysql"
    elif brew list --formula 2>/dev/null | grep -qE "^mariadb$"; then
        echo "mariadb"
    else
        echo ""
    fi
}

# ─── Status ───
cmd_status() {
    title "Status"

    check_valet_sudo

    if valet_running; then
        ok "Valet läuft (nginx auf Port 80/443)"
    else
        fail "Valet läuft nicht"
    fi

    if mysql_running; then
        local svc
        svc=$(mysql_service)
        if [[ -n "$svc" ]]; then
            local ver
            ver=$(mysql_server_version)
            ok "MySQL läuft (via Homebrew $svc, Version $ver)"
        else
            ok "MySQL läuft"
        fi
    else
        fail "MySQL läuft nicht auf Port 3306"
    fi

    if command -v php >/dev/null 2>&1; then
        info "PHP: $(php -r 'echo PHP_VERSION;') ($(which php))"

        local php_ini_file max_exec
        php_ini_file=$(php -r 'echo php_ini_loaded_file();' 2>/dev/null)
        max_exec=$(grep -E '^max_execution_time' "$php_ini_file" 2>/dev/null | head -1 | awk -F'=' '{gsub(/ /,"",$2); print $2}')
        local php_tuning
        php_tuning=$(php -r 'echo ini_get("memory_limit")." / ".ini_get("post_max_size")." / ".ini_get("upload_max_filesize");')
        info "PHP-Tuning (memory/post/upload): $php_tuning"
        info "max_execution_time (php.ini, FPM-relevant): ${max_exec:-?}s"

        if php -m 2>/dev/null | grep -qi "^imagick$"; then
            ok "Imagick-Extension geladen"
        else
            warn "Imagick-Extension fehlt"
        fi
    fi

    if command -v valet >/dev/null 2>&1; then
        info "Valet: $(sudo -n valet --version 2>/dev/null | head -1)"
    fi

    if command -v composer >/dev/null 2>&1; then
        info "Composer: $(composer --version 2>/dev/null | awk '{print $3}')"
    fi

    echo ""
}

# ─── Valet start/stop ───
cmd_valet_start()   { title "Valet starten";        sudo valet start;   echo ""; }
cmd_valet_stop()    { title "Valet stoppen";        sudo valet stop;    echo ""; }
cmd_valet_restart() { title "Valet neu starten";    sudo valet restart; echo ""; }

# ─── MySQL start/stop (Homebrew) ───
cmd_mysql_start() {
    title "MySQL starten"
    local svc; svc=$(mysql_service)
    if [[ -z "$svc" ]]; then
        fail "Kein MySQL/MariaDB via Homebrew installiert"
        info "Installation: brew install mysql"
        return
    fi
    brew services start "$svc"
    echo ""
}

cmd_mysql_stop() {
    title "MySQL stoppen"
    local svc; svc=$(mysql_service)
    [[ -z "$svc" ]] && fail "Kein MySQL/MariaDB via Homebrew installiert" && return
    brew services stop "$svc"
    echo ""
}

cmd_mysql_restart() {
    title "MySQL neu starten"
    local svc; svc=$(mysql_service)
    [[ -z "$svc" ]] && fail "Kein MySQL/MariaDB via Homebrew installiert" && return
    brew services restart "$svc"
    echo ""
}

# ─── Alles start/stop/restart ───
cmd_start() {
    cmd_mysql_start
    cmd_valet_start
    cmd_status
}

cmd_stop() {
    cmd_valet_stop
    cmd_mysql_stop
    cmd_status
}

cmd_restart() {
    cmd_mysql_restart
    cmd_valet_restart
    cmd_status
}

# ─── DB-Operationen ───
require_mysql() {
    if ! mysql_running; then
        fail "MySQL läuft nicht – bitte erst starten (dev.sh start)"
        exit 1
    fi
}

cmd_db_create() {
    require_mysql
    title "Neue Datenbank anlegen"

    local db_name="${1:-}"
    if [[ -z "$db_name" ]]; then
        # Vorschlag aus aktuellem Verzeichnisnamen
        local default_name
        default_name=$(basename "$PWD")
        read -rp "  Datenbankname [$default_name]: " db_name
        db_name="${db_name:-$default_name}"
    fi

    # Zeichensatz-Auswahl (Standard: utf8mb4_unicode_ci für Contao)
    local collation="utf8mb4_unicode_ci"
    read -rp "  Kollation [$collation]: " user_collation
    collation="${user_collation:-$collation}"

    # Existiert die DB schon?
    if mysql_cmd -e "SHOW DATABASES LIKE '$db_name';" 2>/dev/null | grep -q "$db_name"; then
        warn "Datenbank '$db_name' existiert bereits"
        if confirm_yes "Neu anlegen (droppen und erstellen)?"; then
            mysql_cmd -e "DROP DATABASE \`$db_name\`;" && info "Alte DB gelöscht"
        else
            info "Abgebrochen"
            return
        fi
    fi

    if mysql_cmd -e "CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE $collation;" 2>/dev/null; then
        ok "Datenbank '$db_name' angelegt ($collation)"
        echo ""
        local server_ver
        server_ver=$(mysql_server_version)
        info "DATABASE_URL für .env.local:"
        echo "     DATABASE_URL=mysql://$MYSQL_USER:$MYSQL_PASS@$MYSQL_HOST:$MYSQL_PORT/$db_name?serverVersion=$server_ver"
    else
        fail "Fehler beim Anlegen"
    fi
    echo ""
}

cmd_db_list() {
    require_mysql
    title "Datenbanken"
    mysql_cmd -e "SHOW DATABASES;" 2>/dev/null | tail -n +2 | grep -vE "^(information_schema|mysql|performance_schema|sys)$" | sed 's/^/  /'
    echo ""
}

# ─── Hosts auflisten: Umstieg MAMP → Valet erkennbar am HTTPS-Zertifikat
#     (~/.config/valet/Certificates/<host>.crt). Kandidaten sind verlinkte
#     Sites plus geparkte Ordner mit Contao-composer.json ───
VALET_HOME="$HOME/.config/valet"

# DB-Name aus DATABASE_URL in .env.local (Fallback .env) eines Projektordners
_project_db_name() {
    local dir="$1" f line
    for f in "$dir/.env.local" "$dir/.env"; do
        [[ -f "$f" ]] || continue
        line=$(grep -E '^[[:space:]]*DATABASE_URL=' "$f" | tail -1)
        [[ -z "$line" ]] && continue
        line="${line#*=}"
        line="${line//\"/}"
        line="${line//\'/}"
        line="${line%%\?*}"
        echo "${line##*/}"
        return
    done
}

# PHP-Version: per "valet isolate" steht valetXX.sock in der Nginx-Site-Config
_host_php_version() {
    local conf="$VALET_HOME/Nginx/$1" sock
    if [[ -f "$conf" ]]; then
        sock=$(grep -oE 'valet[0-9]+\.sock' "$conf" | head -1)
        if [[ -n "$sock" ]]; then
            sock="${sock#valet}"; sock="${sock%.sock}"
            echo "${sock:0:1}.${sock:1}"
            return
        fi
    fi
    echo "Standard"
}

# Von cmd_hosts_list gefüllt (Index = Nr. in der Tabelle), für cmd_hosts_manage
HOSTS_ROW_NAME=()
HOSTS_ROW_PATH=()
HOSTS_ROW_HTTPS=()
HOSTS_ROW_DB=()
HOSTS_TLD="test"

cmd_hosts_list() {
    title "Hosts (✓ = HTTPS, auf Valet/nativ umgestellt)"

    local tld
    tld=$(grep -oE '"tld": *"[^"]+"' "$VALET_HOME/config.json" 2>/dev/null | sed -E 's/.*"([^"]+)"$/\1/')
    tld="${tld:-test}"
    HOSTS_TLD="$tld"

    # Kandidaten als "host|pfad" sammeln (Bash 3.2: keine assoziativen Arrays)
    local candidates="" link name target parked dir
    for link in "$VALET_HOME"/Sites/*; do
        [[ -L "$link" ]] || continue
        name=$(basename "$link")
        target=$(readlink "$link")
        target="${target%/public}"
        target="${target%/web}"
        candidates="$candidates$name|$target"$'\n'
    done
    while IFS= read -r parked; do
        [[ -z "$parked" || "$parked" == "$VALET_HOME/Sites" ]] && continue
        for dir in "$parked"/*/; do
            dir="${dir%/}"
            [[ -f "$dir/composer.json" ]] && grep -q '"contao/' "$dir/composer.json" || continue
            candidates="$candidates$(basename "$dir")|$dir"$'\n'
        done
    done < <(grep -oE '"/[^"]+"' "$VALET_HOME/config.json" 2>/dev/null | tr -d '"')
    # Zertifikate ohne Projekt (verwaist) ebenfalls zeigen
    local crt
    for crt in "$VALET_HOME"/Certificates/*."$tld".crt; do
        [[ -f "$crt" ]] || continue
        name=$(basename "$crt" ".$tld.crt")
        printf '%s' "$candidates" | grep -q "^$name|" || candidates="$candidates$name|"$'\n'
    done

    local dbs=""
    mysql_running && dbs=$(mysql_cmd -Ne "SHOW DATABASES;" 2>/dev/null)
    [[ -z "$dbs" ]] && warn "MySQL läuft nicht – DB-Existenz wird nicht geprüft"

    # Zeilen erst als Klartext sammeln ("https|url|php|dbstatus|db|pfad"),
    # damit die Spaltenbreiten ohne Farbcodes berechnet werden können
    local rows_ok="" rows_open="" host path url db db_state php path_col n_ok=0 n_open=0
    local w_nr=3 w_url=3 w_php=3 w_db=10 w_path=4
    while IFS='|' read -r name path; do
        [[ -z "$name" ]] && continue
        host="$name.$tld"
        db=""; [[ -n "$path" ]] && db=$(_project_db_name "$path")
        if [[ -z "$db" ]]; then
            db_state="none"; db="-"
        elif [[ -z "$dbs" ]]; then
            db_state="unknown"
        elif printf '%s\n' "$dbs" | grep -qxF "$db"; then
            db_state="ok"
        else
            db_state="missing"
        fi
        php=$(_host_php_version "$host")
        path_col="${path/#$HOME/~}"
        [[ -z "$path" ]] && path_col="Projekt fehlt (Zertifikat verwaist)"
        if [[ -f "$VALET_HOME/Certificates/$host.crt" ]]; then
            url="https://$host"
            rows_ok="${rows_ok}1|$name|$path|$url|$php|$db_state|$db|$path_col"$'\n'
            n_ok=$((n_ok + 1))
        else
            url="http://$host"
            rows_open="${rows_open}0|$name|$path|$url|$php|$db_state|$db|$path_col"$'\n'
            n_open=$((n_open + 1))
        fi
        (( ${#url} > w_url )) && w_url=${#url}
        (( ${#php} > w_php )) && w_php=${#php}
        (( ${#db} + 2 > w_db )) && w_db=$(( ${#db} + 2 ))
        (( ${#path_col} > w_path )) && w_path=${#path_col}
    done < <(printf '%s' "$candidates" | sort -t'|' -k1,1 -u)
    local n_all=$((n_ok + n_open))
    (( ${#n_all} > w_nr )) && w_nr=${#n_all}

    # Rahmenlinie: $1/$2/$3 = linkes/mittleres/rechtes Eckzeichen, $4 = Linienzeichen
    _hosts_line() {
        local w out="  $1" ch="${4:-─}"
        for w in "$w_nr" 1 "$w_url" "$w_php" "$w_db" "$w_path"; do
            out="$out$(printf '%*s' $((w + 2)) '' | sed "s/ /$ch/g")$2"
        done
        echo "${out%$2}$3"
    }

    local https mark dbmark
    _hosts_line "┌" "┬" "┐"
    echo -e "  │ ${BOLD}$(printf '%*s' "$w_nr" "Nr.")${NC} │   │ ${BOLD}$(printf '%-*s' "$w_url" "URL")${NC} │ ${BOLD}$(printf '%-*s' "$w_php" "PHP")${NC} │ ${BOLD}$(printf '%-*s' "$w_db" "DB (nativ)")${NC} │ ${BOLD}$(printf '%-*s' "$w_path" "Pfad")${NC} │"
    _hosts_line "├" "┼" "┤"
    local prev="" nr=0
    HOSTS_ROW_NAME=(); HOSTS_ROW_PATH=(); HOSTS_ROW_HTTPS=(); HOSTS_ROW_DB=()
    while IFS='|' read -r https name path url php db_state db path_col; do
        [[ -z "$url" ]] && continue
        nr=$((nr + 1))
        HOSTS_ROW_NAME[$nr]="$name"
        HOSTS_ROW_PATH[$nr]="$path"
        HOSTS_ROW_HTTPS[$nr]="$https"
        HOSTS_ROW_DB[$nr]="$db_state"
        # Trennlinie zwischen allen Zeilen, doppelt zwischen umgestellten und offenen Hosts
        if [[ -n "$prev" && "$prev" != "$https" ]]; then
            _hosts_line "╞" "╪" "╡" "═"
        elif [[ -n "$prev" ]]; then
            _hosts_line "├" "┼" "┤"
        fi
        prev="$https"
        if [[ "$https" == 1 ]]; then mark="${GREEN}✓${NC}"; else mark="${RED}✗${NC}"; fi
        case "$db_state" in
            ok)      dbmark="${GREEN}✓${NC} " ;;
            missing) dbmark="${RED}✗${NC} " ;;
            none)    dbmark="" ; db="${YELLOW}—${NC}$(printf '%*s' $((w_db - 1)) '')" ;;
            *)       dbmark="  " ;;
        esac
        [[ "$db_state" != none ]] && db="$(printf '%-*s' $((w_db - 2)) "$db")"
        path_col="$(printf '%-*s' "$w_path" "$path_col")"
        [[ "$path_col" == "Projekt fehlt"* ]] && path_col="${YELLOW}$path_col${NC}"
        echo -e "  │ $(printf '%*s' "$w_nr" "$nr") │ $mark │ $(printf '%-*s' "$w_url" "$url") │ $(printf '%-*s' "$w_php" "$php") │ $dbmark$db │ $path_col │"
    done < <(printf '%s' "$rows_ok$rows_open")
    _hosts_line "└" "┴" "┘"
    echo ""
    info "$n_ok umgestellt (HTTPS), $n_open noch offen"
    echo ""
}

# ─── Hosts verwalten: Tabelle + Aktionen per Nr. (Zertifikat ausstellen /
#     erneuern / löschen) oder neuen Host für ein Projekt anlegen ───
_hosts_pick_nr() {
    local nr
    read -rp "  Nr.: " nr
    if [[ ! "$nr" =~ ^[0-9]+$ ]] || [[ -z "${HOSTS_ROW_NAME[$nr]:-}" ]]; then
        [[ -n "$nr" ]] && fail "Ungültige Nr.: $nr" >&2   # stdout wird per $(…) abgefangen
        return 1
    fi
    echo "$nr"
}

_hosts_secure() {
    local nr="$1" name="${HOSTS_ROW_NAME[$1]}" host="${HOSTS_ROW_NAME[$1]}.$HOSTS_TLD"
    if [[ -z "${HOSTS_ROW_PATH[$nr]}" ]]; then
        fail "$host: Projekt fehlt – Zertifikat ausstellen nicht möglich (nur löschen)"
        return
    fi
    if [[ "${HOSTS_ROW_HTTPS[$nr]}" == 1 ]]; then
        confirm_yes "Zertifikat für $host erneuern?" || { info "Abgebrochen"; return; }
    else
        # HTTPS gilt als "umgestellt" – ohne importierte DB wäre das irreführend
        if [[ "${HOSTS_ROW_DB[$nr]}" != ok ]]; then
            warn "DB für $host ist im nativen MySQL nicht vorhanden – Host gilt danach trotzdem als umgestellt"
        fi
        confirm_yes "Zertifikat für $host ausstellen?" || { info "Abgebrochen"; return; }
    fi
    check_valet_sudo
    if sudo valet secure "$name"; then
        ok "https://$host abgesichert"
    else
        fail "valet secure $name fehlgeschlagen"
    fi
}

_hosts_unsecure() {
    local nr="$1" name="${HOSTS_ROW_NAME[$1]}" host="${HOSTS_ROW_NAME[$1]}.$HOSTS_TLD"
    if [[ "${HOSTS_ROW_HTTPS[$nr]}" != 1 ]]; then
        info "$host hat kein Zertifikat"
        return
    fi
    confirm_yes "Zertifikat für $host löschen?" || { info "Abgebrochen"; return; }
    check_valet_sudo
    sudo valet unsecure "$name"
    if [[ -f "$VALET_HOME/Certificates/$host.crt" ]]; then
        fail "Zertifikat ist noch vorhanden: $VALET_HOME/Certificates/$host.crt"
    else
        ok "Zertifikat für $host gelöscht"
    fi
}

# Neuer Host: Projektordner wählen; liegt er nicht direkt in einem geparkten
# Verzeichnis (oder soll anders heißen), wird er per "valet link" verlinkt
_hosts_new() {
    local dir name default_name parent docroot
    read -erp "  Projektordner: " dir
    [[ -z "$dir" ]] && { info "Abgebrochen"; return; }
    dir="${dir/#\~/$HOME}"
    dir="${dir%/}"
    if [[ ! -d "$dir" ]]; then
        fail "Ordner nicht gefunden: $dir"
        return
    fi
    dir="$(cd "$dir" && pwd)"
    default_name="$(basename "$dir")"
    read -rp "  Host-Name ohne .$HOSTS_TLD [$default_name]: " name
    name="${name:-$default_name}"
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        fail "Ungültiger Host-Name: $name (erlaubt: a-z, 0-9, -)"
        return
    fi
    if [[ -f "$VALET_HOME/Certificates/$name.$HOSTS_TLD.crt" ]]; then
        warn "$name.$HOSTS_TLD hat bereits ein Zertifikat"
        confirm_yes "Trotzdem neu ausstellen?" || { info "Abgebrochen"; return; }
    fi

    parent="$(dirname "$dir")"
    if [[ "$name" != "$default_name" ]] || ! grep -qF "\"$parent\"" "$VALET_HOME/config.json"; then
        docroot="$dir"
        [[ -d "$dir/public" ]] && docroot="$dir/public"
        info "Verlinke $name.$HOSTS_TLD → ${docroot/#$HOME/~}"
        if ! (cd "$docroot" && valet link "$name"); then
            fail "valet link $name fehlgeschlagen"
            return
        fi
    fi

    check_valet_sudo
    if sudo valet secure "$name"; then
        ok "https://$name.$HOSTS_TLD angelegt und abgesichert"
    else
        fail "valet secure $name fehlgeschlagen"
    fi
}

cmd_hosts_manage() {
    local action nr
    while true; do
        cmd_hosts_list
        # Darstellung wie ui_menu_plain (Hauptmenü)
        echo "${C_ORANGE}Aktionen${C_RESET}"
        printf "  [%2s] %s\n" "s" "Zertifikat ausstellen / erneuern"
        printf "  [%2s] %s\n" "l" "Zertifikat löschen"
        printf "  [%2s] %s\n" "n" "Neuer Host"
        printf "  ${C_ORANGE}[%2s] %s${C_RESET}\n" "0" "Zurück"
        echo ""
        read -rp "Auswahl: " action
        case "$action" in
            s|S) nr=$(_hosts_pick_nr) && _hosts_secure "$nr" ;;
            l|L) nr=$(_hosts_pick_nr) && _hosts_unsecure "$nr" ;;
            n|N) _hosts_new ;;
            0|"") return ;;
            *)   fail "Unbekannte Aktion: $action" ;;
        esac
        ui_pause
    done
}

# ─── Datenbank aus MAMP PRO exportieren / in nativ importieren (Umstieg auf
#     Valet) – zwei getrennte Schritte über eine .sql-Datei, weil MAMP und
#     Valet laut Workflow nie gleichzeitig laufen (immer nur eins von
#     beiden gestartet). Export braucht nur MAMP, Import nur das native
#     MySQL – zeitlich unabhängig voneinander ausführbar.
#
#     Findet die gerade laufende MAMP-MySQL-Version selbst (57 oder 80),
#     weil deren mysql/mysqldump-Client zur jeweiligen Server-Version passen
#     muss (der native Homebrew-Client kann z.B. MySQL 5.7s
#     mysql_native_password nicht mehr, siehe Fehlermeldung "Authentication
#     plugin ... cannot be loaded") ───
_mamp_mysql_basedir() {
    ps aux | grep "[m]ysqld --defaults-file=.*MAMP/tmp/mysql/my.cnf" \
        | grep -oE -- '--basedir=[^ ]+' | head -1 | cut -d= -f2
}

# Liest Version + Datenpfad aus MAMP PROs eigener Einstellungsdatei (nicht
# raten) – Ausgabe "basedir|datadir", leer wenn nicht ermittelbar.
_mamp_mysql_dirs_from_plist() {
    local plist="$HOME/Library/Preferences/de.appsolute.mamppro.plist"
    local ver major minor
    ver="$(defaults read "$plist" mysqlVersion 2>/dev/null)"
    [[ -z "$ver" ]] && return 1
    major="${ver%%.*}"
    minor="${ver#*.}"; minor="${minor%%.*}"
    echo "/Applications/MAMP/Library/bin/mysql${major}${minor}|/Library/Application Support/appsolute/MAMP PRO/db/mysql${major}${minor}"
}

cmd_db_export_mamp() {
    title "Datenbank aus MAMP exportieren (Datei)"

    local basedir started_by_us=0
    basedir="$(_mamp_mysql_basedir)"

    if [[ -z "$basedir" ]]; then
        # MAMP MySQL läuft nicht – nur die DB-Engine selbst starten (kein
        # Apache!), dadurch kein Port-80-Konflikt mit Valet/nginx. MySQL
        # nutzt bei MAMP ohnehin nur einen Unix-Socket (skip-networking in
        # der my.cnf), der Konflikt mit Valet entsteht ausschließlich über
        # Apache auf Port 80.
        local dirs
        dirs="$(_mamp_mysql_dirs_from_plist)"
        if [[ -z "$dirs" ]]; then
            fail "Konnte MAMP-MySQL-Version nicht ermitteln (keine MAMP-PRO-Einstellungen gefunden)"
            echo ""
            return
        fi
        basedir="${dirs%%|*}"
        local datadir="${dirs#*|}"
        if [[ ! -x "$basedir/bin/mysqld" ]]; then
            fail "mysqld nicht gefunden unter $basedir"
            echo ""
            return
        fi
        if [[ ! -d "$datadir" ]]; then
            fail "Datenverzeichnis nicht gefunden: $datadir"
            echo ""
            return
        fi

        info "MAMP MySQL läuft nicht – starte es kurz eigenständig (ohne Apache) …"
        "$basedir/bin/mysqld" \
            --defaults-file="/Applications/MAMP/tmp/mysql/my.cnf" \
            --basedir="$basedir" \
            --datadir="$datadir" \
            --plugin-dir="$basedir/lib/plugin" \
            --tmpdir="/Applications/MAMP/tmp/mysql/tmpdir" \
            --log-error="/Applications/MAMP/logs/mysql_error.log" \
            --pid-file="/Applications/MAMP/tmp/mysql/mysql.pid" \
            --socket="$MAMP_SOCK" \
            >/dev/null 2>&1 &
        disown

        local waited=0
        while [[ ! -S "$MAMP_SOCK" && $waited -lt 20 ]]; do
            sleep 1
            waited=$((waited + 1))
        done
        if [[ ! -S "$MAMP_SOCK" ]]; then
            fail "MAMP MySQL konnte nicht gestartet werden (Timeout) – siehe /Applications/MAMP/logs/mysql_error.log"
            echo ""
            return
        fi
        ok "MAMP MySQL läuft jetzt (eigenständig, ohne Apache)"
        started_by_us=1
    fi

    # Fahre MAMP MySQL beim Verlassen der Funktion wieder herunter, aber nur
    # wenn wir es selbst gestartet haben (lief es schon vorher – z.B. über
    # die MAMP-PRO-App – lassen wir es unangetastet laufen).
    trap '[[ $started_by_us -eq 1 ]] && { "$basedir/bin/mysqladmin" -S "$MAMP_SOCK" -u "$MAMP_USER" -p"$MAMP_PASS" shutdown >/dev/null 2>&1; info "MAMP MySQL wieder gestoppt"; }' RETURN

    if [[ ! -x "$basedir/bin/mysql" ]]; then
        fail "Konnte MAMPs mysql-Client nicht ermitteln"
        echo ""
        return
    fi
    local mamp_mysql="$basedir/bin/mysql"
    local mamp_mysqldump="$basedir/bin/mysqldump"

    local src_db="${1:-}"
    if [[ -z "$src_db" ]]; then
        info "Verfügbare MAMP-Datenbanken:"
        "$mamp_mysql" -S "$MAMP_SOCK" -u "$MAMP_USER" -p"$MAMP_PASS" -Ne "SHOW DATABASES;" 2>/dev/null \
            | grep -vE "^(information_schema|mysql|performance_schema|sys)$" \
            | sed 's/^/  /'
        echo ""
        read -rp "  MAMP-Datenbank zum Exportieren (exakter Name): " src_db
        [[ -z "$src_db" ]] && { info "Abgebrochen"; echo ""; return; }
    fi

    if ! "$mamp_mysql" -S "$MAMP_SOCK" -u "$MAMP_USER" -p"$MAMP_PASS" -e "SHOW DATABASES LIKE '$src_db';" 2>/dev/null | grep -q "$src_db"; then
        fail "'$src_db' existiert nicht in MAMP"
        echo ""
        return
    fi

    local default_file="$PWD/${src_db}.sql"
    local out_file
    read -rp "  Zieldatei [$default_file]: " out_file
    out_file="${out_file:-$default_file}"

    if [[ -f "$out_file" ]]; then
        warn "Datei existiert bereits: $out_file"
        confirm_yes "Überschreiben?" || { info "Abgebrochen"; echo ""; return; }
    fi

    info "Exportiere '$src_db' nach $out_file …"
    if "$mamp_mysqldump" -S "$MAMP_SOCK" -u "$MAMP_USER" -p"$MAMP_PASS" --routines --triggers "$src_db" > "$out_file" 2>/dev/null; then
        ok "Export abgeschlossen: $out_file ($(du -h "$out_file" | cut -f1))"
        info "Import (später, wenn Valet/nativ läuft): dev db:import-file \"$out_file\""
    else
        fail "Export fehlgeschlagen"
        rm -f "$out_file"
    fi
    echo ""
}

cmd_db_import_file() {
    require_mysql
    title "Datenbank aus Datei importieren"

    local in_file="${1:-}"
    if [[ -z "$in_file" ]]; then
        read -rp "  SQL-Datei: " in_file
        [[ -z "$in_file" ]] && { info "Abgebrochen"; echo ""; return; }
    fi

    if [[ ! -f "$in_file" ]]; then
        fail "Datei nicht gefunden: $in_file"
        echo ""
        return
    fi

    local default_name
    default_name="$(basename "$in_file" .sql)"
    local target_db="${2:-}"
    if [[ -z "$target_db" ]]; then
        read -rp "  Zielname in Valet/nativ [$default_name]: " target_db
        target_db="${target_db:-$default_name}"
    fi

    if mysql_cmd -e "SHOW DATABASES LIKE '$target_db';" 2>/dev/null | grep -q "$target_db"; then
        warn "Datenbank '$target_db' existiert bereits"
        if ! confirm_yes "Überschreiben (droppen und neu anlegen)?"; then
            info "Abgebrochen"
            echo ""
            return
        fi
        mysql_cmd -e "DROP DATABASE \`$target_db\`;" 2>/dev/null
    fi

    if ! mysql_cmd -e "CREATE DATABASE \`$target_db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null; then
        fail "Konnte Ziel-Datenbank nicht anlegen"
        echo ""
        return
    fi

    info "Importiere $in_file nach '$target_db' …"
    if mysql_cmd "$target_db" < "$in_file"; then
        ok "Import abgeschlossen: '$target_db'"

        # Projekt-User anlegen: Schema wie bei bestehenden Projekten –
        # DB-Name, User und Passwort identisch.
        local db_user="$MYSQL_USER" db_pass="$MYSQL_PASS"
        if confirm_yes "Passenden User '$target_db' anlegen (Passwort = Benutzername = DB-Name)?"; then
            if mysql_cmd -Ne "SELECT 1 FROM mysql.user WHERE user='$target_db' AND host='localhost';" 2>/dev/null | grep -q 1; then
                warn "User '$target_db'@'localhost' existiert bereits"
                if confirm_yes "User überschreiben (DROP USER + neu anlegen)?"; then
                    mysql_cmd -e "DROP USER '$target_db'@'localhost';" 2>/dev/null
                else
                    info "User-Anlage übersprungen"
                fi
            fi
            if ! mysql_cmd -Ne "SELECT 1 FROM mysql.user WHERE user='$target_db' AND host='localhost';" 2>/dev/null | grep -q 1; then
                mysql_cmd -e "CREATE USER '$target_db'@'localhost' IDENTIFIED BY '$target_db';" 2>/dev/null
                mysql_cmd -e "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, FILE, INDEX, ALTER, SHOW DATABASES, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, CREATE VIEW, SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE, EVENT, TRIGGER ON *.* TO '$target_db'@'localhost';" 2>/dev/null
                mysql_cmd -e "GRANT ALL PRIVILEGES ON \`$target_db\`.* TO '$target_db'@'localhost';" 2>/dev/null
                mysql_cmd -e "FLUSH PRIVILEGES;" 2>/dev/null
                ok "User '$target_db'@'localhost' angelegt"
                db_user="$target_db"
                db_pass="$target_db"
            fi
        fi

        echo ""
        local server_ver
        server_ver=$(mysql_server_version)
        info "DATABASE_URL für .env.local:"
        echo "     DATABASE_URL=mysql://$db_user:$db_pass@$MYSQL_HOST:$MYSQL_PORT/$target_db?serverVersion=$server_ver"
    else
        fail "Import fehlgeschlagen"
    fi
    echo ""
}

# ─── Valet-Update prüfen (Composer global, kein Autostart im Status wegen Netzwerk-Latenz) ───
cmd_valet_check_update() {
    title "Valet-Update prüfen"

    if ! command -v composer >/dev/null 2>&1; then
        fail "Composer nicht gefunden"
        echo ""
        return
    fi

    info "Frage Packagist/GitHub ab …"
    local json
    json=$(composer global outdated laravel/valet --format=json 2>/dev/null)

    if [[ -z "$json" ]]; then
        fail "Abfrage fehlgeschlagen (kein Internet oder Composer-Fehler)"
        echo ""
        return
    fi

    local installed latest
    installed=$(echo "$json" | jq -r '.versions[0] // empty' 2>/dev/null)
    latest=$(echo "$json" | jq -r '.latest // empty' 2>/dev/null)

    if [[ -z "$installed" || -z "$latest" ]]; then
        fail "Antwort konnte nicht ausgewertet werden"
        echo ""
        return
    fi

    if [[ "$installed" == "$latest" ]]; then
        ok "Valet ist aktuell ($installed)"
    else
        warn "Update verfügbar: $installed → $latest"
        if confirm_yes "Jetzt aktualisieren (composer global update laravel/valet)?"; then
            if composer global update laravel/valet; then
                ok "Valet aktualisiert"
            else
                fail "Update fehlgeschlagen"
            fi
        else
            info "Abgebrochen"
        fi
    fi
    echo ""
}

# ─── PHP-Update prüfen (Homebrew, ohne Auto-Update der Formeln) ───
cmd_php_check_update() {
    title "PHP-Update prüfen"

    if ! command -v brew >/dev/null 2>&1; then
        fail "Homebrew nicht gefunden"
        echo ""
        return
    fi

    local formula out found=0
    for formula in php@8.4 php@8.3; do
        if brew list --formula 2>/dev/null | grep -qx "$formula"; then
            found=1
            out=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated "$formula" --verbose 2>/dev/null)
            if [[ -n "$out" ]]; then
                warn "Update verfügbar: $out"
                if confirm_yes "Jetzt aktualisieren (brew upgrade $formula)?"; then
                    if HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade "$formula"; then
                        ok "$formula aktualisiert"
                        info "Danach: Valet neu starten (Menüpunkt 5 / 'dev valet:restart')"
                    else
                        fail "Update fehlgeschlagen"
                    fi
                else
                    info "Abgebrochen"
                fi
            else
                ok "$formula ist aktuell"
            fi
        fi
    done

    [[ $found -eq 0 ]] && info "Keine Homebrew-PHP-Formel gefunden"
    echo ""
}

# ─── MySQL-Update prüfen (Homebrew, ohne Auto-Update der Formeln) ───
cmd_mysql_check_update() {
    title "MySQL-Update prüfen"

    if ! command -v brew >/dev/null 2>&1; then
        fail "Homebrew nicht gefunden"
        echo ""
        return
    fi

    local out
    out=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated mysql --verbose 2>/dev/null)
    if [[ -n "$out" ]]; then
        warn "Update verfügbar: $out"
        if confirm_yes "Jetzt aktualisieren (brew upgrade mysql)?"; then
            if HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade mysql; then
                ok "MySQL aktualisiert"
                info "Danach: MySQL neu starten (Menüpunkt 6 / 'dev mysql:restart')"
            else
                fail "Update fehlgeschlagen"
            fi
        else
            info "Abgebrochen"
        fi
    else
        ok "MySQL ist aktuell"
    fi
    echo ""
}

# ─── Imagick-Update prüfen (ImageMagick-Bibliothek via Homebrew + PECL-Extension pro PHP-Version) ───
cmd_imagick_check_update() {
    title "Imagick-Update prüfen"

    if command -v brew >/dev/null 2>&1; then
        local lib_out
        lib_out=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated imagemagick --verbose 2>/dev/null)
        if [[ -n "$lib_out" ]]; then
            warn "ImageMagick-Bibliothek: Update verfügbar: $lib_out"
            if confirm_yes "Jetzt aktualisieren (brew upgrade imagemagick)?"; then
                if HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade imagemagick; then
                    ok "ImageMagick-Bibliothek aktualisiert"
                    info "Imagick-Extension danach neu bauen (siehe unten) – Bibliotheksverknüpfung ändert sich"
                else
                    fail "Update fehlgeschlagen"
                fi
            else
                info "Abgebrochen"
            fi
        else
            ok "ImageMagick-Bibliothek ist aktuell"
        fi
    else
        fail "Homebrew nicht gefunden"
    fi

    local latest
    latest=$(pecl remote-info imagick 2>/dev/null | awk '/^Latest/{print $2}')
    if [[ -z "$latest" ]]; then
        warn "Konnte aktuelle PECL-Version von imagick nicht ermitteln"
        echo ""
        return
    fi

    local entry label base phpbin pecl_bin installed
    for entry in "8.4:/opt/homebrew/opt/php@8.4" "8.3:/opt/homebrew/opt/php@8.3"; do
        label="${entry%%:*}"
        base="${entry#*:}"
        phpbin="$base/bin/php"
        pecl_bin="$base/bin/pecl"
        [[ -x "$phpbin" ]] || continue

        installed=$("$phpbin" -r 'echo phpversion("imagick");' 2>/dev/null)
        if [[ -z "$installed" ]]; then
            warn "PHP $label: Imagick-Extension nicht geladen"
            continue
        fi

        if [[ "$installed" == "$latest" ]]; then
            ok "PHP $label: Imagick-Extension aktuell ($installed)"
        else
            warn "PHP $label: Imagick-Extension Update verfügbar: $installed → $latest"
            if confirm_yes "Jetzt neu bauen (pecl install imagick für PHP $label)?"; then
                if "$pecl_bin" install imagick; then
                    ok "PHP $label: Imagick neu gebaut ($latest)"
                else
                    fail "Build fehlgeschlagen"
                fi
            else
                info "Abgebrochen"
            fi
        fi
    done
    echo ""
}

# ─── Untermenü: Updates prüfen ───
update_menu() {
    while true; do
        local choice
        ui_build_status_line
        choice="$(ui_menu "Updates prüfen" "" \
            1 "Valet" \
            2 "PHP" \
            3 "MySQL" \
            4 "Imagick" \
            5 "Alle" \
            0 "Zurück")"
        [ -z "$choice" ] && return
        case "$choice" in
            1) cmd_valet_check_update; ui_pause ;;
            2) cmd_php_check_update; ui_pause ;;
            3) cmd_mysql_check_update; ui_pause ;;
            4) cmd_imagick_check_update; ui_pause ;;
            5) cmd_valet_check_update; cmd_php_check_update; cmd_mysql_check_update; cmd_imagick_check_update; ui_pause ;;
            0) return ;;
        esac
    done
}

# ─── Interaktives Menü ───
menu() {
    while true; do
        local choice
        ui_build_status_line
        choice="$(ui_menu "Valet-Kommandozentrale" "Möge die Macht mit dir sein." \
            "#" "Allgemein" \
            1   "Status anzeigen" \
            "#" "Start / Stop" \
            2   "${C_GREEN}Starten (Valet und MySQL)${C_RESET}" \
            3   "${C_RED}Stoppen${C_RESET}" \
            4   "Alles neu starten" \
            5   "Nur Valet neu starten" \
            6   "Nur MySQL neu starten" \
            "#" "Datenbank" \
            7   "Datenbank anlegen" \
            8   "Datenbanken auflisten" \
            9   "Datenbank aus MAMP exportieren (Datei)" \
            10  "Datenbank aus Datei importieren" \
            "#" "Hosts" \
            11  "Hosts auflisten / Zertifikate verwalten" \
            "#" "Sonstiges" \
            12  "Updates prüfen (Valet/PHP/MySQL/Imagick)" \
            0   "Beenden")"
        [ -z "$choice" ] && exit 0
        case "$choice" in
            1) cmd_status; ui_pause ;;
            2) cmd_start; ui_pause ;;
            3) cmd_stop; ui_pause ;;
            4) cmd_restart; ui_pause ;;
            5) cmd_valet_restart; ui_pause ;;
            6) cmd_mysql_restart; ui_pause ;;
            7) cmd_db_create; ui_pause ;;
            8) cmd_db_list; ui_pause ;;
            9) cmd_db_export_mamp; ui_pause ;;
            10) cmd_db_import_file; ui_pause ;;
            11) cmd_hosts_manage ;;
            12) update_menu ;;
            0) exit 0 ;;
        esac
    done
}

# ─── Hauptprogramm ───
case "${1:-}" in
    ""|menu)          menu ;;
    status)           cmd_status ;;
    start)            cmd_start ;;
    stop)             cmd_stop ;;
    restart)          cmd_restart ;;
    valet:start)      cmd_valet_start ;;
    valet:stop)       cmd_valet_stop ;;
    valet:restart)    cmd_valet_restart ;;
    mysql:start|db:start)     cmd_mysql_start ;;
    mysql:stop|db:stop)       cmd_mysql_stop ;;
    mysql:restart|db:restart) cmd_mysql_restart ;;
    db:create)        cmd_db_create "${2:-}" ;;
    db:list)          cmd_db_list ;;
    db:export-mamp)   cmd_db_export_mamp "${2:-}" ;;
    db:import-file)   cmd_db_import_file "${2:-}" "${3:-}" ;;
    hosts:list)       cmd_hosts_list ;;
    hosts)            cmd_hosts_manage ;;
    valet:check-update)   cmd_valet_check_update ;;
    php:check-update)     cmd_php_check_update ;;
    mysql:check-update)   cmd_mysql_check_update ;;
    imagick:check-update) cmd_imagick_check_update ;;
    check-updates)        cmd_valet_check_update; cmd_php_check_update; cmd_mysql_check_update; cmd_imagick_check_update ;;
    -h|--help|help)
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        fail "Unbekannter Befehl: $1"
        echo "  → dev.sh help"
        exit 1
        ;;
esac
