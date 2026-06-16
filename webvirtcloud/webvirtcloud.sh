#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

cat << "EOF"
 __        __   _  __     ___      _    ____ _                 _ 
 \ \      / ___| |_\ \   / (_)_ __| |_ / ___| | ___  _   _  __| |
  \ \ /\ / / _ | '_ \ \ / /| | '__| __| |   | |/ _ \| | | |/ _` |
   \ V  V |  __| |_) \ V / | | |  | |_| |___| | (_) | |_| | (_| |
    \_/\_/ \___|_.__/ \_/  |_|_|   \__|\____|_|\___/ \__,_|\__,_|
                                                                        
EOF

# Define minimum Docker version
MIN_DOCKER_VERSION="25.0.0"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "\nDocker not found! Please install Docker first.\n"
    exit 1
fi

DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')

# Check docker version function
check_docker_version() {
  # Split version strings into arrays
  IFS='.' read -r -a current_version <<< "$1"
  IFS='.' read -r -a min_version <<< "$2"
  for i in 0 1 2; do
    # Check (major, minor, patch)
    if [[ ${current_version[i]} -gt ${min_version[i]} ]]; then
      return 0
    elif [[ ${current_version[i]} -lt ${min_version[i]} ]]; then
      return 1
    fi
  done
  return 0
}

# Check if Docker version meets the requirement
if check_docker_version "$DOCKER_VERSION" "$MIN_DOCKER_VERSION"; then
    echo -e "\nDocker version $DOCKER_VERSION is sufficient.\n"
else
    echo -e "\nDocker version $DOCKER_VERSION is not sufficient. Please update Docker to version $MIN_DOCKER_VERSION or later.\n"
    exit 1
fi

# Check if Docker Compose is installed
if docker compose version > /dev/null 2>&1; then
    DOCKER_COMPOSE_COMMAND="docker compose"
elif command -v docker-compose > /dev/null 2>&1; then
    DOCKER_COMPOSE_COMMAND="docker-compose"
else
    echo "Neither 'docker compose' nor 'docker-compose' command found."
    echo "未找到 'docker compose' 或 'docker-compose' 命令。"
    exit 1
fi

function say() {
    echo "$1"
    echo "$2"
}

function generate_secret() {
    local bytes="${1:-32}"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex "$bytes"
    else
        python3 -c "import secrets; print(secrets.token_hex(${bytes}))"
    fi
}

function read_env_value() {
    local key="$1"
    if [ -f env.local ]; then
        awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' env.local
    fi
}

function set_env_value() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" env.local 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" env.local
    else
        echo "${key}=${value}" >> env.local
    fi
}

function is_placeholder_value() {
    local value="$1"
    [ -z "$value" ] || [[ "$value" == change-me* ]] || [[ "$value" == *generate-with* ]]
}

function ensure_env_value() {
    local key="$1"
    local value="$2"
    local current_value
    current_value="$(read_env_value "$key")"
    if is_placeholder_value "$current_value"; then
        set_env_value "$key" "$value"
    fi
}

function ensure_runtime_env() {
    touch env.local

    local domain_name
    domain_name="$(read_env_value DOMAIN_NAME)"
    if [ -z "$domain_name" ]; then
        domain_name="localhost"
        set_env_value DOMAIN_NAME "$domain_name"
    fi

    ensure_env_value DJANGO_SECRET_KEY "$(generate_secret 48)"
    ensure_env_value MARIADB_PASSWORD "$(generate_secret 24)"
    ensure_env_value MARIADB_ROOT_PASSWORD "$(generate_secret 24)"
    ensure_env_value RABBITMQ_DEFAULT_PASS "$(generate_secret 24)"
    ensure_env_value DB_PASSWORD "$(read_env_value MARIADB_PASSWORD)"
    ensure_env_value CELERY_BROKER_URL "amqp://django:$(read_env_value RABBITMQ_DEFAULT_PASS)@rabbitmq:5672//webvirtcloud"
    ensure_env_value DJANGO_ALLOWED_HOSTS "$domain_name,localhost,127.0.0.1,backend"
    ensure_env_value CSRF_TRUSTED_ORIGINS "https://${domain_name},http://${domain_name}"
    ensure_env_value WEBVIRT_ADMIN_EMAIL "admin@spiritlhl.net"
    ensure_env_value WEBVIRT_ADMIN_PASSWORD "$(generate_secret 18)"
}

function wait_for_backend() {
    say "Waiting for backend to be ready..." "等待后端服务就绪..."
    for _ in $(seq 1 60); do
        if $DOCKER_COMPOSE_COMMAND exec -T backend python manage.py check >/dev/null 2>&1; then
            say "Backend is ready." "后端服务已就绪。"
            return 0
        fi
        sleep 2
    done

    say "Backend did not become ready in time." "后端服务未在限定时间内就绪。"
    exit 1
}

# Start docker compose
function start_webvirtcloud() {
    INIT_DB=false

    # Check if env.local exists
    if [ ! -f env.local ]; then
        say "File env.local not found; creating a secure default env.local." "未找到 env.local，将创建安全的默认配置。"
    fi
    ensure_runtime_env

    ensure_source_tree

    # Check if .mysql directory exists
    if [ ! -d ".mysql/mysql" ]; then
        INIT_DB=true
    fi
    
    say "Building WebVirtCloud frontend..." "正在构建 WebVirtCloud 前端..."
    $DOCKER_COMPOSE_COMMAND build frontend --no-cache

    say "Building WebVirtCloud backend..." "正在构建 WebVirtCloud 后端..."
    $DOCKER_COMPOSE_COMMAND build backend --no-cache
    
    say "Start WebVirtCloud..." "正在启动 WebVirtCloud..."
    $DOCKER_COMPOSE_COMMAND up -d
    
    # Init database
    if [ "$INIT_DB" = true ]; then
        wait_for_backend
        create_default_admin
    fi
}

function create_default_admin() {
    ensure_runtime_env
    local admin_email
    local admin_password
    admin_email="$(read_env_value WEBVIRT_ADMIN_EMAIL)"
    admin_password="$(read_env_value WEBVIRT_ADMIN_PASSWORD)"

    say "Loading initial data and creating initial admin user..." "正在加载初始数据并创建初始管理员用户..."
    $DOCKER_COMPOSE_COMMAND exec -T \
        -e WEBVIRT_ADMIN_EMAIL="$admin_email" \
        -e WEBVIRT_ADMIN_PASSWORD="$admin_password" \
        backend python manage.py first_init_data
    echo "Admin email / 管理员邮箱: $admin_email"
    echo "Admin password / 管理员密码: $admin_password"
}

# Load initial data
function load_initial_data() {
    say "Loading initial data..." "正在加载初始数据..."
    wait_for_backend
    $DOCKER_COMPOSE_COMMAND exec -T backend python manage.py loaddata initial_data
}

# Init and update submodules
function init_submodules() {
    say "Init submodules..." "正在初始化子模块..."
    git submodule update --init --recursive
}

function ensure_source_tree() {
    if [ ! -d "../webvirtbackend" ] || [ ! -d "../webvirtfrontend" ]; then
        say "Required sibling source directories ../webvirtbackend and ../webvirtfrontend were not found." "未找到必需的同级源码目录 ../webvirtbackend 和 ../webvirtfrontend。"
        say "Run this script from the webvirtcloud/ directory of the full repository checkout." "请在完整仓库检出的 webvirtcloud/ 目录中运行此脚本。"
        exit 1
    fi
}

# Restart docker compose
function restart_webvirtcloud() {
    say "Restarting WebVirtCloud..." "正在重启 WebVirtCloud..."
    $DOCKER_COMPOSE_COMMAND restart
}

# Stop docker compose
function stop_webvirtcloud() {
    say "Stop WebVirtCloud..." "正在停止 WebVirtCloud..."
    $DOCKER_COMPOSE_COMMAND down
}

function uninstall_webvirtcloud() {
    say "Uninstalling WebVirtCloud containers..." "正在卸载 WebVirtCloud 容器..."
    if [ "${WEBVIRT_UNINSTALL_DELETE_VOLUMES:-false}" = "true" ]; then
        say "WEBVIRT_UNINSTALL_DELETE_VOLUMES=true; removing containers, local images, and volumes." "检测到 WEBVIRT_UNINSTALL_DELETE_VOLUMES=true，将删除容器、本地镜像和卷。"
        $DOCKER_COMPOSE_COMMAND down -v --rmi local
    else
        say "Preserving volumes. Set WEBVIRT_UNINSTALL_DELETE_VOLUMES=true to remove database volumes too." "将保留数据卷。如需同时删除数据库卷，请设置 WEBVIRT_UNINSTALL_DELETE_VOLUMES=true。"
        $DOCKER_COMPOSE_COMMAND down --rmi local
    fi
}

# Pull latest changes
function git_pull() {
    say "Pulling latest changes..." "正在拉取最新代码..."
    git pull
    git submodule update
}

# Add base domain to env.local
function add_to_custom_env() {
    echo -e "Enter your domain or IP address. Default: localhost"
    echo -e "请输入域名或 IP 地址。默认: localhost"
    read -p "Enter / 输入: " DOMAIN_NAME
    if [ -z "$DOMAIN_NAME" ]; then
        DOMAIN_NAME="localhost"
    fi
    touch env.local
    set_env_value DOMAIN_NAME "$DOMAIN_NAME"
    echo -e "\nDomain / 域名: '"${DOMAIN_NAME}"' added to env.local\n"
    ensure_runtime_env

    echo -e "Do you want to show prices in sizes on the client side? (yes/no). Default: no"
    echo -e "是否在客户端规格列表显示价格？(yes/no)。默认: no"
    read -p "Enter / 输入: " ENABLE_PRICE
    if [ "$ENABLE_PRICE" = "yes" ]; then
        set_env_value VITE_DISPLAY_PRICES true
        echo -e "\nShow prices enabled on client side / 已启用客户端价格显示\n"
    else
        set_env_value VITE_DISPLAY_PRICES false
        echo -e "\nShow prices is not enabled on client side / 未启用客户端价格显示\n"
    fi

    echo -e "Do you want to enable Load Balancer features on client side? (yes/no). Default: no"
    echo -e "是否启用客户端负载均衡功能？(yes/no)。默认: no"
    read -p "Enter / 输入: " ENABLE_LB
    if [ "$ENABLE_LB" = "yes" ]; then
        set_env_value VITE_LOADBALANCER true
        echo -e "\nLoad Balancer enabled on client side / 已启用客户端负载均衡功能\n"
    else
        set_env_value VITE_LOADBALANCER false
        echo -e "\nLoad Balancer is not enabled on client side / 未启用客户端负载均衡功能\n"
    fi
}

# Show help function
function show_help() {
cat << "EOF"
Available commands:
可用命令:

env             Configure env.local
env             配置 env.local
start           Start WebVirtCloud
start           启动 WebVirtCloud
restart         Restart WebVirtCloud
restart         重启 WebVirtCloud
stop            Stop WebVirtCloud
stop            停止 WebVirtCloud
uninstall       Remove containers and local images; preserves volumes by default
uninstall       删除容器和本地镜像；默认保留数据卷
update          Update WebVirtCloud
update          更新 WebVirtCloud
loaddata        Load initial data
loaddata        加载初始数据
help            Show this message
help            显示帮助信息

EOF
}

# Run functions
case "$1" in
    "help")
        show_help
        ;;
    "env")
        add_to_custom_env
        ;;
    "start")
        start_webvirtcloud
        ;;
    "stop")
        stop_webvirtcloud
        ;;
    "uninstall")
        uninstall_webvirtcloud
        ;;
    "update")
        stop_webvirtcloud
        git_pull
        start_webvirtcloud
        ;;
    "loaddata")
        load_initial_data
        ;;
    "restart")
        restart_webvirtcloud
        ;;
    *)
        say "No command found." "未找到命令。"
        echo
        show_help
        ;;
esac
