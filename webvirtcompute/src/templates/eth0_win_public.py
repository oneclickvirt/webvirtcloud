desc = "Windows based eth0 interface file template for public cloud"
data = """@echo off
echo  ##############################################################################
echo  #                                                                            #
echo  #                            FIRST BOOT SETUP                                #
echo  #                                                                            #
echo  #         Please don't close the window it will closed automatically         #
echo  #                                                                            #
echo  ##############################################################################

REM IPv4 Public
netsh interface ipv4 delete dnsservers "Ethernet" all
netsh interface ipv4 reset
netsh interface ipv4 set address "Ethernet" static {{ ipv4public.address }} {{ ipv4public.netmask }} {{ ipv4public.gateway }}
netsh interface ipv4 add dnsservers "Ethernet" {{ ipv4public.dns1 }}
netsh interface ipv4 add dnsservers "Ethernet" {{ ipv4public.dns2 }} index=2

REM IPv4 Anchor
netsh interface ipv4 add address "Ethernet" {{ ipv4compute.address }} {{ ipv4compute.prefix }}
{% if ipv6public %}
REM IPv6 Public
netsh interface ipv6 delete dnsservers "Ethernet" all
netsh interface ipv6 reset
netsh interface ipv6 set address "Ethernet" {{ ipv6public.address }}/{{ ipv6public.prefix }}
netsh interface ipv6 add route ::/0 "Ethernet" {{ ipv6public.gateway }}
{% for dns_server in ipv6public.dns_servers %}
netsh interface ipv6 add dnsservers "Ethernet" {{ dns_server }} index={{ loop.index }}
{% endfor %}
{% endif %}"""
