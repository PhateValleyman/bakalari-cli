#!/usr/bin/env bash
# Compatibility wrapper for the legacy info.sh entry point.
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)"
exec "$SCRIPT_DIR/bakalari-cli" info "$@"
