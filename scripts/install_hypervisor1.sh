#!/bin/bash
# https://github.com/oneclickvirt/webvirtcloud
# 2025.04.17

###########################################
# 初始化和环境变量设置
###########################################

export DEBIAN_FRONTEND=noninteractive
cd /root >/dev/null 2>&1

# 设置UTF-8语言环境
setup_locale() {
    utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
    if [[ -z "$utf8_locale" ]]; then
        echo "No UTF-8 locale found"
    else
        export LC_ALL="$utf8_locale"
        export LANG="$utf8_locale"
        export LANGUAGE="$utf8_locale"
        echo "Locale set to $utf8_locale"
    fi
}

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" != "0" ]; then
        _red "This script must be run as root" 1>&2
        exit 1
    fi
}

# 系统变量初始化
init_system_vars() {
    temp_file_apt_fix="/tmp/apt_fix.txt"
    REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "arch")
    RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Arch")
    PACKAGE_UPDATE=("! apt-get update && apt-get --fix-broken install -y && apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "pacman -Sy")
    PACKAGE_INSTALL=("apt-get -y install" "apt-get -y install" "yum -y install" "yum -y install" "yum -y install" "pacman -Sy --noconfirm --needed")
    PACKAGE_REMOVE=("apt-get -y remove" "apt-get -y remove" "yum -y remove" "yum -y remove" "yum -y remove" "pacman -Rsc --noconfirm")
    PACKAGE_UNINSTALL=("apt-get -y autoremove" "apt-get -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove" "")
    CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')" "$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)")
    SYS="${CMD[0]}"
    [[ -n $SYS ]] || exit 1
    for ((int = 0; int < ${#REGEX[@]}; int++)); do
        if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
            SYSTEM="${RELEASE[int]}"
            [[ -n $SYSTEM ]] && break
        fi
    done
}

###########################################
# 辅助函数模块
###########################################

# 彩色输出函数
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }

# 检查并更新包管理器
check_update() {
    _yellow "更新包管理源"
    if command -v apt-get >/dev/null 2>&1; then
        distro=""
        codename=""
        is_archive=false
        # 识别系统版本
        if grep -qi debian /etc/os-release; then
            distro="debian"
            debian_ver=$(grep VERSION= /etc/os-release | grep -oE '[0-9]+' | head -n1)
            case "$debian_ver" in
                10) codename="buster" ; is_archive=true ;;
                9)  codename="stretch"; is_archive=true ;;
                8)  codename="jessie" ; is_archive=true ;;
            esac
        elif grep -qi ubuntu /etc/os-release; then
            distro="ubuntu"
            codename=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
            case "$codename" in
                xenial|bionic|eoan|groovy|artful|zesty|yakkety|vivid|wily|utopic)
                    is_archive=true
                    ;;
            esac
        fi
        # 如为归档版本，则替换为归档源
        if [[ "$is_archive" == true ]]; then
            _yellow "检测到归档系统：$distro $codename，请升级系统，正在退出程序"
             1
        fi
        # 更新包列表
        temp_file_apt_fix=$(mktemp)
        apt_update_output=$(apt-get update 2>&1)
        echo "$apt_update_output" >"$temp_file_apt_fix"
        # 修复 NO_PUBKEY 问题
        if grep -q 'NO_PUBKEY' "$temp_file_apt_fix"; then
            public_keys=$(grep -oE 'NO_PUBKEY [0-9A-F]+' "$temp_file_apt_fix" | awk '{ print $2 }')
            joined_keys=$(echo "$public_keys" | paste -sd " ")
            _yellow "缺少公钥: ${joined_keys}"
            apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ${joined_keys}
            apt-get update
            if [ $? -eq 0 ]; then
                _green "已修复"
            fi
        fi
        rm -f "$temp_file_apt_fix"
    else
        ${PACKAGE_UPDATE[int]}
    fi
}

# 检查IP是否为私有IPv4
is_private_ipv4() {
    local ip_address=$1
    local ip_parts
    if [[ -z $ip_address ]]; then
        return 0 # 输入为空
    fi
    IFS='.' read -r -a ip_parts <<<"$ip_address"
    # 检查IP地址是否符合内网IP地址的范围
    # 去除回环，RFC 1918，多播，RFC 6598地址
    if [[ ${ip_parts[0]} -eq 10 ]] ||
        [[ ${ip_parts[0]} -eq 172 && ${ip_parts[1]} -ge 16 && ${ip_parts[1]} -le 31 ]] ||
        [[ ${ip_parts[0]} -eq 192 && ${ip_parts[1]} -eq 168 ]] ||
        [[ ${ip_parts[0]} -eq 127 ]] ||
        [[ ${ip_parts[0]} -eq 0 ]] ||
        [[ ${ip_parts[0]} -eq 100 && ${ip_parts[1]} -ge 64 && ${ip_parts[1]} -le 127 ]] ||
        [[ ${ip_parts[0]} -ge 224 ]]; then
        return 0 # 是内网IP地址
    else
        return 1 # 不是内网IP地址
    fi
}

# 获取IPv4地址
check_ipv4() {
    IPV4=$(ip -4 addr show | grep global | awk '{print $2}' | cut -d '/' -f1 | head -n 1)
    if is_private_ipv4 "$IPV4"; then # 由于是内网IPv4地址，需要通过API获取外网地址
        IPV4=""
        local API_NET=("ipv4.ip.sb" "ipget.net" "ip.ping0.cc" "https://ip4.seeip.org" "https://api.my-ip.io/ip" "https://ipv4.icanhazip.com" "api.ipify.org")
        for p in "${API_NET[@]}"; do
            response=$(curl -s4m8 "$p")
            sleep 1
            if [ $? -eq 0 ] && ! echo "$response" | grep -q "error"; then
                IP_API="$p"
                IPV4="$response"
                break
            fi
        done
    fi
    export IPV4
}

###########################################
# 系统检测模块
###########################################

# 检查系统兼容性
check_system_compatibility() {
    if [[ "${RELEASE[int]}" != "Debian" && "${RELEASE[int]}" != "Ubuntu" && "${RELEASE[int]}" != "CentOS" ]]; then
        _red "不支持当前系统: ${RELEASE[int]}"
         1
    fi
}

###########################################
# 依赖安装模块
###########################################

# 安装基本依赖
install_basic_dependencies() {
    _yellow "安装基本依赖"
    check_update
    if ! command -v curl >/dev/null 2>&1; then
        _yellow "安装 curl"
        ${PACKAGE_INSTALL[int]} curl
    fi
    if ! command -v tar >/dev/null 2>&1; then
        _yellow "安装 tar"
        ${PACKAGE_INSTALL[int]} tar
    fi
    if ! command -v unzip >/dev/null 2>&1; then
        _yellow "安装 unzip"
        ${PACKAGE_INSTALL[int]} unzip
    fi
    if ! command -v git >/dev/null 2>&1; then
        _yellow "安装 git"
        ${PACKAGE_INSTALL[int]} git
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        _yellow "安装 sudo"
        ${PACKAGE_INSTALL[int]} sudo
    fi
    if ! command -v jq >/dev/null 2>&1; then
        _yellow "安装 jq"
        ${PACKAGE_INSTALL[int]} jq
    fi
    if ! command -v openssl >/dev/null 2>&1; then
        _yellow "安装 openssl"
        ${PACKAGE_INSTALL[int]} openssl
    fi
}

install_with_ubuntu() {
    sudo apt update
    sudo apt install -y network-manager firewalld
    FILE="/etc/netplan/00-installer-config.yaml"
    BACKUP_DIR="/etc/netplan"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/00-installer-config.yaml.bak_$TIMESTAMP"
    if [ ! -f "$FILE" ]; then
        cat <<EOF | sudo tee "$FILE"
network:
  version: 2
  renderer: NetworkManager
EOF
    else
        sudo cp "$FILE" "$BACKUP_FILE"
        echo -e "\nnetwork:\n  version: 2\n  renderer: NetworkManager" | sudo tee -a "$FILE" > /dev/null
    fi
    sudo netplan apply
}

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
    ipv4_address=$(ip addr show | awk '/inet .*global/ && !/inet6/ {print $2}' | sed -n '1p')
    ipv4_gateway=$(ip route | awk '/default/ {print $3}' | sed -n '1p')
    echo "检测到的主网卡接口: $interface"
    echo "IPv4 地址: $ipv4_address"
    echo "IPv4 网关: $ipv4_gateway"
    nmcli device status
    nmcli connection delete br-ext 2>/dev/null
    nmcli connection delete "${interface}" 2>/dev/null
    nmcli connection add type bridge ifname br-ext con-name br-ext
    nmcli connection add type bridge-slave ifname "${interface}" con-name "${interface}" master br-ext
    nmcli connection modify br-ext ipv4.method manual
    nmcli connection modify br-ext +ipv4.addresses 10.255.0.1/16            # floating IP
    nmcli connection modify br-ext +ipv4.addresses 169.254.169.254/16       # metadata service
    nmcli connection modify br-ext +ipv4.addresses "${ipv4_address}"
    nmcli connection modify br-ext ipv4.gateway "${ipv4_gateway}"
    nmcli connection modify br-ext ipv4.dns "8.8.8.8 1.1.1.1"
    nmcli connection modify br-ext bridge.stp no
    nmcli connection modify br-ext 802-3-ethernet.mtu 1500
    nmcli connection up br-ext
    nmcli conn add type bridge ifname br-int con-name br-int ipv4.method disabled ipv6.method ignore
    nmcli conn add type bridge-slave ifname "${interface}" con-name "${interface}" master br-int
    nmcli conn modify br-int bridge.stp no
    nmcli conn modify br-int 802-3-ethernet.mtu 1500
    nmcli conn up "${interface}"
    nmcli conn up br-int
}

libvirt_setup() {
    curl -fsSL https://raw.githubusercontent.com/webvirtcloud/webvirtcompute/master/scripts/libvirt.sh | sudo bash
}

prometheus_setup() {
    curl -fsSL https://raw.githubusercontent.com/webvirtcloud/webvirtcompute/master/scripts/prometheus.sh | sudo bash
}




