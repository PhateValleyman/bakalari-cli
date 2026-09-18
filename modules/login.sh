#!/usr/bin/env bash
# login.sh – interactive Bakaláři login and configuration setup.

set -o pipefail
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROFILE=""

usage() {
	cat <<'EOF'
Použití: login.sh [--user PROFILE]

Interaktivně vytvoří nebo upraví profil v konfiguraci bakalari-cli.
Po úspěšném přihlášení uloží získaný token do vybraného profilu.

Volby:
  --user PROFILE   použít zadaný název profilu bez dotazu
  -h, --help       zobrazit tuto nápovědu
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help)
            usage_module_header "Modul: login"
            usage_section "Použití:"
            printf '  %sbakalari-cli login%s [volby]\n' "$C_BOLD" "$C_RESET"
            printf '\n'
            usage_section "Volby:"
            usage_option "--user USER" "Upravit konkrétní profil"
            usage_option "--help" "Zobrazit tuto nápovědu"
            exit 0
            ;;
		--user)
			[[ $# -ge 2 && -n "$2" ]] || {
				log_error "Volba --user vyžaduje název profilu."
				exit "$EXIT_CONFIG"
			}
			PROFILE="$2"
			shift 2
			;;
		--user=*)
			PROFILE="${1#*=}"
			[[ -n "$PROFILE" ]] || {
				log_error "Volba --user vyžaduje název profilu."
				exit "$EXIT_CONFIG"
			}
			shift
			;;
		*)
			log_error "Neznámý argument: $1"
			usage
			exit "$EXIT_CONFIG"
			;;
	esac
done

require_cmd curl jq awk mktemp sed grep || exit "$EXIT_CONFIG"

CONFIG_DIR="$(dirname -- "$BAKALARI_CONFIG")"
if [[ ! -f "$BAKALARI_CONFIG" ]]; then
	mkdir -p "$CONFIG_DIR" || {
		log_error "Nelze vytvořit adresář konfigurace: $CONFIG_DIR"
		exit "$EXIT_CONFIG"
	}
	touch "$BAKALARI_CONFIG" || {
		log_error "Nelze vytvořit konfiguraci: $BAKALARI_CONFIG"
		exit "$EXIT_CONFIG"
	}
	chmod 600 "$BAKALARI_CONFIG" 2>/dev/null || true
fi

if [[ -z "$PROFILE" ]]; then
	printf '%sProfil Bakalářů%s\n' "$C_BOLD" "$C_RESET"
	printf 'Název profilu (např. dzonny): '
	read -r PROFILE
fi

if [[ ! "$PROFILE" =~ ^[A-Za-z0-9._-]+$ ]]; then
	log_error "Název profilu smí obsahovat pouze A-Z, a-z, 0-9, '.', '_' a '-'."
	exit "$EXIT_CONFIG"
fi

profile_exists() {
	grep -Fqx "[$PROFILE]" "$BAKALARI_CONFIG"
}
if profile_exists; then
	log_info "Profil [$PROFILE] již existuje; přihlašovací údaje budou aktualizovány."
	DEFAULT_HOST="$(config_value "$PROFILE" host)"
	DEFAULT_LOGIN="$(config_value "$PROFILE" user)"
	DEFAULT_MAX_HOURS="$(config_value "$PROFILE" max_hours)"
else
	DEFAULT_HOST=""
	DEFAULT_LOGIN=""
	DEFAULT_MAX_HOURS="6"
fi

printf 'Bakaláři host [%s]: ' "$DEFAULT_HOST"
read -r HOST
HOST="${HOST:-$DEFAULT_HOST}"
HOST="${HOST#https://}"
HOST="${HOST%/}"

printf 'Uživatelské jméno [%s]: ' "$DEFAULT_LOGIN"
read -r LOGIN
LOGIN="${LOGIN:-$DEFAULT_LOGIN}"

if [[ -z "$HOST" || -z "$LOGIN" ]]; then
	log_error "Host a uživatelské jméno jsou povinné."
	exit "$EXIT_CONFIG"
fi

printf 'Heslo: '
read -r -s PASSWORD
printf '\n'

if [[ -z "$PASSWORD" ]]; then
	log_error "Heslo nesmí být prázdné."
	unset PASSWORD
	exit "$EXIT_CONFIG"
fi

printf 'Počet hodin rozvrhu [%s]: ' "$DEFAULT_MAX_HOURS"
read -r MAX_HOURS
MAX_HOURS="${MAX_HOURS:-$DEFAULT_MAX_HOURS}"

[[ "$MAX_HOURS" =~ ^[0-9]+$ ]] || {
	log_error "Počet hodin musí být celé číslo."
	unset PASSWORD
	exit "$EXIT_CONFIG"
}

printf '\n%sOvěřuji přihlášení...%s\n' "$C_BOLD" "$C_RESET"

API_BASE_URL="${BAKALARI_BASE_URL:-https://${HOST}}"
LOGIN_URL="$API_BASE_URL/api/login"

TOKEN="$(bakalari_login "$PROFILE" "$LOGIN_URL" "$LOGIN" "$PASSWORD")" || {
	rc=$?
	unset PASSWORD
	exit "$rc"
}

toml_escape() {
	local value="$1"
	value="${value//\\\\/\\\\\\\\}"
	value="${value//\"/\\\\\"}"
	printf '%s' "$value"
}

HOST_ESC="$(toml_escape "$HOST")"
LOGIN_ESC="$(toml_escape "$LOGIN")"
PASS_ESC="$(toml_escape "$PASSWORD")"
TOKEN_ESC="$(toml_escape "$TOKEN")"

upsert_profile() {
	local file="$1" section="$2" host="$3" login="$4" pass="$5" max_hours="$6" token="$7"
	local tmp

	tmp="$(mktemp "${file}.tmp.XXXXXX")" || return 1

	awk -v section="$section" 		-v host="$host" -v login="$login" -v pass="$pass" 		-v max_hours="$max_hours" -v token="$token" '
		BEGIN { insec=0; found=0 }
		{
			header=$0
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", header)
		}
		header == "[" section "]" {
			insec=1
			found=1
			print
			print "host = \"" host "\""
			print "user = \"" login "\""
			print "pass = \"" pass "\""
			print "max_hours = " max_hours
			print "token = \"" token "\""
			next
		}
		insec && /^[[:space:]]*host[[:space:]]*=/ { next }
		insec && /^[[:space:]]*user[[:space:]]*=/ { next }
		insec && /^[[:space:]]*pass[[:space:]]*=/ { next }
		insec && /^[[:space:]]*max_hours[[:space:]]*=/ { next }
		insec && /^[[:space:]]*token[[:space:]]*=/ { next }
		substr(header, 1, 1) == "[" { insec=0 }
		{ print }
		END {
			if (!found) {
				print ""
				print "[" section "]"
				print "host = \"" host "\""
				print "user = \"" login "\""
				print "pass = \"" pass "\""
				print "max_hours = " max_hours
				print "token = \"" token "\""
				print "name = \"\""
				print "class = \"\""
			}
		}
	' "$file" >"$tmp" || {
		rm -f "$tmp"
		return 1
	}

	chmod 600 "$tmp" 2>/dev/null || true
	mv -f "$tmp" "$file"
}
ensure_general_profile() {
	local file="$1" section="$2" tmp num

	if awk -F '=' -v section="$section" '
		/^[[:space:]]*user[0-9]+[[:space:]]*=/ {
			value=$2
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
			gsub(/^"|"$/, "", value)
			if (value == section) found=1
		}
		END { exit(found ? 0 : 1) }
	' "$file"; then
		return 0
	fi

	num="$(awk -F '=' '
		/^[[:space:]]*user[0-9]+[[:space:]]*=/ {
			key=$1
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
			sub(/^user/, "", key)
			if (key ~ /^[0-9]+$/ && key + 0 > max) max=key + 0
		}
		END { printf "%02d", max + 1 }
	' "$file")"

	tmp="$(mktemp "${file}.tmp.XXXXXX")" || return 1

	if grep -Eq '^[[:space:]]*\[general\][[:space:]]*$' "$file"; then
		awk -v key="user$num" -v section="$section" '
			header=$0
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", header)
			header == "[general]" {
				print
				printf "%s = \"%s\"\\n", key, section
				next
			}
			{ print }
		' "$file" >"$tmp"
	else
		{
			printf '[general]\nuser%s = "%s"\n\n' "$num" "$section"
			cat "$file"
		} >"$tmp"
	fi

	chmod 600 "$tmp" 2>/dev/null || true
	mv -f "$tmp" "$file"
}

if ! upsert_profile "$BAKALARI_CONFIG" "$PROFILE" "$HOST_ESC" "$LOGIN_ESC" "$PASS_ESC" "$MAX_HOURS" "$TOKEN_ESC"; then
	unset PASSWORD
	log_error "Nepodařilo se uložit profil do $BAKALARI_CONFIG"
	exit "$EXIT_CONFIG"
fi

if ! ensure_general_profile "$BAKALARI_CONFIG" "$PROFILE"; then
	unset PASSWORD
	log_error "Nepodařilo se aktualizovat [general]."
	exit "$EXIT_CONFIG"
fi

unset PASSWORD HOST_ESC LOGIN_ESC PASS_ESC TOKEN_ESC

printf '\n'
log_ok "Přihlášení proběhlo úspěšně."
log_ok "Profil: [$PROFILE]"
log_ok "Konfigurace: $BAKALARI_CONFIG"
printf '\n%sDostupné profily:%s\n' "$C_BOLD" "$C_RESET"
list_users
