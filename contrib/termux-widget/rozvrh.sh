#!/usr/bin/env bash
# Launch the repository's timetable command from Termux:Widget.
set -Eeuo pipefail

# Resolve the repository path from the environment or the conventional home location.
BAKALARI_CLI_DIR="${BAKALARI_CLI_DIR:-$HOME/bakalari-cli}"

# Fail clearly when the configured repository or executable is unavailable.
CLI="$BAKALARI_CLI_DIR/bakalari-cli"
if [[ ! -x "$CLI" ]]; then
    if command -v termux-toast >/dev/null 2>&1; then
        termux-toast "bakalari-cli nebyl nalezen: $CLI"
    fi
    printf 'Executable not found: %s\n' "$CLI" >&2
    exit 1
fi

# Execute the timetable command and preserve any arguments supplied by Termux:Widget.
exec "$CLI" rozvrh "$@"
