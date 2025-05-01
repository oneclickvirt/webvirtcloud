#!/bin/bash
# https://github.com/oneclickvirt/webvirtcloud
# For https://github.com/retspen/webvirtcloud
# 2025.05.01

set -e
export DEBIAN_FRONTEND=noninteractive

_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }

_info() {
    _green "$1"
    _green "$2"
}

setup_locale() {
    utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
    if [[ -z "$utf8_locale" ]]; then
        _info "No UTF-8 locale found" "未找到UTF-8语言环境"
    else
        export LC_ALL="$utf8_locale"
        export LANG="$utf8_locale"
        export LANGUAGE="$utf8_locale"
        _info "Locale set to $utf8_locale" "语言环境设置为 $utf8_locale"
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
        if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
            OS_TYPE="debian"
            PKG_MANAGER="apt-get"
            PKG_UPDATE="apt-get update"
            PKG_INSTALL="apt-get install -y"
            SYS_GROUP="www-data"
            SYS_USER="www-data"
        elif [[ "$OS" == "almalinux" || "$OS" == "rocky" || "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "fedora" ]]; then
            OS_TYPE="rhel"
            PKG_MANAGER="dnf"
            PKG_UPDATE="dnf check-update || true"
            PKG_INSTALL="dnf install -y"
            if [[ "$OS" == "centos" && "$VER" == "7" ]]; then
                PKG_MANAGER="yum"
                PKG_UPDATE="yum check-update || true"
                PKG_INSTALL="yum install -y"
            fi
            SYS_GROUP="nginx"
            SYS_USER="nginx"
            if [ -f /etc/selinux/config ]; then
                sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
                sed -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
                _info "SELinux has been disabled (requires reboot)" "SELinux已被禁用（需要重启生效）"
                setenforce 0 2>/dev/null || true
                _info "SELinux temporarily set to permissive mode" "SELinux临时设置为宽容模式"
            fi
        else
            _red "This script only supports Ubuntu, Debian, AlmaLinux, RockyLinux, CentOS or RHEL systems"
            _red "此脚本仅支持 Ubuntu、Debian、AlmaLinux、RockyLinux、CentOS 或 RHEL 系统"
            exit 1
        fi
        _info "Detected system: $OS $VER" "检测到系统: $OS $VER"
    else
        _red "Unable to determine OS type"
        _red "无法确定操作系统类型"
        exit 1
    fi
}

check_update() {
    _info "Updating package sources" "更新包管理源"
    if [[ "$OS_TYPE" == "debian" ]]; then
        temp_file_apt_fix=$(mktemp)
        apt_update_output=$(apt-get update 2>&1)
        echo "$apt_update_output" >"$temp_file_apt_fix"
        if grep -q 'NO_PUBKEY' "$temp_file_apt_fix"; then
            public_keys=$(grep -oE 'NO_PUBKEY [0-9A-F]+' "$temp_file_apt_fix" | awk '{ print $2 }')
            joined_keys=$(echo "$public_keys" | paste -sd " ")
            _info "Missing public keys: ${joined_keys}" "缺少公钥: ${joined_keys}"
            apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ${joined_keys}
            apt-get update
            if [ $? -eq 0 ]; then
                _info "Package sources fixed" "已修复包管理源"
            fi
        fi
        rm -f "$temp_file_apt_fix"
    else
        eval $PKG_UPDATE
    fi
}

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
    _info "Detected IP address: $IPV4" "检测到IP地址: $IPV4"
}

check_cdn() {
    local o_url=$1
    local shuffled_cdn_urls=($(shuf -e "${cdn_urls[@]}"))
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
        _info "CDN available, using CDN" "CDN可用，使用CDN"
    else
        _info "No CDN available, no use CDN" "没有可用的CDN，不使用CDN"
    fi
}

statistics_of_run_times() {
    COUNT=$(curl -4 -ksm1 "https://hits.spiritlhl.net/webvirtcloud?action=hit&title=Hits&title_bg=%23555555&count_bg=%2324dde1&edge_flat=false" 2>/dev/null ||
        curl -6 -ksm1 "https://hits.spiritlhl.net/webvirtcloud?action=hit&title=Hits&title_bg=%23555555&count_bg=%2324dde1&edge_flat=false" 2>/dev/null)
    TODAY=$(echo "$COUNT" | grep -oP '"daily":\s*[0-9]+' | sed 's/"daily":\s*\([0-9]*\)/\1/')
    TOTAL=$(echo "$COUNT" | grep -oP '"total":\s*[0-9]+' | sed 's/"total":\s*\([0-9]*\)/\1/')
}

check_python_version() {
    _info "Checking Python version..." "检查Python版本..."
    if command -v python3 >/dev/null 2>&1; then
        python_exec=python3
    elif command -v python >/dev/null 2>&1; then
        _info "python3 not found, trying 'python'..." "未找到 python3，尝试使用 'python'..."
        if python -c 'import sys; exit(0) if sys.version_info.major == 3 else exit(1)' 2>/dev/null; then
            _info "'python' is Python 3.x, creating symlink to 'python3'..." "'python' 是 Python 3，创建符号链接到 'python3'..."
            ln -sf "$(command -v python)" /usr/local/bin/python3
            python_exec=python3
        else
            _info "'python' is not Python 3.x, cannot use it" "'python' 不是 Python 3.x，无法使用"
            return 1
        fi
    else
        _info "Neither python3 nor python found, need to install Python 3.10" "未找到 python3 或 python，需要安装 Python 3.10"
        return 1
    fi
    python_version=$($python_exec -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    _info "System Python version: $python_version" "系统Python版本: $python_version"
    if $python_exec -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'; then
        _info "✓ System Python version meets requirements, skipping Python 3.10 installation" "✓ 系统Python版本已满足要求，跳过Python 3.10安装"
        return 0
    else
        _info "System Python version is lower than 3.10, need to install Python 3.10" "系统Python版本低于3.10，需要安装Python 3.10"
        return 1
    fi
}

install_python310() {
    if command -v python3.10 &>/dev/null; then
        _info "Python 3.10 is already installed." "Python 3.10 已经安装"
        return 0
    fi
    _info "Installing Python 3.10 from source..." "正在从源码安装Python 3.10..."
    if [[ "$OS_TYPE" == "debian" ]]; then
        for pkg in build-essential zlib1g-dev libncurses5-dev libgdbm-dev \
            libnss3-dev libssl-dev libreadline-dev libffi-dev wget; do
            _info "Installing package: $pkg" "正在安装依赖包：$pkg"
            if ! $PKG_INSTALL "$pkg"; then
                _red "✗ Failed to install $pkg" "✗ 安装失败：$pkg"
                exit 1
            fi
        done
    else
        for pkg in gcc make zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel \
            openssl-devel tk-devel libffi-devel xz-devel wget; do
            _info "Installing package: $pkg" "正在安装依赖包：$pkg"
            if ! $PKG_INSTALL "$pkg"; then
                _red "✗ Failed to install $pkg" "✗ 安装失败：$pkg"
                exit 1
            fi
        done
    fi
    cd /tmp
    wget https://www.python.org/ftp/python/3.10.13/Python-3.10.13.tgz
    tar -xf Python-3.10.13.tgz
    cd Python-3.10.13
    ./configure --enable-optimizations --enable-loadable-sqlite-extensions
    make -j $(nproc)
    make altinstall
    ln -sf /usr/local/bin/python3.10 /usr/local/bin/python310
    ln -sf /usr/local/bin/pip3.10 /usr/local/bin/pip310
    if python3.10 --version; then
        _info "✓ Python 3.10 installation successful" "✓ Python 3.10 安装成功"
    else
        _red "✗ Python 3.10 installation failed"
        _red "✗ Python 3.10 安装失败"
        exit 1
    fi
}

install_dependencies() {
    _info "Starting dependencies installation..." "开始安装依赖..."
    check_update
    if [[ "$OS_TYPE" == "debian" ]]; then
        packages=("python3" "python3-pip" "python3-dev" "python3-lxml" "libvirt-dev" "zlib1g-dev"
            "libxslt1-dev" "gcc" "pkg-config" "git" "virtualenv" "python3-virtualenv" "supervisor"
            "libsasl2-modules" "wget" "curl" "nginx" "qemu-kvm" "libvirt-daemon-system"
            "libvirt-clients" "bridge-utils" "virt-manager" "sasl2-bin" "libldap2-dev"
            "libsasl2-dev" "lsb-release" "libsqlite3-dev" "libguestfs0" "libguestfs-tools" "python3-libguestfs")
        for pkg in "${packages[@]}"; do
            _yellow "安装包: $pkg"
            $PKG_INSTALL $pkg
            if [ $? -ne 0 ]; then
                _red "✗ 安装 $pkg 失败"
                exit 1
            else
                _green "✓ 安装 $pkg 成功"
            fi
        done
        if [ -x "$(command -v apt-get)" ]; then
            _yellow "安装包: python3-guestfs"
            $PKG_INSTALL python3-guestfs
            if [ $? -ne 0 ]; then
                _red "✗ 安装 python3-guestfs 失败"
            else
                _green "✓ 安装 python3-guestfs 成功"
            fi
        fi
    else
        _yellow "安装包: epel-release"
        $PKG_INSTALL epel-release
        if [ $? -ne 0 ]; then
            _red "✗ 安装 epel-release 失败"
            exit 1
        else
            _green "✓ 安装 epel-release 成功"
        fi
        if grep -qi "almalinux" /etc/os-release; then
            alma_ver=$(grep -oP '(?<=VERSION_ID=")[0-9]+' /etc/os-release)
            if [[ "$alma_ver" == "8" ]]; then
                _yellow "启用 powertools 仓库 (AlmaLinux 8)"
                dnf config-manager --set-enabled powertools
            elif [[ "$alma_ver" == "9" ]]; then
                _yellow "启用 crb 仓库 (AlmaLinux 9)"
                dnf config-manager --set-enabled crb
            fi
            dnf makecache
        fi
        if [[ "$OS" == "centos" && "$VER" == "7" ]]; then
            _yellow "安装 remi 仓库"
            yum install -y http://rpms.remirepo.net/enterprise/remi-release-7.rpm
            if [ $? -ne 0 ]; then
                _red "✗ 安装 remi 仓库失败"
                exit 1
            else
                _green "✓ 安装 remi 仓库成功"
            fi
        fi
        packages=("python3" "python3-pip" "python3-devel" "libxml2-devel" "libxslt-devel" "gcc"
            "pkgconfig" "git" "supervisor" "wget" "curl" "nginx" "qemu-kvm"
            "libvirt" "libvirt-devel" "libvirt-client" "bridge-utils" "virt-manager" "cyrus-sasl-devel"
            "openldap-devel" "sqlite-devel" "libguestfs" "libguestfs-tools" "python3-libguestfs")
        for pkg in "${packages[@]}"; do
            _yellow "安装包: $pkg"
            $PKG_INSTALL $pkg
            if [ $? -ne 0 ]; then
                _red "✗ 安装 $pkg 失败"
                exit 1
            else
                _green "✓ 安装 $pkg 成功"
            fi
        done
        _yellow "安装包: python3-virtualenv"
        $PKG_INSTALL python3-virtualenv
        if [ $? -ne 0 ]; then
            _red "✗ 安装 python3-virtualenv 失败，尝试使用 pip 安装 virtualenv"
            pip3 install virtualenv
            if [ $? -ne 0 ]; then
                _red "✗ pip 安装 virtualenv 也失败"
                exit 1
            else
                _green "✓ pip 安装 virtualenv 成功"
            fi
        else
            _green "✓ 安装 python3-virtualenv 成功"
        fi
        if ! id -u $SYS_USER &>/dev/null; then
            _yellow "创建用户: $SYS_USER"
            useradd -r -s /sbin/nologin $SYS_USER
            if [ $? -ne 0 ]; then
                _red "✗ 创建用户 $SYS_USER 失败"
            else
                _green "✓ 创建用户 $SYS_USER 成功"
            fi
        fi
        if [[ "$OS" != "debian" ]]; then
            _yellow "启用 supervisord 服务"
            systemctl enable supervisord
        else
            _yellow "启用 supervisor 服务"
            systemctl enable supervisor
        fi
    fi
    _info "All dependencies installed" "所有依赖包安装完成"
}

setup_user() {
    _info "Setting up user and permissions..." "设置用户和权限..."
    webvirtmgr_user=$SYS_USER
    webvirtmgr_group=$SYS_GROUP
    if ! id -u $webvirtmgr_user &>/dev/null; then
        if [[ "$OS_TYPE" == "debian" ]]; then
            useradd -m -s /bin/bash $webvirtmgr_user
        else
            useradd -r -s /sbin/nologin $webvirtmgr_user
        fi
        _info "✓ Created user $webvirtmgr_user" "✓ 创建用户 $webvirtmgr_user"
    else
        _info "✓ User $webvirtmgr_user already exists" "✓ 用户 $webvirtmgr_user 已存在"
    fi
    if ! getent group $webvirtmgr_group &>/dev/null; then
        groupadd $webvirtmgr_group
        _info "✓ Created group $webvirtmgr_group" "✓ 创建用户组 $webvirtmgr_group"
    else
        _info "✓ Group $webvirtmgr_group already exists" "✓ 用户组 $webvirtmgr_group 已存在"
    fi
}

generate_secret_key() {
    _info "Generating security key..." "生成安全密钥..."
    secret_key=$(python3 -c 'import random, string; haystack = string.ascii_letters + string.digits; print("".join([random.SystemRandom().choice(haystack) for _ in range(50)]))')
    _info "✓ Key generation successful" "✓ 密钥生成成功"
}

clone_webvirtcloud() {
    _yellow "Cloning WebVirtCloud repository..."
    _yellow "克隆WebVirtCloud仓库..."
    cd /tmp
    if [ -d "webvirtcloud" ]; then
        rm -rf webvirtcloud
    fi
    git clone "${cdn_success_url}https://github.com/retspen/webvirtcloud.git"
    if [ $? -ne 0 ]; then
        _red "✗ Repository clone failed"
        _red "✗ 仓库克隆失败"
        exit 1
    fi
    _green "✓ Repository clone successful"
    _green "✓ 仓库克隆成功"
    _yellow "Configuring WebVirtCloud..."
    _yellow "配置WebVirtCloud..."
    cd webvirtcloud
    cp webvirtcloud/settings.py.template webvirtcloud/settings.py
    sed -i "s/SECRET_KEY = \"\"/SECRET_KEY = \"${secret_key}\"/g" webvirtcloud/settings.py
    # https://github.com/retspen/webvirtcloud/issues/630
    sed -i "s|\(\['http://localhost'\)|\1, 'http://${IPV4}'|" webvirtcloud/settings.py
    if [ -d "/etc/supervisord.d" ]; then
        SUPERVISOR_CONF_DIR="/etc/supervisord.d"
        # 为 AlmaLinux 添加特殊处理
        if grep -qi "almalinux" /etc/os-release || grep -qi "rocky" /etc/os-release || grep -qi "centos" /etc/os-release || grep -qi "rhel" /etc/os-release; then
            if [ -f "/etc/supervisord.conf" ]; then
                if ! grep -q "\[program:webvirtcloud\]" /etc/supervisord.conf; then
                    cat >>/etc/supervisord.conf <<EOF
[program:webvirtcloud]
command=/srv/webvirtcloud/venv/bin/gunicorn webvirtcloud.wsgi:application -c /srv/webvirtcloud/gunicorn.conf.py
directory=/srv/webvirtcloud
user=${webvirtmgr_user}
autostart=true
autorestart=true
redirect_stderr=true

[program:novncd]
command=/srv/webvirtcloud/venv/bin/python3 /srv/webvirtcloud/console/novncd
directory=/srv/webvirtcloud
user=${webvirtmgr_user}
autostart=true
autorestart=true
redirect_stderr=true
EOF
                    _green "✓ 已将 supervisor 程序配置添加到 /etc/supervisord.conf"
                    _green "✓ Supervisor program configuration added to /etc/supervisord.conf"
                else
                    _yellow "Supervisor 配置已存在，跳过添加"
                    _yellow "Supervisor configuration already exists, skipping addition"
                fi
            else
                _red "✗ /etc/supervisord.conf 文件不存在"
                _red "✗ /etc/supervisord.conf file does not exist"
                exit 1
            fi
        else
            cp conf/supervisor/webvirtcloud.conf $SUPERVISOR_CONF_DIR/
            sed -i "s/user=www-data/user=${webvirtmgr_user}/g" $SUPERVISOR_CONF_DIR/webvirtcloud.conf
        fi
    elif [ -d "/etc/supervisor/conf.d" ]; then
        SUPERVISOR_CONF_DIR="/etc/supervisor/conf.d"
        cp conf/supervisor/webvirtcloud.conf $SUPERVISOR_CONF_DIR/
        sed -i "s/user=www-data/user=${webvirtmgr_user}/g" $SUPERVISOR_CONF_DIR/webvirtcloud.conf
    else
        _red "✗ Supervisor 配置目录不存在"
        _red "✗ Supervisor configuration directory does not exist"
        exit 1
    fi
    mkdir -p /srv
    if [ -d "/srv/webvirtcloud" ]; then
        rm -rf /srv/webvirtcloud
    fi
    mv /tmp/webvirtcloud /srv/
    chown -R ${webvirtmgr_user}:${webvirtmgr_group} /srv/webvirtcloud
    _green "✓ WebVirtCloud configuration complete"
    _green "✓ WebVirtCloud配置完成"
}

setup_virtualenv() {
    _yellow "设置Python虚拟环境..."
    cd /srv/webvirtcloud
    if command -v python3.10 >/dev/null 2>&1 || command -v /usr/local/bin/python3.10 >/dev/null 2>&1; then
        _green "使用Python 3.10创建虚拟环境"
        python_cmd=$(command -v python3.10 || command -v /usr/local/bin/python3.10)
        $python_cmd -m venv venv
    else
        _green "使用系统Python创建虚拟环境"
        if [[ "$OS_TYPE" == "rhel" ]]; then
            python3 -m venv venv
        else
            virtualenv -p python3 venv
        fi
    fi
    if [ $? -ne 0 ]; then
        _red "✗ 虚拟环境创建失败"
        exit 1
    fi
    _green "✓ 虚拟环境创建成功"
    _yellow "安装Python依赖..."
    source venv/bin/activate
    pip install -r conf/requirements.txt
    if [ $? -ne 0 ]; then
        _red "✗ Python依赖安装失败"
        exit 1
    fi
    _green "✓ Python依赖安装成功"
    _yellow "运行数据库迁移..."
    python3 manage.py migrate
    if [ $? -ne 0 ]; then
        _red "✗ 数据库迁移失败"
        exit 1
    fi
    _green "✓ 数据库迁移成功"
    deactivate
    chown -R ${webvirtmgr_user}:${webvirtmgr_group} /srv/webvirtcloud
}

configure_libvirt() {
    _yellow "配置libvirt..."
    usermod -aG libvirt $webvirtmgr_user
    usermod -aG kvm $webvirtmgr_user
    if [[ "$OS_TYPE" == "debian" ]]; then
        sed -i 's/libvirtd_opts="-d"/libvirtd_opts="-d -l"/g' /etc/default/libvirtd 2>/dev/null || echo 'libvirtd_opts="-d -l"' >>/etc/default/libvirtd
    else
        if [ -f /etc/sysconfig/libvirtd ]; then
            sed -i 's/#LIBVIRTD_ARGS="--listen"/LIBVIRTD_ARGS="--listen"/g' /etc/sysconfig/libvirtd
        fi
    fi
    sed -i 's/#listen_tls/listen_tls/g' /etc/libvirt/libvirtd.conf
    sed -i 's/#listen_tcp/listen_tcp/g' /etc/libvirt/libvirtd.conf
    sed -i 's/#auth_tcp/auth_tcp/g' /etc/libvirt/libvirtd.conf
    sed -i 's/#[ ]*vnc_listen.*/vnc_listen = "0.0.0.0"/g' /etc/libvirt/qemu.conf
    sed -i 's/#[ ]*spice_listen.*/spice_listen = "0.0.0.0"/g' /etc/libvirt/qemu.conf
    _green "✓ libvirt配置完成"
}

configure_gstfsd() {
    _yellow "配置gstfsd服务..."
    cp /srv/webvirtcloud/conf/daemon/gstfsd /usr/local/bin/gstfsd
    chmod +x /usr/local/bin/gstfsd
    if [ -d "/etc/supervisord.d" ]; then
        SUPERVISOR_CONF_DIR="/etc/supervisord.d"
    elif [ -d "/etc/supervisor/conf.d" ]; then
        SUPERVISOR_CONF_DIR="/etc/supervisor/conf.d"
    else
        _red "✗ Supervisor 配置目录不存在"
        exit 1
    fi
    cp /srv/webvirtcloud/conf/supervisor/gstfsd.conf $SUPERVISOR_CONF_DIR/gstfsd.conf
    _green "✓ gstfsd配置完成"
}

configure_nginx() {
    _yellow "配置Nginx..."
    if [[ "$OS_TYPE" == "debian" ]]; then
        nginx_config="/etc/nginx/sites-available/webvirtcloud"
        mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    else
        nginx_config="/etc/nginx/conf.d/webvirtcloud.conf"
        mkdir -p /etc/nginx/conf.d
    fi
    cat >"$nginx_config" <<EOF
# WebVirtCloud
server {
    listen 80;
    #server_name webvirtcloud.example.com;
    #access_log /var/log/nginx/webvirtcloud-access_log; 
    location /static/ {
        root /srv/webvirtcloud;
        expires max;
    }
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-for \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$host:\$server_port;
        proxy_set_header X-Forwarded-Proto \$remote_addr;
        proxy_set_header X-Forwarded-Ssl off;
        proxy_connect_timeout 1800;
        proxy_read_timeout 1800;
        proxy_send_timeout 1800;
        client_max_body_size 1024M;
    }
    location /novncd/ {
        proxy_pass http://wsnovncd;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
upstream wsnovncd {
      server 127.0.0.1:6080;
}
EOF
    if [[ "$OS_TYPE" == "debian" ]]; then
        ln -sf /etc/nginx/sites-available/webvirtcloud /etc/nginx/sites-enabled/
        rm -f /etc/nginx/sites-enabled/default
    fi
    if [[ "$OS_TYPE" == "rhel" ]]; then
        chown -R $webvirtmgr_user:$webvirtmgr_group /var/lib/nginx
        setsebool -P httpd_can_network_connect 1
    fi
    systemctl enable nginx
    _green "✓ Nginx配置完成"
}

create_admin() {
    _yellow "创建管理员用户..."
    cd /srv/webvirtcloud
    source venv/bin/activate
    echo "from django.contrib.auth.models import User; User.objects.create_superuser('admin', 'admin@example.com', 'admin')" | python3 manage.py shell || echo "Admin user already exists, skipping creation"
    deactivate
    _green "✓ 管理员用户设置完成"
}

restart_services() {
    _yellow "重启相关服务..."
    systemctl restart libvirtd
    if [ $? -ne 0 ]; then
        _red "✗ libvirtd重启失败，请检查日志"
        systemctl status libvirtd
    else
        _green "✓ libvirtd重启成功"
    fi
    if [[ "$OS" != "debian" ]]; then
        systemctl restart supervisord
        if [ $? -ne 0 ]; then
            _red "✗ supervisord重启失败，请检查日志"
            systemctl status supervisord
        else
            _green "✓ supervisord重启成功"
        fi
    else
        systemctl restart supervisor
        if [ $? -ne 0 ]; then
            _red "✗ supervisor重启失败，请检查日志"
            systemctl status supervisor
        else
            _green "✓ supervisor重启成功"
        fi
    fi
    systemctl restart nginx
    if [ $? -ne 0 ]; then
        _red "✗ nginx重启失败，请检查日志"
        systemctl status nginx
    else
        _green "✓ nginx重启成功"
    fi
    sudo virsh net-autostart default || true
    sudo virsh net-start default || true
    sudo virsh net-list --all
}

configure_firewall() {
    _yellow "配置防火墙规则..."
    local has_ufw=0
    local has_firewalld=0
    if command -v ufw >/dev/null 2>&1; then
        has_ufw=1
    fi
    if command -v firewall-cmd >/dev/null 2>&1; then
        has_firewalld=1
    fi
    if [[ $has_ufw -eq 0 && $has_firewalld -eq 0 ]]; then
        _yellow "未检测到防火墙，正在安装firewalld..."
        if [[ "$OS_TYPE" == "debian" ]]; then
            $PKG_INSTALL firewalld
        else
            $PKG_INSTALL firewalld
        fi
        systemctl enable firewalld
        systemctl start firewalld
        has_firewalld=1
        _green "✓ firewalld安装并启动成功"
    fi
    if [ $has_ufw -eq 1 ]; then
        ufw allow 80/tcp
        ufw allow 6080/tcp
        _green "✓ ufw防火墙规则已添加"
    fi
    if [ $has_firewalld -eq 1 ]; then
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=6080/tcp
        firewall-cmd --reload
        _green "✓ firewalld防火墙规则已添加"
    fi
}

show_completion() {
    _green "WebVirtCloud 安装完成! / WebVirtCloud installation completed!"
    _yellow "访问地址: http://$IPV4 / Access URL: http://$IPV4"
    _yellow "默认用户名: admin / Default username: admin"
    _yellow "默认密码: admin / Default password: admin"
}

main() {
    _blue "开始安装 WebVirtCloud..."
    setup_locale
    check_root
    check_os
    install_dependencies
    statistics_of_run_times
    _green "脚本当天运行次数:${TODAY}，累计运行次数:${TOTAL}"
    if ! check_python_version; then
        install_python310
    fi
    setup_user
    cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn1.spiritlhl.net/" "http://cdn2.spiritlhl.net/" "http://cdn3.spiritlhl.net/" "http://cdn4.spiritlhl.net/")
    check_cdn_file
    get_ip_address
    generate_secret_key
    clone_webvirtcloud
    setup_virtualenv
    configure_libvirt
    configure_gstfsd
    configure_nginx
    create_admin
    restart_services
    configure_firewall
    show_completion
}

main
