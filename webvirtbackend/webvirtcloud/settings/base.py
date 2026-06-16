"""
Django settings for webvirtcloud project.
"""

import base64
import os
import uuid
from pathlib import Path
from celery.schedules import crontab
from theme.crispy_forms import WEBVIRTCLOUD_CRISPY_CLASS_CONVERTERS

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent


def env_bool(name, default=False):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


def env_list(name, default=None):
    value = os.environ.get(name)
    if not value:
        return default or []
    return [item.strip() for item in value.split(",") if item.strip()]


def env_int(name, default):
    value = os.environ.get(name)
    if value is None:
        return default
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


# Base domain
BASE_DOMAIN = os.environ.get("DOMAIN_NAME", "spiritlhl.net")

# SECURITY WARNING: keep the secret key used in production secret.
# Production settings validate that DJANGO_SECRET_KEY/SECRET_KEY is explicitly set.
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY") or os.environ.get("SECRET_KEY")
if not SECRET_KEY:
    SECRET_KEY = base64.urlsafe_b64encode(os.urandom(48)).decode()

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = env_bool("DJANGO_DEBUG", True)

# Allowed hosts
ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", [BASE_DOMAIN, f".{BASE_DOMAIN}", "localhost", "127.0.0.1"])

# Authentication definition
AUTH_USER_MODEL = "account.User"

# Application definition
INSTALLED_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
]

# Project application definition
INSTALLED_APPS += [
    "api",
    "size",
    "admin",
    "image",
    "lbaas",
    "region",
    "account",
    "billing",
    "compute",
    "keypair",
    "project",
    "network",
    "virtance",
    "firewall",
    "floating_ip",
    "webvirtcloud",
]

# Third party application definition
INSTALLED_APPS += [
    "theme",
    "tailwind",
    "django_htmx",
    "crispy_forms",
    "crispy_tailwind",
    "rest_framework",
    "django_filters",
    "django_tables2",
    "django_celery_results",
]

# Middleware definition
MIDDLEWARE = [
    "django_htmx.middleware.HtmxMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

# Rest framework definition
REST_FRAMEWORK = {
    "EXCEPTION_HANDLER": "webvirtcloud.views.app_exception_handler",
    "DEFAULT_PARSER_CLASSES": ("rest_framework.parsers.JSONParser",),
    "DEFAULT_RENDERER_CLASSES": ("rest_framework.renderers.JSONRenderer",),
    "DEFAULT_PERMISSION_CLASSES": ("webvirtcloud.permissions.IsAuthenticatedAndVerified",),
    "DEFAULT_AUTHENTICATION_CLASSES": ("webvirtcloud.authentication.TokenAuthentication",),
}

# Root URL definition
ROOT_URLCONF = "webvirtcloud.urls"

# Templates definition
TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": ["templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

# WSGI definition
WSGI_APPLICATION = "webvirtcloud.wsgi.application"

# Database settings
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.mysql",
        "CONN_MAX_AGE": 3600,
        "NAME": os.environ.get("DB_NAME", "webvirtcloud"),
        "USER": os.environ.get("DB_USER", "django"),
        "PASSWORD": os.environ.get("DB_PASSWORD", ""),
        "HOST": os.environ.get("DB_HOST", "127.0.0.1"),
        "PORT": os.environ.get("DB_PORT", 3306),
        "OPTIONS": {
            "init_command": "SET sql_mode='STRICT_TRANS_TABLES'",
        },
    },
}

# Celery settings
CELERY_BROKER_URL = os.environ.get("CELERY_BROKER_URL", "amqp://guest:guest@127.0.0.1:5672")
CELERY_TASK_TRACK_STARTED = True
CELERY_TASK_TIME_LIMIT = 30 * 60
CELERY_RESULT_BACKEND = "django-db"
CELERY_BEAT_SCHEDULE = {
    "virtance_counter": {
        "task": "virtance.tasks.virtance_counter",
        "schedule": crontab(minute=0, hour="*/1"),
    },
    "virtance_backup": {
        "task": "virtance.tasks.virtance_backup",
        "schedule": crontab(minute=0, hour="*/1"),
    },
    "snapshot_counter": {
        "task": "image.tasks.snapshot_counter",
        "schedule": crontab(minute=0, hour="*/1"),
    },
    "floating_ip_counter": {
        "task": "floating_ip.tasks.floating_ip_counter",
        "schedule": crontab(minute=0, hour="*/1"),
    },
    "make_monthly_invoice": {
        "task": "billing.tasks.make_monthly_invoice",
        "schedule": crontab(minute=0, hour=0, day_of_month=1),
    },
}

# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {
        "NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator",
    },
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
    },
    {
        "NAME": "django.contrib.auth.password_validation.CommonPasswordValidator",
    },
    {
        "NAME": "django.contrib.auth.password_validation.NumericPasswordValidator",
    },
]


# Internationalization
LANGUAGE_CODE = "en-us"

TIME_ZONE = "UTC"

USE_I18N = True

USE_TZ = True

# Static files (CSS, JavaScript, Images)
STATIC_URL = "/static/"
STATIC_ROOT = os.path.join(BASE_DIR, "../../", "static")
STATICFILES_DIRS = [os.path.join(os.path.join(BASE_DIR, "../"), "static")]

# Default primary key field type
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# Login redirect url
LOGIN_URL = "/admin/sign_in/"
LOGIN_REDIRECT_URL = "/admin/"

# Crispy forms
CRISPY_TEMPLATE_PACK = "webvirtcloud"
CRISPY_ALLOWED_TEMPLATE_PACKS = ("webvirtcloud",)
CRISPY_CLASS_CONVERTERS = WEBVIRTCLOUD_CRISPY_CLASS_CONVERTERS

# Tailwind settings
TAILWIND_APP_NAME = "theme"
TAILWIND_CSS_PATH = "admin/css/styles.css"

# Email settings
EMAIL_BACKEND = "django.core.mail.backends.smtp.EmailBackend"
EMAIL_PORT = env_int("EMAIL_PORT", 587)
EMAIL_HOST = os.environ.get("EMAIL_HOST", "smtp.gmail.com")
EMAIL_FROM = os.environ.get("EMAIL_FROM", "WebVirtCloud <noreply@spiritlhl.net>")
EMAIL_USE_TLS = env_bool("EMAIL_USE_TLS", False)
EMAIL_USE_SSL = env_bool("EMAIL_USE_SSL", False)
EMAIL_HOST_USER = os.environ.get("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = os.environ.get("EMAIL_HOST_PASSWORD", "")

# WebVirtCloud Settings

#
# Domain and URL settings
#
# Security settings
SESSION_COOKIE_DOMAIN = os.environ.get("SESSION_COOKIE_DOMAIN", f"{BASE_DOMAIN}")

# CSFR Trusted hosts
CSRF_TRUSTED_ORIGINS = env_list("CSRF_TRUSTED_ORIGINS", [f"https://{BASE_DOMAIN}", f"http://{BASE_DOMAIN}"])

#
# Panel settings
#
# Encryption key
# Generate a new own key with the following command:
# python3 -c 'import os, base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())'
# or use the default key generated unique static node ID
UNIQ_NODE_ID = f"webvirtcloud-{uuid.getnode():x}".ljust(32, "0").encode()
ENCRYPTION_KEY = os.environ.get("ENCRYPTION_KEY", base64.urlsafe_b64encode(UNIQ_NODE_ID).decode())

# Public images URL storage (Distributions, Applicatons)
PUBLIC_IMAGES_URL = os.environ.get("PUBLIC_IMAGES_URL", "https://cdn.spiritlhl.net/github.com/oneclickvirt/webvirtcloud/releases/download/webvirtcloud_images/")

# Compute settings
COMPUTE_PORT = env_int("COMPUTE_PORT", 8884)
COMPUTE_VM_IMAGES_POOL = os.environ.get("COMPUTE_VM_IMAGES_POOL", "images")
COMPUTE_CPU_RATIO_OVERCOMMIT = env_int("COMPUTE_CPU_RATIO_OVERCOMMIT", 2)
COMPUTE_MEMORY_PERCENTAGE_USAGE = env_int("COMPUTE_MEMORY_PERCENTAGE_USAGE", 85)
COMPUTE_STORAGE_PERCENTAGE_USAGE = env_int("COMPUTE_STORAGE_PERCENTAGE_USAGE", 85)

# Virtual machine name prefix
VM_NAME_PREFIX = os.environ.get("VM_NAME_PREFIX", "Virtance-")

# Port mapping sync settings
PORT_MAPPING_FILE = os.environ.get("PORT_MAPPING_FILE", "/etc/vm_port_mapping/mapping.txt")
PORT_MAPPING_PUBLIC_IP = os.environ.get("PORT_MAPPING_PUBLIC_IP", "")
PORT_MAPPING_PUBLIC_IP_ENDPOINTS = env_list(
    "PORT_MAPPING_PUBLIC_IP_ENDPOINTS",
    ["https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com"],
)
PORT_MAPPING_PUBLIC_IP_TIMEOUT = env_int("PORT_MAPPING_PUBLIC_IP_TIMEOUT", 5)

# Websocket settings
WEBSOCKET_HOST = os.environ.get("WEBSOCKET_HOST", "0.0.0.0")
WEBSOCKET_PORT = env_int("WEBSOCKET_PORT", 6080)
WEBSOCKET_CERT = os.environ.get("WEBSOCKET_CERT", None)

# noVNC settings
NOVNC_URL = os.environ.get("NOVNC_URL", f"{BASE_DOMAIN}/novnc/")
NOVNC_PORT = env_int("NOVNC_PORT", 443)
NOVNC_PASSWD_PREFIX_LENGHT = env_int("NOVNC_PASSWD_PREFIX_LENGHT", 6)
NOVNC_PASSWD_SUFFIX_LENGHT = env_int("NOVNC_PASSWD_SUFFIX_LENGHT", 12)

# Recovery image settings
RECOVERY_ISO_NAME = os.environ.get("RECOVERY_ISO_NAME", "finnix-125.iso")

# LBaaS settings
LBAAS_IPV4_ACCESS_LIST = env_list("LBAAS_IPV4_ACCESS_LIST", [])

# Backup settings
BACKUP_PER_MONTH = env_int("BACKUP_PER_MONTH", 4)
BACKUP_PERIOD_DAYS = env_int("BACKUP_PERIOD_DAYS", 7)
BACKUP_COST_PERCENTAGE = env_int("BACKUP_COST_PERCENTAGE", 20)

# Verification settings
VERIFICATION_ENABLED = env_bool("VERIFICATION_ENABLED", False)

# Registration settings
REGISTRATION_ENABLED = env_bool("REGISTRATION_ENABLED", False)
