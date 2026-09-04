# SLEAP GPU Docker

This image runs [SLEAP 1.6.5](https://github.com/talmolab/sleap/releases/tag/v1.6.5)
with CUDA 11.8 on either an NVIDIA-enabled Ubuntu host or Docker Desktop's WSL2
backend. It provides two localhost-only browser services:

- SLEAP's native Qt GUI through noVNC.
- JupyterLab using the same Python environment and GPU.

The image is locked to Python 3.13, `sleap-nn` 0.3.3,
`torch` 2.7.1+cu118 and `torchvision` 0.22.1+cu118. In addition to SLEAP's own
scientific dependencies, it contains statsmodels, h5py, PyTables, PyArrow,
OpenPyXL, XlsxWriter, Plotly, ipywidgets and tqdm.

## Layout

```text
sleap_docker/
├── Dockerfile
├── compose.yml             # Image, GPU, ports, health and persistent home
├── compose.data.yml        # Host DATA_DIR -> /data only
├── pyproject.toml
├── uv.lock
├── config/                 # Supervisor and Jupyter configuration
└── scripts/
    ├── start.sh            # Recommended start command and port reporting
    ├── bootstrap-wsl.sh    # Fresh WSL2 validation, configuration and startup
    └── smoke-test.sh       # Package, data and GPU verification
```

`compose.yml` deliberately has no host-data bind mount. The mapping exists only
in `compose.data.yml`, so host paths stay deployment-specific.

## Host prerequisites

### Ubuntu with an NVIDIA GPU

Install a current NVIDIA driver, Docker Engine, Docker Compose and the NVIDIA
Container Toolkit. Confirm that Docker can see the GPU before building SLEAP:

```bash
nvidia-smi
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
docker compose version
```

### Windows with WSL2 and an NVIDIA GPU

Use a current Windows NVIDIA driver, update WSL and enable Docker Desktop's WSL2
engine plus integration for the Linux distribution. Do not install a second
Linux display driver inside WSL.

```powershell
wsl --update
wsl -l -v
```

From the WSL distribution, confirm Docker GPU access:

```bash
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

For best bind-mount performance, keep active datasets in the WSL Linux
filesystem, for example `/home/your-user/sleap-data`. `/mnt/c/...` is supported
but is normally slower for many small files.

## End-to-end deployment on a new WSL2 machine

Run the following in an **Administrator PowerShell** on Windows:

```powershell
wsl --install --distribution Ubuntu
wsl --update
winget install --exact --id Docker.DockerDesktop
```

Restart Windows if requested, open Ubuntu once to create the Linux user, then
start Docker Desktop. In Docker Desktop, enable **Use the WSL 2 based engine**
and enable the Ubuntu distribution under **Settings > Resources > WSL
Integration**. Keep Docker Desktop in Linux-container mode. Install a current
Windows NVIDIA driver, but do not install a second Linux display driver inside
Ubuntu.

Open the Ubuntu terminal and run:

```bash
sudo apt-get update
sudo apt-get install -y git openssl ca-certificates

cd ~
git clone https://github.com/Zeyuyang-0420/sleap_docker.git
cd sleap_docker
./scripts/bootstrap-wsl.sh
```

The bootstrap script performs the following actions:

1. Confirms that it is running inside WSL2 and that Docker Desktop integration
   and Docker Compose are available.
2. Runs an NVIDIA CUDA test container and prints the detected GPU.
3. Creates `~/sleap-data` and a mode-`600` `.env` with random VNC and Jupyter
   credentials.
4. Pulls `yzy0000/sleap-gpu:1.6.5-cu118` from Docker Hub, starts it with
   `--no-build`, reports the actual localhost ports, and runs the
   GPU/package/data smoke test.

Use a different WSL data directory when needed:

```bash
./scripts/bootstrap-wsl.sh --data-dir /home/$USER/my-sleap-data
```

If `.env` already exists, the script preserves it and uses its existing data
path and credentials. Display the generated credentials locally with:

```bash
sed -n -e '/^VNC_PASSWORD=/p' -e '/^JUPYTER_TOKEN=/p' .env
```

Open the exact URLs printed by the script in the Windows browser. Normally
they are `http://127.0.0.1:6080/vnc.html` for SLEAP and
`http://127.0.0.1:8899/lab` for JupyterLab. The Jupyter port can be different
when 8899 is already occupied.

## Configure

```bash
cd sleap_docker
cp .env.example .env
mkdir -p data
openssl rand -hex 24   # generate VNC_PASSWORD
openssl rand -hex 24   # generate JUPYTER_TOKEN
```

Edit `.env` and set at least:

```dotenv
DATA_DIR=./data
VNC_PASSWORD=<generated-value>
JUPYTER_TOKEN=<generated-value>
```

On native Linux, set `USER_UID` and `USER_GID` to the owner of the data
directory, then rebuild the image:

```bash
id -u
id -g
```

Classic VNC authentication uses the first eight characters of
`VNC_PASSWORD`. Jupyter requires a token of at least 16 characters.

## Start

Use the wrapper rather than calling `docker compose up` directly:

```bash
./scripts/start.sh
```

To use the published Docker Hub image instead of building locally, set these
values in `.env`:

```dotenv
IMAGE_NAME=yzy0000/sleap-gpu
IMAGE_TAG=1.6.5-cu118
SLEAP_IMAGE_MODE=pull
```

Then run the same wrapper:

```bash
./scripts/start.sh
```

In `pull` mode the wrapper runs `docker compose pull` and starts with
`--no-build`, so the local Dockerfile is not built. The image can also be
preloaded explicitly and inspected in Docker Desktop:

```bash
docker pull yzy0000/sleap-gpu:1.6.5-cu118
docker image inspect yzy0000/sleap-gpu:1.6.5-cu118 \
  --format 'ID={{.Id}} OS={{.Os}} ARCH={{.Architecture}}'
```

The script validates configuration and data permissions, builds or pulls the
image according to `SLEAP_IMAGE_MODE`, waits for the health check, asks Docker
which ports were actually published, and prints English access instructions:

```text
SLEAP container started successfully.
SLEAP GUI:  http://127.0.0.1:6080/vnc.html
JupyterLab: http://127.0.0.1:8899/lab
JupyterLab is using the preferred port 8899.
```

JupyterLab prefers port 8899. The wrapper first asks Docker to bind that exact
port, so the availability check and reservation are atomic. Only when Docker
reports an 8899 bind conflict does the wrapper retry with the `8900-8999`
fallback range. It then reports the port Docker selected, for example:

```text
JupyterLab port 8899 was busy; Docker selected port 8900.
```

If the entire range is occupied, startup fails and does not print a success
message. Change `JUPYTER_PORT_RANGE` in `.env` to use another port or range.
The noVNC port is fixed by `NOVNC_PORT` and fails clearly if that port is busy.

At the noVNC page, select **Connect** and enter `VNC_PASSWORD`. At the
JupyterLab page, enter `JUPYTER_TOKEN` when prompted.

## Remote Ubuntu access

Both services bind only to `127.0.0.1`. After `start.sh` prints the actual
ports, forward them over SSH. If Jupyter selected 8900, run this on the client:

```bash
ssh -N \
  -L 6080:127.0.0.1:6080 \
  -L 8900:127.0.0.1:8900 \
  user@ubuntu-server
```

Then open `http://127.0.0.1:6080/vnc.html` and
`http://127.0.0.1:8900/lab` locally. There is no public VNC port, built-in TLS
or SSH server in the container.

## Verify and operate

Run the full smoke test after startup:

```bash
./scripts/smoke-test.sh
```

It imports the analysis stack, checks `/data` write access, asserts CUDA 11.8,
prints the detected GPU, runs `sleap doctor`, and checks both managed services.

Useful commands:

```bash
# Logs
docker compose -f compose.yml -f compose.data.yml logs -f sleap

# Interactive shell
docker compose -f compose.yml -f compose.data.yml exec sleap bash

# GPU and SLEAP diagnostics
docker compose -f compose.yml -f compose.data.yml exec sleap nvidia-smi
docker compose -f compose.yml -f compose.data.yml exec sleap sleap doctor

# Stop without deleting the persistent home volume
docker compose -f compose.yml -f compose.data.yml down
```

The named `/home/sleap` volume keeps SLEAP and Jupyter user settings across
container recreation. Dataset files, labels, trained models and predictions
remain in the host `DATA_DIR` mounted at `/data`.

## Troubleshooting

- **`/data is not writable`**: set `USER_UID` and `USER_GID` to the host data
  owner and rebuild. The entrypoint never changes ownership of the host path.
- **No GPU in `sleap doctor`**: first rerun the prerequisite CUDA container.
  Fix the host runtime before debugging SLEAP.
- **Jupyter range exhausted**: expand or move `JUPYTER_PORT_RANGE`, such as
  `9000-9099`.
- **noVNC port occupied**: change `NOVNC_PORT`; it intentionally does not scan
  because its URL is expected to remain stable.
- **GUI is slow**: Qt/OpenGL rendering is intentionally software-based for
  portability. Model training and inference still use CUDA.
