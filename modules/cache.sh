#!/usr/bin/env bash
# cache.sh – inspect and clear the local API cache.

set -o pipefail
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_cmd find sort || exit "$EXIT_CONFIG"

ACTION="list"

usage() {
    usage_module_header "Modul: cache"
    usage_section "Použití:"
    printf '  %sbakalari-cli cache%s [volby]\n' "$C_BOLD" "$C_RESET"
    printf '\n'
    usage_section "Volby:"
    usage_option "--list" "Vypsat soubory cache (výchozí)"
    usage_option "--path" "Vypsat cestu cache"
    usage_option "--clear" "Smazat všechny soubory cache"
    usage_option "--help" "Zobrazit tuto nápovědu"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --list) ACTION="list"; shift ;;
        --path) ACTION="path"; shift ;;
        --clear) ACTION="clear"; shift ;;
        *) log_error "Neznámý argument: $1"; usage >&2; exit "$EXIT_CONFIG" ;;
    esac
done

case "$ACTION" in
    path)
        printf '%s\n' "$BAKALARI_CACHE_DIR"
        ;;
    list)
        if [[ ! -d "$BAKALARI_CACHE_DIR" ]]; then
            printf '%s\n' "(cache zatím neexistuje)"
            exit 0
        fi
        find "$BAKALARI_CACHE_DIR" -maxdepth 1 -type f -printf '%f\t%s B\n' 2>/dev/null | sort ||
            { log_error "Nelze přečíst cache: $BAKALARI_CACHE_DIR"; exit "$EXIT_CONFIG"; }
        ;;
    clear)
        if [[ -d "$BAKALARI_CACHE_DIR" ]]; then
            find "$BAKALARI_CACHE_DIR" -maxdepth 1 -type f -delete 2>/dev/null ||
                { log_error "Nelze vyčistit cache: $BAKALARI_CACHE_DIR"; exit "$EXIT_CONFIG"; }
        fi
        log_ok "Cache vyčištěna: $BAKALARI_CACHE_DIR"
        ;;
esac
