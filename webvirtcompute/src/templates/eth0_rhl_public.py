desc = "RedHat based eth0 interface file template for public cloud"
data = """DEVICE=eth0
TYPE=Ethernet
ONBOOT=yes
BOOTPROTO=none
IPADDR1={{ ipv4public.address }}
PREFIX1={{ ipv4public.prefix }}
GATEWAY1={{ ipv4public.gateway }}
IPADDR2={{ ipv4compute.address }}
PREFIX2={{ ipv4compute.prefix }}
DNS1={{ ipv4public.dns1 }}
DNS2={{ ipv4public.dns2 }}
{% if ipv6public %}
IPV6INIT=yes
IPV6_AUTOCONF=no
IPV6ADDR={{ ipv6public.address }}/{{ ipv6public.prefix }}
IPV6_DEFAULTGW={{ ipv6public.gateway }}{% if ipv6public.gateway_is_link_local %}%eth0{% endif %}
{% for dns_server in ipv6public.dns_servers %}
DNS{{ loop.index + 2 }}={{ dns_server }}
{% endfor %}
{% endif %}"""
