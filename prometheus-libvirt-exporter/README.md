# The original project has been deleted. This is only a personal archive.

# Prometheus libvirt exporter

This is a simple libvirt exporter for prometheus. It is written in python and uses the libvirt python bindings to get the metrics.

# Requirements

- python3.6 or higher
- libvirt
- prometheus_client

# How to run

```bash
pip install -r requirements.txt
python3 prometheus-libvirt-exporter.py
```

# Configuration

The exporter can be configured using the following environment variables:

- `-p` or `--port`: The port the exporter will listen on. Default: `9177`
- `-u` or `--uri`: The URI to connect to libvirt. Default: `qemu:///system`
- `-a` or `--address`: The address the exporter will listen on. Default: `localhost`

# Metrics
The following metrics/labels are being exported:

```text
# HELP libvirt_up Whether scraping libvirt's metrics was successful
# TYPE libvirt_up gauge
libvirt_up 1.0
# HELP libvirt_domain_info_state Current state 0 - inactive; 1 - active, 2 - paused
# TYPE libvirt_domain_info_state gauge
libvirt_domain_info_state{domain="instance-911"} 1.0
# HELP libvirt_domain_info_cpu_time_total CPU time spent by the domain in nanoseconds
# TYPE libvirt_domain_info_cpu_time_total counter
libvirt_domain_info_cpu_time_total{domain="instance-911"} 1.52068273e+011
# HELP libvirt_domain_info_cpu_time_created CPU time spent by the domain in nanoseconds
# TYPE libvirt_domain_info_cpu_time_created gauge
libvirt_domain_info_cpu_time_created{domain="instance-911"} 1.7121748834579952e+09
# HELP libvirt_domain_info_cpu_time_user_total CPU time spent by the domain in user mode
# TYPE libvirt_domain_info_cpu_time_user_total counter
libvirt_domain_info_cpu_time_user_total{domain="instance-911"} 1.19966803e+011
# HELP libvirt_domain_info_cpu_time_user_created CPU time spent by the domain in user mode
# TYPE libvirt_domain_info_cpu_time_user_created gauge
libvirt_domain_info_cpu_time_user_created{domain="instance-911"} 1.7121748834580069e+09
# HELP libvirt_domain_info_cpu_time_system_total CPU time spent by the domain in system mode
# TYPE libvirt_domain_info_cpu_time_system_total counter
libvirt_domain_info_cpu_time_system_total{domain="instance-911"} 3.2101467e+010
# HELP libvirt_domain_info_cpu_time_system_created CPU time spent by the domain in system mode
# TYPE libvirt_domain_info_cpu_time_system_created gauge
libvirt_domain_info_cpu_time_system_created{domain="instance-911"} 1.712174883458012e+09
# HELP libvirt_domain_info_memory_actual Actual memory usage of the domain
# TYPE libvirt_domain_info_memory_actual gauge
libvirt_domain_info_memory_actual{domain="instance-911"} 8.388608e+06
# HELP libvirt_domain_info_memory_usable Usable memory of the domain
# TYPE libvirt_domain_info_memory_usable gauge
libvirt_domain_info_memory_usable{domain="instance-911"} 7.855912e+06
# HELP libvirt_domain_info_memory_unused Unused memory of the domain
# TYPE libvirt_domain_info_memory_unused gauge
libvirt_domain_info_memory_unused{domain="instance-911"} 7.959572e+06
# HELP libvirt_domain_info_memory_available Available memory of the domain
# TYPE libvirt_domain_info_memory_available gauge
libvirt_domain_info_memory_available{domain="instance-911"} 8.150676e+06
# HELP libvirt_domain_info_block_read_bytes_total Bytes read per second
# TYPE libvirt_domain_info_block_read_bytes_total counter
libvirt_domain_info_block_read_bytes_total{dev="vda",domain="instance-911"} 3.382222848e+09
# HELP libvirt_domain_info_block_read_bytes_created Bytes read per second
# TYPE libvirt_domain_info_block_read_bytes_created gauge
libvirt_domain_info_block_read_bytes_created{dev="vda",domain="instance-911"} 1.7121748834624734e+09
# HELP libvirt_domain_info_block_read_requests_total Read requests per second
# TYPE libvirt_domain_info_block_read_requests_total counter
libvirt_domain_info_block_read_requests_total{dev="vda",domain="instance-911"} 62848.0
# HELP libvirt_domain_info_block_read_requests_created Read requests per second
# TYPE libvirt_domain_info_block_read_requests_created gauge
libvirt_domain_info_block_read_requests_created{dev="vda",domain="instance-911"} 1.7121748834624846e+09
# HELP libvirt_domain_info_block_write_bytes_total Bytes written per second
# TYPE libvirt_domain_info_block_write_bytes_total counter
libvirt_domain_info_block_write_bytes_total{dev="vda",domain="instance-911"} 9.54433536e+08
# HELP libvirt_domain_info_block_write_bytes_created Bytes written per second
# TYPE libvirt_domain_info_block_write_bytes_created gauge
libvirt_domain_info_block_write_bytes_created{dev="vda",domain="instance-911"} 1.7121748834624906e+09
# HELP libvirt_domain_info_block_write_requests_total Write requests per second
# TYPE libvirt_domain_info_block_write_requests_total counter
libvirt_domain_info_block_write_requests_total{dev="vda",domain="instance-911"} 3776.0
# HELP libvirt_domain_info_block_write_requests_created Write requests per second
# TYPE libvirt_domain_info_block_write_requests_created gauge
libvirt_domain_info_block_write_requests_created{dev="vda",domain="instance-911"} 1.7121748834624956e+09
# HELP libvirt_domain_info_net_rx_bytes_total Bytes received per second
# TYPE libvirt_domain_info_net_rx_bytes_total counter
libvirt_domain_info_net_rx_bytes_total{dev="vnet0",domain="instance-911"} 511694.0
libvirt_domain_info_net_rx_bytes_total{dev="vnet1",domain="instance-911"} 29664.0
libvirt_domain_info_net_rx_bytes_total{dev="vnet2",domain="instance-911"} 29664.0
libvirt_domain_info_net_rx_bytes_total{dev="vnet3",domain="instance-911"} 29456.0
# HELP libvirt_domain_info_net_rx_bytes_created Bytes received per second
# TYPE libvirt_domain_info_net_rx_bytes_created gauge
libvirt_domain_info_net_rx_bytes_created{dev="vnet0",domain="instance-911"} 1.712174883462706e+09
libvirt_domain_info_net_rx_bytes_created{dev="vnet1",domain="instance-911"} 1.7121748834628267e+09
libvirt_domain_info_net_rx_bytes_created{dev="vnet2",domain="instance-911"} 1.7121748834629207e+09
libvirt_domain_info_net_rx_bytes_created{dev="vnet3",domain="instance-911"} 1.712174883463054e+09
# HELP libvirt_domain_info_net_rx_packets_total Packets received per second
# TYPE libvirt_domain_info_net_rx_packets_total counter
libvirt_domain_info_net_rx_packets_total{dev="vnet0",domain="instance-911"} 3241.0
libvirt_domain_info_net_rx_packets_total{dev="vnet1",domain="instance-911"} 528.0
libvirt_domain_info_net_rx_packets_total{dev="vnet2",domain="instance-911"} 528.0
libvirt_domain_info_net_rx_packets_total{dev="vnet3",domain="instance-911"} 524.0
# HELP libvirt_domain_info_net_rx_packets_created Packets received per second
# TYPE libvirt_domain_info_net_rx_packets_created gauge
libvirt_domain_info_net_rx_packets_created{dev="vnet0",domain="instance-911"} 1.7121748834627166e+09
libvirt_domain_info_net_rx_packets_created{dev="vnet1",domain="instance-911"} 1.7121748834628315e+09
libvirt_domain_info_net_rx_packets_created{dev="vnet2",domain="instance-911"} 1.7121748834629252e+09
libvirt_domain_info_net_rx_packets_created{dev="vnet3",domain="instance-911"} 1.712174883463059e+09
# HELP libvirt_domain_info_net_tx_bytes_total Bytes transmitted per second
# TYPE libvirt_domain_info_net_tx_bytes_total counter
libvirt_domain_info_net_tx_bytes_total{dev="vnet0",domain="instance-911"} 616888.0
libvirt_domain_info_net_tx_bytes_total{dev="vnet1",domain="instance-911"} 8496.0
libvirt_domain_info_net_tx_bytes_total{dev="vnet2",domain="instance-911"} 9504.0
libvirt_domain_info_net_tx_bytes_total{dev="vnet3",domain="instance-911"} 6368.0
# HELP libvirt_domain_info_net_tx_bytes_created Bytes transmitted per second
# TYPE libvirt_domain_info_net_tx_bytes_created gauge
libvirt_domain_info_net_tx_bytes_created{dev="vnet0",domain="instance-911"} 1.7121748834627228e+09
libvirt_domain_info_net_tx_bytes_created{dev="vnet1",domain="instance-911"} 1.712174883462836e+09
libvirt_domain_info_net_tx_bytes_created{dev="vnet2",domain="instance-911"} 1.7121748834629297e+09
libvirt_domain_info_net_tx_bytes_created{dev="vnet3",domain="instance-911"} 1.7121748834630632e+09
# HELP libvirt_domain_info_net_tx_packets_total Packets transmitted per second
# TYPE libvirt_domain_info_net_tx_packets_total counter
libvirt_domain_info_net_tx_packets_total{dev="vnet0",domain="instance-911"} 3560.0
libvirt_domain_info_net_tx_packets_total{dev="vnet1",domain="instance-911"} 120.0
libvirt_domain_info_net_tx_packets_total{dev="vnet2",domain="instance-911"} 144.0
libvirt_domain_info_net_tx_packets_total{dev="vnet3",domain="instance-911"} 80.0
# HELP libvirt_domain_info_net_tx_packets_created Packets transmitted per second
# TYPE libvirt_domain_info_net_tx_packets_created gauge
libvirt_domain_info_net_tx_packets_created{dev="vnet0",domain="instance-911"} 1.712174883462728e+09
libvirt_domain_info_net_tx_packets_created{dev="vnet1",domain="instance-911"} 1.7121748834628403e+09
libvirt_domain_info_net_tx_packets_created{dev="vnet2",domain="instance-911"} 1.7121748834629338e+09
libvirt_domain_info_net_tx_packets_created{dev="vnet3",domain="instance-911"} 1.7121748834630675e+09
# HELP libvirt_domain_info_vcpu_time_total CPU time used by the domain in nanoseconds
# TYPE libvirt_domain_info_vcpu_time_total counter
```
