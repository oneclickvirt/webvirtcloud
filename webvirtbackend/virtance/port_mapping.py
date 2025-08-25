import os
import subprocess
from typing import Dict, Optional, Tuple


def get_public_ip() -> Optional[str]:
    """获取公网IP地址"""
    try:
        # 尝试多种方法获取公网IP
        methods = [
            "curl -s ifconfig.me",
            "curl -s ipinfo.io/ip",
            "curl -s icanhazip.com",
            "dig +short myip.opendns.com @resolver1.opendns.com"
        ]
        
        for method in methods:
            try:
                result = subprocess.run(method.split(), capture_output=True, text=True, timeout=5)
                if result.returncode == 0 and result.stdout.strip():
                    ip = result.stdout.strip()
                    # 简单验证IP格式
                    if '.' in ip and len(ip.split('.')) == 4:
                        return ip
            except:
                continue
        return None
    except:
        return None


def read_port_mapping_file() -> Dict[str, Dict[str, any]]:
    """读取端口映射文件并返回映射信息"""
    mapping_file = "/etc/vm_port_mapping/mapping.txt"
    mapping_data = {}
    
    if not os.path.exists(mapping_file):
        return mapping_data
    
    try:
        with open(mapping_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    parts = line.split()
                    if len(parts) >= 6:
                        vm_name = parts[0]
                        vm_ip = parts[1]
                        mac_address = parts[2]
                        ssh_port = int(parts[3])
                        port_start = int(parts[4])
                        port_end = int(parts[5])
                        
                        mapping_data[vm_name] = {
                            'vm_ip': vm_ip,
                            'mac_address': mac_address,
                            'ssh_port': ssh_port,
                            'port_start': port_start,
                            'port_end': port_end
                        }
    except Exception as e:
        # 记录错误但不抛出异常
        pass
    
    return mapping_data


def get_vm_port_mapping(vm_name: str) -> Optional[Dict[str, any]]:
    """获取指定虚拟机的端口映射信息"""
    mapping_data = read_port_mapping_file()
    return mapping_data.get(vm_name)


def update_virtance_port_mapping(virtance):
    """更新虚拟机实例的端口映射信息"""
    mapping_info = get_vm_port_mapping(virtance.name)
    public_ip = get_public_ip()
    
    if mapping_info and public_ip:
        virtance.public_ip = public_ip
        virtance.ssh_port = mapping_info['ssh_port']
        virtance.port_range_start = mapping_info['port_start']
        virtance.port_range_end = mapping_info['port_end']
        virtance.save()
        return True
    return False