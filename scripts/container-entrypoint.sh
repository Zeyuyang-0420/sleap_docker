#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${VNC_PASSWORD:-}" ]]; then
    echo "ERROR: VNC_PASSWORD must not be empty." >&2
    exit 64
fi

if (( ${#VNC_PASSWORD} < 8 )); then
    echo "ERROR: VNC_PASSWORD must contain at least 8 characters." >&2
    exit 64
fi

if [[ -z "${JUPYTER_TOKEN:-}" ]]; then
    echo "ERROR: JUPYTER_TOKEN must not be empty." >&2
    exit 64
fi

if (( ${#JUPYTER_TOKEN} < 16 )); then
    echo "ERROR: JUPYTER_TOKEN must contain at least 16 characters." >&2
    exit 64
fi

sleap_gid="$(id -g sleap)"
install -d -m 0750 -o sleap -g "${sleap_gid}" /run/sleap
install -d -m 0700 -o sleap -g "${sleap_gid}" /tmp/runtime-sleap
install -d -m 1777 /tmp/.X11-unix
chown "sleap:${sleap_gid}" /home/sleap

x11vnc -storepasswd "${VNC_PASSWORD}" /run/sleap/vnc.pass >/dev/null
chown "sleap:${sleap_gid}" /run/sleap/vnc.pass
chmod 0600 /run/sleap/vnc.pass
unset VNC_PASSWORD

if ! runuser -u sleap -- test -w /data; then
    echo "ERROR: /data is not writable by the sleap user." >&2
    echo "Set USER_UID and USER_GID to the owner of DATA_DIR, then rebuild." >&2
    exit 73
fi

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/sleap.conf
