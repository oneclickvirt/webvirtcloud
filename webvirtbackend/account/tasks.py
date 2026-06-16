from django.conf import settings

from webvirtcloud.celery import app
from webvirtcloud.email import send_email


def build_site_url(path="/"):
    base_url = settings.BASE_DOMAIN.strip().rstrip("/")
    if not base_url.startswith(("http://", "https://")):
        scheme = "http" if settings.DEBUG else "https"
        base_url = f"{scheme}://{base_url}"
    if not path.startswith("/"):
        path = f"/{path}"
    return f"{base_url}{path}"


@app.task
def email_confirm_register(recipient, hash):
    subject = "WebVirtCloud confirm registration"
    confirm_url = build_site_url(f"/confirm-email/{hash}/")
    context = {"confirm_url": confirm_url, "site_url": build_site_url()}
    send_email(subject, recipient, context, "email/account-registration-confirm.html")


@app.task
def email_reset_password(recipient, hash):
    subject = "WebVirtCloud reset password"
    reset_url = build_site_url(f"/reset-password/{hash}/")
    context = {"reset_url": reset_url, "site_url": build_site_url()}
    send_email(subject, recipient, context, "email/account-reset-password.html")
