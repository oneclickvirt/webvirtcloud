"""IPv6 pool helpers shared by provisioning and network administration."""

from ipaddress import IPv4Address, IPv4Network, IPv6Address, IPv6Network, ip_address


def ipv6_prefix_length(netmask):
    """Return a prefix length for an IPv6 prefix or conventional netmask."""
    value = str(netmask).strip()
    if value.isdigit():
        prefix = int(value)
        if 0 <= prefix <= 128:
            return prefix
        raise ValueError("IPv6 prefix length must be between 0 and 128")

    mask = int(IPv6Address(value))
    bits = f"{mask:0128b}"
    if "01" in bits:
        raise ValueError("IPv6 netmask must contain contiguous leading bits")
    return bits.count("1")


def ipv6_network(cidr, netmask):
    """Build a normalized IPv6 network from legacy model field values."""
    return IPv6Network((str(cidr), ipv6_prefix_length(netmask)), strict=False)


def network_from_values(cidr, netmask):
    """Build a normalized IPv4 or IPv6 network from model form values."""
    address = ip_address(str(cidr))
    if address.version == 6:
        return ipv6_network(address, netmask)
    return IPv4Network((IPv4Address(str(address)), str(netmask)), strict=False)


def first_assignable_ipv6_address(network, assigned_addresses, gateway=None):
    """Find a free IPv6 address without expanding a possibly huge prefix."""
    if network.num_addresses < 3:
        return None

    occupied = {int(network.network_address)}
    if gateway:
        gateway_address = IPv6Address(str(gateway))
        if gateway_address in network:
            occupied.add(int(gateway_address))

    for raw_address in assigned_addresses:
        try:
            address = IPv6Address(str(raw_address))
        except ValueError:
            # Historic data can contain an address from the wrong family. It
            # cannot occupy an IPv6 pool, so do not let it block allocation.
            continue
        if address in network:
            occupied.add(int(address))

    candidate = int(network.network_address) + 1
    last_address = int(network.broadcast_address)
    for address in sorted(occupied):
        if address < candidate:
            continue
        if address > candidate:
            return IPv6Address(candidate)
        candidate += 1
        if candidate > last_address:
            return None

    return IPv6Address(candidate) if candidate <= last_address else None


def ipv6_network_config(address, cidr, netmask, gateway, dns_servers=()):
    """Normalize one assigned IPv6 address for the compute service contract."""
    network = ipv6_network(cidr, netmask)
    host_address = IPv6Address(str(address))
    gateway_address = IPv6Address(str(gateway))
    if host_address not in network:
        raise ValueError(f"IPv6 address {host_address} is outside {network}")
    if gateway_address.is_unspecified or gateway_address.is_multicast:
        raise ValueError(f"IPv6 gateway {gateway_address} is not usable")
    if not gateway_address.is_link_local and gateway_address not in network:
        raise ValueError(f"IPv6 gateway {gateway_address} is outside {network}")

    valid_dns_servers = []
    for raw_server in dns_servers:
        if not raw_server:
            continue
        try:
            server = IPv6Address(str(raw_server))
        except ValueError:
            continue
        if server.is_unspecified or server.is_loopback or server.is_multicast or server.is_link_local:
            continue
        if server in valid_dns_servers:
            continue
        valid_dns_servers.append(server)

    return {
        "address": str(host_address),
        "prefix": network.prefixlen,
        "gateway": str(gateway_address),
        "gateway_is_link_local": gateway_address.is_link_local,
        "dns_servers": [str(server) for server in valid_dns_servers],
    }
