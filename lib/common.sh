# shellcheck shell=bash
# lib/common.sh
# Sdílené funkce a konfigurace pro bakalari-cli.
# Tento soubor se pouze SOURCUJE z ostatních skriptů (rozvrh.sh, ukoly.sh, ...),
# sám o sobě se nespouští.
#
# Cíl: aby všechny nástroje v tomto repozitáři používaly stejné:
#   - načítání konfigurace (config.toml)
#   - přihlašování k Bakalářům a ukládání TOKENu
#   - barevný a jednotný výstup (INFO/WARN/ERROR/OK)
#   - kontrolu závislostí (curl, jq, ...)
#
# Poznámka k budoucímu přechodu na Go: veškerá logika, která bude potřeba
# přenést (config parsing, login flow, token cache), je soustředěná právě
# zde – ne rozeseta po jednotlivých skriptech. Viz TODOO.md.

# --- Barvy (čisté ANSI escape sekvence, bez závislosti na tput/terminfo,
#     aby fungovaly i na minimálních systémech jako ffp na ZyXEL NSA320) ---
# shellcheck disable=SC2034  # barvy jsou veřejné API pro skripty, co lib sourcují
readonly C_RESET=$'\033[0m'
readonly C_BOLD=$'\033[1m'
readonly C_RED=$'\033[1;31m'
readonly C_GREEN=$'\033[1;32m'
readonly C_YELLOW=$'\033[1;33m'
readonly C_BLUE=$'\033[1;34m'
readonly C_GRAY=$'\033[0;90m'

# --- Jednotné logovací funkce (vše na stderr, aby stdout zůstal čistý
#     pro data/tabulky, které může chtít někdo dál zpracovávat) ------------
log_info()  { printf '%sINFO:%s  %s\n' "$C_BLUE"   "$C_RESET" "$*" >&2; }
log_warn()  { printf '%sWARN:%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%sERROR:%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }
log_ok()    { printf '%sOK:%s    %s\n' "$C_GREEN"  "$C_RESET" "$*" >&2; }

# require_cmd curl jq ...
require_cmd() {
    local missing=() c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if (( ${#missing[@]} > 0 )); then
        log_error "Chybí požadované nástroje: ${missing[*]}"
        return 1
    fi
    return 0
}

# --- Konfigurace ------------------------------------------------------------
# Lze přebít proměnnou prostředí BAKALARI_CONFIG (např. pro testy nebo
# alternativní profil na daném zařízení).
BAKALARI_CONFIG="${BAKALARI_CONFIG:-$HOME/.config/bakalari/config.toml}"

require_config() {
    if [[ ! -f "$BAKALARI_CONFIG" ]]; then
        log_error "Konfigurační soubor nenalezen: $BAKALARI_CONFIG"
        log_error "Zkopíruj config.toml.example do tohoto umístění a uprav podle sebe."
        return 1
    fi
    return 0
}

# config_value <sekce> <klíč>
# Čte hodnotu z jednoduchého TOML-like souboru (sekce v hranatých závorkách,
# klíč = hodnota). Stejná logika se používá pro čtení i zápis (save_token),
# takže obě funkce musí zůstat konzistentní.
config_value() {
    local section="$1" key="$2"
    local rsection="${section//./\\.}"
    awk -F '=' -v section="$rsection" -v key="$key" '
        $0 ~ "^\\[" section "\\][[:space:]]*$" { insec=1; next }
        /^\[/ { insec=0 }
        insec && $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
            value=$0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^"|"$/, "", value)
            print value
            exit
        }
    ' "$BAKALARI_CONFIG" 2>/dev/null
}

# save_token <sekce> <token>
# Zapíše/aktualizuje TOKEN v příslušné sekci konfiguračního souboru.
save_token() {
    local section="$1" token="$2" tmp
    local rsection="${section//./\\.}"
    tmp="$(mktemp)" || return 1
    awk -v section="$rsection" -v token="$token" '
        $0 ~ "^\\[" section "\\][[:space:]]*$" { insec=1; print; next }
        /^\[/ { insec=0 }
        insec && /^[[:space:]]*TOKEN[[:space:]]*=/ { print "TOKEN = \"" token "\""; next }
        { print }
    ' "$BAKALARI_CONFIG" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$BAKALARI_CONFIG"
}

# --- Bakaláři API ------------------------------------------------------------

# bakalari_login <school> <login_url> <username> <password>
# Vypíše nový access token na stdout, nebo vrátí nenulový kód a chybu na stderr.
bakalari_login() {
    local school="$1" login_url="$2" username="$3" password="$4" response
    log_info "Přihlašuji se k $school ..."
    response="$(
        curl -fsS -X POST "$login_url" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "client_id=ANDR" \
            --data-urlencode "grant_type=password" \
            --data-urlencode "username=$username" \
            --data-urlencode "password=$password"
    )" || { log_error "Přihlášení k Bakalářům selhalo (síť/HTTP)."; return 1; }

    local token
    token="$(printf '%s' "$response" | jq -r '.access_token // empty')"
    if [[ -z "$token" ]]; then
        log_error "Odpověď při přihlášení neobsahuje access_token."
        return 1
    fi
    printf '%s' "$token"
}

# fetch_json <url> <token>
fetch_json() {
    curl -fsS -X GET "$1" -H "Authorization: Bearer $2"
}

# --- Notifikace (Termux na Androidu) -----------------------------------------
# notify_android <id> <title> <content>
# Na zařízeních bez termux-notification (NSA320, běžné PC) tiše nic neudělá.
notify_android() {
    command -v termux-notification >/dev/null 2>&1 || return 0
    termux-notification \
        --id "$1" \
        --title "$2" \
        --content "$3" \
        --priority high \
        --sound \
        --vibrate 500,200,500
}
