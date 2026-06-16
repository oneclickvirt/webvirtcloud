import ipaddress
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Optional

import requests
from django.conf import settings


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class PortMapping:
    vm_name: str
    vm_ip: str
    mac_address: str
    ssh_port: int
    port_range_start: int
    port_range_end: int

    @property
    def port_range(self):
        return f"{self.port_range_start}-{self.port_range_end}"


def get_virtance_mapping_name(virtance):
    return f"{settings.VM_NAME_PREFIX}{virtance.id}"


def _valid_port(value):
    return 1 <= value <= 65535


def _parse_mapping_line(line, line_number):
    parts = line.split()
    if len(parts) < 6:
        logger.warning("Skipping malformed port mapping line %s: expected 6 fields", line_number)
        return None

    vm_name, vm_ip, mac_address, ssh_port_raw, port_start_raw, port_end_raw = parts[:6]
    try:
        ipaddress.ip_address(vm_ip)
        ssh_port = int(ssh_port_raw)
        port_start = int(port_start_raw)
        port_end = int(port_end_raw)
    except ValueError:
        logger.warning("Skipping malformed port mapping line %s: invalid IP or port", line_number)
        return None

    if not _valid_port(ssh_port) or not _valid_port(port_start) or not _valid_port(port_end) or port_start > port_end:
        logger.warning("Skipping malformed port mapping line %s: invalid port range", line_number)
        return None

    return PortMapping(
        vm_name=vm_name,
        vm_ip=vm_ip,
        mac_address=mac_address,
        ssh_port=ssh_port,
        port_range_start=port_start,
        port_range_end=port_end,
    )


def read_port_mapping_file(mapping_file=None) -> Dict[str, PortMapping]:
    path = Path(mapping_file or settings.PORT_MAPPING_FILE)
    mapping_data = {}

    if not path.exists():
        return mapping_data

    try:
        with path.open("r", encoding="utf-8") as file_obj:
            for line_number, raw_line in enumerate(file_obj, start=1):
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue

                mapping = _parse_mapping_line(line, line_number)
                if mapping:
                    mapping_data[mapping.vm_name] = mapping
    except OSError as exc:
        logger.warning("Unable to read port mapping file %s: %s", path, exc)

    return mapping_data


def _normalize_public_ip(public_ip):
    if not public_ip:
        return None

    public_ip = public_ip.strip()
    try:
        ipaddress.ip_address(public_ip)
    except ValueError:
        logger.warning("Ignoring invalid public IP value: %s", public_ip)
        return None

    return public_ip


def get_public_ip(public_ip=None, allow_probe=False) -> Optional[str]:
    configured_ip = _normalize_public_ip(public_ip or settings.PORT_MAPPING_PUBLIC_IP)
    if configured_ip or not allow_probe:
        return configured_ip

    for url in settings.PORT_MAPPING_PUBLIC_IP_ENDPOINTS:
        try:
            response = requests.get(url, timeout=settings.PORT_MAPPING_PUBLIC_IP_TIMEOUT)
            response.raise_for_status()
        except requests.RequestException as exc:
            logger.debug("Public IP probe failed for %s: %s", url, exc)
            continue

        probed_ip = _normalize_public_ip(response.text)
        if probed_ip:
            return probed_ip

    return None


def get_vm_port_mapping(vm_name: str, mapping_file=None) -> Optional[PortMapping]:
    mapping_data = read_port_mapping_file(mapping_file)
    return mapping_data.get(vm_name)


def update_virtance_port_mapping(virtance, mapping_info=None, public_ip=None, save=True):
    mapping = mapping_info or get_vm_port_mapping(get_virtance_mapping_name(virtance))
    normalized_public_ip = get_public_ip(public_ip)

    if not mapping or not normalized_public_ip:
        return False

    fields = {
        "public_ip": normalized_public_ip,
        "ssh_port": mapping.ssh_port,
        "port_range_start": mapping.port_range_start,
        "port_range_end": mapping.port_range_end,
    }

    changed_fields = []
    for field, value in fields.items():
        if getattr(virtance, field) != value:
            setattr(virtance, field, value)
            changed_fields.append(field)

    if save and changed_fields:
        virtance.save(update_fields=[*changed_fields, "updated"])

    return True


def clear_virtance_port_mapping(virtance):
    fields = ("public_ip", "ssh_port", "port_range_start", "port_range_end")
    changed_fields = []
    for field in fields:
        if getattr(virtance, field) is not None:
            setattr(virtance, field, None)
            changed_fields.append(field)

    if changed_fields:
        virtance.save(update_fields=[*changed_fields, "updated"])
        return True

    return False
