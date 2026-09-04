#!/usr/bin/env bash
set -euo pipefail

for _ in $(seq 1 60); do
    if DISPLAY=:1 xdpyinfo >/dev/null 2>&1; then
        exec "$@"
    fi
    sleep 1
done

echo "ERROR: X display :1 did not become ready within 60 seconds." >&2
exit 1

