#!/usr/bin/env bash
# config.sh – interactive configuration editor.

set -o pipefail
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROFILE=""
NEW_PROFILE=0

usage() {
    usage_module_header "Modul: config"
    usage_section "Použití:"
    printf '  %sbakalari-cli config%s [volby]\n' "$C_BOLD" "$C_RESET"
    printf '\n'
    usage_section "Volby:"
    usage_option "--user PROFILE" "Upravit konkrétní profil"
    usage_option "--new" "Vytvořit nový profil"
    usage_option "--help" "Zobrazit tuto nápovědu"
    printf '\n'
    printf 'Editor používá gum, pokud je nainstalovaný; jinak textové dotazy.\n'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --user)
            [[ $# -ge 2 && -n "$2" ]] || { log_error "Volba --user vyžaduje profil."; exit "$EXIT_CONFIG"; }
            PROFILE="$2"
            shift 2
            ;;
        --user=*)
            PROFILE="${1#*=}"
            [[ -n "$PROFILE" ]] || { log_error "Volba --user vyžaduje profil."; exit "$EXIT_CONFIG"; }
            shift
            ;;
        --new) NEW_PROFILE=1; shift ;;
        *) log_error "Neznámý argument: $1"; usage >&2; exit "$EXIT_CONFIG" ;;
    esac
done

require_cmd awk grep mktemp sed || exit "$EXIT_CONFIG"

CONFIG_DIR="$(dirname -- "$BAKALARI_CONFIG")"
if [[ ! -f "$BAKALARI_CONFIG" ]]; then
    mkdir -p "$CONFIG_DIR" || { log_error "Nelze vytvořit adresář konfigurace: $CONFIG_DIR"; exit "$EXIT_CONFIG"; }
    touch "$BAKALARI_CONFIG" || { log_error "Nelze vytvořit konfiguraci: $BAKALARI_CONFIG"; exit "$EXIT_CONFIG"; }
    chmod 600 "$BAKALARI_CONFIG" 2>/dev/null || true
fi

gum_input() {
    local prompt="$1" value="${2:-}" secret="${3:-0}"
    if command -v gum >/dev/null 2>&1; then
        if (( secret )); then
            gum input --password --prompt "$prompt: "
        else
            gum input --prompt "$prompt: " --value "$value"
        fi
    else
        printf '%s [%s]: ' "$prompt" "$value" >&2
        if (( secret )); then
            read -r -s answer
            printf '\n' >&2
        else
            read -r answer
        fi
        printf '%s' "${answer:-$value}"
    fi
}

select_profile() {
    local profiles
    profiles="$(list_users | cut -f2-)"
    if [[ -z "$profiles" ]]; then
        return 1
    fi
    if command -v gum >/dev/null 2>&1; then
        gum choose --header "Vyber profil" <<<"$profiles"
    else
        printf 'Dostupné profily:\n%s\n' "$profiles" >&2
        printf 'Profil: '
        read -r PROFILE
        printf '%s' "$PROFILE"
    fi
}

if (( NEW_PROFILE )); then
    PROFILE="$(gum_input "Název nového profilu" "")"
elif [[ -z "$PROFILE" ]]; then
    PROFILE="$(select_profile || true)"
    [[ -n "$PROFILE" ]] || PROFILE="$(gum_input "Název profilu" "")"
fi

[[ "$PROFILE" =~ ^[A-Za-z0-9._-]+$ ]] || {
    log_error "Název profilu smí obsahovat pouze A-Z, a-z, 0-9, '.', '_' a '-'."
    exit "$EXIT_CONFIG"
}

HOST="$(config_value "$PROFILE" host)"
LOGIN="$(config_value "$PROFILE" user)"
PASS="$(config_value "$PROFILE" pass)"
MAX_HOURS="$(config_value "$PROFILE" max_hours)"
NAME="$(config_value "$PROFILE" name)"
CLASS="$(config_value "$PROFILE" class)"
TOKEN="$(config_value "$PROFILE" token)"
MAX_HOURS="${MAX_HOURS:-6}"

HOST="$(gum_input "Bakaláři host" "$HOST")"
HOST="${HOST#https://}"
HOST="${HOST#http://}"
HOST="${HOST%/}"
LOGIN="$(gum_input "Uživatelské jméno" "$LOGIN")"
NEW_PASS="$(gum_input "Heslo (prázdné = zachovat)" "" 1)"
[[ -n "$NEW_PASS" ]] && PASS="$NEW_PASS"
MAX_HOURS="$(gum_input "Počet hodin rozvrhu" "$MAX_HOURS")"
NAME="$(gum_input "Jméno" "$NAME")"
CLASS="$(gum_input "Třída" "$CLASS")"

[[ -n "$HOST" && -n "$LOGIN" ]] || { log_error "Host a uživatelské jméno jsou povinné."; exit "$EXIT_CONFIG"; }
[[ "$MAX_HOURS" =~ ^[0-9]+$ ]] || { log_error "Počet hodin musí být celé číslo."; exit "$EXIT_CONFIG"; }
[[ -n "$PASS" ]] || { log_error "Heslo nesmí být prázdné."; exit "$EXIT_CONFIG"; }

toml_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

HOST="$(toml_escape "$HOST")"
LOGIN="$(toml_escape "$LOGIN")"
PASS="$(toml_escape "$PASS")"
NAME="$(toml_escape "$NAME")"
CLASS="$(toml_escape "$CLASS")"
TOKEN="$(toml_escape "$TOKEN")"

tmp="$(mktemp "${BAKALARI_CONFIG}.tmp.XXXXXX")" || exit "$EXIT_CONFIG"
awk -v section="$PROFILE" -v host="$HOST" -v login="$LOGIN" -v pass="$PASS" \
    -v max_hours="$MAX_HOURS" -v name="$NAME" -v class_name="$CLASS" -v token="$TOKEN" '
    function emit() {
        print "host = \"" host "\""
        print "user = \"" login "\""
        print "pass = \"" pass "\""
        print "max_hours = " max_hours
        print "token = \"" token "\""
        print "name = \"" name "\""
        print "class = \"" class_name "\""
    }
    {
        header=$0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", header)
    }
    header == "[" section "]" {
        insec=1
        found=1
        print
        emit()
        next
    }
    insec && /^[[:space:]]*(host|user|pass|max_hours|token|name|class)[[:space:]]*=/ { next }
    substr(header, 1, 1) == "[" {
        insec=0
    }
    { print }
    END {
        if (!found) {
            print ""
            print "[" section "]"
            emit()
        }
    }
' "$BAKALARI_CONFIG" >"$tmp" || { rm -f "$tmp"; exit "$EXIT_CONFIG"; }
chmod 600 "$tmp" 2>/dev/null || true
mv -f "$tmp" "$BAKALARI_CONFIG" || { rm -f "$tmp"; exit "$EXIT_CONFIG"; }

if ! awk -F '=' -v profile="$PROFILE" '
    /^[[:space:]]*user[0-9]+[[:space:]]*=/ {
        value=$2
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        gsub(/^"|"$/, "", value)
        if (value == profile) found=1
    }
    END { exit(found ? 0 : 1) }
' "$BAKALARI_CONFIG"; then
    num="$(awk -F '=' '
        /^[[:space:]]*user[0-9]+[[:space:]]*=/ {
            key=$1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            sub(/^user/, "", key)
            if (key ~ /^[0-9]+$/ && key + 0 > max) max=key + 0
        }
        END { printf "%02d", max + 1 }
    ' "$BAKALARI_CONFIG")"
    tmp="$(mktemp "${BAKALARI_CONFIG}.tmp.XXXXXX")" || exit "$EXIT_CONFIG"
    if grep -Eq '^[[:space:]]*\[general\][[:space:]]*$' "$BAKALARI_CONFIG"; then
        awk -v key="user$num" -v profile="$PROFILE" '
            /^[[:space:]]*\[general\][[:space:]]*$/ {
                print
                printf "%s = \"%s\"\n", key, profile
                next
            }
            { print }
        ' "$BAKALARI_CONFIG" >"$tmp"
    else
        { printf '[general]\nuser%s = "%s"\n\n' "$num" "$PROFILE"; cat "$BAKALARI_CONFIG"; } >"$tmp"
    fi
    chmod 600 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$BAKALARI_CONFIG" || { rm -f "$tmp"; exit "$EXIT_CONFIG"; }
fi

unset PASS NEW_PASS TOKEN
log_ok "Profil [$PROFILE] byl uložen do $BAKALARI_CONFIG"
