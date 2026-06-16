"""
Django develop settings for WebVirtCloud project.

"""

import socket

from .base import *


# Django settings
DEBUG = True

# Allowed hosts
ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", [BASE_DOMAIN, f".{BASE_DOMAIN}", "localhost", "127.0.0.1"])

# Application definition
INSTALLED_APPS += [
    "drf_yasg",
    "corsheaders",
    "debug_toolbar",
    "django_browser_reload",
]

# CORS settings
CORS_ORIGIN_ALLOW_ALL = env_bool("DJANGO_CORS_ALLOW_ALL", False)
CORS_ALLOWED_ORIGINS = env_list(
    "DJANGO_CORS_ALLOWED_ORIGINS",
    [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
    ],
)

# Security settings
SESSION_COOKIE_DOMAIN = os.environ.get("SESSION_COOKIE_DOMAIN", None)

# DebugToolBar
try:
    hostname, _, ips = socket.gethostbyname_ex(socket.gethostname())
except socket.gaierror:
    ips = []
INTERNAL_IPS = [ip[: ip.rfind(".")] + ".1" for ip in ips] + ["127.0.0.1", "localhost"]

# Middleware definition
MIDDLEWARE += [
    "corsheaders.middleware.CorsMiddleware",
    "debug_toolbar.middleware.DebugToolbarMiddleware",
    "django_browser_reload.middleware.BrowserReloadMiddleware",
]

# Static URL
STATIC_URL = "static/"

# noVNC settings
NOVNC_URL = "localhost"
NOVNC_PORT = 6080

# Email settings
EMAIL_PORT = os.environ.get("EMAIL_PORT", 1025)
EMAIL_HOST = os.environ.get("EMAIL_HOST", "mailpit")
EMAIL_FROM = os.environ.get("EMAIL_FROM", "WebVirtCloud <noreply@spiritlhl.net>")
EMAIL_USE_TLS = os.environ.get("EMAIL_USE_TLS", False)
EMAIL_USE_SSL = os.environ.get("EMAIL_USE_SSL", False)
EMAIL_HOST_USER = os.environ.get("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = os.environ.get("EMAIL_HOST_PASSWORD", "")

try:
    from .local import *
except ImportError:
    pass
