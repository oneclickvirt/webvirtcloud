import random
from ipaddress import IPv4Network

from django.db import transaction

from virtance.models import Virtance
from .models import Network, IPAddress
from .ipv6 import first_assignable_ipv6_address, ipv6_network, ipv6_network_config


# First is a gateway and 2 lasts are reserved for broadcast and system needs
SUBNET_V4_RANGE = slice(2, -2)


def assign_free_ipv4_compute(virtance_id):
    virtance = Virtance.objects.select_related("compute", "region").get(id=virtance_id, is_deleted=False)
    virtances = Virtance.objects.filter(compute=virtance.compute, is_deleted=False)
    network = Network.objects.get(
        region=virtance.region, version=Network.IPv4, type=Network.COMPUTE, is_active=True, is_deleted=False
    )
    assigned_ipv4_compute = IPAddress.objects.filter(network=network, virtance__in=virtances)
    ipaddrs = list(IPv4Network(f"{network.cidr}/{network.netmask}"))[SUBNET_V4_RANGE]
    for ipaddr in random.sample(ipaddrs, k=len(ipaddrs)):
        if str(ipaddr) not in [ip.address for ip in assigned_ipv4_compute]:
            ipaddr = IPAddress.objects.create(network=network, address=str(ipaddr), virtance=virtance)
            return ipaddr.id
    return None


def assign_free_ipv4_public(virtance_id, is_float=False):
    virtance = Virtance.objects.select_related("region").get(id=virtance_id, is_deleted=False)
    networks = Network.objects.filter(
        region=virtance.region, version=Network.IPv4, type=Network.PUBLIC, is_active=True, is_deleted=False
    )
    for net in networks:
        ipaddrs = list(IPv4Network(f"{net.cidr}/{net.netmask}"))[SUBNET_V4_RANGE]
        for ipaddr in random.sample(ipaddrs, k=len(ipaddrs)):
            if not IPAddress.objects.filter(network=net, address=str(ipaddr)).exists():
                ipaddr = IPAddress.objects.create(
                    network=net, address=str(ipaddr), virtance=virtance, is_float=is_float
                )
                return ipaddr.id
    return None


def assign_free_ipv4_private(virtance_id):
    virtance = Virtance.objects.select_related("region").get(id=virtance_id, is_deleted=False)
    networks = Network.objects.filter(
        region=virtance.region, version=Network.IPv4, type=Network.PRIVATE, is_active=True, is_deleted=False
    )
    for net in networks:
        ipaddrs = list(IPv4Network(f"{net.cidr}/{net.netmask}"))[SUBNET_V4_RANGE]
        for ipaddr in random.sample(ipaddrs, k=len(ipaddrs)):
            if not IPAddress.objects.filter(network=net, address=str(ipaddr)).exists():
                ipaddr = IPAddress.objects.create(network=net, address=str(ipaddr), virtance=virtance)
                return ipaddr.id
    return None


def assign_free_ipv6_public(virtance_id):
    # Lock the virtance and its candidate pools together. This keeps retries
    # idempotent and prevents two concurrent create requests from leasing the
    # same IPv6 address without ever expanding a /64 or larger prefix.
    with transaction.atomic():
        virtance = Virtance.objects.select_for_update().select_related("region").get(id=virtance_id, is_deleted=False)
        existing = IPAddress.objects.filter(
            virtance=virtance,
            is_float=False,
            network__type=Network.PUBLIC,
            network__version=Network.IPv6,
        ).first()
        if existing is not None:
            return existing.id

        networks = Network.objects.select_for_update().filter(
            region=virtance.region,
            version=Network.IPv6,
            type=Network.PUBLIC,
            is_active=True,
            is_deleted=False,
        ).order_by("id")
        for net in networks:
            try:
                subnet = ipv6_network(net.cidr, net.netmask)
                assigned_addresses = (
                    IPAddress.objects.select_for_update().filter(network=net).values_list("address", flat=True)
                )
                address = first_assignable_ipv6_address(subnet, assigned_addresses, gateway=net.gateway)
            except ValueError:
                continue

            if address is not None:
                ipaddr = IPAddress.objects.create(network=net, address=str(address), virtance=virtance)
                return ipaddr.id
    return None


def ipv6_public_network_config(ipaddr):
    return ipv6_network_config(
        ipaddr.address,
        ipaddr.network.cidr,
        ipaddr.network.netmask,
        ipaddr.network.gateway,
        dns_servers=(ipaddr.network.dns1, ipaddr.network.dns2),
    )
