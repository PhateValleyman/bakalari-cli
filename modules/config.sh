#!/usr/bin/env bash
# config.sh - tabular interactive configuration editor.

set -o pipefail
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROFILE=""
NEW_PROFILE=0
SCOPE=""
FIELDS=(host user pass max_hours name class color_Hv color_M color_Čj color_Prv color_Vv color_Pč color_Tv)
LABELS=("Host" "Uživatel" "Heslo" "Hodin rozvrhu" "Jméno" "Třída"
    "Barva Hv" "Barva M" "Barva Čj" "Barva Prv" "Barva Vv" "Barva Pč" "Barva Tv")
COLOR_VALUES=(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)
COLOR_NAMES=("Černá" "Červená" "Zelená" "Žlutá" "Modrá" "Fialová" "Azurová" "Bílá"
    "Šedá" "Světle červená" "Světle zelená" "Světle žlutá" "Světle modrá"
    "Světle fialová" "Světle azurová" "Jasně bílá")

usage() {
    usage_module_header "Modul: config"
    usage_section "Použití:"
    printf '  %sbakalari-cli config%s [volby]\n\n' "$C_BOLD" "$C_RESET"
    usage_section "Volby:"
    usage_option "--user PROFILE" "Upravit konkrétní profil"
    usage_option "--new" "Vytvořit nový profil"
    usage_option "--global" "Upravit globální nastavení"
    usage_option "--help" "Zobrazit tuto nápovědu"
    printf '\nEditor zobrazuje vlevo položky a vpravo jejich hodnoty. Gum je volitelný.\n'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --user) [[ $# -ge 2 ]] || exit "$EXIT_CONFIG"; PROFILE="$2"; shift 2 ;;
        --user=*) PROFILE="${1#*=}"; shift ;;
        --new) NEW_PROFILE=1; shift ;;
        --global) SCOPE="global"; shift ;;
        *) log_error "Neznámý argument: $1"; usage >&2; exit "$EXIT_CONFIG" ;;
    esac
done

require_cmd awk grep mktemp sed || exit "$EXIT_CONFIG"
if [[ ! -f "$BAKALARI_CONFIG" ]]; then
    mkdir -p "$(dirname -- "$BAKALARI_CONFIG")" || exit "$EXIT_CONFIG"
    touch "$BAKALARI_CONFIG" || exit "$EXIT_CONFIG"
    chmod 600 "$BAKALARI_CONFIG" 2>/dev/null || true
fi

input_value() {
    local label="$1" value="${2:-}" secret="${3:-0}" answer
    if command -v gum >/dev/null 2>&1; then
        if (( secret )); then
            gum input --password --prompt "$label: "
        else
            gum input --prompt "$label: " --value "$value"
        fi
    else
        printf '%-18s [%s]: ' "$label" "$([[ "$secret" == 1 ]] && printf 'skryté' || printf '%s' "$value")" >&2
        if (( secret )); then read -r -s answer; printf '\n' >&2; else read -r answer; fi
        printf '%s' "${answer:-$value}"
    fi
}

color_preview() {
    local color="${1:-}" label
    [[ "$color" =~ ^[0-9]+$ ]] || { printf '%-8s' "-"; return; }
    label="        "
    printf '\033[48;5;%sm\033[38;5;255m%s\033[0m' "$color" "$label"
}

color_text() {
    case "$1" in
        3|7|10|11|12|13|14|15) printf '\033[30m' ;;
        *) printf '\033[97m' ;;
    esac
}

color_swatch() {
    local color="$1" name="$2" marker="${3:-}"
    printf '%s\033[48;5;%sm%s %-20s \033[0m' "$marker" "$color" \
        "$(color_text "$color")" "$name"
}

render_color_picker() {
    local current="$1" index="$2"
    local i row col marker value

    printf '\033[2J\033[H'
    printf '%s%s%s\n' "$C_BOLD" "Výběr barvy předmětu" "$C_RESET"
    printf '%sAktuální: %s%b  (↑/↓/←/→, Enter, Esc)%s\n\n' \
        "$C_GRAY" "$current" "$(color_preview "$current")" "$C_RESET"

    for ((row=0; row<16; row++)); do
        for ((col=0; col<16; col++)); do
            i=$((row * 16 + col))
            marker=' '
            (( i == index )) && marker='>'
            value="$i"
            printf '%s%3d%b  ' "$marker" "$value" "$(color_text "$value")"
        done
        printf '\n'
    done

    printf '\n%sEnter%s potvrdit   %sEsc%s zrušit\n' "$C_GRAY" "$C_RESET" "$C_GRAY" "$C_RESET"
}
select_color_value() {
    local current="$1"
    local index=0 key old_stty

    if ! [[ -t 0 && -t 2 ]]; then
        input_value "Barva (0-255)" "$current"
        return
    fi

    if [[ "$current" =~ ^[0-9]+$ ]] && (( current >= 0 && current <= 255 )); then
        index="$current"
    fi

    old_stty="$(stty -g)" || return 1
    stty -echo -icanon min 1 time 0 || return 1

    while :; do
        render_color_picker "$current" "$index" >&2
        IFS= read -r -s -n1 key

        if [[ "$key" == $'\e' ]]; then
            IFS= read -r -s -n2 key
            case "$key" in
                '[A') (( index >= 16 )) && ((index -= 16)) ;;
                '[B') (( index < 240 )) && ((index += 16)) ;;
                '[C') (( index % 16 < 15 )) && ((index++)) ;;
                '[D') (( index % 16 > 0 )) && ((index--)) ;;
                '') stty "$old_stty"; return 1 ;;
            esac
        elif [[ "$key" == $'\n' || "$key" == $'\r' ]]; then
            stty "$old_stty"
            printf '%s' "$index"
            return 0
        fi
    done
}
select_profile() {
    local profiles choice
    profiles="$(list_users | cut -f2-)"
    [[ -n "$profiles" ]] || return 1
    if command -v gum >/dev/null 2>&1; then
        choice="$(printf '← Zpět\n%s\n' "$profiles" | gum choose --header 'config/users')"
        [[ "$choice" == "← Zpět" ]] && return 2
        printf '%s' "$choice"
    else
        printf 'config/users\n← Zpět\n%s\n' "$profiles" >&2
        printf 'Profil: ' >&2
        read -r PROFILE
        [[ "$PROFILE" == b || "$PROFILE" == B ]] && return 2
        printf '%s' "$PROFILE"
    fi
}

select_scope() {
    if command -v gum >/dev/null 2>&1; then
        gum choose --header "Co chceš upravit?" users global
    else
        printf '1) users - profily uživatelů\n2) global - barvy a cache\nVolba [1]: ' >&2
        read -r choice
        [[ "$choice" == 2 || "$choice" == global ]] && printf 'global' || printf 'users'
    fi
}

if [[ -z "$SCOPE" ]]; then
    if (( NEW_PROFILE )) || [[ -n "$PROFILE" ]]; then
        SCOPE="users"
    else
        SCOPE="$(select_scope)"
    fi
fi

edit_global() {
    local -a global_fields=("cache_dir" "color_Hv" "color_M" "color_Čj" "color_Prv" "color_Vv" "color_Pč" "color_Tv")
    local -a global_labels=("Cache složka" "Barva Hv" "Barva M" "Barva Čj" "Barva Prv" "Barva Vv" "Barva Pč" "Barva Tv")
    local -A global_values=()
    local i field value choice new_value marker selected=0
    global_values[cache_dir]="$(config_value general cache_dir)"
    global_values[cache_dir]="${global_values[cache_dir]:-${XDG_CACHE_HOME:-$HOME/.cache}/bakalari-cli}"
    for subject in Hv M Čj Prv Vv Pč Tv; do
        global_values[color_$subject]="$(subject_color "$subject" "$(
            case "$subject" in
                Hv) printf 135 ;; M) printf 33 ;; Čj) printf 34 ;; Prv) printf 172 ;;
                Vv) printf 44 ;; Pč) printf 160 ;; Tv) printf 170 ;;
            esac
        )")"
    done

    while :; do
        if command -v gum >/dev/null 2>&1; then
            menu_items=("← Zpět")
            for i in "${!global_labels[@]}"; do
                field="${global_fields[i]}"
                value="${global_values[$field]:-}"
                [[ -z "$value" ]] && value="-"
                if [[ "$field" == color_* ]]; then
                    menu_items+=("$(printf '%-20s  %s  %b' "${global_labels[i]}" "$value" "$(color_preview "$value")")")
                else
                    menu_items+=("$(printf '%-20s  %s' "${global_labels[i]}" "$value")")
                fi
            done
            menu_items+=("Uložit a skončit")
            choice="$(printf '%s\n' "${menu_items[@]}" | gum choose --header 'Upravit položku')"
            [[ "$choice" == "Uložit a skončit" ]] && break
            [[ "$choice" == "← Zpět" ]] && return 0
            for i in "${!global_labels[@]}"; do
                if [[ "$choice" == "${global_labels[i]}"* ]]; then
                    selected="$i"
                    field="${global_fields[i]}"
                    if [[ "$field" == color_* ]]; then
                        new_value="$(select_color_value "${global_values[$field]:-}" global_fields global_labels global_values "$i")"
                    else
                        new_value="$(input_value "${global_labels[i]}" "${global_values[$field]:-}")"
                    fi
                    global_values[$field]="$new_value"
                fi
            done
        else
            printf '\n%s%-24s %s %s%s\n' "$C_BOLD" "Upravit položku" "Hodnoty" "Barva" "$C_RESET"
            printf '%s\n' '------------------------------------------------------------------------'
            for i in "${!global_fields[@]}"; do
                field="${global_fields[i]}"
                value="${global_values[$field]:-}"
                [[ -z "$value" ]] && value="-"
                marker=" "
                (( i == selected )) && marker=">"
                if [[ "$field" == color_* ]]; then
                    printf '%s %-20s %2s %-18s %s %b\n' "$marker" "${global_labels[i]}" "$((i + 1))" "${global_labels[i]}" "$value" "$(color_preview "$value")"
                else
                    printf '%s %-20s %2s %-18s %s\n' "$marker" "${global_labels[i]}" "$((i + 1))" "${global_labels[i]}" "$value"
                fi
            done
            printf '\n%s q%s  Uložit a skončit\n' "$C_GRAY" "$C_RESET"
            printf 'Položka: ' >&2
            read -r choice
            [[ "$choice" == q || "$choice" == Q ]] && break
            [[ "$choice" == b || "$choice" == B ]] && return 0
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#global_fields[@]} )); then
                i=$((choice - 1))
                selected="$i"
                field="${global_fields[i]}"
                if [[ "$field" == color_* ]]; then
                    new_value="$(select_color_value "${global_values[$field]:-}" global_fields global_labels global_values "$i")"
                else
                    new_value="$(input_value "${global_labels[i]}" "${global_values[$field]:-}")"
                fi
                global_values[$field]="$new_value"
            else
                log_warn "Zadej číslo 1-${#global_fields[@]} nebo q."
            fi
        fi
    done

    if [[ -n "${global_values[cache_dir]}" ]]; then
        update_config_key general cache_dir "${global_values[cache_dir]}"
    fi
    for subject in Hv M Čj Prv Vv Pč Tv; do
        value="${global_values[color_$subject]:-}"
        [[ -z "$value" || "$value" =~ ^[0-9]+$ ]] && [[ -z "$value" || "$value" -le 255 ]] ||
            { log_error "Barva $subject musí být číslo 0-255."; return "$EXIT_CONFIG"; }
        [[ -n "$value" ]] && update_config_key colors "$subject" "$value"
    done
    log_ok "Globální konfigurace byla uložena do $BAKALARI_CONFIG"
}

update_config_key() {
    local section="$1" key="$2" value="$3" tmp
    tmp="$(mktemp "${BAKALARI_CONFIG}.tmp.XXXXXX")" || return 1
    awk -v section="$section" -v key="$key" -v value="$value" '
        function emit() {
            if (section == "colors") print "\"" key "\" = " value
            else print key " = \"" value "\""
            done=1
        }
        {
            header=$0
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", header)
        }
        header == "[" section "]" { insec=1; found=1; print; next }
        insec {
            current_key=$1
            gsub(/^"|"$/, "", current_key)
            if (current_key == key) { emit(); next }
        }
        substr(header, 1, 1) == "[" {
            if (insec && !done) emit()
            insec=0
        }
        { print }
        END {
            if (insec && !done) emit()
            if (!found) { print ""; print "[" section "]"; emit() }
        }
    ' "$BAKALARI_CONFIG" >"$tmp" || { rm -f "$tmp"; return 1; }
    chmod 600 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$BAKALARI_CONFIG"
}

if [[ "$SCOPE" == "global" ]]; then
    edit_global
    exit "$?"
fi

if (( NEW_PROFILE )); then
    PROFILE="$(input_value "Nový profil")"
elif [[ -z "$PROFILE" ]]; then
    if PROFILE="$(select_profile)"; then
        :
    else
        rc=$?
        (( rc == 2 )) && exit 0
        PROFILE="$(input_value "Profil")"
    fi
fi
[[ "$PROFILE" =~ ^[A-Za-z0-9._-]+$ ]] || { log_error "Neplatný název profilu."; exit "$EXIT_CONFIG"; }

declare -A VALUES=()
VALUES[host]="$(config_value "$PROFILE" host)"
VALUES[user]="$(config_value "$PROFILE" user)"
VALUES[pass]="$(config_value "$PROFILE" pass)"
VALUES[max_hours]="$(config_value "$PROFILE" max_hours)"
VALUES[name]="$(config_value "$PROFILE" name)"
VALUES[class]="$(config_value "$PROFILE" class)"
VALUES[max_hours]="${VALUES[max_hours]:-6}"
for subject in Hv M Čj Prv Vv Pč Tv; do
    VALUES[color_$subject]="$(subject_color "$subject" "$(
        case "$subject" in
            Hv) printf 135 ;; M) printf 33 ;; Čj) printf 34 ;; Prv) printf 172 ;;
            Vv) printf 44 ;; Pč) printf 160 ;; Tv) printf 170 ;;
        esac
    )")"
done

show_table() {
    local selected="${1:-0}" i field value marker
    printf '\n%s%-24s %s %s%s\n' "$C_BOLD" "Upravit položku" "Hodnoty" "Barva" "$C_RESET"
    printf '%s\n' '------------------------------------------------------------------------'
    for i in "${!FIELDS[@]}"; do
        field="${FIELDS[i]}"
        value="${VALUES[$field]:-}"
        [[ "$field" == "pass" ]] && value="********"
        [[ -z "$value" ]] && value="-"
        marker=" "
        (( i == selected )) && marker=">"
        if [[ "$field" == color_* ]]; then
            printf '%s %-20s %2s %-18s %s %b\n' "$marker" "${LABELS[i]}" "$((i + 1))" "${LABELS[i]}" "$value" "$(color_preview "$value")"
        else
            printf '%s %-20s %2s %-18s %s\n' "$marker" "${LABELS[i]}" "$((i + 1))" "${LABELS[i]}" "$value"
        fi
    done
    printf '\n%s q%s  Uložit a skončit\n' "$C_GRAY" "$C_RESET"
}

edit_field() {
    local index="$1" field value new_value
    field="${FIELDS[index]}"
    value="${VALUES[$field]:-}"
    if [[ "$field" == color_* ]]; then
        new_value="$(select_color_value "$value" FIELDS LABELS VALUES "$index")" || return 0
        [[ -z "$new_value" || "$new_value" =~ ^[0-9]+$ ]] &&
            { [[ -z "$new_value" || "$new_value" -le 255 ]] || return 1; } ||
            return 1
    elif [[ "$field" == pass ]]; then
        new_value="$(input_value "Nové heslo (prázdné = zachovat)" "" 1)"
        [[ -z "$new_value" ]] && return 0
    else
        new_value="$(input_value "${LABELS[index]}" "$value")"
    fi
    VALUES[$field]="$new_value"
}

selected=0
while :; do
    if command -v gum >/dev/null 2>&1; then
        menu_items=("← Zpět")
        for i in "${!LABELS[@]}"; do
            field="${FIELDS[i]}"
            value="${VALUES[$field]:-}"
            [[ "$field" == "pass" ]] && value="********"
            [[ -z "$value" ]] && value="-"
            if [[ "$field" == color_* ]]; then
                menu_items+=("$(printf '%-20s  %s  %b' "${LABELS[i]}" "$value" "$(color_preview "$value")")")
            else
                menu_items+=("$(printf '%-20s  %s' "${LABELS[i]}" "$value")")
            fi
        done
        menu_items+=("Uložit a skončit")
        choice="$(printf '%s\n' "${menu_items[@]}" | gum choose --header 'Upravit položku')"
        [[ "$choice" == "Uložit a skončit" ]] && break
        [[ "$choice" == "← Zpět" ]] && exit 0
        for i in "${!LABELS[@]}"; do
            if [[ "${choice}" == "${LABELS[i]}"* ]]; then
                selected="$i"
                edit_field "$i"
            fi
        done
    else
        show_table "$selected"
        printf 'Položka: ' >&2
        read -r choice
        [[ "$choice" == q || "$choice" == Q ]] && break
        [[ "$choice" == b || "$choice" == B ]] && exit 0
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#FIELDS[@]} )); then
            selected="$((choice - 1))"
            edit_field "$selected"
        else
            log_warn "Zadej číslo 1-${#FIELDS[@]} nebo q."
        fi
    fi
done

[[ -n "${VALUES[host]}" && -n "${VALUES[user]}" ]] || { log_error "Host a uživatel jsou povinné."; exit "$EXIT_CONFIG"; }
[[ "${VALUES[max_hours]}" =~ ^[0-9]+$ ]] || { log_error "Počet hodin musí být celé číslo."; exit "$EXIT_CONFIG"; }
[[ -n "${VALUES[pass]}" ]] || { log_error "Heslo nesmí být prázdné."; exit "$EXIT_CONFIG"; }

toml_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

tmp="$(mktemp "${BAKALARI_CONFIG}.tmp.XXXXXX")" || exit "$EXIT_CONFIG"
awk -v section="$PROFILE" \
    -v host="$(toml_escape "${VALUES[host]}")" -v login="$(toml_escape "${VALUES[user]}")" \
    -v pass="$(toml_escape "${VALUES[pass]}")" -v max_hours="${VALUES[max_hours]}" \
    -v name="$(toml_escape "${VALUES[name]}")" -v class_name="$(toml_escape "${VALUES[class]}")" \
    -v token="$(config_value "$PROFILE" token)" '
    function emit() {
        print "host = \"" host "\""; print "user = \"" login "\""; print "pass = \"" pass "\""
        print "max_hours = " max_hours; print "token = \"" token "\""
        print "name = \"" name "\""; print "class = \"" class_name "\""
    }
    { header=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", header) }
    header == "[" section "]" { insec=1; found=1; print; emit(); next }
    insec && /^[[:space:]]*(host|user|pass|max_hours|token|name|class)[[:space:]]*=/ { next }
    substr(header, 1, 1) == "[" { insec=0 }
    { print }
    END { if (!found) { print ""; print "[" section "]"; emit() } }
' "$BAKALARI_CONFIG" >"$tmp" || { rm -f "$tmp"; exit "$EXIT_CONFIG"; }
chmod 600 "$tmp" 2>/dev/null || true
mv -f "$tmp" "$BAKALARI_CONFIG" || exit "$EXIT_CONFIG"

for subject in Hv M Čj Prv Vv Pč Tv; do
    value="${VALUES[color_$subject]:-}"
    if [[ -z "$value" ]]; then
        continue
    fi
    tmp="$(mktemp "${BAKALARI_CONFIG}.tmp.XXXXXX")" || exit "$EXIT_CONFIG"
    awk -v key="$subject" -v value="$value" '
        /^[[:space:]]*\[colors\][[:space:]]*$/ { insec=1; found=1; print; next }
        /^[[:space:]]*\[/ {
            if (insec && !done) { print "\"" key "\" = " value; done=1 }
            insec=0
        }
        insec {
            current_key=$1
            gsub(/^"|"$/, "", current_key)
            if (current_key == key) { print "\"" key "\" = " value; done=1; next }
        }
        { print }
        END {
            if (insec && !done) print "\"" key "\" = " value
            if (!found) { print ""; print "[colors]"; print "\"" key "\" = " value }
        }
    ' "$BAKALARI_CONFIG" >"$tmp" || { rm -f "$tmp"; exit "$EXIT_CONFIG"; }
    chmod 600 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$BAKALARI_CONFIG" || exit "$EXIT_CONFIG"
done

if ! grep -Eq "^[[:space:]]*user[0-9]+[[:space:]]*=[[:space:]]*\"$PROFILE\"" "$BAKALARI_CONFIG"; then
    num="$(list_users | awk -F '\t' 'BEGIN { max=0 } $1 + 0 > max { max=$1 } END { printf "%02d", max + 1 }')"
    tmp="$(mktemp "${BAKALARI_CONFIG}.tmp.XXXXXX")" || exit "$EXIT_CONFIG"
    if grep -Eq '^[[:space:]]*\[general\][[:space:]]*$' "$BAKALARI_CONFIG"; then
        awk -v key="user$num" -v profile="$PROFILE" '/^[[:space:]]*\[general\][[:space:]]*$/ { print; printf "%s = \"%s\"\n", key, profile; next } { print }' "$BAKALARI_CONFIG" >"$tmp"
    else
        { printf '[general]\nuser%s = "%s"\n\n' "$num" "$PROFILE"; cat "$BAKALARI_CONFIG"; } >"$tmp"
    fi
    chmod 600 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$BAKALARI_CONFIG" || exit "$EXIT_CONFIG"
fi

unset VALUES PASS TOKEN
log_ok "Profil [$PROFILE] byl uložen do $BAKALARI_CONFIG"
