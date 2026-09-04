# syntax=docker/dockerfile:1.7

ARG UV_VERSION=0.8.15
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM ubuntu:22.04

ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH=/opt/venv/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    UV_PYTHON_BIN_DIR=/opt/uv/bin \
    UV_LINK_MODE=copy \
    UV_NO_CACHE=1 \
    DISPLAY=:1 \
    QT_X11_NO_MITSHM=1 \
    LIBGL_ALWAYS_SOFTWARE=1 \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dbus-x11 \
        ffmpeg \
        fonts-dejavu-core \
        git \
        libdbus-1-3 \
        libegl1 \
        libfontconfig1 \
        libgl1 \
        libgl1-mesa-dri \
        libglib2.0-0 \
        libice6 \
        libopengl0 \
        libsm6 \
        libx11-6 \
        libx11-xcb1 \
        libxcb-cursor0 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-randr0 \
        libxcb-render-util0 \
        libxcb-shape0 \
        libxcb-xfixes0 \
        libxcb-xinerama0 \
        libxext6 \
        libxkbcommon-x11-0 \
        libxrender1 \
        mesa-utils \
        nano \
        novnc \
        openbox \
        procps \
        supervisor \
        tini \
        vim-tiny \
        websockify \
        x11-utils \
        x11vnc \
        xvfb && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd --gid "${USER_GID}" sleap && \
    useradd --uid "${USER_UID}" --gid "${USER_GID}" \
        --create-home --home-dir /home/sleap --shell /bin/bash sleap && \
    install -d -o sleap -g sleap /data /home/sleap /opt/uv /opt/venv && \
    install -d -m 1777 /tmp/.X11-unix

COPY --from=uv /uv /uvx /usr/local/bin/
WORKDIR /opt/sleap-environment
COPY pyproject.toml uv.lock ./

RUN uv python install 3.13 && \
    uv sync --frozen --no-dev --no-install-project --python 3.13 && \
    /opt/venv/bin/python -c \
      "import sleap, sleap_nn, torch; assert torch.version.cuda == '11.8', torch.version.cuda; print(sleap.__version__, sleap_nn.__version__, torch.__version__, torch.version.cuda)"

ENV HOME=/home/sleap \
    USER=sleap \
    LOGNAME=sleap

COPY config/supervisord.conf /etc/supervisor/conf.d/sleap.conf
COPY config/jupyter_server_config.py /etc/sleap/jupyter_server_config.py
COPY scripts/container-entrypoint.sh scripts/wait-for-display.sh scripts/healthcheck.sh /usr/local/bin/

RUN chmod 0755 \
        /usr/local/bin/container-entrypoint.sh \
        /usr/local/bin/wait-for-display.sh \
        /usr/local/bin/healthcheck.sh && \
    chown -R root:root /etc/sleap /etc/supervisor/conf.d/sleap.conf

WORKDIR /data
EXPOSE 6080 8888

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/container-entrypoint.sh"]
