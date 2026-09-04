#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${ENV_FILE:-${project_dir}/.env}"
compose=(docker compose --env-file "${env_file}" -f "${project_dir}/compose.yml" -f "${project_dir}/compose.data.yml")

"${compose[@]}" exec -T sleap /opt/venv/bin/python - <<'PY'
import importlib
import os

import torch

packages = [
    "h5py", "ipywidgets", "jupyterlab", "openpyxl", "plotly", "pyarrow",
    "sleap", "sleap_io", "sleap_nn", "statsmodels", "tables", "tqdm",
    "xlsxwriter",
]
for package in packages:
    importlib.import_module(package)

assert torch.version.cuda == "11.8", torch.version.cuda
assert torch.cuda.is_available(), "PyTorch cannot access CUDA"
probe = "/data/.sleap-container-write-test"
with open(probe, "w", encoding="utf-8") as file:
    file.write("ok\n")
os.remove(probe)
print(f"GPU: {torch.cuda.get_device_name(0)}")
print("Python packages, CUDA 11.8, and /data write access: OK")
PY

"${compose[@]}" exec -T sleap sleap doctor
"${compose[@]}" exec -T sleap /usr/local/bin/healthcheck.sh

jupyter_mapping="$("${compose[@]}" port sleap 8888)"
novnc_mapping="$("${compose[@]}" port sleap 6080)"
echo "noVNC mapping: ${novnc_mapping}"
echo "JupyterLab mapping: ${jupyter_mapping}"
echo "Smoke test passed."

