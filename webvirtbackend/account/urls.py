from django.urls import re_path

from .views import Login, Register, ResetPassword, ResetPasswordHash, VerifyHashEmail, VerifyResendEmail

urlpatterns = [
    re_path(r"login/?$", Login.as_view(), name="login"),
    re_path(r"register/?$", Register.as_view(), name="register"),
    re_path(r"reset_password/?$", ResetPassword.as_view(), name="reset_password"),
    re_path(r"reset_password/(?P<hash>\w+)/?$", ResetPasswordHash.as_view(), name="reset_password_hash"),
    re_path(r"verify_email/?$", VerifyResendEmail.as_view(), name="verify_resend_email"),
    re_path(r"verify_email/(?P<hash>\w+)/?$", VerifyHashEmail.as_view(), name="verify_hash_email"),
]
