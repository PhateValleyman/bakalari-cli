#!/usr/bin/env bash
# Run smoke tests against the local fake Bakalari API.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
TMP_DIR="$(mktemp -d)"
SERVER_PID=""

cleanup() {
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

CONFIG="$TMP_DIR/config.toml"
PORT_FILE="$TMP_DIR/port"

cat >"$CONFIG" <<'EOF'
[general]
school = "mock.bakalari.test"
max_hours = 2

[colors]
M = 226

[mock.bakalari.test]
user = "test-user"
pass = "test-pass"
TOKEN = ""
EOF

python3 "$ROOT_DIR/tests/mock_server.py" >"$PORT_FILE" &
SERVER_PID=$!

for _ in {1..50}; do
    [[ -s "$PORT_FILE" ]] && break
    sleep 0.1
done

if [[ ! -s "$PORT_FILE" ]]; then
    echo "ERROR: mock server did not start" >&2
    exit 1
fi

PORT="$(cat "$PORT_FILE")"
export BAKALARI_CONFIG="$CONFIG"
export BAKALARI_BASE_URL="http://127.0.0.1:$PORT"

ROZVRH_OUTPUT="$TMP_DIR/rozvrh.out"
UKOLY_OUTPUT="$TMP_DIR/ukoly.out"

"$ROOT_DIR/rozvrh.sh" >"$ROZVRH_OUTPUT"

grep -Fq 'TOKEN = "test-token"' "$CONFIG"
grep -Fq $'\033[48;5;226m' "$ROZVRH_OUTPUT"
grep -Fq $'\033[48;5;135m' "$ROZVRH_OUTPUT"

"$ROOT_DIR/ukoly.sh" >"$UKOLY_OUTPUT"
grep -Fq "Smoke test" "$UKOLY_OUTPUT"

printf 'OK: rozvrh.sh smoke test\n'
printf 'OK: ukoly.sh smoke test\n'
