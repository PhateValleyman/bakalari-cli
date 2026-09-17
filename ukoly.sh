#!/usr/bin/env bash
# ukoly.sh – zkontroluje nesplněné domácí úkoly v Bakalářích a (na Androidu
# v Termuxu) o nich pošle notifikaci.
#
# Konfigurace a přihlašovací logika je sdílená s rozvrh.sh přes lib/common.sh.
#
# Použití:
#   ./ukoly.sh
#
# Proměnné prostředí:
#   BAKALARI_CONFIG   cesta ke config.toml (výchozí: ~/.config/bakalari/config.toml)

set -o pipefail
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    printf 'Použití: %s\nZkontroluje nesplněné domácí úkoly v Bakalářích.\n' "$0"
    exit 0
fi

require_cmd curl jq || exit 1
require_config || exit 1

SCHOOL="$(config_value general school)"
SCHOOL="${SCHOOL:-zssumava.bakalari.cz}"
LOGIN_URL="https://${SCHOOL}/api/login"
HOMEWORKS_URL="https://${SCHOOL}/api/3/homeworks"

USERNAME="$(config_value "$SCHOOL" user)"
PASSWORD="$(config_value "$SCHOOL" pass)"
TOKEN="$(config_value "$SCHOOL" TOKEN)"

if [[ -z "$USERNAME" ]]; then
    log_error "Chybí \"user\" v $BAKALARI_CONFIG"
    exit 1
fi
if [[ -z "$PASSWORD" ]]; then
    log_error "Chybí \"pass\" v $BAKALARI_CONFIG"
    exit 1
fi

fetch_homeworks() {
    fetch_json "$HOMEWORKS_URL" "$TOKEN"
}

# Zkus nejdřív uložený TOKEN; pokud chybí nebo je neplatný, přihlas se znovu.
if [[ -z "$TOKEN" ]] || ! RESPONSE="$(fetch_homeworks 2>/dev/null)"; then
    if ! TOKEN="$(bakalari_login "$SCHOOL" "$LOGIN_URL" "$USERNAME" "$PASSWORD")"; then
        exit 1
    fi
    save_token "$SCHOOL" "$TOKEN" || log_warn "Nepodařilo se uložit TOKEN do $BAKALARI_CONFIG"
    if ! RESPONSE="$(fetch_homeworks)"; then
        log_error "Požadavek na úkoly selhal i po přihlášení."
        exit 1
    fi
fi

if ! printf '%s' "$RESPONSE" | jq -e '.Homeworks' >/dev/null 2>&1; then
    log_error "Neplatná odpověď z Bakalářů API."
    printf '%s' "$RESPONSE" | jq . 2>/dev/null || printf '%s\n' "$RESPONSE"
    exit 1
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
