#!/bin/bash
# https://github.com/oneclickvirt/webvirtcloud
# 2025.04.18

###########################################
# 初始化和环境变量设置
###########################################
set -e
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
            exit 1
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
        exit 1
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

#######################
# Docker安装模块
#######################
check_china() {
    _yellow "检测IP区域......"
    if [[ -z "${CN}" ]]; then
        if [[ $(curl -m 6 -s https://ipapi.co/json | grep 'China') != "" ]]; then
            _yellow "根据ipapi.co提供的信息，当前IP可能在中国"
            read -e -r -p "是否选用中国镜像完成相关组件安装? ([y]/n) " input
            case $input in
            [yY][eE][sS] | [yY])
                echo "使用中国镜像"
                CN=true
                ;;
            [nN][oO] | [nN])
                echo "不使用中国镜像"
                ;;
            *)
                echo "使用中国镜像"
                CN=true
                ;;
            esac
        fi
    fi
}

install_docker_and_compose() {
    _green "This may stay for 2~3 minutes, please be patient..."
    _green "此处可能会停留2~3分钟，请耐心等待。。。"
    sleep 1
    if ! command -v docker >/dev/null 2>&1; then
        _yellow "Installing docker"
        if [[ -z "${CN}" || "${CN}" != true ]]; then
            bash <(curl -sSL https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/DockerInstallation.sh) \
                --source download.docker.com \
                --source-registry registry.hub.docker.com \
                --protocol http \
                --install-latest true \
                --close-firewall true \
                --ignore-backup-tips | awk '/脚本运行完毕，更多使用教程详见官网/ {exit} {print}'
        else
            bash <(curl -sSL https://gitee.com/SuperManito/LinuxMirrors/raw/main/DockerInstallation.sh) \
              --source mirrors.tencent.com/docker-ce \
              --source-registry registry.hub.docker.com \
              --protocol http \
              --install-latest true \
              --close-firewall true \
              --ignore-backup-tips | awk '/脚本运行完毕，更多使用教程详见官网/ {exit} {print}'
        fi
    fi
    if ! command -v docker-compose >/dev/null 2>&1; then
        if [[ -z "${CN}" || "${CN}" != true ]]; then
            _yellow "Installing docker-compose"
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            docker-compose --version
        else
            _yellow "Installing docker-compose"
            curl -L "https://cdn.spiritlhl.net/https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            docker-compose --version
        fi
    fi
    sleep 1
}

install_controller() {
    _yellow "开始安装控制器"
    cd /root
    if [ -d "webvirtcloud" ]; then
        rm -rf webvirtcloud
    fi
    if [[ -z "${CN}" || "${CN}" != true ]]; then
        git clone https://github.com/webvirtcloud/webvirtcloud.git
    else
        wget https://cdn.spiritlhl.net/https://github.com/webvirtcloud/webvirtcloud/archive/refs/heads/master.zip
        unzip master.zip
        mv webvirtcloud-master webvirtcloud
        rm -f master.zip
    fi
    cd webvirtcloud
    if [ -z "$IPV4" ]; then
        _red "错误: IPV4变量未设置，正在重新获取..."
        check_ipv4
        if [ -z "$IPV4" ]; then
            _red "无法获取IPV4地址，请手动设置后重试"
            return 1
        fi
    fi
    _yellow "创建环境配置文件..."
    DOMAIN_NAME="$(echo "$IPV4" | tr '.' '-')".nip.io
    mkdir -p .caddy/certs
    openssl req -x509 -newkey rsa:4096 -keyout .caddy/certs/key.pem -out .caddy/certs/cert.pem -days 365 -nodes -subj "/CN=${DOMAIN_NAME}"
    cp Caddyfile.selfsigned Caddyfile
    cat > env.local <<EOF
DOMAIN_NAME=${DOMAIN_NAME}
VITE_DISPLAY_PRICES=true
VITE_LOADBALANCER=true
EOF
    cat env.local
    _yellow "启动WebVirtCloud..."
    ./webvirtcloud.sh start
    if [ $? -eq 0 ]; then
        _green "WebVirtCloud installation completed successfully!"
        _green "You can access the WebVirtCloud interface at"
        _green "User Panel: https://${DOMAIN_NAME}"
        _green "Admin Panel: https://${DOMAIN_NAME}/admin/"
        _green "Ensure your firewall allows access to ports 80 (HTTP) and 443 (HTTPS) for the WebVirtCloud interface."
        _green "Default Credentials:"
        _green "Username: admin@webvirt.cloud"
        _green "Password: admin"
    else
        _red "WebVirtCloud failed to start. Please check the logs for more information."
    fi
}

###########################################
# 主函数
###########################################

main() {
    check_root
    setup_locale
    init_system_vars
    check_system_compatibility
    _yellow "正在检测IP地址..."
    check_ipv4
    _green "当前IP地址: $IPV4"
    check_china
    install_basic_dependencies
    case "$1" in
        ctl|controller)
            _yellow "准备安装WebVirtCloud控制器..."
            install_docker_and_compose
            install_controller
            ;;
        *)
            _yellow "使用方法: $0 ctl"
            _yellow "请指定正确的参数运行脚本"
            exit 1
            ;;
    esac
    _green "执行完成!"
}

main "$@"
