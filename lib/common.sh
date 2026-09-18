# shellcheck shell=bash
# lib/common.sh
# Shared functions and configuration for bakalari-cli.
# This file is sourced by the individual scripts.

readonly C_RESET=$'\033[0m'
readonly C_BOLD=$'\033[1m'
readonly C_RED=$'\033[1;31m'
readonly C_GREEN=$'\033[1;32m'
readonly C_YELLOW=$'\033[1;33m'
readonly C_BLUE=
# Shared process exit codes.
readonly EXIT_CONFIG=2
readonly EXIT_NETWORK=3
readonly EXIT_DATA=4
log_info()  { printf '%sINFO:%s  %s\n' "$C_BLUE"   "$C_RESET" "$*" >&2; }
log_warn()  { printf '%sWARN:%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%sERROR:%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }
log_ok()    { printf '%sOK:%s    %s\n' "$C_GREEN"  "$C_RESET" "$*" >&2; }

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
BAKALARI_CACHE_DIR="${BAKALARI_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/bakalari}"

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
                    if (key ~ /^[0-9]+$/) printf "%010d\t%s\n", key, $2
                }
            ' "$BAKALARI_CONFIG" | sort -n | head -n 1 | cut -f2- |
            sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//'
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
        $0 ~ "^\\[" section "\\][[:space:]]*$" { insec=1; print; next }
        /^\[/ { insec=0 }
        insec && /^[[:space:]]*token[[:space:]]*=/ {
            print "token = \"" token "\""
            found=1
            next
        }
        { print }
        END { if (!found) exit 2 }
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
    SUBJECT_COLORS[Hv]="$(subject_color Hv 135)"
    SUBJECT_COLORS[M]="$(subject_color M 33)"
    SUBJECT_COLORS[Čj]="$(subject_color Čj 34)"
    SUBJECT_COLORS[Prv]="$(subject_color Prv 172)"
    SUBJECT_COLORS[Vv]="$(subject_color Vv 44)"
    SUBJECT_COLORS[Pč]="$(subject_color Pč 160)"
    SUBJECT_COLORS[Tv]="$(subject_color Tv 170)"
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
        curl -fsS -X POST "$login_url" \
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
    curl -fsS -X GET "$1" -H "Authorization: Bearer $2" || return "$EXIT_NETWORK"
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
}\033[1;34m'
readonly C_CYAN=
# Shared process exit codes.
readonly EXIT_CONFIG=2
readonly EXIT_NETWORK=3
readonly EXIT_DATA=4
log_info()  { printf '%sINFO:%s  %s\n' "$C_BLUE"   "$C_RESET" "$*" >&2; }
log_warn()  { printf '%sWARN:%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%sERROR:%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }
log_ok()    { printf '%sOK:%s    %s\n' "$C_GREEN"  "$C_RESET" "$*" >&2; }

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
BAKALARI_CACHE_DIR="${BAKALARI_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/bakalari}"

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
                    if (key ~ /^[0-9]+$/) printf "%010d\t%s\n", key, $2
                }
            ' "$BAKALARI_CONFIG" | sort -n | head -n 1 | cut -f2- |
            sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//'
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
        $0 ~ "^\\[" section "\\][[:space:]]*$" { insec=1; print; next }
        /^\[/ { insec=0 }
        insec && /^[[:space:]]*token[[:space:]]*=/ {
            print "token = \"" token "\""
            found=1
            next
        }
        { print }
        END { if (!found) exit 2 }
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
    SUBJECT_COLORS[Hv]="$(subject_color Hv 135)"
    SUBJECT_COLORS[M]="$(subject_color M 33)"
    SUBJECT_COLORS[Čj]="$(subject_color Čj 34)"
    SUBJECT_COLORS[Prv]="$(subject_color Prv 172)"
    SUBJECT_COLORS[Vv]="$(subject_color Vv 44)"
    SUBJECT_COLORS[Pč]="$(subject_color Pč 160)"
    SUBJECT_COLORS[Tv]="$(subject_color Tv 170)"
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
        curl -fsS -X POST "$login_url" \
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
    curl -fsS -X GET "$1" -H "Authorization: Bearer $2" || return "$EXIT_NETWORK"
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
}\033[1;36m'
readonly C_GRAY=
# Shared process exit codes.
readonly EXIT_CONFIG=2
readonly EXIT_NETWORK=3
readonly EXIT_DATA=4
log_info()  { printf '%sINFO:%s  %s\n' "$C_BLUE"   "$C_RESET" "$*" >&2; }
log_warn()  { printf '%sWARN:%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%sERROR:%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }
log_ok()    { printf '%sOK:%s    %s\n' "$C_GREEN"  "$C_RESET" "$*" >&2; }

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
BAKALARI_CACHE_DIR="${BAKALARI_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/bakalari}"

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
                    if (key ~ /^[0-9]+$/) printf "%010d\t%s\n", key, $2
                }
            ' "$BAKALARI_CONFIG" | sort -n | head -n 1 | cut -f2- |
            sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//'
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
        $0 ~ "^\\[" section "\\][[:space:]]*$" { insec=1; print; next }
        /^\[/ { insec=0 }
        insec && /^[[:space:]]*token[[:space:]]*=/ {
            print "token = \"" token "\""
            found=1
            next
        }
        { print }
        END { if (!found) exit 2 }
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
    SUBJECT_COLORS[Hv]="$(subject_color Hv 135)"
    SUBJECT_COLORS[M]="$(subject_color M 33)"
    SUBJECT_COLORS[Čj]="$(subject_color Čj 34)"
    SUBJECT_COLORS[Prv]="$(subject_color Prv 172)"
    SUBJECT_COLORS[Vv]="$(subject_color Vv 44)"
    SUBJECT_COLORS[Pč]="$(subject_color Pč 160)"
    SUBJECT_COLORS[Tv]="$(subject_color Tv 170)"
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
        curl -fsS -X POST "$login_url" \
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
    curl -fsS -X GET "$1" -H "Authorization: Bearer $2" || return "$EXIT_NETWORK"
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
}\033[0;90m'

# Shared process exit codes.
readonly EXIT_CONFIG=2
readonly EXIT_NETWORK=3
readonly EXIT_DATA=4
log_info()  { printf '%sINFO:%s  %s\n' "$C_BLUE"   "$C_RESET" "$*" >&2; }
log_warn()  { printf '%sWARN:%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%sERROR:%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }
log_ok()    { printf '%sOK:%s    %s\n' "$C_GREEN"  "$C_RESET" "$*" >&2; }

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
BAKALARI_CACHE_DIR="${BAKALARI_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/bakalari}"

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
                    if (key ~ /^[0-9]+$/) printf "%010d\t%s\n", key, $2
                }
            ' "$BAKALARI_CONFIG" | sort -n | head -n 1 | cut -f2- |
            sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//'
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
        $0 ~ "^\\[" section "\\][[:space:]]*$" { insec=1; print; next }
        /^\[/ { insec=0 }
        insec && /^[[:space:]]*token[[:space:]]*=/ {
            print "token = \"" token "\""
            found=1
            next
        }
        { print }
        END { if (!found) exit 2 }
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
    SUBJECT_COLORS[Hv]="$(subject_color Hv 135)"
    SUBJECT_COLORS[M]="$(subject_color M 33)"
    SUBJECT_COLORS[Čj]="$(subject_color Čj 34)"
    SUBJECT_COLORS[Prv]="$(subject_color Prv 172)"
    SUBJECT_COLORS[Vv]="$(subject_color Vv 44)"
    SUBJECT_COLORS[Pč]="$(subject_color Pč 160)"
    SUBJECT_COLORS[Tv]="$(subject_color Tv 170)"
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
        curl -fsS -X POST "$login_url" \
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
    curl -fsS -X GET "$1" -H "Authorization: Bearer $2" || return "$EXIT_NETWORK"
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