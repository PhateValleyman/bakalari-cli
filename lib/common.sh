# shellcheck shell=bash
# lib/common.sh
# Shared functions and configuration for bakalari-cli.
# This file is sourced by the individual scripts.

if ! declare -p C_RESET >/dev/null 2>&1; then readonly C_RESET="$(printf '\033[0m')"; fi
if ! declare -p C_BOLD >/dev/null 2>&1; then readonly C_BOLD="$(printf '\033[1m')"; fi
if ! declare -p C_RED >/dev/null 2>&1; then readonly C_RED="$(printf '\033[1;31m')"; fi
if ! declare -p C_GREEN >/dev/null 2>&1; then readonly C_GREEN="$(printf '\033[1;32m')"; fi
if ! declare -p C_YELLOW >/dev/null 2>&1; then readonly C_YELLOW="$(printf '\033[1;33m')"; fi
if ! declare -p C_BLUE >/dev/null 2>&1; then readonly C_BLUE="$(printf '\033[1;34m')"; fi
if ! declare -p C_CYAN >/dev/null 2>&1; then readonly C_CYAN="$(printf '\033[1;36m')"; fi
if ! declare -p C_GRAY >/dev/null 2>&1; then readonly C_GRAY="$(printf '\033[0;90m')"; fi

# Shared process exit codes.
if ! declare -p EXIT_CONFIG >/dev/null 2>&1; then readonly EXIT_CONFIG=2; fi
if ! declare -p EXIT_NETWORK >/dev/null 2>&1; then readonly EXIT_NETWORK=3; fi
if ! declare -p EXIT_DATA >/dev/null 2>&1; then readonly EXIT_DATA=4; fi
log_info()  { printf '%sINFO:%s  %s\n' "$C_BLUE"   "$C_RESET" "$*" >&2; }
log_warn()  { printf '%sWARN:%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%sERROR:%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }
log_ok()    { printf '%sOK:%s    %s\n' "$C_GREEN"  "$C_RESET" "$*" >&2; }
c256()      { printf '\033[38;5;%sm' "$1"; }

require_cmd() {
    local missing=() c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if (( ${#missing[@]} > 0 )); then
        log_error "Chybí požadované nástroje: ${missing[*]}"
        return "$EXIT_CONFIG"
    fi
    return 0
}

# Config precedence:
# 1. Explicit BAKALARI_CONFIG.
# 2. Legacy ~/.bakalariclirc, when it exists.
# 3. Main ~/.config/bakalari-cli/config.toml.
if [[ -z "${BAKALARI_CONFIG:-}" ]]; then
    if [[ -f "$HOME/.bakalariclirc" ]]; then
        BAKALARI_CONFIG="$HOME/.bakalariclirc"
    else
        BAKALARI_CONFIG="$HOME/.config/bakalari-cli/config.toml"
    fi
fi

# Local cache directory for data that should remain available offline.
if [[ -n "${BAKALARI_CACHE_DIR:-}" ]]; then
    BAKALARI_CACHE_DIR_FROM_ENV=1
else
    BAKALARI_CACHE_DIR_FROM_ENV=0
    BAKALARI_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bakalari-cli"
fi

cache_file() {
    local name="$1" safe
    safe="${name//[^A-Za-z0-9._-]/_}"
    mkdir -p "$BAKALARI_CACHE_DIR" 2>/dev/null || return 1
    printf '%s/%s' "$BAKALARI_CACHE_DIR" "$safe"
}

cache_save() {
    local name="$1" data="$2" file tmp
    file="$(cache_file "$name")" || return 1
    tmp="$(mktemp "${file}.tmp.XXXXXX")" || return 1
    if ! printf '%s' "$data" >"$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    chmod 600 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$file"
}

cache_load() {
    local name="$1" file
    file="$(cache_file "$name")" || return 1
    [[ -s "$file" ]] || return 1
    cat "$file"
}

cache_load_valid() {
    local name="$1" validator="$2" data
    data="$(cache_load "$name" 2>/dev/null)" || return 1
    printf '%s' "$data" | jq -e "$validator" >/dev/null 2>&1 || return 1
    printf '%s' "$data"
}

configure_cache_dir() {
    local configured
    if [[ "${BAKALARI_CACHE_DIR_FROM_ENV:-0}" -eq 1 ]]; then
        return 0
    fi
    configured="$(config_value general cache_dir)"
    [[ -n "$configured" ]] || configured="$(config_value "${BAKALARI_USER:-}" cache_dir)"
    [[ -n "$configured" ]] && BAKALARI_CACHE_DIR="$configured"
}

fetch_cached_json() {
    local name="$1" url="$2" token="$3" validator="$4" data
    if data="$(fetch_json "$url" "$token" 2>/dev/null)" &&
       printf '%s' "$data" | jq -e "$validator" >/dev/null 2>&1; then
        cache_save "$name" "$data" || log_warn "Nepodařilo se uložit cache $name."
        printf '%s' "$data"
        return 0
    fi
    if data="$(cache_load_valid "$name" "$validator")"; then
        log_warn "API není dostupné; používám uloženou cache $name."
        printf '%s' "$data"
        return 0
    fi
    return "$EXIT_NETWORK"
}


require_config() {
    if [[ ! -f "$BAKALARI_CONFIG" ]]; then
        log_error "Konfigurační soubor nenalezen: $BAKALARI_CONFIG"
        log_error "Zkopíruj config.toml.example do tohoto umístění a uprav podle sebe."
        return "$EXIT_CONFIG"
    fi
    return 0
}

config_value() {
    local section="${1:-}" key="${2:-}"
    local rsection="${section//./\\.}"
    awk -F '=' -v section="$rsection" -v key="$key" '
        $0 ~ "^\\[" section "\\][[:space:]]*$" { insec=1; next }
        /^\[/ { insec=0 }
        insec && $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
            value=$0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            gsub(/^[[:space:]]*#[^"]*$/, "", value) # remove trailing comments outside quotes
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^"|"$/, "", value)
            print value
            exit
        }
    ' "$BAKALARI_CONFIG" 2>/dev/null
}

# Resolve a user profile. With no argument, use the first configured userNN entry.
resolve_user() {
    local requested="${1:-}" key value
    if [[ -n "$requested" ]]; then
        BAKALARI_USER="$requested"
    else
        BAKALARI_USER="$(
            awk -F '=' '
                /^[[:space:]]*user[0-9]+[[:space:]]*=/ {
                    key=$1
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
                    sub(/^user/, "", key)
                    if (key ~ /^[0-9]+$/) {
                        val=$2
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
                        gsub(/^"|"$/, "", val)
                        printf "%010d\t%s\n", key, val
                    }
                }
            ' "$BAKALARI_CONFIG" | sort -n | head -n 1 | cut -f2-
        )"
    fi
    if [[ -z "$BAKALARI_USER" ]]; then
        log_error "V [general] není nakonfigurován žádný userNN."
        return "$EXIT_CONFIG"
    fi
    BAKALARI_HOST="$(config_value "$BAKALARI_USER" host)"
    BAKALARI_LOGIN="$(config_value "$BAKALARI_USER" user)"
    BAKALARI_PASS="$(config_value "$BAKALARI_USER" pass)"
    BAKALARI_TOKEN="$(config_value "$BAKALARI_USER" token)"
    BAKALARI_NAME="$(config_value "$BAKALARI_USER" name)"
    BAKALARI_CLASS="$(config_value "$BAKALARI_USER" class)"
    BAKALARI_MAX_HOURS="$(config_value "$BAKALARI_USER" max_hours)"
    [[ -n "$BAKALARI_HOST" ]] || { log_error "V konfiguraci chybí "host" v [$BAKALARI_USER]."; return "$EXIT_CONFIG"; }
    [[ -n "$BAKALARI_LOGIN" ]] || { log_error "V konfiguraci chybí "user" v [$BAKALARI_USER]."; return "$EXIT_CONFIG"; }
    [[ -n "$BAKALARI_PASS" ]] || { log_error "V konfiguraci chybí "pass" v [$BAKALARI_USER]."; return "$EXIT_CONFIG"; }
    return 0
}

list_users() {
    awk -F '=' '
        /^[[:space:]]*user[0-9]+[[:space:]]*=/ {
            key=$1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            sub(/^user/, "", key)
            value=$2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^"|"$/, "", value)
            printf "%s\t%s\n", key, value
        }
    ' "$BAKALARI_CONFIG" | sort -n
}

save_token() {
    local section="$1" token="$2" tmp
    local rsection="${section//./\\.}"
    tmp="$(mktemp)" || return 1
    awk -v section="$rsection" -v token="$token" '
        $0 ~ "^\\[" section "\\][[:space:]]*$" {
            insec=1
            found=1
            print
            next
        }
        insec && /^[[:space:]]*token[[:space:]]*=/ {
            print "token = \"" token "\""
            token_found=1
            next
        }
        /^\[/ {
            if (insec && !token_found) print "token = \"" token "\""
            insec=0
        }
        { print }
        END {
            if (insec && !token_found) print "token = \"" token "\""
            if (!found) exit 2
        }
    ' "$BAKALARI_CONFIG" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$BAKALARI_CONFIG"
}

# Load a timetable subject color from [colors], returning the default when absent.
subject_color() {
    local subject="$1" default="$2" value
    value="$(config_value colors "$subject")"
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 0 && value <= 255 )); then
        printf '%s' "$value"
    else
        printf '%s' "$default"
    fi
}

# Return the configured timetable color as an associative array entry.
load_subject_colors() {
    declare -gA SUBJECT_COLORS=()
    local subjects subjects_raw
    subjects_raw="$(
        awk '
            /^\[colors\]/ { insec=1; next }
            /^\[/ { insec=0 }
            insec && /^[[:space:]]*[^=]+[[:space:]]*=[[:space:]]*[0-9]+/ {
                sub(/^[[:space:]]*/, "")
                sub(/[[:space:]]*=.*/, "")
                print
            }
        ' "$BAKALARI_CONFIG"
    )"
    while read -r s; do
        [[ -n "$s" ]] && SUBJECT_COLORS["$s"]="$(subject_color "$s" 226)"
    done <<< "$subjects_raw"

    # Built-in defaults for common subjects if not in config
    [[ -n "${SUBJECT_COLORS[Hv]:-}" ]] || SUBJECT_COLORS[Hv]=135
    [[ -n "${SUBJECT_COLORS[M]:-}" ]]  || SUBJECT_COLORS[M]=33
    [[ -n "${SUBJECT_COLORS[Čj]:-}" ]] || SUBJECT_COLORS[Čj]=34
    [[ -n "${SUBJECT_COLORS[Prv]:-}" ]] || SUBJECT_COLORS[Prv]=172
    [[ -n "${SUBJECT_COLORS[Vv]:-}" ]] || SUBJECT_COLORS[Vv]=44
    [[ -n "${SUBJECT_COLORS[Pč]:-}" ]] || SUBJECT_COLORS[Pč]=160
    [[ -n "${SUBJECT_COLORS[Tv]:-}" ]] || SUBJECT_COLORS[Tv]=170
}
usage_header() {
    printf '%s%sBakaláři CLI%s\n' "$C_BOLD" "$C_BLUE" "$C_RESET"
}

usage_module_header() {
    printf '%s%s%s%s\n' "$C_BOLD" "$C_BLUE" "$1" "$C_RESET"
}

usage_section() {
    printf '%s%s%s%s\n' "$C_BOLD" "$C_YELLOW" "$1" "$C_RESET"
}

usage_item() {
    printf '  %s%-12s%s %s\n' "$C_GREEN" "$1" "$C_RESET" "$2"
}

usage_option() {
    printf '  %s%-14s%s %s\n' "$C_CYAN" "$1" "$C_RESET" "$2"
}

bakalari_login() {
    local school="$1" login_url="$2" username="$3" password="$4" response
    log_info "Přihlašuji se k $school ..."
    response="$(
        curl -fsS --connect-timeout 10 --max-time 30 -X POST "$login_url" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "client_id=ANDR" \
            --data-urlencode "grant_type=password" \
            --data-urlencode "username=$username" \
            --data-urlencode "password=$password"
    )" || { log_error "Přihlášení k Bakalářům selhalo (síť/HTTP)."; return "$EXIT_NETWORK"; }

    local token
    token="$(printf '%s' "$response" | jq -r '.access_token // empty')"
    if [[ -z "$token" ]]; then
        log_error "Odpověď při přihlášení neobsahuje access_token."
        return "$EXIT_DATA"
    fi
    printf '%s' "$token"
}

fetch_json() {
    curl -fsS --connect-timeout 10 --max-time 30 -X GET "$1" -H "Authorization: Bearer $2" ||
        return "$EXIT_NETWORK"
}

api_base_url() {
    local host="${1:-}" base
    base="${BAKALARI_BASE_URL:-$host}"
    base="${base%/}"
    if [[ "$base" != http://* && "$base" != https://* ]]; then
        base="https://$base"
    fi
    printf '%s' "$base"
}

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
