#!/bin/bash
# https://github.com/oneclickvirt/webvirtcloud
# For https://github.com/webvirtcloud/webvirtcloud (Already deleted, using archive for build)
# 2025.06.03

###########################################
# 初始化和环境变量设置
###########################################
set -e
export DEBIAN_FRONTEND=noninteractive
cd /root >/dev/null 2>&1
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

check_root() {
    if [ "$(id -u)" != "0" ]; then
        _red "This script must be run as root" 1>&2
        exit 1
    fi
}

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

statistics_of_run_times() {
    COUNT=$(curl -4 -ksm1 "https://hits.spiritlhl.net/webvirtcloud?action=hit&title=Hits&title_bg=%23555555&count_bg=%2324dde1&edge_flat=false" 2>/dev/null ||
        curl -6 -ksm1 "https://hits.spiritlhl.net/webvirtcloud?action=hit&title=Hits&title_bg=%23555555&count_bg=%2324dde1&edge_flat=false" 2>/dev/null)
    TODAY=$(echo "$COUNT" | grep -oP '"daily":\s*[0-9]+' | sed 's/"daily":\s*\([0-9]*\)/\1/')
    TOTAL=$(echo "$COUNT" | grep -oP '"total":\s*[0-9]+' | sed 's/"total":\s*\([0-9]*\)/\1/')
}

###########################################
# 辅助函数模块
###########################################
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }

check_update() {
    _yellow "Updating package repositories"
    _yellow "更新包管理源"
    if command -v apt-get >/dev/null 2>&1; then
        distro=""
        codename=""
        is_archive=false
        if grep -qi debian /etc/os-release; then
            distro="debian"
            debian_ver=$(grep VERSION= /etc/os-release | grep -oE '[0-9]+' | head -n1)
            case "$debian_ver" in
            10)
                codename="buster"
                is_archive=true
                ;;
            9)
                codename="stretch"
                is_archive=true
                ;;
            8)
                codename="jessie"
                is_archive=true
                ;;
            esac
        elif grep -qi ubuntu /etc/os-release; then
            distro="ubuntu"
            codename=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
            case "$codename" in
            xenial | bionic | eoan | groovy | artful | zesty | yakkety | vivid | wily | utopic)
                is_archive=true
                ;;
            esac
        fi
        # 如为归档版本，则替换为归档源
        if [[ "$is_archive" == true ]]; then
            _yellow "Archived system detected: $distro $codename, please upgrade your system. Exiting program."
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
            _yellow "Missing public keys: ${joined_keys}"
            _yellow "缺少公钥: ${joined_keys}"
            apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ${joined_keys}
            apt-get update
            if [ $? -eq 0 ]; then
                _green "Fixed"
                _green "已修复"
            fi
        fi
        rm -f "$temp_file_apt_fix"
    elif command -v yum >/dev/null 2>&1; then
        ${PACKAGE_UPDATE[int]}
    else
        ${PACKAGE_UPDATE[int]}
    fi
}

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

check_cdn() {
    local o_url=$1
    local shuffled_cdn_urls=($(shuf -e "${cdn_urls[@]}")) # 打乱数组顺序
    for cdn_url in "${shuffled_cdn_urls[@]}"; do
        if curl -sL -k "$cdn_url$o_url" --max-time 6 | grep -q "success" >/dev/null 2>&1; then
            export cdn_success_url="$cdn_url"
            return
        fi
        sleep 0.5
    done
    export cdn_success_url=""
}

check_cdn_file() {
    check_cdn "https://raw.githubusercontent.com/spiritLHLS/ecs/main/back/test"
    if [ -n "$cdn_success_url" ]; then
        _yellow "CDN available, using CDN"
        _yellow "CDN可用，使用CDN"
    else
        _yellow "No CDN available, no use CDN"
        _yellow "没有可用的CDN，不使用CDN"
    fi
}

###########################################
# 系统检测模块
###########################################
check_system_compatibility() {
    if [[ "${RELEASE[int]}" != "Debian" && "${RELEASE[int]}" != "Ubuntu" && "${RELEASE[int]}" != "CentOS" ]]; then
        _red "Current system not supported: ${RELEASE[int]}"
        _red "不支持当前系统: ${RELEASE[int]}"
        exit 1
    fi
}

###########################################
# 依赖安装模块
###########################################
install_basic_dependencies() {
    _yellow "Installing basic dependencies"
    _yellow "安装基本依赖"
    check_update
    local packages=("curl" "tar" "unzip" "git" "sudo" "jq" "openssl")
    for pkg in "${packages[@]}"; do
        if ! command -v ${pkg} >/dev/null 2>&1; then
            _yellow "Installing ${pkg}"
            _yellow "安装 ${pkg}"
            ${PACKAGE_INSTALL[int]} ${pkg}
        fi
    done
    if [[ "${RELEASE[int]}" == "CentOS" ]]; then
        if ! rpm -q epel-release >/dev/null 2>&1; then
            _yellow "Installing EPEL repository for RedHat-based systems"
            _yellow "为RedHat系统安装EPEL仓库"
            ${PACKAGE_INSTALL[int]} epel-release
            ${PACKAGE_UPDATE[int]}
        fi
    fi
}

#######################
# Docker安装模块
#######################
check_china() {
    _yellow "Detecting IP region......"
    _yellow "检测IP区域......"
    if [[ -z "${CN}" ]]; then
        if [[ $(curl -m 6 -s https://ipapi.co/json | grep 'China') != "" ]]; then
            _yellow "According to ipapi.co, your current IP may be in China"
            _yellow "根据ipapi.co提供的信息，当前IP可能在中国"
            read -e -r -p "Use Chinese mirrors to install components? ([y]/n) " input
            case $input in
            [yY][eE][sS] | [yY])
                echo "Using Chinese mirrors"
                echo "使用中国镜像"
                CN=true
                ;;
            [nN][oO] | [nN])
                echo "Not using Chinese mirrors"
                echo "不使用中国镜像"
                ;;
            *)
                echo "Using Chinese mirrors"
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
        _yellow "安装 docker"
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
            _yellow "安装 docker-compose"
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            docker-compose --version
        else
            _yellow "Installing docker-compose"
            _yellow "安装 docker-compose"
            curl -L "https://cdn.spiritlhl.net/https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            docker-compose --version
        fi
    fi
    sleep 1
}

install_controller() {
    _yellow "Starting controller installation"
    _yellow "开始安装控制器"
    cd /root
    if [ -d "webvirtcloud" ]; then
        rm -rf webvirtcloud
    fi
    if [[ -z "${CN}" || "${CN}" != true ]]; then
        git clone "${cdn_success_url}https://github.com/oneclickvirt/webvirtcloud.git"
    else
        wget "${cdn_success_url}https://github.com/oneclickvirt/webvirtcloud/archive/refs/heads/main.zip"
        unzip main.zip
        mv webvirtcloud-main webvirtcloud
        rm -f main.zip
    fi
    cd webvirtcloud/archive
    if [ -z "$IPV4" ]; then
        _red "Error: IPV4 variable not set, getting it again..."
        _red "错误: IPV4变量未设置，正在重新获取..."
        check_ipv4
        if [ -z "$IPV4" ]; then
            _red "Unable to get IPV4 address, please set it manually and try again"
            _red "无法获取IPV4地址，请手动设置后重试"
            return 1
        fi
    fi
    _yellow "Creating environment configuration file..."
    _yellow "创建环境配置文件..."
    DOMAIN_NAME="$(echo "$IPV4" | tr '.' '-')".nip.io
    mkdir -p .caddy/certs
    openssl req -x509 -newkey rsa:4096 -keyout .caddy/certs/key.pem -out .caddy/certs/cert.pem -days 365 -nodes -subj "/CN=${DOMAIN_NAME}"
    cp Caddyfile.selfsigned Caddyfile
    cat >env.local <<EOF
DOMAIN_NAME=${DOMAIN_NAME}
VITE_DISPLAY_PRICES=true
VITE_LOADBALANCER=true
EOF
    cat env.local
    _yellow "Starting WebVirtCloud..."
    _yellow "启动WebVirtCloud..."
    chmod 777 webvirtcloud.sh
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
        _green "WebVirtCloud安装成功完成！"
        _green "您可以通过以下地址访问WebVirtCloud界面"
        _green "用户面板: https://${DOMAIN_NAME}"
        _green "管理员面板: https://${DOMAIN_NAME}/admin/"
        _green "请确保您的防火墙允许访问WebVirtCloud界面的80端口（HTTP）和443端口（HTTPS）。"
        _green "默认凭据："
        _green "用户名: admin@webvirt.cloud"
        _green "密码: admin"
    else
        _red "WebVirtCloud failed to start. Please check the logs for more information."
        _red "WebVirtCloud启动失败。请查看日志以获取更多信息。"
    fi
}

###########################################
# 主函数
###########################################

main() {
    check_root
    setup_locale
    init_system_vars
    if [[ "${RELEASE[int]}" != "Debian" && "${RELEASE[int]}" != "Ubuntu" && "${RELEASE[int]}" != "CentOS" ]]; then
        _yellow "Current system: ${RELEASE[int]}"
        _yellow "当前系统: ${RELEASE[int]}"
        if grep -qi "rhel\|rocky\|alma\|centos" /etc/os-release 2>/dev/null; then
            _yellow "RedHat family OS detected, proceeding with CentOS compatible mode"
            _yellow "检测到RedHat系统家族，将以CentOS兼容模式继续"
            SYSTEM="CentOS"
            for ((i=0; i<${#RELEASE[@]}; i++)); do
                if [[ "${RELEASE[i]}" == "CentOS" ]]; then
                    int=$i
                    break
                fi
            done
        else
            _red "Current system not supported"
            _red "不支持当前系统"
            exit 1
        fi
    fi
    _yellow "Detecting IP address..."
    _yellow "正在检测IP地址..."
    check_ipv4
    _green "Current IP address: $IPV4"
    _green "当前IP地址: $IPV4"
    check_china
    install_basic_dependencies
    cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn1.spiritlhl.net/" "http://cdn2.spiritlhl.net/" "http://cdn3.spiritlhl.net/" "http://cdn4.spiritlhl.net/")
    check_cdn_file
    statistics_of_run_times
    _green "Script run count today: ${TODAY}, total run count: ${TOTAL}"
    _green "脚本当天运行次数:${TODAY}，累计运行次数:${TOTAL}"
    _yellow "Preparing to install WebVirtCloud controller..."
    _yellow "准备安装WebVirtCloud控制器..."
    install_docker_and_compose
    install_controller
    _green "Execution completed!"
    _green "执行完成!"
}

main
