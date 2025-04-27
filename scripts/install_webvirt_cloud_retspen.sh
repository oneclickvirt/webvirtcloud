#!/bin/bash
# https://github.com/oneclickvirt/webvirtcloud
# For https://github.com/retspen/webvirtcloud
# 2025.04.27

###########################################
# 初始化和环境变量设置
###########################################
set -e
export DEBIAN_FRONTEND=noninteractive

# 彩色输出函数
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }

# 设置UTF-8语言环境
setup_locale() {
    utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
    if [[ -z "$utf8_locale" ]]; then
        _yellow "未找到UTF-8语言环境"
    else
        export LC_ALL="$utf8_locale"
        export LANG="$utf8_locale"
        export LANGUAGE="$utf8_locale"
        _green "语言环境设置为 $utf8_locale"
    fi
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
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
            _red "此脚本仅支持 Ubuntu 或 Debian 系统"
            exit 1
        fi
        _green "检测到系统: $OS $VER"
    else
        _red "无法确定操作系统类型"
        exit 1
    fi
}

# 检查并更新包管理器
check_update() {
    _yellow "更新包管理源"
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
            _green "已修复包管理源"
        fi
    fi
    rm -f "$temp_file_apt_fix"
}

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
    _green "检测到IP地址: $IPV4"
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
    else
        _yellow "No CDN available, no use CDN"
    fi
}

###########################################
# 安装流程
###########################################

check_python_version() {
    _yellow "检查Python版本..."
    if command -v python3 >/dev/null 2>&1; then
        python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
        _green "系统Python版本: $python_version"
        if dpkg --compare-versions "$python_version" ge "3.10"; then
            _green "✓ 系统Python版本已满足要求，跳过Python 3.10安装"
            return 0
        else
            _yellow "系统Python版本低于3.10，需要安装Python 3.10"
            return 1
        fi
    else
        _yellow "未检测到Python3，需要安装Python 3.10"
        return 1
    fi
}

# 从源码安装Python 3.10
install_python310() {
    _yellow "正在从源码安装Python 3.10..."
    apt-get install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev \
        libnss3-dev libssl-dev libreadline-dev libffi-dev wget
    cd /tmp
    wget https://www.python.org/ftp/python/3.10.13/Python-3.10.13.tgz
    tar -xf Python-3.10.13.tgz
    cd Python-3.10.13
    ./configure --enable-optimizations
    make -j $(nproc)
    make altinstall
    ln -sf /usr/local/bin/python3.10 /usr/local/bin/python310
    ln -sf /usr/local/bin/pip3.10 /usr/local/bin/pip310
    if python3.10 --version; then
        _green "✓ Python 3.10 安装成功"
    else
        _red "✗ Python 3.10 安装失败"
        exit 1
    fi
}

# 安装依赖包
install_dependencies() {
    _yellow "开始安装依赖..."
    check_update
    # 安装所需包
    local packages=(
        "python3" "python3-pip" "python3-dev" "python3-lxml" "python3-guestfs"
        "libvirt-dev" "zlib1g-dev" "libxslt1-dev" "gcc" "pkg-config"
        "git" "virtualenv" "python3-virtualenv" "supervisor"
        "libsasl2-modules" "wget" "curl" "nginx"
        "qemu-kvm" "libvirt-daemon-system" "libvirt-clients" "bridge-utils" "virt-manager" "sasl2-bin"
        "libldap2-dev" "libsasl2-dev" "lsb-release"
    )
    for pkg in "${packages[@]}"; do
        _blue "正在安装: $pkg"
        apt install -y "$pkg"
        if [ $? -eq 0 ]; then
            _green "✓ $pkg 安装成功"
        else
            _red "✗ $pkg 安装失败"
            exit 1
        fi
    done
    _green "所有依赖包安装完成"
}

# 用户和权限设置
setup_user() {
    _yellow "设置用户和权限..."
    webvirtmgr_user="www-data"
    webvirtmgr_group="www-data"
    if ! id -u $webvirtmgr_user &>/dev/null; then
        useradd -m -s /bin/bash $webvirtmgr_user
        _green "✓ 创建用户 $webvirtmgr_user"
    else
        _green "✓ 用户 $webvirtmgr_user 已存在"
    fi
    if ! getent group $webvirtmgr_group &>/dev/null; then
        groupadd $webvirtmgr_group
        _green "✓ 创建用户组 $webvirtmgr_group"
    else
        _green "✓ 用户组 $webvirtmgr_group 已存在"
    fi
}

# 创建密钥
generate_secret_key() {
    _yellow "生成安全密钥..."
    secret_key=$(python3 -c 'import random, string; haystack = string.ascii_letters + string.digits; print("".join([random.SystemRandom().choice(haystack) for _ in range(50)]))')
    _green "✓ 密钥生成成功"
}

# 克隆和配置WebVirtCloud
clone_webvirtcloud() {
    _yellow "克隆WebVirtCloud仓库..."
    cd /tmp
    if [ -d "webvirtcloud" ]; then
        rm -rf webvirtcloud
    fi
    git clone "${cdn_success_url}https://github.com/retspen/webvirtcloud.git"
    if [ $? -ne 0 ]; then
        _red "✗ 仓库克隆失败"
        exit 1
    fi
    _green "✓ 仓库克隆成功"
    _yellow "配置WebVirtCloud..."
    cd webvirtcloud
    cp webvirtcloud/settings.py.template webvirtcloud/settings.py
    sed -i "s/SECRET_KEY = \"\"/SECRET_KEY = \"${secret_key}\"/g" webvirtcloud/settings.py
    # https://github.com/retspen/webvirtcloud/issues/630
    sed -i "s|\(\['http://localhost'\)|\1, 'http://${IPV4}'|" webvirtcloud/settings.py
    cp conf/supervisor/webvirtcloud.conf /etc/supervisor/conf.d/
    sed -i "s/user=www-data/user=${webvirtmgr_user}/g" /etc/supervisor/conf.d/webvirtcloud.conf
    mkdir -p /srv
    if [ -d "/srv/webvirtcloud" ]; then
        rm -rf /srv/webvirtcloud
    fi
    mv /tmp/webvirtcloud /srv/
    chown -R ${webvirtmgr_user}:${webvirtmgr_group} /srv/webvirtcloud
    _green "✓ WebVirtCloud配置完成"
}

# 设置Python虚拟环境和依赖
setup_virtualenv() {
    _yellow "设置Python虚拟环境..."
    cd /srv/webvirtcloud
    if command -v python3.10 >/dev/null 2>&1 || command -v /usr/local/bin/python3.10 >/dev/null 2>&1; then
        _green "使用Python 3.10创建虚拟环境"
        python_cmd=$(command -v python3.10 || command -v /usr/local/bin/python3.10)
        $python_cmd -m venv venv
    else
        _green "使用系统Python创建虚拟环境"
        virtualenv -p python3 venv
    fi
    if [ $? -ne 0 ]; then
        _red "✗ 虚拟环境创建失败"
        exit 1
    fi
    _green "✓ 虚拟环境创建成功"
    _yellow "安装Python依赖..."
    ubuntu_version=$(lsb_release -rs)
    os_name=$(lsb_release -si)
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

# 配置libvirt
configure_libvirt() {
    _yellow "配置libvirt..."
    adduser ${webvirtmgr_user} libvirt
    adduser ${webvirtmgr_user} kvm
    sed -i 's/libvirtd_opts="-d"/libvirtd_opts="-d -l"/g' /etc/default/libvirtd 2>/dev/null || echo 'libvirtd_opts="-d -l"' >>/etc/default/libvirtd
    sed -i 's/#listen_tls/listen_tls/g' /etc/libvirt/libvirtd.conf
    sed -i 's/#listen_tcp/listen_tcp/g' /etc/libvirt/libvirtd.conf
    sed -i 's/#auth_tcp/auth_tcp/g' /etc/libvirt/libvirtd.conf
    sed -i 's/#[ ]*vnc_listen.*/vnc_listen = "0.0.0.0"/g' /etc/libvirt/qemu.conf
    sed -i 's/#[ ]*spice_listen.*/spice_listen = "0.0.0.0"/g' /etc/libvirt/qemu.conf
    _green "✓ libvirt配置完成"
}

# 配置gstfsd
configure_gstfsd() {
    _yellow "配置gstfsd服务..."
    cp /srv/webvirtcloud/conf/daemon/gstfsd /usr/local/bin/gstfsd
    chmod +x /usr/local/bin/gstfsd
    cp /srv/webvirtcloud/conf/supervisor/gstfsd.conf /etc/supervisor/conf.d/gstfsd.conf
    _green "✓ gstfsd配置完成"
}

# 配置Nginx
configure_nginx() {
    _yellow "配置Nginx..."
    cat >/etc/nginx/sites-available/webvirtcloud <<EOF
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
    ln -sf /etc/nginx/sites-available/webvirtcloud /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    _green "✓ Nginx配置完成"
}

# 创建管理员用户
create_admin() {
    _yellow "创建管理员用户..."
    cd /srv/webvirtcloud
    source venv/bin/activate
    echo "from django.contrib.auth.models import User; User.objects.create_superuser('admin', 'admin@example.com', 'admin')" | python3 manage.py shell || echo "管理员用户已存在，跳过创建"
    deactivate
    _green "✓ 管理员用户设置完成"
}

# 重启服务
restart_services() {
    _yellow "重启相关服务..."
    systemctl restart libvirtd
    if [ $? -ne 0 ]; then
        _red "✗ libvirtd重启失败，请检查日志"
        systemctl status libvirtd
    else
        _green "✓ libvirtd重启成功"
    fi
    systemctl restart supervisor
    if [ $? -ne 0 ]; then
        _red "✗ supervisor重启失败，请检查日志"
        systemctl status supervisor
    else
        _green "✓ supervisor重启成功"
    fi
    systemctl restart nginx
    if [ $? -ne 0 ]; then
        _red "✗ nginx重启失败，请检查日志"
        systemctl status nginx
    else
        _green "✓ nginx重启成功"
    fi
}

# 配置防火墙
configure_firewall() {
    _yellow "配置防火墙规则..."
    if [ -x "$(command -v ufw)" ]; then
        ufw allow 80/tcp
        ufw allow 6080/tcp
        _green "✓ ufw防火墙规则已添加"
    fi
    if [ -x "$(command -v firewall-cmd)" ]; then
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=6080/tcp
        firewall-cmd --reload
        _green "✓ firewalld防火墙规则已添加"
    fi
}

show_completion() {
    _green "WebVirtCloud 安装完成!"
    _yellow "访问地址: http://$IPV4"
    _yellow "默认用户名: admin"
    _yellow "默认密码: admin"
}

main() {
    _blue "开始安装 WebVirtCloud..."
    setup_locale
    check_root
    check_os
    install_dependencies
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
