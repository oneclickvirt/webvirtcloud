#!/usr/bin/env python

import time
import libvirt
from xml.dom import minidom
from optparse import OptionParser
from prometheus_client import start_http_server, Gauge, Counter


# Initialize Prometheus metrics
label = ["domain"]
labels = ["dev", "domain"]

# Up metric
libvirt_up = Gauge(
    "libvirt_up", 
    "Whether scraping libvirt's metrics was successful"
)

# Domain stats
libvirt_domain_info_state = Gauge(
    "libvirt_domain_info_state",
    "Current state 0 - inactive; 1 - active, 2 - paused",
    label,
)

# vCPU numbers
libvirt_domain_info_vcpu_num = Gauge(
    "libvirt_domain_info_vcpu_num",
    "Number of virtual CPUs for the domain",
    label,
)

# vCPU time
libvirt_domain_info_vcpu_time = Gauge(
    "libvirt_domain_info_vcpu_time",
    "CPU time spent by the domain in nanoseconds",
    label,
)

# CPU stats
libvirt_domain_info_cpu_time = Gauge(
    "libvirt_domain_info_cpu_time",
    "CPU time spent by the domain in nanoseconds",
    label,
)
libvirt_domain_info_cpu_time_user = Gauge(
    "libvirt_domain_info_cpu_time_user",
    "CPU time spent by the domain in user mode",
    label,
)
libvirt_domain_info_cpu_time_system = Gauge(
    "libvirt_domain_info_cpu_time_system",
    "CPU time spent by the domain in system mode",
    label,
)

# Memory stats
libvirt_domain_info_memory_actual = Gauge(
    "libvirt_domain_info_memory_actual", 
    "Actual memory of the domain", 
    label
)
libvirt_domain_info_memory_usable = Gauge(
    "libvirt_domain_info_memory_usable", 
    "Usable memory of the domain", 
    label
)
libvirt_domain_info_memory_unused = Gauge(
    "libvirt_domain_info_memory_unused", 
    "Unused memory of the domain", 
    label
)
libvirt_domain_info_memory_available = Gauge(
    "libvirt_domain_info_memory_available", 
    "Available memory of the domain", 
    label
)

# Block stats
libvirt_domain_info_block_read_bytes = Gauge(
    "libvirt_domain_info_block_read_bytes", 
    "Bytes read per second", 
    labels
)
libvirt_domain_info_block_read_requests = Gauge(
    "libvirt_domain_info_block_read_requests", 
    "Read requests per second", 
    labels
)
libvirt_domain_info_block_write_bytes = Gauge(
    "libvirt_domain_info_block_write_bytes", 
    "Bytes written per second", 
    labels
)
libvirt_domain_info_block_write_requests = Gauge(
    "libvirt_domain_info_block_write_requests", 
    "Write requests per second", 
    labels
)

# Network stats
libvirt_domain_info_net_rx_bytes = Gauge(
    "libvirt_domain_info_net_rx_bytes", 
    "Bytes received per second", 
    labels
)
libvirt_domain_info_net_rx_packets = Gauge(
    "libvirt_domain_info_net_rx_packets", 
    "Packets received per second", 
    labels
)
libvirt_domain_info_net_tx_bytes = Gauge(
    "libvirt_domain_info_net_tx_bytes", 
    "Bytes transmitted per second", 
    labels
)
libvirt_domain_info_net_tx_packets = Gauge(
    "libvirt_domain_info_net_tx_packets", 
    "Packets transmitted per second", 
    labels
)


def main(uri):
    conn = None

    try:
        conn = libvirt.open(uri)
    except libvirt.libvirtError as e:
        print("Failed to open connection to libvirt")

    if conn is None:
        libvirt_up.set(0)

    if conn is not None:
        libvirt_up.set(1)

        for dom in conn.listAllDomains(True):
            dom_xml = minidom.parseString(dom.XMLDesc(0))
            dom_name = dom.name()
            dom_state, dom_maxmem, dom_mem, dom_vcpus, dom_cputime = dom.info()

            # Get domain state
            libvirt_domain_info_state.labels(domain=dom_name).set(dom_state)

            # Get vCPU details
            libvirt_domain_info_vcpu_num.labels(domain=dom_name).set(dom_vcpus)

            # Get vCPU time
            libvirt_domain_info_vcpu_time.labels(domain=dom_name).set(dom_cputime)

            # Get CPU stats
            cpu_stats = dom.getCPUStats(True)[0]
            libvirt_domain_info_cpu_time.labels(domain=dom_name).set(
                cpu_stats.get("cpu_time", 0)
            )
            libvirt_domain_info_cpu_time_user.labels(domain=dom_name).set(
                cpu_stats.get("user_time", 0)
            )
            libvirt_domain_info_cpu_time_system.labels(domain=dom_name).set(
                cpu_stats.get("system_time", 0)
            )

            # Get memory stats
            memory_stats = dom.memoryStats()
            libvirt_domain_info_memory_actual.labels(domain=dom_name).set(
                memory_stats.get("actual", 0)
            )
            libvirt_domain_info_memory_usable.labels(domain=dom_name).set(
                memory_stats.get("usable", 0)
            )
            libvirt_domain_info_memory_unused.labels(domain=dom_name).set(
                memory_stats.get("unused", 0)
            )
            libvirt_domain_info_memory_available.labels(domain=dom_name).set(
                memory_stats.get("available", 0)
            )

            # Get block stats
            for diskType in dom_xml.getElementsByTagName("disk"):
                diskNodes = diskType.childNodes
                for diskNode in diskNodes:
                    if diskNode.nodeName == "target":
                        disk_dev = diskNode.getAttribute("dev")
                        rd_req, rd_byte, wr_req, wr_byte, _ = dom.blockStats(disk_dev)
                        libvirt_domain_info_block_read_bytes.labels(
                            dev=disk_dev, domain=dom_name
                        ).set(rd_byte)
                        libvirt_domain_info_block_read_requests.labels(
                            dev=disk_dev, domain=dom_name
                        ).set(rd_req)
                        libvirt_domain_info_block_write_bytes.labels(
                            dev=disk_dev, domain=dom_name
                        ).set(wr_byte)
                        libvirt_domain_info_block_write_requests.labels(
                            dev=disk_dev, domain=dom_name
                        ).set(wr_req)

            # Get network stats
            for ifaceType in dom_xml.getElementsByTagName("interface"):
                ifaceNodes = ifaceType.childNodes
                for ifaceNode in ifaceNodes:
                    if ifaceNode.nodeName == "target":
                        iface_dev = ifaceNode.getAttribute("dev")
                        (
                            rx_byte,
                            rx_pack,
                            rx_err,
                            rx_drop,
                            tx_byte,
                            tx_pack,
                            tx_err,
                            tx_drop,
                        ) = dom.interfaceStats(iface_dev)
                        libvirt_domain_info_net_rx_bytes.labels(
                            dev=iface_dev, domain=dom_name
                        ).set(rx_byte)
                        libvirt_domain_info_net_rx_packets.labels(
                            dev=iface_dev, domain=dom_name
                        ).set(rx_pack)
                        libvirt_domain_info_net_tx_bytes.labels(
                            dev=iface_dev, domain=dom_name
                        ).set(tx_byte)
                        libvirt_domain_info_net_tx_packets.labels(
                            dev=iface_dev, domain=dom_name
                        ).set(tx_pack)

        conn.close()


if __name__ == "__main__":
    parser = OptionParser()
    parser.add_option(
        "-p", "--port", type="int", dest="port", default=9177, help="Port to listen on"
    )
    parser.add_option(
        "-a", "--address", dest="address", default="localhost", help="Address to listen on"
    )
    parser.add_option(
        "-u", "--uri", dest="uri", default="qemu:///system", help="Libvirt URI"
    )
    (options, args) = parser.parse_args()

    start_http_server(options.port, options.address)

    print("Started Prometheus Libvirt Exporter")

    while True:
        main(options.uri)
        time.sleep(1)
