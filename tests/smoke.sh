#!/usr/bin/env bash
# Run smoke tests against the local fake Bakalari API.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$BASH_SOURCE")/.." >/dev/null 2>&1 && pwd)"
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
user01 = "mock"

[mock]
host = "mock.bakalari.test"
user = "test-user"
pass = "test-pass"
token = ""
max_hours = 2

[colors]
M = 226

EOF

python3 "$ROOT_DIR/tests/mock_server.py" >"$PORT_FILE" &
SERVER_PID=$!

for _ in {1..50}; do
    [[ -s "$PORT_FILE" ]] && break
    sleep 0.1
done
[[ -s "$PORT_FILE" ]] || { echo "ERROR: mock server did not start" >&2; exit 1; }

PORT="$(cat "$PORT_FILE")"
export BAKALARI_CONFIG="$CONFIG"
export BAKALARI_BASE_URL="http://127.0.0.1:$PORT"
export BAKALARI_CACHE_DIR="$TMP_DIR/cache"

"$ROOT_DIR/bakalari-cli" rozvrh --user mock >"$TMP_DIR/rozvrh.out"
grep -Fq 'token = "test-token"' "$CONFIG"
grep -Fq $'\033[48;5;226m' "$TMP_DIR/rozvrh.out"
grep -Fq $'\033[48;5;135m' "$TMP_DIR/rozvrh.out"

"$ROOT_DIR/bakalari-cli" ukoly --user mock >"$TMP_DIR/ukoly.out"
grep -Fq "Smoke test" "$TMP_DIR/ukoly.out"

"$ROOT_DIR/bakalari-cli" znamky --user mock >"$TMP_DIR/znamky.out"
grep -Fq "Smoke" "$TMP_DIR/znamky.out"
grep -Fq "1,50" "$TMP_DIR/znamky.out"

"$ROOT_DIR/bakalari-cli" absence --user mock >"$TMP_DIR/absence.out"
grep -Fq "01.01.2099" "$TMP_DIR/absence.out"
grep -Fq "Zameškáno" "$TMP_DIR/absence.out"
grep -Fq "CELKEM" "$TMP_DIR/absence.out"

"$ROOT_DIR/bakalari-cli" info --user mock >"$TMP_DIR/info.out"
grep -Fq "Test" "$TMP_DIR/info.out"
grep -Fq "Student" "$TMP_DIR/info.out"
grep -Fq "8.A" "$TMP_DIR/info.out"
grep -Fq "Jan Test" "$TMP_DIR/info.out"
grep -Fq "Zameškané hodiny:" "$TMP_DIR/info.out"
grep -Fq "Omluvené hodiny:" "$TMP_DIR/info.out"
grep -Fq "Neomluvené / nevyřešené:" "$TMP_DIR/info.out"
grep -Fq "Matematika" "$TMP_DIR/info.out"
grep -Fq "1,50" "$TMP_DIR/info.out"

LOGIN_INPUT=$'login-test-school\ntest-user\ntest-pass\n2\n'
printf "%s" "$LOGIN_INPUT" | "$ROOT_DIR/bakalari-cli" login --user login-test >"$TMP_DIR/login.out"
grep -Fq 'user02 = "login-test"' "$CONFIG"
grep -Fq '[login-test]' "$CONFIG"
grep -Fq 'token = "test-token"' "$CONFIG"

kill "$SERVER_PID"
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

"$ROOT_DIR/bakalari-cli" rozvrh --user mock >"$TMP_DIR/rozvrh-offline.out" 2>"$TMP_DIR/rozvrh-offline.err"
grep -Fq "08:00" "$TMP_DIR/rozvrh-offline.out"
grep -Fq "používám uložený rozvrh" "$TMP_DIR/rozvrh-offline.err"

"$ROOT_DIR/bakalari-cli" ukoly --user mock >"$TMP_DIR/ukoly-offline.out" 2>"$TMP_DIR/ukoly-offline.err"
grep -Fq "Smoke test" "$TMP_DIR/ukoly-offline.out"
grep -Fq "cache" "$TMP_DIR/ukoly-offline.err"

"$ROOT_DIR/bakalari-cli" znamky --user mock >"$TMP_DIR/znamky-offline.out" 2>"$TMP_DIR/znamky-offline.err"
grep -Fq "Smoke" "$TMP_DIR/znamky-offline.out"
grep -Fq "cache" "$TMP_DIR/znamky-offline.err"

"$ROOT_DIR/bakalari-cli" absence --user mock >"$TMP_DIR/absence-offline.out" 2>"$TMP_DIR/absence-offline.err"
grep -Fq "01.01.2099" "$TMP_DIR/absence-offline.out"
grep -Fq "cache" "$TMP_DIR/absence-offline.err"

"$ROOT_DIR/bakalari-cli" info --user mock >"$TMP_DIR/info-offline.out" 2>"$TMP_DIR/info-offline.err"
grep -Fq "Test" "$TMP_DIR/info-offline.out"
grep -Fq "Student" "$TMP_DIR/info-offline.out"
grep -Fq "CACHE" "$TMP_DIR/info-offline.out"

printf 'OK: rozvrh.sh smoke test\n'
printf 'OK: ukoly.sh smoke test\n'
printf 'OK: znamky.sh smoke test\n'
printf 'OK: absence.sh smoke test\n'
printf 'OK: info.sh smoke test\n'
printf 'OK: login.sh smoke test\n'
printf 'OK: offline cache smoke test\n'

"$ROOT_DIR/bakalari-cli" --help >"$TMP_DIR/cli-help.out"
grep -Fq "Bakaláři CLI" "$TMP_DIR/cli-help.out"
grep -Fq "absence" "$TMP_DIR/cli-help.out"
