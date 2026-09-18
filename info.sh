#!/usr/bin/env bash
# info.sh – souhrn informací o studentovi
set -o pipefail
set -u
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

USER_OVERRIDE=""
LIST_USERS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) printf 'Použití: %s [--user USER]\n' "$0"; exit 0 ;;
        --user) [[ $# -ge 2 && -n "$2" ]] || { log_error "Volba --user vyžaduje profil."; exit "$EXIT_CONFIG"; }; USER_OVERRIDE="$2"; shift 2 ;;
        --user=*) USER_OVERRIDE="${1#*=}"; [[ -n "$USER_OVERRIDE" ]] || { log_error "Volba --user vyžaduje profil."; exit "$EXIT_CONFIG"; }; shift ;;
        --list-users) LIST_USERS=1; shift ;;
        *) log_error "Neznámý argument: $1"; exit "$EXIT_CONFIG" ;;
    esac
done

require_cmd curl jq sort sed awk || exit "$EXIT_CONFIG"
require_config || exit "$EXIT_CONFIG"
if (( LIST_USERS )); then list_users; exit 0; fi
resolve_user "$USER_OVERRIDE" || exit "$EXIT_CONFIG"

SCHOOL="$BAKALARI_HOST"
USERNAME="$BAKALARI_LOGIN"
PASSWORD="$BAKALARI_PASS"
TOKEN="$BAKALARI_TOKEN"
API_BASE_URL="${BAKALARI_BASE_URL:-https://$SCHOOL}"
LOGIN_URL="$API_BASE_URL/api/login"
USER_URL="$API_BASE_URL/api/3/user"
ABSENCE_URL="$API_BASE_URL/api/3/absence/student"
MARKS_URL="$API_BASE_URL/api/3/marks"
TIMETABLE_URL="$API_BASE_URL/api/3/timetable/actual"

login_again() {
    TOKEN="$(bakalari_login "$BAKALARI_USER" "$LOGIN_URL" "$USERNAME" "$PASSWORD")" || return 1
    save_token "$BAKALARI_USER" "$TOKEN" || log_warn "Nepodařilo se uložit TOKEN do $BAKALARI_CONFIG"
}

if [[ -z "$TOKEN" ]]; then login_again || exit "$EXIT_NETWORK"; fi
if ! USER_DATA="$(fetch_json "$USER_URL" "$TOKEN" 2>/dev/null)"; then
    login_again || exit "$EXIT_NETWORK"
    USER_DATA="$(fetch_json "$USER_URL" "$TOKEN")" || { log_error "Požadavek na informace o uživateli selhal."; exit "$EXIT_NETWORK"; }
fi
printf '%s' "$USER_DATA" | jq -e 'type == "object"' >/dev/null 2>&1 || { log_error "Neplatná odpověď pro informace o uživateli."; exit "$EXIT_DATA"; }

ABSENCE_DATA="$(fetch_json "$ABSENCE_URL" "$TOKEN" 2>/dev/null || printf '%s' '{"Absences":[],"AbsencesPerSubject":[]}')"
MARKS_DATA="$(fetch_json "$MARKS_URL" "$TOKEN" 2>/dev/null || printf '%s' '{"Subjects":[]}')"
printf '%s' "$ABSENCE_DATA" | jq -e 'type == "object" and (.Absences | type == "array")' >/dev/null 2>&1 || ABSENCE_DATA='{"Absences":[],"AbsencesPerSubject":[]}'
printf '%s' "$MARKS_DATA" | jq -e 'type == "object" and (.Subjects | type == "array")' >/dev/null 2>&1 || MARKS_DATA='{"Subjects":[]}'

TIMETABLE_DATA=""
if [[ -n "$TOKEN" ]]; then
    TIMETABLE_DATA="$(fetch_json "$TIMETABLE_URL" "$TOKEN" 2>/dev/null || true)"
fi
if ! printf '%s' "$TIMETABLE_DATA" | jq -e 'type == "object" and (.Days | type == "array") and (.Teachers | type == "array")' >/dev/null 2>&1; then
    CONFIG_CACHE_DIR="$(config_value general cache_dir)"
    if [[ -z "$CONFIG_CACHE_DIR" ]]; then
        CONFIG_CACHE_DIR="$(config_value "$BAKALARI_USER" cache_dir)"
    fi
    if [[ -n "$CONFIG_CACHE_DIR" && -z "${BAKALARI_CACHE_DIR:-}" ]]; then
        BAKALARI_CACHE_DIR="$CONFIG_CACHE_DIR"
    fi
    CACHE_NAME="timetable-$BAKALARI_USER-$SCHOOL.json"
    TIMETABLE_DATA="$(cache_load "$CACHE_NAME" 2>/dev/null || true)"
fi
if ! printf '%s' "$TIMETABLE_DATA" | jq -e 'type == "object" and (.Days | type == "array") and (.Teachers | type == "array")' >/dev/null 2>&1; then
    TIMETABLE_DATA=""
fi

c256() { printf '\033[38;5;%sm' "$1"; }
row() { printf '%s%-27s%s %s%s%s\n' "$(c256 "$3")" "$1" "$C_RESET" "$(c256 255)" "$2" "$C_RESET"; }

FULL_NAME="$(printf '%s' "$USER_DATA" | jq -r '.FullName // empty')"
FIRST_NAME="$(printf '%s' "$USER_DATA" | jq -r '.FirstName // empty')"
LAST_NAME="$(printf '%s' "$USER_DATA" | jq -r '.LastName // empty')"
CLASS_NAME="$(printf '%s' "$USER_DATA" | jq -r '.Class.Name // .Class.Abbrev // empty')"
CLASS_TEACHER="$(printf '%s' "$USER_DATA" | jq -r '.Class.Teacher.Name // .Class.Teacher.FullName // .Class.ClassTeacher.Name // .Class.ClassTeacher.FullName // .ClassTeacher.Name // .ClassTeacher.FullName // (if (.ClassTeacher | type) == "string" then .ClassTeacher else empty end) // empty')"
if [[ -z "$FIRST_NAME" || -z "$LAST_NAME" ]]; then
    NAME_PART="${FULL_NAME%%,*}"
    FULL_CLASS="${FULL_NAME#*,}"
    if [[ "$FULL_NAME" == *,* && -z "$CLASS_NAME" ]]; then
        CLASS_NAME="$(printf '%s' "$FULL_CLASS" | sed 's/^[[:space:]]*//')"
    fi
    LAST_NAME="$(printf '%s' "$NAME_PART" | awk '{print $1}')"
    FIRST_NAME="$(printf '%s' "$NAME_PART" | awk '{$1=""; sub(/^ /,""); print}')"
fi
[[ -n "$FULL_NAME" ]] || FULL_NAME="$FIRST_NAME $LAST_NAME"
[[ -n "$CLASS_NAME" ]] || CLASS_NAME="${BAKALARI_CLASS:--}"
if [[ -z "$CLASS_TEACHER" && -n "$TIMETABLE_DATA" ]]; then
    CLASS_TEACHER="$(printf '%s' "$TIMETABLE_DATA" | jq -r '
        ([.Teachers[] | {key: (.Id | tostring | gsub("\\s"; "")), name: (.Name // .Abbrev // "")}] | from_entries) as $teachers
        | [.Days[]?.Atoms[]?.TeacherId? | tostring | gsub("\\s"; "") | $teachers[.] // empty]
        | map(select(type == "string" and length > 0))
        | group_by(.)
        | map({name: .[0], count: length})
        | sort_by(-.count, .name)
        | .[0].name // ""
    ' 2>/dev/null)"
fi
[[ -n "$CLASS_TEACHER" ]] || CLASS_TEACHER="-"

read -r ABS_TOTAL ABS_UNSOLVED ABS_EXCUSED <<EOF
$(printf '%s' "$ABSENCE_DATA" | jq -r '
    . as $d
    | ($d.AbsencesPerSubject // []) as $by_subject
    | ($d.Absences // []) as $absences
    | {
        total: (if ($by_subject | length) > 0
                then ($by_subject | map(.Base // .Missed // 0) | add // 0)
                else ($absences | map(.Missed // 0) | add // 0)
                end),
        unsolved: ($absences | map(.Unsolved // 0) | add // 0)
      }
    | "\(.total) \(.unsolved) \((.total - .unsolved) | if . < 0 then 0 else . end)"
')
EOF
OVERALL_AVG="$(printf '%s' "$MARKS_DATA" | jq -r '[.Subjects[]?.AverageText | select(type=="string" and length>0) | gsub(",";".") | tonumber?] | if length==0 then "-" else ((add/length)*100|round/100|tostring|gsub("\\.";",")) end')"

printf '%s%s=== Informace o uživateli ===%s\n' "$C_BOLD" "$(c256 39)" "$C_RESET"
printf '%sProfil: %s%s\n' "$(c256 244)" "$BAKALARI_USER" "$C_RESET"
row "Jméno:" "${FIRST_NAME:--}" 45
row "Příjmení:" "${LAST_NAME:--}" 45
row "Celé jméno:" "${FULL_NAME:--}" 45
row "Třída:" "$CLASS_NAME" 45
row "Třídní učitel:" "$CLASS_TEACHER" 45

printf '\n%s%s=== Docházka ===%s\n' "$C_BOLD" "$(c256 39)" "$C_RESET"
row "Zameškané hodiny:" "$ABS_TOTAL" 208
row "Omluvené hodiny:" "$ABS_EXCUSED" 40
row "Neomluvené / nevyřešené:" "$ABS_UNSOLVED" 196

printf '\n%s%s=== Průměry podle předmětů ===%s\n' "$C_BOLD" "$(c256 39)" "$C_RESET"
printf '%s%-28s %-12s%s\n' "$(c256 244)" "Předmět" "Průměr" "$C_RESET"
printf '%s----------------------------------------%s\n' "$(c256 244)" "$C_RESET"
MARKS_COUNT="$(printf '%s' "$MARKS_DATA" | jq -r '.Subjects | length')"
if [[ "$MARKS_COUNT" -eq 0 ]]; then
    printf '%s(žádné známky)%s\n' "$(c256 244)" "$C_RESET"
else
    printf '%s' "$MARKS_DATA" | jq -r '.Subjects[] | [(.Subject.Abbrev // .Subject.Name // "?"),(.Subject.Name // .Subject.Abbrev // "?"),(.AverageText // "-")] | @tsv' |
    while IFS=
\t' read -r abbrev name average; do
        printf '%s%-28s %-12s%s\n' "$(c256 226)" "$abbrev ($name)" "$average" "$C_RESET"
    done
    printf '%sCelkový průměr předmětů:%s %s%s%s\n' "$(c256 39)" "$C_RESET" "$(c256 226)" "$OVERALL_AVG" "$C_RESET"
fi
