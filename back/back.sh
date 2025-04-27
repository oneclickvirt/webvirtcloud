#!/bin/bash
# https://github.com/oneclickvirt/webvirtcloud
# 2025.04.20

    ubuntu_version=$(lsb_release -rs)
    os_name=$(lsb_release -si)
    if [ "$os_name" == "Ubuntu" ]; then
        if dpkg --compare-versions "$ubuntu_version" le "22.04"; then
            echo "Detected Ubuntu $ubuntu_version, patching conf/requirements.txt..."
            sed -i 's/^django_bootstrap5==[0-9.]*$/django_bootstrap5==24.3/' conf/requirements.txt
            sed -i 's/^django-bootstrap-icons==[0-9.]*$/django-bootstrap-icons==0.8.7/' conf/requirements.txt
            sed -i 's/^django-qr-code==[0-9.]*$/django-qr-code==4.0.1/' conf/requirements.txt
            sed -i 's/^django-auth-ldap==[0-9.]*$/django-auth-ldap==5.0.0/' conf/requirements.txt
            sed -i 's/^qrcode==[0-9.]*$/qrcode==7.4.2/' conf/requirements.txt
            sed -i 's/^whitenoise==[0-9.]*$/whitenoise==6.7.0/' conf/requirements.txt
            sed -i 's/^zipp==[0-9.]*$/zipp==3.20.2/' conf/requirements.txt
            source venv/bin/activate
            pip install -r conf/requirements.txt
            # https://github.com/retspen/webvirtcloud/issues/641
            sed -i 's/^import zoneinfo$/from backports.zoneinfo import ZoneInfo as zoneinfo/' /srv/webvirtcloud/venv/lib/python3.8/site-packages/qr_code/qrcode/utils.py
        else
            echo "Ubuntu $ubuntu_version detected, no patch needed."
            source venv/bin/activate
            pip install -r conf/requirements.txt
        fi
    else
        source venv/bin/activate
        pip install -r conf/requirements.txt
    fi

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

############## 单网卡

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
    systemctl restart NetworkManager
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

#################### VETH

create_veth_and_setup_cron() {
    SCRIPT_DIR="/usr/local/bin"
    SCRIPT_FILE="${SCRIPT_DIR}/setup-veth.sh"
    echo "创建设置 veth 接口的脚本..."
    cat << 'EOF' > "${SCRIPT_FILE}"
#!/bin/bash
ip link add veth-br-ext type veth peer name veth-br-int
ip link set veth-br-ext master br-ext
ip link set veth-br-int master br-int
ip link set veth-br-ext up
ip link set veth-br-int up
nmcli device set veth-br-ext managed yes
nmcli device set veth-br-int managed yes
EOF
    chmod +x "${SCRIPT_FILE}"
    echo "添加定时任务 @reboot..."
    (crontab -l 2>/dev/null; echo "@reboot ${SCRIPT_FILE}") | crontab -
    echo "当前 crontab 设置："
    crontab -l
}

rebuild_network() {
    # 获取物理网卡
    interface=$(ls /sys/class/net/ | grep -E '^(eth|en|eno|ens|enp)' | grep -v lo | head -n 1)
    ipv4_address=$(ip addr show "$interface" | awk '/inet / {print $2}' | head -n 1)
    ipv4_gateway=$(ip route | awk '/default/ {print $3}' | head -n 1)
    echo "检测到的主网卡接口: $interface"
    echo "IPv4 地址: $ipv4_address"
    echo "IPv4 网关: $ipv4_gateway"
    # 删除旧配置
    nmcli connection delete br-ext 2>/dev/null || true
    nmcli connection delete br-int 2>/dev/null || true
    nmcli connection delete "${interface}" 2>/dev/null || true
    # 创建 br-ext 网桥并绑定物理网卡
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
    # 创建 br-int 私网桥
    nmcli connection add type bridge ifname br-int con-name br-int
    nmcli connection modify br-int ipv4.addresses 10.10.10.1/24
    nmcli connection modify br-int ipv4.method manual ipv4.dns 8.8.8.8,1.1.1.1
    nmcli connection modify br-int bridge.stp no
    nmcli connection modify br-int 802-3-ethernet.mtu 1500
    nmcli connection up br-int
    # 创建 veth 对连接两个网桥
    ip link add veth-br-ext type veth peer name veth-br-int
    ip link set veth-br-ext master br-ext
    ip link set veth-br-int master br-int
    ip link set veth-br-ext up
    ip link set veth-br-int up
    # 启用 IP 转发
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-sysctl.conf
    sysctl -p
    nmcli device set veth-br-ext managed yes
    nmcli device set veth-br-int managed yes
    sleep 3
    echo "=== 网络状态 ==="
    nmcli device status
    ip a
}

firewall_setup() {
    systemctl enable --now firewalld
    # 桥接网络允许转发
    firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 1 -m physdev --physdev-is-bridged -j ACCEPT
    # br-int -> br-ext 的 NAT 转发（私网访问外网）
    firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.10.10.0/24 -o br-ext -j MASQUERADE
    # Floating IP 功能
    firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -d 10.255.0.0/16 -j MASQUERADE
    # 仅在源地址不是 169.254.0.0/16 时进行 DNAT 重定向
    firewall-cmd --permanent --direct --add-rule ipv4 nat PREROUTING 0 -i br-ext -d 169.254.169.254 -p tcp --dport 80 -m iprange ! --src-range 169.254.0.0-169.254.255.255 -j DNAT --to-destination "$WEBVIRTBACKED_IP":80
    # 信任 zone 设置（接口和 metadata 地址）
    firewall-cmd --permanent --zone=trusted --add-source=169.254.0.0/16
    firewall-cmd --permanent --zone=trusted --add-interface=br-ext
    firewall-cmd --permanent --zone=trusted --add-interface=br-int
    # 放通所有 TCP/UDP 端口
    firewall-cmd --zone=public --add-port=1-65535/tcp --permanent
    firewall-cmd --zone=public --add-port=1-65535/udp --permanent
    firewall-cmd --reload
}
