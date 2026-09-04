"""Jupyter Server configuration for the SLEAP container."""

import os

c = get_config()  # noqa: F821 - injected by Jupyter when loading this file
c.ServerApp.ip = "0.0.0.0"
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.root_dir = "/data"
c.ServerApp.allow_remote_access = True
c.ServerApp.quit_button = False
c.IdentityProvider.token = os.environ["JUPYTER_TOKEN"]

