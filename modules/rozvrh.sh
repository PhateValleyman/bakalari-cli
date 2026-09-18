#!/usr/bin/env bash
# rozvrh.sh – zobrazí barevný rozvrh z Bakalářů.

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

require_cmd curl jq awk sort sed || exit "$EXIT_CONFIG"
require_config || exit "$EXIT_CONFIG"

if (( LIST_USERS )); then
    list_users
    exit 0
fi

resolve_user "$USER_OVERRIDE" || exit "$EXIT_CONFIG"

CONFIG_CACHE_DIR="$(config_value general cache_dir)"
if [[ -z "$CONFIG_CACHE_DIR" ]]; then
    CONFIG_CACHE_DIR="$(config_value "$BAKALARI_USER" cache_dir)"
fi
if [[ -n "$CONFIG_CACHE_DIR" && -z "${BAKALARI_CACHE_DIR:-}" ]]; then
    BAKALARI_CACHE_DIR="$CONFIG_CACHE_DIR"
fi

SCHOOL="$BAKALARI_HOST"
MAX_HOUR="${BAKALARI_MAX_HOURS:-6}"
API_BASE_URL="${BAKALARI_BASE_URL:-https://$SCHOOL}"
LOGIN_URL="$API_BASE_URL/api/login"
TIMETABLE_URL="$API_BASE_URL/api/3/timetable/actual"

if command -v gawk >/dev/null 2>&1; then
    AWK="$(command -v gawk)"
else
    AWK="$(command -v awk)"
    log_warn "gawk nenalezen, používám $AWK."
fi

USERNAME="$BAKALARI_LOGIN"
PASSWORD="$BAKALARI_PASS"
TOKEN="$BAKALARI_TOKEN"

if [[ -z "$USERNAME" ]]; then
    log_error "Chybí \"user\" v [$BAKALARI_USER]"
    exit "$EXIT_CONFIG"
fi
if [[ -z "$PASSWORD" ]]; then
    log_error "Chybí \"pass\" v [$BAKALARI_USER]"
    exit "$EXIT_CONFIG"
fi

fetch_timetable() {
    fetch_json "$TIMETABLE_URL" "$TOKEN"
}

CACHE_NAME="timetable-$BAKALARI_USER-$SCHOOL.json"

valid_timetable() {
    jq -e '
        type == "object"
        and (.Days | type == "array")
        and (.Hours | type == "array")
        and (.Subjects | type == "array")
    ' >/dev/null 2>&1
}

DATA=""
ONLINE=0

if [[ -n "$TOKEN" ]] && DATA="$(fetch_timetable 2>/dev/null)" && printf '%s' "$DATA" | valid_timetable; then
    ONLINE=1
else
    if TOKEN="$(bakalari_login "$BAKALARI_USER" "$LOGIN_URL" "$USERNAME" "$PASSWORD" 2>/dev/null)"; then
        save_token "$BAKALARI_USER" "$TOKEN" || log_warn "Nepodařilo se uložit token do $BAKALARI_CONFIG"
        if DATA="$(fetch_timetable 2>/dev/null)" && printf '%s' "$DATA" | valid_timetable; then
            ONLINE=1
        fi
    fi
fi

if (( ONLINE )); then
    cache_save "$CACHE_NAME" "$DATA" || log_warn "Nepodařilo se uložit místní cache rozvrhu."
else
    if DATA="$(cache_load "$CACHE_NAME" 2>/dev/null)" && printf '%s' "$DATA" | valid_timetable; then
        log_warn "Zařízení je offline nebo API není dostupné; používám uložený rozvrh."
    else
        log_error "Rozvrh není dostupný online a nebyla nalezena platná místní cache."
        exit "$EXIT_NETWORK"
    fi
fi

if ! printf '%s' "$DATA" | jq -e . >/dev/null 2>&1; then
    log_error "Bakaláři vrátili neplatný JSON."
    exit "$EXIT_DATA"
fi

load_subject_colors

# Build the printable timetable rows with a deliberately simple jq pipeline.
if ! TABLE="$(
    printf '%s' "$DATA" |
    jq -r --argjson maxhour "$MAX_HOUR" '
        ([.Subjects[] | {
            key: (.Id | tostring | gsub("\\s"; "")),
            value: (.Abbrev // .Name // "?")
        }] | from_entries) as $subjects
        |
        ([.Teachers[] | {
            key: (.Id | tostring | gsub("\\s"; "")),
            value: (
                (.Name // .Abbrev // "?")
                | gsub("\\s+"; " ")
                | split(" ")
                | map(select(length > 0))
                | if length > 0 then .[-1] else "?" end
            )
        }] | from_entries) as $teachers
        |
        ([.Hours[] | {
            Id: (.Id | tonumber),
            Cap: ((.Caption // (.Id | tostring)) | tostring),
            Begin: ((.BeginTime // "") | tostring),
            End: ((.EndTime // "") | tostring)
        }] | sort_by(.Id) | .[0:$maxhour]) as $hourinfo
        |
        (["HDR"] + [
            $hourinfo[] | .Cap + "\u001f" + .Begin + "\u001f" + .End
        ] | @tsv),
        (
            .Days[]
            | . as $day
            | (
                if $day.DayOfWeek == 1 then "Po"
                elif $day.DayOfWeek == 2 then "Út"
                elif $day.DayOfWeek == 3 then "St"
                elif $day.DayOfWeek == 4 then "Čt"
                elif $day.DayOfWeek == 5 then "Pá"
                else ($day.DayOfWeek | tostring)
                end
            ) as $dn
            | ([$dn] + [
                $hourinfo[]
                | (.Id | tostring) as $hid
                | [
                    $day.Atoms[]?
                    | select((.HourId | tostring) == $hid)
                    | (.SubjectId | tostring | gsub("\\s"; "")) as $sid
                    | {
                        a: ($subjects[$sid] // "?"),
                        t: ($teachers[(.TeacherId | tostring | gsub("\\s"; ""))] // "")
                    }
                ]
                | if length == 0 then ""
                  else (map(.a) | join("/")) + "\u001f" + (map(.t) | join(","))
                  end
            ] | @tsv)
        )
    '
)"; then
    log_error "Nepodařilo se vykreslit rozvrh."
    exit "$EXIT_DATA"
fi

if [[ -z "$TABLE" ]]; then
    log_error "Rozvrh je prázdný."
    exit "$EXIT_DATA"
fi

# Read configured subject colors while preserving the original defaults.
COLOR_HV="${SUBJECT_COLORS[Hv]}"
COLOR_M="${SUBJECT_COLORS[M]}"
COLOR_CJ="${SUBJECT_COLORS[Čj]}"
COLOR_PRV="${SUBJECT_COLORS[Prv]}"
COLOR_VV="${SUBJECT_COLORS[Vv]}"
COLOR_PC="${SUBJECT_COLORS[Pč]}"
COLOR_TV="${SUBJECT_COLORS[Tv]}"

# Render the timetable as a bordered terminal table.
printf '%s\n' "$TABLE" | "$AWK" \
    -v color_hv="$COLOR_HV" \
    -v color_m="$COLOR_M" \
    -v color_cj="$COLOR_CJ" \
    -v color_prv="$COLOR_PRV" \
    -v color_vv="$COLOR_VV" \
    -v color_pc="$COLOR_PC" \
    -v color_tv="$COLOR_TV" '
    function rep(c, n,   s, i) {
        s = ""
        for (i = 0; i < n; i++) s = s c
        return s
    }

    function center(s, w,   total, ls, rs) {
        total = w - length(s)
        if (total < 0) total = 0
        ls = int(total / 2)
        rs = total - ls
        return rep(" ", ls) s rep(" ", rs)
    }

    BEGIN {
        FS  = "\t"
        ESC = "\033"
        US  = "\037"

        HI  = ESC "[48;5;255m" ESC "[38;5;16m"
        HID = ESC "[48;5;255m" ESC "[38;5;245m"
        RST = ESC "[0m"

        col["Hv"]  = color_hv
        col["M"]   = color_m
        col["Čj"]  = color_cj
        col["Prv"] = color_prv
        col["Vv"]  = color_vv
        col["Pč"]  = color_pc
        col["Tv"]  = color_tv
    }

    NR == 1 {
        for (i = 2; i <= NF; i++) {
            n = split($i, p, US)
            cap[i-1]   = (n >= 1) ? p[1] : ""
            tfrom[i-1] = (n >= 2) ? p[2] : ""
            tto[i-1]   = (n >= 3) ? p[3] : ""

            l1 = length(cap[i-1])
            l2 = length(tfrom[i-1])
            l3 = length(tto[i-1])
            w = l1
            if (l2 > w) w = l2
            if (l3 > w) w = l3
            if (w > maxw) maxw = w
        }
        ncols = NF - 1
        next
    }

    NR >= 2 {
        ri = NR - 1
        D[ri] = $1
        for (i = 2; i <= NF; i++) {
            n = split($i, p, US)
            a = (n >= 1) ? p[1] : ""
            t = (n >= 2) ? p[2] : ""
            if (a == "" || a == "--") { a = ""; t = "" }
            A[ri, i-1] = a
            T[ri, i-1] = t
            la = length(a)
            lt = length(t)
            w = (la > lt) ? la : lt
            if (w > maxw) maxw = w
        }
        nrows = ri
    }

    END {
        dayw  = 4
        cellw = maxw

        TOP = "┌" rep("─", dayw) "┬"
        SEP = "├" rep("─", dayw) "┼"
        BOT = "└" rep("─", dayw) "┴"
        for (c = 1; c <= ncols; c++) {
            TOP = TOP rep("─", cellw)
            SEP = SEP rep("─", cellw)
            BOT = BOT rep("─", cellw)
            if (c < ncols) {
                TOP = TOP "┬"
                SEP = SEP "┼"
                BOT = BOT "┴"
            } else {
                TOP = TOP "┐"
                SEP = SEP "┤"
                BOT = BOT "┘"
            }
        }

        print TOP

        h1 = "│" HI center("", dayw) RST "│"
        for (c = 1; c <= ncols; c++) h1 = h1 HI center(cap[c], cellw) RST "│"
        print h1

        h2 = "│" HI center("", dayw) RST "│"
        for (c = 1; c <= ncols; c++) h2 = h2 HID center(tfrom[c], cellw) RST "│"
        print h2

        h3 = "│" HI center("", dayw) RST "│"
        for (c = 1; c <= ncols; c++) h3 = h3 HID center(tto[c], cellw) RST "│"
        print h3

        print SEP

        for (r = 1; r <= nrows; r++) {
            if (r > 1) print SEP

            l1 = "│" HI center(D[r], dayw) RST "│"
            l2 = "│" HI center("", dayw) RST "│"

            for (c = 1; c <= ncols; c++) {
                a = A[r, c]
                t = T[r, c]
                if (a == "") {
                    blank = rep(" ", cellw)
                    l1 = l1 blank "│"
                    l2 = l2 blank "│"
                } else {
                    cc = col[a]
                    if (cc == "") cc = 244
                    bg = ESC "[48;5;" cc "m" ESC "[97m"
                    l1 = l1 bg center(a, cellw) RST "│"
                    l2 = l2 bg center(t, cellw) RST "│"
                }
            }
            print l1
            print l2
        }
        print BOT
    }
'