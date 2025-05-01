#!/bin/bash
# https://github.com/oneclickvirt/webvirtcloud
# 虚拟机端口映射守护进程(libvirtd)
# 功能：
# 1. 监控虚拟机状态，自动配置端口映射规则
# 2. 持久化映射规则
# 3. 根据IP地址自动计算映射端口
# 4. 在虚拟机删除时自动清理规则
# 5. 在宿主机重启后自动恢复规则
# 6. 维护映射信息日志文件

# 配置参数
SCRIPT_PATH="/usr/local/sbin/vm_port_mapping_daemon.sh"
MAPPING_FILE="/etc/vm_port_mapping/mapping.txt"
MAPPING_DIR="/etc/vm_port_mapping"
PUBLIC_INTERFACE=$(ls /sys/class/net/ | grep -E '^(eth|en|eno|ens|enp)' | grep -v lo | head -n 1)
SLEEP_INTERVAL=60 # 监控间隔（秒）
LOG_FILE="/var/log/vm_port_mapping.log"
PID_FILE="/var/run/vm_port_mapping.pid"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_already_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" >/dev/null 2>&1; then
            log "守护进程已经在运行中，PID: $pid"
            return 0
        else
            log "发现过期的PID文件，将重新启动"
            rm -f "$PID_FILE"
        fi
    fi
    return 1
}

create_pid_file() {
    echo $$ >"$PID_FILE"
    log "创建PID文件: $PID_FILE, PID: $$"
}

initialize_mapping_file() {
    if [ ! -d "$MAPPING_DIR" ]; then
        mkdir -p "$MAPPING_DIR"
        chmod 750 "$MAPPING_DIR"
        log "创建映射目录: $MAPPING_DIR"
    fi
    if [ ! -f "$MAPPING_FILE" ]; then
        touch "$MAPPING_FILE"
        chmod 640 "$MAPPING_FILE"
        log "创建映射文件: $MAPPING_FILE"
    fi
}

get_vm_info() {
    vm_name=$1
    if ! virsh list --all | grep -q "$vm_name"; then
        log "虚拟机 $vm_name 不存在"
        return 1
    fi
    local bridge_name=""
    local mac_address=""
    while read -r line; do
        if echo "$line" | grep -q "public"; then
            bridge_name=$(echo "$line" | awk '{print $3}')
            mac_address=$(echo "$line" | awk '{print $5}')
            break
        fi
    done < <(virsh domiflist "$vm_name")
    if [ -z "$mac_address" ]; then
        log "无法获取虚拟机 $vm_name 的MAC地址"
        return 1
    fi
    local ip_address=""
    ip_address=$(ip neigh | grep -i "$mac_address" | head -n 1 | awk '{print $1}')

    if [ -z "$ip_address" ]; then
        log "无法获取虚拟机 $vm_name 的IP地址"
        return 1
    fi
    echo "$vm_name $ip_address $mac_address"
    return 0
}

generate_vm_id() {
    local vm_name=$1
    local ip=$2
    local last_octet=$(echo "$ip" | awk -F. '{print $4}')
    echo "$last_octet"
}

calculate_ports() {
    local vm_id=$1
    # 计算SSH端口映射: 最后一部分(VM ID)*100+22后加10000
    local ssh_port=$((vm_id * 100 + 22 + 10000))
    # 为每个VM分配一个专用的端口区间（VM ID决定区间）
    # 每个VM得到100个端口的区间，从20000开始
    local port_start=$((20000 + vm_id * 100))
    local port_end=$((port_start + 9)) # 分配10个端口
    echo "$ssh_port $port_start $port_end"
}

is_port_used() {
    local port=$1
    local vm_ip=$2
    if iptables-save | grep -v "$vm_ip" | grep -q "dport $port "; then
        return 0
    fi
    if firewall-cmd --permanent --list-forward-ports 2>/dev/null | grep -v "$vm_ip" | grep -q "port=$port:"; then
        return 0
    fi
    return 1
}

find_available_ports() {
    local vm_id=$1
    local vm_ip=$2
    local ports=$(calculate_ports "$vm_id")
    read -r ssh_port port_start port_end <<<"$ports"
    local base_ssh_port=$ssh_port
    while is_port_used "$ssh_port" "$vm_ip"; do
        ssh_port=$((ssh_port + 1))
        if [ $((ssh_port - base_ssh_port)) -gt 1000 ]; then
            log "无法为虚拟机 IP $vm_ip 找到可用的SSH端口"
            return 1
        fi
    done
    local base_port_start=$port_start
    while true; do
        local conflict=false
        for ((port = port_start; port <= port_end; port++)); do
            if is_port_used "$port" "$vm_ip"; then
                conflict=true
                break
            fi
        done
        if [ "$conflict" = false ]; then
            break
        fi
        port_start=$((port_start + 10))
        port_end=$((port_end + 10))
        if [ $((port_start - base_port_start)) -gt 1000 ]; then
            log "无法为虚拟机 IP $vm_ip 找到可用的端口范围"
            return 1
        fi
    done
    echo "$ssh_port $port_start $port_end"
    return 0
}

apply_firewall_rules() {
    local vm_name=$1
    local ip_address=$2
    local mac_address=$3
    local ssh_port=$4
    local port_start=$5
    local port_end=$6
    clean_firewall_rules "$ip_address"
    iptables -t nat -A PREROUTING -i "$PUBLIC_INTERFACE" -p tcp --dport "$ssh_port" -j DNAT --to-destination "$ip_address:22"
    iptables -t nat -A POSTROUTING -p tcp -d "$ip_address" --dport 22 -j MASQUERADE
    iptables -I INPUT -p tcp --dport "$ssh_port" -j ACCEPT
    log "为虚拟机 $vm_name ($ip_address) 添加SSH端口映射: 公网端口 $ssh_port -> 内部端口 22"
    for ((port = port_start; port <= port_end; port++)); do
        iptables -t nat -A PREROUTING -i "$PUBLIC_INTERFACE" -p tcp --dport "$port" -j DNAT --to-destination "$ip_address:$port"
        iptables -t nat -A POSTROUTING -p tcp -d "$ip_address" --dport "$port" -j MASQUERADE
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
        log "为虚拟机 $vm_name ($ip_address) 添加额外端口映射: 公网端口 $port -> 内部端口 $port"
    done
    local rule_exists=false
    if ! firewall-cmd --permanent --query-forward-port="port=$ssh_port:proto=tcp:toport=22:toaddr=$ip_address" &>/dev/null; then
        firewall-cmd --permanent --add-forward-port="port=$ssh_port:proto=tcp:toport=22:toaddr=$ip_address" &>/dev/null
        rule_exists=true
    fi
    for ((port = port_start; port <= port_end; port++)); do
        if ! firewall-cmd --permanent --query-forward-port="port=$port:proto=tcp:toport=$port:toaddr=$ip_address" &>/dev/null; then
            firewall-cmd --permanent --add-forward-port="port=$port:proto=tcp:toport=$port:toaddr=$ip_address" &>/dev/null
            rule_exists=true
        fi
    done
    if [ "$rule_exists" = true ]; then
        firewall-cmd --reload &>/dev/null
        log "防火墙规则已持久化并重新加载"
    fi
}

clean_firewall_rules() {
    local ip_address=$1
    iptables-save | grep -v "$ip_address" | iptables-restore
    local forward_ports=$(firewall-cmd --permanent --list-forward-ports 2>/dev/null | grep "$ip_address")
    if [ -n "$forward_ports" ]; then
        echo "$forward_ports" | while read -r port_rule; do
            local port=$(echo "$port_rule" | grep -oP 'port=\K[0-9]+')
            local proto=$(echo "$port_rule" | grep -oP 'proto=\K[a-z]+')
            local toport=$(echo "$port_rule" | grep -oP 'toport=\K[0-9]+')
            if [ -n "$port" ] && [ -n "$proto" ] && [ -n "$toport" ]; then
                firewall-cmd --permanent --remove-forward-port="port=$port:proto=$proto:toport=$toport:toaddr=$ip_address" &>/dev/null
            fi
        done
        firewall-cmd --reload &>/dev/null
        log "已清理 $ip_address 的防火墙转发规则"
    fi
}

update_mapping_file() {
    local temp_file=$(mktemp)
    virsh list --name | while read -r vm_name; do
        if [ -n "$vm_name" ]; then
            vm_info=$(get_vm_info "$vm_name")
            if [ $? -eq 0 ] && [ -n "$vm_info" ]; then
                read -r name ip mac <<<"$vm_info"
                local existing_ports=""
                if grep -q "^$name " "$MAPPING_FILE"; then
                    existing_ports=$(grep "^$name " "$MAPPING_FILE" | awk '{print $4" "$5" "$6}')
                fi
                if [ -z "$existing_ports" ]; then
                    local vm_id=$(generate_vm_id "$name" "$ip")
                    ports=$(find_available_ports "$vm_id" "$ip")
                    if [ $? -ne 0 ]; then
                        log "无法为虚拟机 $name 分配端口，跳过"
                        continue
                    fi
                else
                    ports="$existing_ports"
                fi
                read -r ssh_port port_start port_end <<<"$ports"
                echo "$name $ip $mac $ssh_port $port_start $port_end" >>"$temp_file"
            fi
        fi
    done
    if [ -s "$temp_file" ]; then
        mv "$temp_file" "$MAPPING_FILE"
        chmod 640 "$MAPPING_FILE"
        log "映射文件已更新: $MAPPING_FILE"
    else
        rm "$temp_file"
        log "没有发现活动的虚拟机，映射文件未更新"
    fi
}

apply_all_rules() {
    update_mapping_file
    if [ -f "$MAPPING_FILE" ] && [ -s "$MAPPING_FILE" ]; then
        while read -r vm_name ip_address mac_address ssh_port port_start port_end; do
            if virsh list | grep -q "$vm_name"; then
                apply_firewall_rules "$vm_name" "$ip_address" "$mac_address" "$ssh_port" "$port_start" "$port_end"
            fi
        done <"$MAPPING_FILE"
    else
        log "映射文件不存在或为空，没有规则需要应用"
    fi
}

check_and_restore_rules() {
    if [ -f "$MAPPING_FILE" ] && [ -s "$MAPPING_FILE" ]; then
        while read -r vm_name ip_address mac_address ssh_port port_start port_end; do
            if virsh list | grep -q "$vm_name"; then
                if ! iptables-save | grep -q "$ip_address:22"; then
                    log "检测到虚拟机 $vm_name 的规则丢失，正在恢复..."
                    apply_firewall_rules "$vm_name" "$ip_address" "$mac_address" "$ssh_port" "$port_start" "$port_end"
                fi
            else
                if ! virsh list --all | grep -q "$vm_name"; then
                    log "虚拟机 $vm_name 已被删除，清理相关规则"
                    clean_firewall_rules "$ip_address"
                    sed -i "/^$vm_name /d" "$MAPPING_FILE"
                fi
            fi
        done <"$MAPPING_FILE"
    fi
}

monitor_vm_changes() {
    local previous_vms=""
    local current_vms=""

    log "开始监控虚拟机状态变化..."
    while true; do
        current_vms=$(virsh list --all | grep -v "Id.*Name.*State" | sort | tr '\n' ' ')
        if [ "$current_vms" != "$previous_vms" ]; then
            log "检测到虚拟机状态变化，重新应用规则"
            apply_all_rules
        else
            check_and_restore_rules
        fi
        previous_vms="$current_vms"
        sleep "$SLEEP_INTERVAL"
    done
}

run_daemon() {
    if check_already_running; then
        exit 0
    fi

    create_pid_file
    log "启动虚拟机端口映射守护进程"
    initialize_mapping_file
    apply_all_rules
    monitor_vm_changes
}

create_systemd_service() {
    # 检查服务是否已经存在
    if [ -f "/etc/systemd/system/vm-port-mapping.service" ]; then
        log "服务已存在，跳过创建"
        return
    fi

    cat >/etc/systemd/system/vm-port-mapping.service <<EOF
[Unit]
Description=VM Port Mapping Daemon
After=network.target libvirtd.service
Wants=firewalld.service

[Service]
Type=simple
ExecStart=$SCRIPT_PATH run
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 /etc/systemd/system/vm-port-mapping.service
    systemctl daemon-reload
    systemctl enable vm-port-mapping.service
    systemctl start vm-port-mapping.service
    log "systemd服务已创建并启动"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "$1" in
    install)
        # 安装模式：复制脚本并创建服务
        if [ ! -f "$SCRIPT_PATH" ] || [ "$(realpath "${BASH_SOURCE[0]}")" != "$(realpath "$SCRIPT_PATH")" ]; then
            cp "${BASH_SOURCE[0]}" "$SCRIPT_PATH"
            chmod 755 "$SCRIPT_PATH"
            log "脚本已复制到 $SCRIPT_PATH"
        fi
        create_systemd_service
        ;;
    run)
        # 运行模式：直接启动守护进程
        run_daemon
        ;;
    *)
        # 默认模式：如果是第一次运行则安装，否则运行
        if [ "$(realpath "${BASH_SOURCE[0]}")" != "$(realpath "$SCRIPT_PATH")" ]; then
            # 不是从安装位置运行，执行安装
            "$0" install
        else
            # 从安装位置运行，执行守护进程
            "$0" run
        fi
        ;;
    esac
fi
