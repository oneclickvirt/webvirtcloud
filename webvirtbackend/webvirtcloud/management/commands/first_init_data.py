import os
import secrets
from django.core.management import call_command
from django.core.management.base import BaseCommand

from account.models import User


class Command(BaseCommand):
    help = "Initialize data for webvirtcloud"

    def handle(self, *args, **kwargs):
        call_command("loaddata", "initial_data")
        self.stdout.write(self.style.SUCCESS("Initial data successfully loaded"))

        # Create admin superuser
        admin_email = os.environ.get("WEBVIRT_ADMIN_EMAIL", "admin@localdomain")
        admin_password = os.environ.get("WEBVIRT_ADMIN_PASSWORD") or secrets.token_urlsafe(24)
        try:
            User.objects.get(email=admin_email)
            self.stdout.write(self.style.SUCCESS(f"User '{admin_email}' already exists"))
        except User.DoesNotExist:
            user = User.objects.create_superuser(
                email=admin_email,
                password=admin_password,
            )
            user.first_name = "Charlie"
            user.last_name = "Root"
            user.is_active = True
            user.is_verified = True
            user.is_email_verified = True
            user.save()
            user.update_hash()
            self.stdout.write(self.style.SUCCESS(f"User '{admin_email}' successfully created"))
            self.stdout.write(self.style.SUCCESS(f"Initial admin password: {admin_password}"))
