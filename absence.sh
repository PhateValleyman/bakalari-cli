#!/usr/bin/env bash
# absence.sh – zobrazí přehled absence z Bakalářů v terminálu.

set -o pipefail
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SCHOOL_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            printf 'Použití: %s [--school DOMÉNA]\nZobrazí absenci z Bakalářů.\n' "$0"
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

require_cmd curl jq || exit 1
require_config || exit 1

SCHOOL="$(config_value general school)"
[[ -n "$SCHOOL_OVERRIDE" ]] && SCHOOL="$SCHOOL_OVERRIDE"
SCHOOL="${SCHOOL:-zssumava.bakalari.cz}"
BAKALARI_BASE_URL="${BAKALARI_BASE_URL-}"
API_BASE_URL="https://$SCHOOL"
[[ -n "$BAKALARI_BASE_URL" ]] && API_BASE_URL="$BAKALARI_BASE_URL"
LOGIN_URL="$API_BASE_URL/api/login"
ABSENCE_URL="$API_BASE_URL/api/3/absence/student"

USERNAME="$(config_value "$SCHOOL" user)"
PASSWORD="$(config_value "$SCHOOL" pass)"
TOKEN="$(config_value "$SCHOOL" TOKEN)"

[[ -n "$USERNAME" ]] || { log_error "Chybí \"user\" v $BAKALARI_CONFIG"; exit 1; }
[[ -n "$PASSWORD" ]] || { log_error "Chybí \"pass\" v $BAKALARI_CONFIG"; exit 1; }

fetch_absence() { fetch_json "$ABSENCE_URL" "$TOKEN"; }

if [[ -z "$TOKEN" ]] || ! DATA="$(fetch_absence 2>/dev/null)"; then
    if ! TOKEN="$(bakalari_login "$SCHOOL" "$LOGIN_URL" "$USERNAME" "$PASSWORD")"; then exit 1; fi
    save_token "$SCHOOL" "$TOKEN" || log_warn "Nepodařilo se uložit TOKEN do $BAKALARI_CONFIG"
    if ! DATA="$(fetch_absence)"; then
        log_error "Požadavek na absenci selhal i po přihlášení."
        exit 1
    fi
fi

if ! printf '%s' "$DATA" | jq -e 'type == "object" and (.Absences | type == "array")' >/dev/null 2>&1; then
    log_error "Neplatná odpověď z Bakalářů API pro absenci."
    exit 1
fi

printf '%s=== Absence ===%s\n' "$C_BOLD" "$C_RESET"
printf '%s' "$DATA" | jq -r '
    [.Absences[]?]
    | {
        ok: (map(.Ok // 0) | add // 0),
        missed: (map(.Missed // 0) | add // 0),
        late: (map(.Late // 0) | add // 0),
        soon: (map(.Soon // 0) | add // 0),
        unsolved: (map(.Unsolved // 0) | add // 0)
      }
    | "Docházka: přítomno=\(.ok), zameškáno=\(.missed), pozdě=\(.late), dříve=\(.soon), nevyřešeno=\(.unsolved)"
'

if printf '%s' "$DATA" | jq -e '.AbsencesPerSubject | type == "array" and length > 0' >/dev/null 2>&1; then
    printf '\n%sPodle předmětů:%s\n' "$C_BOLD" "$C_RESET"
    printf '%s' "$DATA" | jq -r '
        .AbsencesPerSubject[]?
        | "  " + (.SubjectName // "?")
        + ": zameškáno=" + ((.Base // 0) | tostring)
        + ", pozdě=" + ((.Late // 0) | tostring)
        + ", dříve=" + ((.Soon // 0) | tostring)
        + ", hodin=" + ((.LessonsCount // 0) | tostring)
    '
fi
