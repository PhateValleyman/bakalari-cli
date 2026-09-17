#!/data/data/com.termux/files/usr/bin/bash

set -o pipefail

CONFIG="$HOME/.config/bakalari/config.toml"
SCHOOL="zssumava.bakalari.cz"
LOGIN_URL="https://${SCHOOL}/api/login"
TIMETABLE_URL="https://${SCHOOL}/api/3/timetable/actual"
MAX_HOUR=6

if command -v gawk >/dev/null 2>&1; then
    AWK="$(command -v gawk)"
else
    AWK="$(command -v awk)"
    printf 'WARN: gawk not found, falling back to %s.\n' "$AWK" >&2
fi

config_value() {
    local key="$1"
    awk -F '=' -v key="$key" '
        /^\[zssumava\.bakalari\.cz\]$/ { section=1; next }
        /^\[/ { section=0 }
        section && $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
            value=$0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^"|"$/, "", value)
            print value
            exit
        }
    ' "$CONFIG"
}

if [[ ! -f "$CONFIG" ]]; then
    printf 'ERROR: Configuration file not found: %s\n' "$CONFIG" >&2
    exit 1
fi

USERNAME="$(config_value user)"
PASSWORD="$(config_value pass)"
TOKEN="$(config_value TOKEN)"

if [[ -z "$USERNAME" ]]; then
    printf 'ERROR: Missing "user" in %s\n' "$CONFIG" >&2
    exit 1
fi
if [[ -z "$PASSWORD" ]]; then
    printf 'ERROR: Missing "pass" in %s\n' "$CONFIG" >&2
    exit 1
fi

login() {
    local response
    printf 'INFO: Access token expired or invalid. Logging in...\n' >&2
    response="$(
        curl -fsS -X POST "$LOGIN_URL" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "client_id=ANDR" \
            --data-urlencode "grant_type=password" \
            --data-urlencode "username=$USERNAME" \
            --data-urlencode "password=$PASSWORD"
    )" || { printf 'ERROR: Bakalari login failed.\n' >&2; return 1; }
    TOKEN="$(printf '%s\n' "$response" | jq -r '.access_token // empty')"
    if [[ -z "$TOKEN" ]]; then
        printf 'ERROR: Login response does not contain access_token.\n' >&2
        return 1
    fi
    return 0
}

save_token() {
    local tmp
    tmp="$(mktemp)" || return 1
    awk -v token="$TOKEN" '
        /^\[zssumava\.bakalari\.cz\]$/ { section=1; print; next }
        /^\[/ { section=0 }
        section && /^[[:space:]]*TOKEN[[:space:]]*=/ { print "TOKEN = " token; next }
        { print }
    ' "$CONFIG" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$CONFIG"
}

fetch_timetable() {
    curl -fsS -X GET "$TIMETABLE_URL" -H "Authorization: Bearer $TOKEN"
}

if ! DATA="$(fetch_timetable 2>/dev/null)"; then
    if ! login; then exit 1; fi
    if ! save_token; then
        printf 'WARN: Could not update TOKEN in %s\n' "$CONFIG" >&2
    fi
    if ! DATA="$(fetch_timetable)"; then
        printf 'ERROR: Timetable request failed even after login.\n' >&2
        exit 1
    fi
fi

if ! printf '%s\n' "$DATA" | jq -e . >/dev/null 2>&1; then
    printf 'ERROR: Bakalari returned invalid JSON.\n' >&2
    exit 1
fi

if ! printf '%s\n' "$DATA" | jq -e '
    type == "object"
    and (.Days | type == "array")
    and (.Hours | type == "array")
    and (.Subjects | type == "array")
' >/dev/null 2>&1; then
    printf 'ERROR: Unexpected timetable JSON structure.\n' >&2
    exit 1
fi

if ! TABLE="$(
    printf '%s\n' "$DATA" |
    jq -r --argjson maxhour "$MAX_HOUR" '
        ([.Subjects[] | {
            key:   (.Id|tostring|gsub("\\s";"")),
            value: (.Abbrev // .Name // "?")
        }] | from_entries) as $subjects

        | ([.Teachers[] | {
            key:   (.Id|tostring|gsub("\\s";"")),
            value: (
                (.Name // .Abbrev // "?")
                | gsub("\\s+";" ")
                | split(" ")
                | map(select(length > 0))
                | (if length > 0 then .[-1] else "?" end)
            )
        }] | from_entries) as $teachers

        | ([.Hours[] | {
              Id:    (.Id | tonumber),
              Cap:   ((.Caption // (.Id|tostring)) | tostring),
              Begin: ((.BeginTime // "") | tostring),
              End:   ((.EndTime   // "") | tostring)
          }]
          | sort_by(.Id)
          | .[0:$maxhour]
          ) as $hourinfo

        | (
            ((["HDR"] + [
                $hourinfo[] | .Cap + "\u001f" + .Begin + "\u001f" + .End
              ]) | @tsv),

            ( .Days[]
              | . as $day
              | (if $day.DayOfWeek == 1 then "Po"
                 elif $day.DayOfWeek == 2 then "Út"
                 elif $day.DayOfWeek == 3 then "St"
                 elif $day.DayOfWeek == 4 then "Čt"
                 elif $day.DayOfWeek == 5 then "Pá"
                 else ($day.DayOfWeek|tostring) end) as $dn
              | ([$dn] + [
                    $hourinfo[] | (.Id | tostring) as $hid
                    | [ $day.Atoms[]?
                        | select((.HourId|tostring) == $hid)
                        | (.SubjectId|tostring|gsub("\\s";"")) as $sid
                        | {
                            a: ($subjects[$sid] // "?"),
                            t: ($teachers[(.TeacherId|tostring|gsub("\\s";""))] // "")
                          }
                      ]
                    | if length == 0 then ""
                      else (map(.a)|join("/")) + "\u001f" + (map(.t)|join(","))
                      end
                  ]) | @tsv
            )
          )
    '
)"; then
    printf 'ERROR: Failed to render timetable.\n' >&2
    exit 1
fi

if [[ -z "$TABLE" ]]; then
    printf 'ERROR: Timetable is empty.\n' >&2
    exit 1
fi

printf '%s\n' "$TABLE" | "$AWK" '
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

        HI  = ESC "[48;5;255m" ESC "[38;5;16m"    # bílé pozadí, černý text
        HID = ESC "[48;5;255m" ESC "[38;5;245m"   # bílé pozadí, šedý text
        RST = ESC "[0m"

        col["Hv"]  = 135
        col["M"]   = 33
        col["Čj"]  = 34
        col["Prv"] = 172
        col["Vv"]  = 44
        col["Pč"]  = 160
        col["Tv"]  = 170
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
            w = l1; if (l2 > w) w = l2; if (l3 > w) w = l3
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
            la = length(a); lt = length(t)
            w = (la > lt) ? la : lt
            if (w > maxw) maxw = w
        }
        nrows = ri
    }

    END {
        # Minimální šířky: den = 4 znaky (Po/Út/…), buňka = maxw (0 paddingu).
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
                TOP = TOP "┬"; SEP = SEP "┼"; BOT = BOT "┴"
            } else {
                TOP = TOP "┐"; SEP = SEP "┤"; BOT = BOT "┘"
            }
        }

        print TOP

        # Řádek 1: číslo hodiny.
        h1 = "│" HI center("", dayw) RST "│"
        for (c = 1; c <= ncols; c++) h1 = h1 HI center(cap[c], cellw) RST "│"
        print h1

        # Řádek 2: čas od (světle šedý text).
        h2 = "│" HI center("", dayw) RST "│"
        for (c = 1; c <= ncols; c++) h2 = h2 HID center(tfrom[c], cellw) RST "│"
        print h2

        # Řádek 3: čas do (světle šedý text).
        h3 = "│" HI center("", dayw) RST "│"
        for (c = 1; c <= ncols; c++) h3 = h3 HID center(tto[c], cellw) RST "│"
        print h3

        print SEP

        for (r = 1; r <= nrows; r++) {
            if (r > 1) print SEP

            l1 = "│" HI center(D[r], dayw) RST "│"
            l2 = "│" HI center("",   dayw) RST "│"

            for (c = 1; c <= ncols; c++) {
                a = A[r, c]
                t = T[r, c]
                if (a == "") {
                    blank = rep(" ", cellw)
                    l1 = l1 blank "│"
                    l2 = l2 blank "│"
                } else {
                    cc = col[a]; if (cc == "") cc = 244
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
