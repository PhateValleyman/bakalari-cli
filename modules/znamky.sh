#!/usr/bin/env bash
# znamky.sh – zobrazení známek

set -o pipefail
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

USER_OVERRIDE=""
LIST_USERS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage_module_header "Modul: znamky"
            usage_section "Použití:"
            printf '  %sbakalari-cli znamky%s [volby]\n' "$C_BOLD" "$C_RESET"
            printf '\n'
            usage_section "Volby:"
            usage_option "--user USER" "Použít konkrétní profil"
            usage_option "--list-users" "Vypsat dostupné profily"
            usage_option "--help" "Zobrazit tuto nápovědu"
            exit 0
            
        --user)
            [[ $# -ge 2 && -n "$2" ]] || { log_error "Volba --user vyžaduje profil."; exit 2; }
            USER_OVERRIDE="$2"
            shift 2
            ;;
        --user=*)
            USER_OVERRIDE="${1#*=}"
            [[ -n "$USER_OVERRIDE" ]] || { log_error "Volba --user vyžaduje profil."; exit 2; }
            shift
            ;;
        --list-users)
            LIST_USERS=1
            shift
            ;;
        *)
            log_error "Neznámý argument: $1"
            exit 2
            ;;
    esac
done

require_cmd curl jq sort sed || exit "$EXIT_CONFIG"
require_config || exit "$EXIT_CONFIG"

if (( LIST_USERS )); then
    list_users
    exit 0
fi

resolve_user "$USER_OVERRIDE" || exit "$EXIT_CONFIG"

SCHOOL="$BAKALARI_HOST"
USERNAME="$BAKALARI_LOGIN"
PASSWORD="$BAKALARI_PASS"
TOKEN="$BAKALARI_TOKEN"
API_BASE_URL="${BAKALARI_BASE_URL:-https://$SCHOOL}"
LOGIN_URL="$API_BASE_URL/api/login"
MARKS_URL="$API_BASE_URL/api/3/marks"
fetch_marks() { fetch_json "$MARKS_URL" "$TOKEN"; }

if [[ -z "$TOKEN" ]] || ! DATA="$(fetch_marks 2>/dev/null)"; then
    if ! TOKEN="$(bakalari_login "$BAKALARI_USER" "$LOGIN_URL" "$USERNAME" "$PASSWORD")"; then exit 1; fi
    save_token "$BAKALARI_USER" "$TOKEN" || log_warn "Nepodařilo se uložit TOKEN do $BAKALARI_CONFIG"
    if ! DATA="$(fetch_marks)"; then
        log_error "Požadavek na známky selhal i po přihlášení."
        exit "$EXIT_NETWORK"
    fi
fi

if ! printf '%s' "$DATA" | jq -e 'type == "object" and (.Subjects | type == "array")' >/dev/null 2>&1; then
    log_error "Neplatná odpověď z Bakalářů API pro známky."
    exit "$EXIT_DATA"
fi

printf '%s=== Známky ===%s\n' "$C_BOLD" "$C_RESET"
printf '%s' "$DATA" | jq -r '
    .Subjects[]?
    | "[" + (.Subject.Abbrev // .Subject.Name // "?") + "] průměr: " + (.AverageText // "-"),
      (.Marks[]?
        | "  " + (.MarkText // "-")
        + "  " + (.Caption // "")
        + "  " + (.MarkDate[0:10] // "")
        + "  váha: " + ((.Weight // "-") | tostring)
        + (if .IsNew == true then "  *NOVÁ*" else "" end))
'
