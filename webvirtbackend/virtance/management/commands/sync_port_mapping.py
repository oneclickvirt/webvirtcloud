from django.conf import settings
from django.db.models import Q
from django.core.management.base import BaseCommand

from virtance.models import Virtance
from virtance.port_mapping import (
    clear_virtance_port_mapping,
    get_public_ip,
    get_virtance_mapping_name,
    read_port_mapping_file,
    update_virtance_port_mapping,
)


class Command(BaseCommand):
    help = "Synchronize VM port mapping information into the database."

    def add_arguments(self, parser):
        parser.add_argument(
            "--vm-name",
            type=str,
            help="Sync one VM by database display name, numeric ID, or libvirt domain name.",
        )
        parser.add_argument(
            "--mapping-file",
            type=str,
            help="Path to mapping.txt. Defaults to PORT_MAPPING_FILE.",
        )
        parser.add_argument(
            "--public-ip",
            type=str,
            help="Public IP to expose in API responses. Overrides PORT_MAPPING_PUBLIC_IP.",
        )
        parser.add_argument(
            "--no-probe-public-ip",
            action="store_false",
            dest="probe_public_ip",
            default=True,
            help="Disable public IP probing when no IP is configured.",
        )
        parser.add_argument(
            "--clear-missing",
            action="store_true",
            help="Clear cached mapping fields for virtances missing from the mapping file.",
        )

    def _get_virtances(self, vm_name):
        queryset = Virtance.objects.filter(is_deleted=False)
        if not vm_name:
            return queryset

        filters = Q(name=vm_name)
        if vm_name.isdigit():
            filters |= Q(id=int(vm_name))

        prefix = settings.VM_NAME_PREFIX
        if vm_name.startswith(prefix):
            maybe_id = vm_name.removeprefix(prefix)
            if maybe_id.isdigit():
                filters |= Q(id=int(maybe_id))

        return queryset.filter(filters)

    def handle(self, *args, **options):
        vm_name = options.get("vm_name")
        mapping_data = read_port_mapping_file(options.get("mapping_file"))
        public_ip = get_public_ip(options.get("public_ip"), allow_probe=options.get("probe_public_ip"))

        if not public_ip:
            self.stderr.write(self.style.ERROR("Unable to resolve a valid public IP for port mappings."))
            return

        if vm_name and vm_name in mapping_data:
            virtance_id = vm_name.removeprefix(settings.VM_NAME_PREFIX)
            virtances = Virtance.objects.filter(id=virtance_id, is_deleted=False) if virtance_id.isdigit() else []
        else:
            virtances = self._get_virtances(vm_name)

        checked_count = 0
        updated_count = 0
        cleared_count = 0

        for virtance in virtances:
            checked_count += 1
            mapping_name = get_virtance_mapping_name(virtance)
            mapping_info = mapping_data.get(mapping_name)

            if mapping_info:
                if update_virtance_port_mapping(virtance, mapping_info=mapping_info, public_ip=public_ip):
                    updated_count += 1
                    self.stdout.write(f"Synced {mapping_name} ({virtance.name})")
            elif options.get("clear_missing") and clear_virtance_port_mapping(virtance):
                cleared_count += 1
                self.stdout.write(f"Cleared stale mapping for {mapping_name} ({virtance.name})")

        if vm_name and checked_count == 0:
            self.stderr.write(self.style.ERROR(f"Virtance '{vm_name}' was not found."))
            return

        self.stdout.write(
            self.style.SUCCESS(
                f"Port mapping sync complete: checked={checked_count}, updated={updated_count}, cleared={cleared_count}"
            )
        )
