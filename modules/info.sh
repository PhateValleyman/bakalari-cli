#!/usr/bin/env bash
# info.sh – souhrn informací o studentovi
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
            usage_module_header "Modul: info"
            usage_section "Použití:"
            printf '  %sbakalari-cli info%s [volby]\n' "$C_BOLD" "$C_RESET"
            printf '\n'
            usage_section "Volby:"
            usage_option "--user USER" "Použít konkrétní profil"
            usage_option "--list-users" "Vypsat dostupné profily"
            usage_option "--help" "Zobrazit tuto nápovědu"
            exit 0
            ;;
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

CONFIG_CACHE_DIR="$(config_value general cache_dir)"
if [[ -z "$CONFIG_CACHE_DIR" ]]; then
    CONFIG_CACHE_DIR="$(config_value "$BAKALARI_USER" cache_dir)"
fi
if [[ -n "$CONFIG_CACHE_DIR" && "${BAKALARI_CACHE_DIR_FROM_ENV:-0}" -eq 0 ]]; then
    BAKALARI_CACHE_DIR="$CONFIG_CACHE_DIR"
fi

DATA_FROM_CACHE=0
LATEST_STAMP=0
USER_CACHE="info-$BAKALARI_USER-$SCHOOL-user.json"
ABSENCE_CACHE="info-$BAKALARI_USER-$SCHOOL-absence.json"
MARKS_CACHE="info-$BAKALARI_USER-$SCHOOL-marks.json"
TIMETABLE_CACHE="timetable-$BAKALARI_USER-$SCHOOL.json"

cache_stamp_save() {
    local name="$1" file
    file="$(cache_file "${name}.timestamp")" || return 1
    printf '%s\n' "$(date +%s)" >"$file"
    chmod 600 "$file" 2>/dev/null || true
}

cache_stamp_load() {
    local name="$1" file
    file="$(cache_file "${name}.timestamp")" || return 1
    [[ -s "$file" ]] || return 1
    cat "$file"
}

cache_stamp_text() {
    local ts="$1"
    [[ "$ts" =~ ^[0-9]+$ ]] || return 1
    date -d "@$ts" '+%d.%m.%Y %H:%M:%S'
}

load_data() {
    local target="$1" cache_name="$2" url="$3" validator="$4" required="$5"
    local data=""
    if [[ -z "$TOKEN" ]]; then
        login_again || true
    fi
    if data="$(fetch_json "$url" "$TOKEN" 2>/dev/null)" &&
       printf '%s' "$data" | jq -e "$validator" >/dev/null 2>&1; then
        cache_save "$cache_name" "$data" || log_warn "Nepodařilo se uložit cache $cache_name."
        cache_stamp_save "$cache_name" || true
        printf -v "$target" '%s' "$data"
        return 0
    fi
    if [[ "${AUTH_RETRIED:-0}" -eq 0 ]] && login_again; then
        AUTH_RETRIED=1
        if data="$(fetch_json "$url" "$TOKEN" 2>/dev/null)" &&
           printf '%s' "$data" | jq -e "$validator" >/dev/null 2>&1; then
            cache_save "$cache_name" "$data" || log_warn "Nepodařilo se uložit cache $cache_name."
            cache_stamp_save "$cache_name" || true
            printf -v "$target" '%s' "$data"
            return 0
        fi
    fi
    if data="$(cache_load "$cache_name" 2>/dev/null)" &&
       printf '%s' "$data" | jq -e "$validator" >/dev/null 2>&1; then
        DATA_FROM_CACHE=1
        printf -v "$target" '%s' "$data"
        return 0
    fi
    if [[ "$required" == "1" ]]; then
        return 1
    fi
    printf -v "$target" '%s' '{}'
}

load_data USER_DATA "$USER_CACHE" "$USER_URL" 'type == "object"' 1 || {
    log_error "Informace o uživateli nejsou dostupné online ani z cache."
    exit "$EXIT_NETWORK"
}
load_data ABSENCE_DATA "$ABSENCE_CACHE" "$ABSENCE_URL" 'type == "object" and (.Absences | type == "array")' 0
load_data MARKS_DATA "$MARKS_CACHE" "$MARKS_URL" 'type == "object" and (.Subjects | type == "array")' 0
load_data TIMETABLE_DATA "$TIMETABLE_CACHE" "$TIMETABLE_URL" 'type == "object" and (.Days | type == "array") and (.Teachers | type == "array")' 0
printf '%s' "$ABSENCE_DATA" | jq -e 'type == "object" and (.Absences | type == "array")' >/dev/null 2>&1 || ABSENCE_DATA='{"Absences":[],"AbsencesPerSubject":[]}'
printf '%s' "$MARKS_DATA" | jq -e 'type == "object" and (.Subjects | type == "array")' >/dev/null 2>&1 || MARKS_DATA='{"Subjects":[]}'

for cache_name in "$USER_CACHE" "$ABSENCE_CACHE" "$MARKS_CACHE" "$TIMETABLE_CACHE"; do
    stamp="$(cache_stamp_load "$cache_name" 2>/dev/null || true)"
    if [[ "$stamp" =~ ^[0-9]+$ && "$stamp" -gt "$LATEST_STAMP" ]]; then
        LATEST_STAMP="$stamp"
    fi
done
c256() { printf '\033[38;5;%sm' "$1"; }
row() {
    local label="$1" value="$2" color="$3" width=25 pad
    pad=$((width - ${#label}))
    (( pad < 1 )) && pad=1
    printf '%s%s%s%*s%s%s%s\n' \
        "$(c256 "$color")" "$label" "$C_RESET" "$pad" "" "$(c256 255)" "$value" "$C_RESET"
}

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

if (( LATEST_STAMP > 0 )); then
    UPDATE_TEXT="$(cache_stamp_text "$LATEST_STAMP" 2>/dev/null || printf '%s' "$LATEST_STAMP")"
else
    UPDATE_TEXT="-"
fi
if (( DATA_FROM_CACHE )); then
    UPDATE_COLOR=196
    UPDATE_STATE="CACHE"
else
    UPDATE_COLOR=46
    UPDATE_STATE="AKTUÁLNÍ"
fi

printf '%s%s=== Informace o uživateli ===%s\n' "$C_BOLD" "$(c256 39)" "$C_RESET"
printf '%sProfil: %s%s\n' "$(c256 244)" "$BAKALARI_USER" "$C_RESET"
printf '%sPoslední aktualizace: %s %s%s%s\n' "$(c256 244)" "$UPDATE_STATE" "$(c256 "$UPDATE_COLOR")" "$UPDATE_TEXT" "$C_RESET"
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
    while IFS=$'\t' read -r abbrev name average; do
        printf '%s%-28s %-12s%s\n' "$(c256 226)" "$abbrev ($name)" "$average" "$C_RESET"
    done
    printf '%sCelkový průměr předmětů:%s %s%s%s\n' "$(c256 39)" "$C_RESET" "$(c256 226)" "$OVERALL_AVG" "$C_RESET"
fi
