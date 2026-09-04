#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${ENV_FILE:-${project_dir}/.env}"
compose_files=(-f "${project_dir}/compose.yml" -f "${project_dir}/compose.data.yml")
cd "${project_dir}"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

command -v docker >/dev/null 2>&1 || fail "Docker is not installed or not in PATH."
docker compose version >/dev/null 2>&1 || fail "Docker Compose is not available."
[[ -f "${env_file}" ]] || fail "Environment file not found: ${env_file}. Copy .env.example to .env first."

set -a
# shellcheck disable=SC1090
source "${env_file}"
set +a

[[ -n "${DATA_DIR:-}" ]] || fail "DATA_DIR must be set in ${env_file}."
[[ -d "${DATA_DIR}" ]] || fail "DATA_DIR does not exist: ${DATA_DIR}"
[[ -n "${VNC_PASSWORD:-}" ]] || fail "VNC_PASSWORD must be set in ${env_file}."
(( ${#VNC_PASSWORD} >= 8 )) || fail "VNC_PASSWORD must contain at least 8 characters."
[[ -n "${JUPYTER_TOKEN:-}" ]] || fail "JUPYTER_TOKEN must be set in ${env_file}."
(( ${#JUPYTER_TOKEN} >= 16 )) || fail "JUPYTER_TOKEN must contain at least 16 characters."

port_range="${JUPYTER_PORT_RANGE:-8899-8999}"
if [[ "${port_range}" =~ ^([0-9]+)(-([0-9]+))?$ ]]; then
    preferred_port="${BASH_REMATCH[1]}"
    last_port="${BASH_REMATCH[3]:-${preferred_port}}"
else
    fail "Invalid JUPYTER_PORT_RANGE: ${port_range}"
fi
(( preferred_port >= 1 && preferred_port <= 65535 )) || fail "Invalid preferred JupyterLab port: ${preferred_port}"
(( last_port >= preferred_port && last_port <= 65535 )) || fail "Invalid JUPYTER_PORT_RANGE: ${port_range}"

fallback_range=""
if (( last_port > preferred_port )); then
    fallback_range="$((preferred_port + 1))-${last_port}"
fi

compose=(docker compose --env-file "${env_file}" "${compose_files[@]}")
image_mode="${SLEAP_IMAGE_MODE:-build}"
up_image_options=()

case "${image_mode}" in
    build)
        echo "Building the SLEAP image from source..."
        "${compose[@]}" build sleap
        ;;
    pull)
        echo "Pulling the prebuilt SLEAP image..."
        "${compose[@]}" pull sleap
        up_image_options=(--no-build)
        ;;
    *)
        fail "SLEAP_IMAGE_MODE must be either 'build' or 'pull', not: ${image_mode}"
        ;;
esac

run_up() {
    local published_port="$1"
    local attempt_log
    attempt_log="$(mktemp)"

    set +e
    JUPYTER_PUBLISHED_PORT="${published_port}" \
        "${compose[@]}" up -d --wait "${up_image_options[@]}" 2>&1 | tee "${attempt_log}"
    up_status=${PIPESTATUS[0]}
    set -e

    up_output="$(<"${attempt_log}")"
    unlink "${attempt_log}"
    return "${up_status}"
}

echo "Starting SLEAP on the preferred JupyterLab port ${preferred_port}..."
if run_up "${preferred_port}"; then
    :
else
    if ! grep -Eiq 'address already in use|port is already allocated|failed to bind' <<<"${up_output}" || \
       ! grep -Eq "(^|[^0-9])${preferred_port}([^0-9]|$)" <<<"${up_output}"; then
        echo "ERROR: The SLEAP container did not become healthy." >&2
        echo "Inspect the Compose output above and the service logs." >&2
        exit 1
    fi

    if [[ -z "${fallback_range}" ]]; then
        echo "ERROR: JupyterLab port ${preferred_port} is busy and no fallback range is configured." >&2
        exit 1
    fi

    echo "JupyterLab port ${preferred_port} is busy; trying ${fallback_range}..."
    if ! run_up "${fallback_range}"; then
        echo "ERROR: The SLEAP container did not become healthy." >&2
        echo "The JupyterLab fallback range may be exhausted: ${fallback_range}." >&2
        echo "Inspect the Compose output above and the service logs." >&2
        exit 1
    fi
fi

if ! "${compose[@]}" ps --status running --services | grep -qx sleap; then
    echo "ERROR: The SLEAP service is not running after startup." >&2
    echo "Inspect the service with: docker compose --env-file ${env_file} ${compose_files[*]} logs sleap" >&2
    exit 1
fi

jupyter_mapping="$("${compose[@]}" port sleap 8888)"
novnc_mapping="$("${compose[@]}" port sleap 6080)"
jupyter_port="${jupyter_mapping##*:}"
novnc_port="${novnc_mapping##*:}"

[[ "${jupyter_port}" =~ ^[0-9]+$ ]] || fail "Could not determine the JupyterLab host port from: ${jupyter_mapping}"
[[ "${novnc_port}" =~ ^[0-9]+$ ]] || fail "Could not determine the noVNC host port from: ${novnc_mapping}"

echo
echo "SLEAP container started successfully."
printf 'SLEAP GUI:  http://127.0.0.1:%s/vnc.html\n' "${novnc_port}"
printf 'JupyterLab: http://127.0.0.1:%s/lab\n' "${jupyter_port}"
if [[ "${jupyter_port}" == "${preferred_port}" ]]; then
    printf 'JupyterLab is using the preferred port %s.\n' "${preferred_port}"
else
    printf 'JupyterLab port %s was busy; Docker selected port %s.\n' \
        "${preferred_port}" "${jupyter_port}"
fi
