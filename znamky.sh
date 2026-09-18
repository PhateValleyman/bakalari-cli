#!/usr/bin/env bash
# znamky.sh – zobrazí známky z Bakalářů v terminálu.

set -o pipefail
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SCHOOL_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            printf 'Použití: %s [--school DOMÉNA]\nZobrazí známky z Bakalářů.\n' "$0"
            exit 0
            ;;
        --school)
            [[ $# -ge 2 && -n "$2" ]] || { log_error "Volba --school vyžaduje doménu školy."; exit 2; }
            SCHOOL_OVERRIDE="$2"
            shift 2
            ;;
        *)
            log_error "Neznámý argument: $1"
            exit 2
            ;;
    esac
done

require_cmd curl jq || exit "$EXIT_CONFIG"
require_config || exit "$EXIT_CONFIG"

SCHOOL="$(config_value general school)"
[[ -n "$SCHOOL_OVERRIDE" ]] && SCHOOL="$SCHOOL_OVERRIDE"
SCHOOL="${SCHOOL:-zssumava.bakalari.cz}"
BAKALARI_BASE_URL="${BAKALARI_BASE_URL-}"
API_BASE_URL="https://$SCHOOL"
[[ -n "$BAKALARI_BASE_URL" ]] && API_BASE_URL="$BAKALARI_BASE_URL"
LOGIN_URL="$API_BASE_URL/api/login"
MARKS_URL="$API_BASE_URL/api/3/marks"

USERNAME="$(config_value "$SCHOOL" user)"
PASSWORD="$(config_value "$SCHOOL" pass)"
TOKEN="$(config_value "$SCHOOL" TOKEN)"

[[ -n "$USERNAME" ]] || { log_error "Chybí \"user\" v $BAKALARI_CONFIG"; exit 1; }
[[ -n "$PASSWORD" ]] || { log_error "Chybí \"pass\" v $BAKALARI_CONFIG"; exit 1; }

fetch_marks() { fetch_json "$MARKS_URL" "$TOKEN"; }

if [[ -z "$TOKEN" ]] || ! DATA="$(fetch_marks 2>/dev/null)"; then
    if ! TOKEN="$(bakalari_login "$SCHOOL" "$LOGIN_URL" "$USERNAME" "$PASSWORD")"; then exit 1; fi
    save_token "$SCHOOL" "$TOKEN" || log_warn "Nepodařilo se uložit TOKEN do $BAKALARI_CONFIG"
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
