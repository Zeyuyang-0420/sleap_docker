#!/usr/bin/env bash
set -euo pipefail

curl --fail --silent --show-error --max-time 5 \
    http://127.0.0.1:6080/vnc.html >/dev/null
curl --fail --silent --show-error --max-time 5 \
    "http://127.0.0.1:8888/api/status?token=${JUPYTER_TOKEN}" >/dev/null

statuses="$(supervisorctl -c /etc/supervisor/conf.d/sleap.conf status)"
if grep -Ev '^[^ ]+[[:space:]]+RUNNING([[:space:]]|$)' <<<"${statuses}" | grep -q .; then
    printf '%s\n' "${statuses}" >&2
    exit 1
fi

