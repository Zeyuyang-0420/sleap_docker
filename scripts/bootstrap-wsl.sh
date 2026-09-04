#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${ENV_FILE:-${project_dir}/.env}"
data_dir="${SLEAP_DATA_DIR:-${HOME}/sleap-data}"
cuda_test_image="${CUDA_TEST_IMAGE:-nvidia/cuda:11.8.0-base-ubuntu22.04}"
run_gpu_test=1
run_smoke_test=1

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: ./scripts/bootstrap-wsl.sh [options]

Options:
  --data-dir PATH       Host data directory mounted at /data.
                        Default: $HOME/sleap-data
  --skip-gpu-test       Skip the NVIDIA CUDA test container.
  --skip-smoke-test     Skip the post-start SLEAP smoke test.
  -h, --help            Show this help text.

Environment overrides:
  ENV_FILE              Configuration file path (default: PROJECT/.env)
  SLEAP_DATA_DIR        Same purpose as --data-dir
  CUDA_TEST_IMAGE       CUDA image used to verify Docker GPU access
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --data-dir)
            (( $# >= 2 )) || fail "--data-dir requires a path."
            data_dir="$2"
            shift 2
            ;;
        --skip-gpu-test)
            run_gpu_test=0
            shift
            ;;
        --skip-smoke-test)
            run_smoke_test=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
done

grep -Eqi 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null || \
    fail "This bootstrap script must be run inside a WSL2 Linux distribution."
[[ "$(uname -m)" == "x86_64" ]] || fail "This image currently supports x86_64/amd64 hosts only."

command -v docker >/dev/null 2>&1 || \
    fail "Docker CLI is unavailable. Enable this distribution in Docker Desktop > Settings > Resources > WSL Integration."
docker info >/dev/null 2>&1 || \
    fail "Docker Desktop is not running or its WSL integration is unavailable."
docker compose version >/dev/null 2>&1 || fail "Docker Compose is unavailable."
command -v openssl >/dev/null 2>&1 || fail "OpenSSL is required. Install it with: sudo apt-get install openssl"
command -v realpath >/dev/null 2>&1 || fail "realpath is required (GNU coreutils)."

if (( run_gpu_test == 1 )); then
    echo "Checking NVIDIA GPU access from Docker..."
    docker run --rm --gpus all "${cuda_test_image}" nvidia-smi || \
        fail "Docker cannot access the NVIDIA GPU. Update the Windows NVIDIA driver, WSL, and Docker Desktop before retrying."
fi

if [[ -e "${env_file}" ]]; then
    echo "Using existing configuration: ${env_file}"
    echo "The existing DATA_DIR and credentials take precedence over --data-dir."
else
    mkdir -p -- "${data_dir}"
    data_dir="$(realpath -- "${data_dir}")"
    [[ -d "${data_dir}" && -w "${data_dir}" ]] || fail "Data directory is not writable: ${data_dir}"
    [[ "${data_dir}" != *$'\n'* && "${data_dir}" != *'"'* && \
       "${data_dir}" != *'$'* && "${data_dir}" != *'`'* && \
       "${data_dir}" != *'\\'* ]] || \
        fail "The data directory path contains characters that cannot be written safely to .env."

    vnc_password="$(openssl rand -hex 24)"
    jupyter_token="$(openssl rand -hex 24)"
    user_uid="$(id -u)"
    user_gid="$(id -g)"

    umask 077
    cat >"${env_file}" <<EOF
DATA_DIR="${data_dir}"
VNC_PASSWORD=${vnc_password}
JUPYTER_TOKEN=${jupyter_token}

NOVNC_PORT=6080
JUPYTER_PORT_RANGE=8899-8999

DISPLAY_WIDTH=1920
DISPLAY_HEIGHT=1080
SHM_SIZE=8gb
GPU_COUNT=1

USER_UID=${user_uid}
USER_GID=${user_gid}

IMAGE_NAME=yzy0000/sleap-gpu
IMAGE_TAG=1.6.5-cu118
SLEAP_IMAGE_MODE=pull
COMPOSE_PROJECT_NAME=sleap
UV_VERSION=0.8.15
EOF
    chmod 600 "${env_file}"
    echo "Created configuration with generated credentials: ${env_file}"
fi

echo "Pulling and starting the prebuilt SLEAP image. The first download can take a long time..."
ENV_FILE="${env_file}" "${project_dir}/scripts/start.sh"

if (( run_smoke_test == 1 )); then
    echo "Running the SLEAP GPU smoke test..."
    ENV_FILE="${env_file}" "${project_dir}/scripts/smoke-test.sh"
fi

echo
echo "WSL2 deployment completed successfully."
echo "Credentials are stored locally in: ${env_file}"
echo "Display them with: sed -n -e '/^VNC_PASSWORD=/p' -e '/^JUPYTER_TOKEN=/p' '${env_file}'"
