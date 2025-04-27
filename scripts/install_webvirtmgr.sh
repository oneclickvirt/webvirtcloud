#!/bin/bash
# https://github.com/oneclickvirt/webvirtcloud
# Based on https://github.com/retspen/webvirtmgr
# 2025.04.27

set -e
export DEBIAN_FRONTEND=noninteractive
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }

check_root() {
    if [ "$(id -u)" != "0" ]; then
        _red "此脚本必须以root用户运行" 1>&2
        _red "This script must be run as root" 1>&2
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
            _red "This script only supports Ubuntu or Debian systems"
            exit 1
        fi
        _green "检测到系统: $OS $VER"
        _green "Detected system: $OS $VER"
    else
        _red "无法确定操作系统类型"
        _red "Cannot determine OS type"
        exit 1
    fi
}

setup_locale() {
    utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
    if [[ -z "$utf8_locale" ]]; then
        _yellow "未找到UTF-8语言环境"
        _yellow "No UTF-8 locale found"
    else
        export LC_ALL="$utf8_locale"
        export LANG="$utf8_locale"
        export LANGUAGE="$utf8_locale"
        _green "语言环境设置为 $utf8_locale"
        _green "Locale set to $utf8_locale"
    fi
}

check_update() {
    _yellow "更新包管理源"
    _yellow "Updating package sources"
    add-apt-repository universe -y
    temp_file_apt_fix=$(mktemp)
    apt_update_output=$(apt-get update 2>&1)
    echo "$apt_update_output" >"$temp_file_apt_fix"
    # Fix NO_PUBKEY issues
    if grep -q 'NO_PUBKEY' "$temp_file_apt_fix"; then
        public_keys=$(grep -oE 'NO_PUBKEY [0-9A-F]+' "$temp_file_apt_fix" | awk '{ print $2 }')
        joined_keys=$(echo "$public_keys" | paste -sd " ")
        _yellow "缺少公钥: ${joined_keys}"
        _yellow "Missing public keys: ${joined_keys}"
        apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ${joined_keys}
        apt-get update
        if [ $? -eq 0 ]; then
            _green "已修复包管理源"
            _green "Package sources fixed"
        fi
    fi
    rm -f "$temp_file_apt_fix"
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
    _green "检测到IP地址: $IPV4"
    _green "Detected IP address: $IPV4"
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
        _yellow "CDN可用，使用CDN"
        _yellow "CDN available, using CDN"
    else
        _yellow "没有可用的CDN，不使用CDN"
        _yellow "No CDN available, no use CDN"
    fi
}

install_kvm() {
    _blue "安装KVM"
    _blue "Installing KVM"
    apt install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils sasl2-bin -y
    adduser ${webvirtmgr_user} libvirt
    adduser ${webvirtmgr_user} kvm
}

install_build_dependencies() {
    _blue "安装编译依赖"
    _blue "Installing build dependencies"
    apt install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev \
        libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev libxml2-dev libxslt1-dev \
        libvirt-dev git supervisor nginx curl uuid-dev libkrb5-dev
}

compile_python27() {
    _blue "编译安装 Python 2.7"
    _blue "Compiling and installing Python 2.7"
    cd /tmp
    wget https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tgz
    tar -xf Python-2.7.18.tgz
    cd Python-2.7.18
    ./configure --prefix=/opt/python2.7 --enable-optimizations --enable-unicode=ucs4 --with-openssl=/usr/lib/ssl
    make -j$(nproc)
    make altinstall
    ln -sf /opt/python2.7/bin/python2.7 /usr/local/bin/python2.7
    ln -sf /opt/python2.7/bin/pip2.7 /usr/local/bin/pip2.7
    python2.7 --version
    wget https://bootstrap.pypa.io/pip/2.7/get-pip.py
    python2.7 get-pip.py
    cd /tmp
    rm -rf Python-2.7.18*
    rm -f get-pip.py
    _green "Python 2.7 安装完成"
    _green "Python 2.7 installation completed"
}

install_virtualenv() {
    _blue "安装虚拟环境"
    _blue "Installing virtual environment"
    /opt/python2.7/bin/pip2.7 install virtualenv
    mkdir -p /var/www
    /opt/python2.7/bin/virtualenv --python=/opt/python2.7/bin/python2.7 /var/www/webvirtmgr_env
    chown -R ${webvirtmgr_user}:${webvirtmgr_group} /var/www/webvirtmgr_env
}

install_python_deps() {
    _blue "安装Python依赖"
    _blue "Installing Python dependencies"
    source /var/www/webvirtmgr_env/bin/activate
    pip install libvirt-python==4.0.0
    pip install lxml
    deactivate
}

install_webvirtmgr() {
    _blue "安装webvirtmgr"
    _blue "Installing webvirtmgr"
    source /var/www/webvirtmgr_env/bin/activate
    # 克隆仓库
    if [ -n "$cdn_success_url" ]; then
        git clone "${cdn_success_url}git://github.com/retspen/webvirtmgr.git" /var/www/webvirtmgr
    else
        git clone "git://github.com/retspen/webvirtmgr.git" /var/www/webvirtmgr
    fi
    cd /var/www/webvirtmgr
    pip install -r requirements.txt
    pip install websockify
    python manage.py syncdb --noinput
    _blue "创建管理员用户"
    _blue "Creating admin user"
    ADMIN_USERNAME="admin"
    ADMIN_EMAIL="admin@example.com"
    ADMIN_PASSWORD="Admin@2025"
    echo "from django.contrib.auth.models import User; User.objects.create_superuser('$ADMIN_USERNAME', '$ADMIN_EMAIL', '$ADMIN_PASSWORD')" | python manage.py shell
    _green "✓ 管理员账号已创建"
    _green "✓ Admin account created"
    _green "用户名/Username: $ADMIN_USERNAME"
    _green "密码/Password: $ADMIN_PASSWORD"
    _yellow "请登录后立即修改密码"
    _yellow "Please change the password immediately after login"
    python manage.py collectstatic --noinput
    deactivate
    chown -R ${webvirtmgr_user}:${webvirtmgr_group} /var/www/webvirtmgr
}

configure_webvirtmgr() {
    _blue "设置webvirtmgr"
    _blue "Configuring webvirtmgr"
    cat >webvirtmgr.conf <<EOF
[program:webvirtmgr]
command=/var/www/webvirtmgr_env/bin/python /var/www/webvirtmgr/manage.py run_gunicorn -c /var/www/webvirtmgr/conf/gunicorn.conf.py
directory=/var/www/webvirtmgr
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/webvirtmgr.log
redirect_stderr=true
user=${webvirtmgr_user}

[program:webvirtmgr-console]
command=/var/www/webvirtmgr_env/bin/python /var/www/webvirtmgr/console/webvirtmgr-console
directory=/var/www/webvirtmgr
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/webvirtmgr-console.log
redirect_stderr=true
user=${webvirtmgr_user}
EOF
    mv webvirtmgr.conf /etc/supervisor/conf.d/
    if [ -f /etc/default/libvirtd ]; then
        sed -i 's/libvirtd_opts="-d"/libvirtd_opts="-d -l"/g' /etc/default/libvirtd
    elif [ -f /etc/default/libvirt-daemon ]; then
        sed -i 's/libvirtd_opts="-d"/libvirtd_opts="-d -l"/g' /etc/default/libvirt-daemon
    fi
    sed -i 's/#listen_tls/listen_tls/g' /etc/libvirt/libvirtd.conf
    sed -i 's/#listen_tcp/listen_tcp/g' /etc/libvirt/libvirtd.conf
    sed -i 's/#auth_tcp/auth_tcp/g' /etc/libvirt/libvirtd.conf
    sed -i 's/#[ ]*vnc_listen.*/vnc_listen = "0.0.0.0"/g' /etc/libvirt/qemu.conf
    sed -i 's/#[ ]*spice_listen.*/spice_listen = "0.0.0.0"/g' /etc/libvirt/qemu.conf
}

configure_nginx() {
    _blue "设置Nginx"
    _blue "Configuring Nginx"
    cat >/etc/nginx/sites-available/webvirtmgr <<EOF
# WebVirtMgr
server {
    listen 80;
    server_name $HOSTNAME;
    #access_log /var/log/nginx/webvirtmgr_access_log; 
    location /static/ {
        root /var/www/webvirtmgr/webvirtmgr; # or /srv instead of /var
        expires max;
    }
    location ~ .*\.(js|css)$ {
        proxy_pass http://127.0.0.1:8000;
    }
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-for \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$host:\$server_port;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 600;
        proxy_read_timeout 600;
        proxy_send_timeout 600;
        client_max_body_size 1024M; # Set higher depending on your needs 
    }
}
EOF
    ln -sf /etc/nginx/sites-available/webvirtmgr /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
}

restart_services() {
    _blue "重启服务"
    _blue "Restarting services"
    if systemctl list-unit-files | grep -q libvirtd.service; then
        systemctl restart libvirtd
    elif systemctl list-unit-files | grep -q libvirt-daemon.service; then
        systemctl restart libvirt-daemon
    fi
    systemctl stop supervisor
    systemctl start supervisor
    systemctl restart nginx
}

completion_message() {
    _green "WebVirtMgr 安装完成!"
    _green "WebVirtMgr installation completed!"
    _green "访问 WebVirtMgr: http://$IPV4"
    _green "Access WebVirtMgr at: http://$IPV4"
    _green "管理员账号/Admin account: admin"
    _green "管理员密码/Admin password: Admin@2025"
    _yellow "请登录后立即修改密码"
    _yellow "Please change the password immediately after login"
    _yellow "注意: WebVirtMgr 安装在Python虚拟环境中，Python 2.7编译安装在 /opt/python2.7"
    _yellow "Note: WebVirtMgr is installed in a Python virtual environment, Python 2.7 is compiled and installed in /opt/python2.7"
}

setup_user() {
    _yellow "设置用户和权限..."
    _yellow "Setting up user and permissions..."
    webvirtmgr_user="www-data"
    webvirtmgr_group="www-data"
    if ! id -u $webvirtmgr_user &>/dev/null; then
        useradd -m -s /bin/bash $webvirtmgr_user
        _green "✓ 创建用户 $webvirtmgr_user"
        _green "✓ Created user $webvirtmgr_user"
    else
        _green "✓ 用户 $webvirtmgr_user 已存在"
        _green "✓ User $webvirtmgr_user already exists"
    fi
    if ! getent group $webvirtmgr_group &>/dev/null; then
        groupadd $webvirtmgr_group
        _green "✓ 创建用户组 $webvirtmgr_group"
        _green "✓ Created group $webvirtmgr_group"
    else
        _green "✓ 用户组 $webvirtmgr_group 已存在"
        _green "✓ Group $webvirtmgr_group already exists"
    fi
}

main() {
    check_root
    check_os
    setup_locale
    check_update
    get_ip_address
    setup_user
    install_build_dependencies
    compile_python27
    install_kvm
    cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn1.spiritlhl.net/" "http://cdn2.spiritlhl.net/" "http://cdn3.spiritlhl.net/" "http://cdn4.spiritlhl.net/")
    check_cdn_file
    install_virtualenv
    install_python_deps
    install_webvirtmgr
    configure_webvirtmgr
    configure_nginx
    restart_services
    completion_message
}

main
