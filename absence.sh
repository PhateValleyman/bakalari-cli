#!/usr/bin/env bash
# absence.sh – zobrazení absence

set -o pipefail
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

USER_OVERRIDE=""
LIST_USERS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            printf 'Použití: %s [--user USER]\n' "$0"
            exit 0
            ;;
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

require_cmd curl jq || exit "$EXIT_CONFIG"
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
ABSENCE_URL="$API_BASE_URL/api/3/absence/student"
fetch_absence() { fetch_json "$ABSENCE_URL" "$TOKEN"; }

if [[ -z "$TOKEN" ]] || ! DATA="$(fetch_absence 2>/dev/null)"; then
    if ! TOKEN="$(bakalari_login "$BAKALARI_USER" "$LOGIN_URL" "$USERNAME" "$PASSWORD")"; then exit 1; fi
    save_token "$BAKALARI_USER" "$TOKEN" || log_warn "Nepodařilo se uložit TOKEN do $BAKALARI_CONFIG"
    if ! DATA="$(fetch_absence)"; then
        log_error "Požadavek na absenci selhal i po přihlášení."
        exit "$EXIT_NETWORK"
    fi
fi

if ! printf '%s' "$DATA" | jq -e 'type == "object" and (.Absences | type == "array")' >/dev/null 2>&1; then
    log_error "Neplatná odpověď z Bakalářů API pro absenci."
    exit "$EXIT_DATA"
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
