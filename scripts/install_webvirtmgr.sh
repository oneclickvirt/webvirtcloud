#!/bin/bash
# https://github.com/oneclickvirt/webvirtcloud
# For https://github.com/retspen/webvirtmgr
# 2025.04.27

###########################################
# Initialization and Environment Variables
# 初始化和环境变量设置
###########################################
set -e
export DEBIAN_FRONTEND=noninteractive

# Colored output functions
# 彩色输出函数
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }

# Set UTF-8 locale
# 设置UTF-8语言环境
setup_locale() {
    utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
    if [[ -z "$utf8_locale" ]]; then
        _yellow "No UTF-8 locale found"
        _yellow "未找到UTF-8语言环境"
    else
        export LC_ALL="$utf8_locale"
        export LANG="$utf8_locale"
        export LANGUAGE="$utf8_locale"
        _green "Locale set to $utf8_locale"
        _green "语言环境设置为 $utf8_locale"
    fi
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        _red "This script must be run as root" 1>&2
        _red "此脚本必须以root用户运行" 1>&2
        exit 1
    fi
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        if [ "$OS" != "ubuntu" ] && [ "$OS" != "debian" ]; then
            _red "This script only supports Ubuntu or Debian systems"
            _red "此脚本仅支持 Ubuntu 或 Debian 系统"
            exit 1
        fi
        _green "Detected system: $OS $VER"
        _green "检测到系统: $OS $VER"
    else
        _red "Unable to determine OS type"
        _red "无法确定操作系统类型"
        exit 1
    fi
}

# Check and update package manager
# 检查并更新包管理器
check_update() {
    _yellow "Updating package sources"
    _yellow "更新包管理源"
    temp_file_apt_fix=$(mktemp)
    apt_update_output=$(apt-get update 2>&1)
    echo "$apt_update_output" >"$temp_file_apt_fix"
    # Fix NO_PUBKEY issues
    # 修复 NO_PUBKEY 问题
    if grep -q 'NO_PUBKEY' "$temp_file_apt_fix"; then
        public_keys=$(grep -oE 'NO_PUBKEY [0-9A-F]+' "$temp_file_apt_fix" | awk '{ print $2 }')
        joined_keys=$(echo "$public_keys" | paste -sd " ")
        _yellow "Missing public keys: ${joined_keys}"
        _yellow "缺少公钥: ${joined_keys}"
        apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ${joined_keys}
        apt-get update
        if [ $? -eq 0 ]; then
            _green "Package sources fixed"
            _green "已修复包管理源"
        fi
    fi
    rm -f "$temp_file_apt_fix"
}

# Get IP address
# 获取IP地址
get_ip_address() {
    IPV4=$(ip -4 addr show | grep global | awk '{print $2}' | cut -d '/' -f1 | head -n 1)
    local ip_parts
    IFS='.' read -r -a ip_parts <<<"$IPV4"
    if [[ ${ip_parts[0]} -eq 10 ]] ||
        [[ ${ip_parts[0]} -eq 172 && ${ip_parts[1]} -ge 16 && ${ip_parts[1]} -le 31 ]] ||
        [[ ${ip_parts[0]} -eq 192 && ${ip_parts[1]} -eq 168 ]] ||
        [[ ${ip_parts[0]} -eq 127 ]]; then
        local API_NET=("ipv4.ip.sb" "ipget.net" "ip.ping0.cc" "https://ip4.seeip.org")
        for p in "${API_NET[@]}"; do
            response=$(curl -s4m8 "$p")
            if [ $? -eq 0 ] && ! echo "$response" | grep -q "error"; then
                IPV4="$response"
                break
            fi
        done
    fi
    _green "Detected IP address: $IPV4"
    _green "检测到IP地址: $IPV4"
}

check_cdn() {
    local o_url=$1
    local shuffled_cdn_urls=($(shuf -e "${cdn_urls[@]}")) # Shuffle array order
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