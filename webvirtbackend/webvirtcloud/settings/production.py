"""
Django production settings for WebVirtCloud project.

"""

import os

from django.core.exceptions import ImproperlyConfigured

from .base import *

# Django settings
DEBUG = False


def require_strong_secret(name, *aliases):
    value = next((os.environ.get(key) for key in (name, *aliases) if os.environ.get(key)), "")
    weak_values = {"admin", "django", "password", "root", "changeme", "change-me"}
    if not value or value.lower() in weak_values or value.lower().startswith("change-me"):
        raise ImproperlyConfigured(f"{name} must be set to a strong non-placeholder value in production.")
    return value


require_strong_secret("DJANGO_SECRET_KEY", "SECRET_KEY")
require_strong_secret("DB_PASSWORD")

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
CSRF_COOKIE_SECURE = os.environ.get("CSRF_COOKIE_SECURE", "true").lower() in ("1", "true", "yes", "on")
SESSION_COOKIE_SECURE = os.environ.get("SESSION_COOKIE_SECURE", "true").lower() in ("1", "true", "yes", "on")

try:
    from .local import *
except ImportError:
    pass
