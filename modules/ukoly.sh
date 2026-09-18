#!/usr/bin/env bash
# ukoly.sh – kontrola nesplněných domácích úkolů

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
            usage_module_header "Modul: ukoly"
            usage_section "Použití:"
            printf '  %sbakalari-cli ukoly%s [volby]\n' "$C_BOLD" "$C_RESET"
            printf '\n'
            usage_section "Volby:"
            usage_option "--user USER" "Použít konkrétní profil"
            usage_option "--list-users" "Vypsat dostupné profily"
            usage_option "--help" "Zobrazit tuto nápovědu"
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
HOMEWORKS_URL="$API_BASE_URL/api/3/homeworks"
fetch_homeworks() {
    fetch_json "$HOMEWORKS_URL" "$TOKEN"
}

# Zkus nejdřív uložený TOKEN; pokud chybí nebo je neplatný, přihlas se znovu.
if [[ -z "$TOKEN" ]] || ! RESPONSE="$(fetch_homeworks 2>/dev/null)"; then
    TOKEN="$(bakalari_login "$BAKALARI_USER" "$LOGIN_URL" "$USERNAME" "$PASSWORD")" || exit "$?"
    save_token "$BAKALARI_USER" "$TOKEN" || log_warn "Nepodařilo se uložit TOKEN do $BAKALARI_CONFIG"
    if ! RESPONSE="$(fetch_homeworks)"; then
        log_error "Požadavek na úkoly selhal i po přihlášení."
        exit "$EXIT_NETWORK"
    fi
fi

if ! printf '%s' "$RESPONSE" | jq -e '.Homeworks' >/dev/null 2>&1; then
    log_error "Neplatná odpověď z Bakalářů API."
    printf '%s' "$RESPONSE" | jq . 2>/dev/null || printf '%s\n' "$RESPONSE"
    exit "$EXIT_DATA"
fi

UNFINISHED="$(printf '%s' "$RESPONSE" | jq -r '
    .Homeworks[]? | select(.IsDone == false or .IsDone == null) |
    "[" + (.Subject.Abbrev // "?") + "] " + .Content + " (do: " + .DateEnd[0:10] + ")"
')"

if [[ -n "$UNFINISHED" && "$UNFINISHED" != "null" ]]; then
    COUNT="$(printf '%s\n' "$UNFINISHED" | wc -l)"
    MESSAGE="$(printf '%s\n' "$UNFINISHED" | head -n 3 | tr '\n' ' ')"

    printf '%s[!] Nalezeny nesplněné domácí úkoly (%s):%s\n' "$C_RED" "$COUNT" "$C_RESET"
    printf '%s\n' "$UNFINISHED"

    notify_android "bakalari_hw_alert" "Bakaláři: Nesplněný úkol ($COUNT)" "$MESSAGE"
else
    printf '%s[✓] Všechny domácí úkoly jsou hotové nebo žádné nejsou zadány.%s\n' "$C_GREEN" "$C_RESET"
fi
