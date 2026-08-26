#!/usr/bin/env python3
"""Regression coverage for IPv6 network normalization and allocation."""

import sys
import unittest
from ipaddress import IPv6Address
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPOSITORY_ROOT / "webvirtbackend"))

from network.ipv6 import first_assignable_ipv6_address, ipv6_network, ipv6_network_config, ipv6_prefix_length


class IPv6NetworkTests(unittest.TestCase):
    def test_accepts_non_nibble_prefix_stored_as_netmask(self):
        network = ipv6_network("2a14:7c0:1002:10f8::1", "ffff:ffff:fc00::")

        self.assertEqual("2a14:7c0:1000::/38", str(network))
        self.assertEqual(38, ipv6_prefix_length("ffff:ffff:fc00::"))

    def test_rejects_non_contiguous_netmask(self):
        with self.assertRaises(ValueError):
            ipv6_prefix_length("ffff:ffff:ff00:ffff::")

    def test_finds_first_free_address_without_expanding_a_64(self):
        network = ipv6_network("2001:db8:1::", "ffff:ffff:ffff:ffff::")
        address = first_assignable_ipv6_address(
            network,
            ["2001:db8:1::2", "2001:db8:1::4"],
            gateway="2001:db8:1::1",
        )

        self.assertEqual(IPv6Address("2001:db8:1::3"), address)

    def test_small_prefixes_do_not_claim_the_network_or_gateway(self):
        cases = (
            ("2001:db8:2::", "ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffe"),
            ("2001:db8:2::", "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"),
        )
        for cidr, netmask in cases:
            network = ipv6_network(cidr, netmask)
            self.assertIsNone(first_assignable_ipv6_address(network, [], gateway=str(network.network_address + 1)))

    def test_configuration_keeps_link_local_gateway_and_ipv6_dns(self):
        config = ipv6_network_config(
            "2001:db8:3::2",
            "2001:db8:3::",
            "ffff:ffff:ffff:ffff::",
            "fe80::1",
            dns_servers=("2606:4700:4700::1111", "0.0.0.0", "2606:4700:4700::1001"),
        )

        self.assertEqual(64, config["prefix"])
        self.assertEqual("fe80::1", config["gateway"])
        self.assertTrue(config["gateway_is_link_local"])
        self.assertEqual(["2606:4700:4700::1111", "2606:4700:4700::1001"], config["dns_servers"])

    def test_configuration_omits_unusable_ipv6_dns_servers(self):
        config = ipv6_network_config(
            "2001:db8:4::2",
            "2001:db8:4::",
            "64",
            "2001:db8:4::1",
            dns_servers=("::", "::1", "ff02::1", "fe80::1"),
        )

        self.assertFalse(config["gateway_is_link_local"])
        self.assertEqual([], config["dns_servers"])

    def test_allocation_ignores_wrong_family_historic_records(self):
        network = ipv6_network("2001:db8:5::", "64")

        address = first_assignable_ipv6_address(network, ["192.0.2.1"], gateway="2001:db8:5::1")

        self.assertEqual(IPv6Address("2001:db8:5::2"), address)


if __name__ == "__main__":
    unittest.main()
