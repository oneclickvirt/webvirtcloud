#!/bin/bash
# https://github.com/oneclickvirt/webvirtcloud
# 2025.04.20

install_with_debian() {
    sudo apt install -y network-manager firewalld
    CONF_FILE="/etc/NetworkManager/NetworkManager.conf"
    BACKUP_FILE="${CONF_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
    if [ ! -f "$CONF_FILE" ]; then
        {
            echo "[main]"
            echo "plugins=ifupdown,keyfile"
            echo "[ifupdown]"
            echo "managed=true"
        } | sudo tee "$CONF_FILE" > /dev/null
        return 0
    fi
    sudo cp "$CONF_FILE" "$BACKUP_FILE"
    if grep -q "^\[ifupdown\]" "$CONF_FILE"; then
        if grep -q "^\s*managed=" "$CONF_FILE"; then
            sudo sed -i '/^\[ifupdown\]/,/^\[.*\]/ s/^\s*managed=.*/managed=true/' "$CONF_FILE"
        else
            sudo sed -i '/^\[ifupdown\]/ a managed=true' "$CONF_FILE"
        fi
    else
        {
            echo ""
            echo "[ifupdown]"
            echo "managed=true"
        } | sudo tee -a "$CONF_FILE" > /dev/null
    fi
    # if ! grep -q "^\[main\]" "$CONF_FILE"; then
    #     {
    #         echo "[main]"
    #         echo "plugins=ifupdown,keyfile"
    #     } | sudo tee -a "$CONF_FILE" > /dev/null
    # elif ! grep -q "^\s*plugins=.*ifupdown.*keyfile.*" "$CONF_FILE"; then
    #     sudo sed -i '/^\[main\]/,/^\[.*\]/ s/^\s*plugins=.*/plugins=ifupdown,keyfile/' "$CONF_FILE"
    # fi
}

rebuild_network() {
    interface=$(ls /sys/class/net/ | grep -E '^(eth|en|eno|ens|enp)' | grep -v lo | head -n 1)
    ipv4_address=$(ip addr show "$interface" | awk '/inet / {print $2}' | head -n 1)
    ipv4_gateway=$(ip route | awk '/default/ {print $3}' | head -n 1)
    echo "检测到的主网卡接口: $interface"
    echo "IPv4 地址: $ipv4_address"
    echo "IPv4 网关: $ipv4_gateway"
    # 旧配置删除
    nmcli connection delete br-ext 2>/dev/null || true
    nmcli connection delete br-int 2>/dev/null || true
    nmcli connection delete "${interface}" 2>/dev/null || true
    # 公网网桥创建
    nmcli connection add type bridge ifname br-ext con-name br-ext
    nmcli connection add type bridge-slave ifname "${interface}" con-name "${interface}" master br-ext
    nmcli connection modify br-ext +ipv4.addresses 10.255.0.1/16
    nmcli connection modify br-ext +ipv4.addresses 169.254.169.254/16
    nmcli connection modify br-ext +ipv4.addresses "${ipv4_address}"
    nmcli connection modify br-ext ipv4.gateway "${ipv4_gateway}"
    nmcli connection modify br-ext ipv4.method manual ipv4.dns 8.8.8.8,1.1.1.1
    nmcli connection modify br-ext bridge.stp no
    nmcli connection modify br-ext 802-3-ethernet.mtu 1500
    nmcli connection up br-ext
    # 内网网桥创建 由于单网卡，仅内部通信
    nmcli connection add type bridge ifname br-int con-name br-int ipv4.method disabled ipv6.method ignore
    nmcli connection modify br-int bridge.stp no
    nmcli connection modify br-int 802-3-ethernet.mtu 1500
    nmcli connection up br-int
    sleep 3
    echo "=== 网络状态 ==="
    nmcli device status
}

firewall_setup() {
    systemctl enable --now firewalld
    firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 1 -m physdev --physdev-is-bridged -j ACCEPT # Bridge traffic rule
    firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -d 10.255.0.0/16 -j MASQUERADE # Floating IP feature rule
    firewall-cmd --permanent --direct --add-rule ipv4 nat PREROUTING 0 -i br-ext '!' -s 169.254.0.0/16 -d 169.254.169.254 -p tcp -m tcp --dport 80 -j DNAT --to-destination $WEBVIRTBACKED_IP:80 # CLoud-init metadata service rule
    firewall-cmd --permanent --zone=trusted --add-source=169.254.0.0/16 # Move cloud-init metadata service to trusted zone
    firewall-cmd --permanent --zone=trusted --add-interface=br-ext # Move br-ext to trusted zone
    firewall-cmd --permanent --zone=trusted --add-interface=br-int # Move br-int to trusted zone
    firewall-cmd --zone=public --add-port=1-65535/tcp --permanent
    firewall-cmd --zone=public --add-port=1-65535/udp --permanent
    firewall-cmd --reload
}
