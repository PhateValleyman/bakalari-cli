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

printf '\n%s%-12s %-8s %7s %9s %7s %7s %12s%s\n' \
    "$C_BOLD" "Datum" "Den" "Hodiny" "Zameškáno" "Pozdě" "Dříve" "Nevyřešeno" "$C_RESET"
printf '%s\n' '---------------------------------------------------------------'

DAILY_TOTALS="$(printf '%s' "$DATA" | jq -r '
    [.Absences[]?
      | {
          date: (.Date[0:10] // "?"),
          day: (
              ((.Date[0:10] // "0000-00-00") | strptime("%Y-%m-%d") | .[6])
              // -1
          ),
          ok: (.Ok // 0),
          missed: (.Missed // 0),
          late: (.Late // 0),
          soon: (.Soon // 0),
          unsolved: (.Unsolved // 0)
        }
      | .hours = (.ok + .missed + .late + .soon)
      | [.date, .day, .hours, .missed, .late, .soon, .unsolved]
      | @tsv
    ] | .[]
' 2>/dev/null || true)"

if [[ -n "$DAILY_TOTALS" ]]; then
    printf '%s\n' "$DAILY_TOTALS" |
        sort -r -k1,1 |
        while IFS=$'\t' read -r date day hours missed late soon unsolved; do
            case "$day" in
                0) day_name="Po" ;;
                1) day_name="Út" ;;
                2) day_name="St" ;;
                3) day_name="Čt" ;;
                4) day_name="Pá" ;;
                5) day_name="So" ;;
                6) day_name="Ne" ;;
                *) day_name="?" ;;
            esac

            if [[ "$missed" -gt 0 || "$unsolved" -gt 0 ]]; then
                row_color="$C_RESET"
            else
                row_color="$C_DIM"
            fi

            printf '%s%-12s %-8s %7s %9s %7s %7s %12s%s\n' \
                "$row_color" "$date" "$day_name" "$hours" "$missed" "$late" "$soon" "$unsolved" "$C_RESET"
        done
else
    printf '%s%-12s%s\n' "$C_DIM" "(žádná data)" "$C_RESET"
fi

printf '%s\n' '---------------------------------------------------------------'
printf '%s' "$DATA" | jq -r '
    [.Absences[]?]
    | {
        hours: (map((.Ok // 0) + (.Missed // 0) + (.Late // 0) + (.Soon // 0)) | add // 0),
        missed: (map(.Missed // 0) | add // 0),
        late: (map(.Late // 0) | add // 0),
        soon: (map(.Soon // 0) | add // 0),
        unsolved: (map(.Unsolved // 0) | add // 0)
      }
    | [.hours, .missed, .late, .soon, .unsolved]
    | @tsv
' | while IFS=$'\t' read -r hours missed late soon unsolved; do
    printf '%s%-12s %-8s %7s %9s %7s %7s %12s%s\n' \
        "$C_BOLD" "CELKEM" "" "$hours" "$missed" "$late" "$soon" "$unsolved" "$C_RESET"
done
