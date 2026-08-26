desc = "Debian based eth0 interfaces file template for public cloud"
data = """# This file describes the network interfaces available on your
# system and how to activate them. For more information, see
# interfaces(5).

# The loopback network interface
auto lo
iface lo inet loopback
    dns-nameservers {{ ipv4public.dns1 }} {{ ipv4public.dns2 }}
{% if ipv6public and ipv6public.dns_servers %}
    dns-nameservers {{ ipv6public.dns_servers | join(' ') }}
{% endif %}
# The primary network interface
auto eth0
iface eth0 inet static
    address {{ ipv4public.address }}
    netmask {{ ipv4public.netmask }}
    gateway {{ ipv4public.gateway }}

iface eth0 inet static
    address {{ ipv4compute.address }}
    netmask {{ ipv4compute.netmask }}

{% if ipv6public %}
iface eth0 inet6 static
    address {{ ipv6public.address }}
    netmask {{ ipv6public.prefix }}
{% if ipv6public.gateway_is_link_local %}
    up ip -6 route replace default via {{ ipv6public.gateway }} dev $IFACE
    down ip -6 route del default via {{ ipv6public.gateway }} dev $IFACE || true
{% else %}
    gateway {{ ipv6public.gateway }}
{% endif %}
{% endif %}"""
