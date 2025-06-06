#!/usr/bin/env bash
set -e

DISTRO_NAME=""
OS_RELEASE="/etc/os-release"
PKG_MANAGER="dnf"

if [[ -f $OS_RELEASE ]]; then
  source $OS_RELEASE
  if [[ "$ID" =~ ^(rhel|rocky|centos|almalinux)$ ]] && [[ $VERSION_ID == [89]* ]]; then
    DISTRO_NAME="rhel"
    PKG_MANAGER="dnf"
  elif [[ $ID == "debian" ]] && [[ $VERSION_ID == "12" ]]; then
    DISTRO_NAME="debian"
    PKG_MANAGER="apt"
  elif [[ $ID == "ubuntu" ]] && [[ $VERSION_ID == "22.04" ]] || [[ $VERSION_ID == "24.04" ]]; then
    DISTRO_NAME="ubuntu"
    PKG_MANAGER="apt"
  else
    echo -e "\nUnsupported distribution or version! Supported releases: Rocky Linux 8-9, CentOS 8-9, AlmaLinux 8-9, Debian 12, Ubuntu 22.04 and Ubuntu 24.04.\n"
    exit 1
  fi
fi

# Check if br-ext is configured
if ! ip link show br-ext > /dev/null 2>&1; then
  echo -e "\nBridge br-ext is not found. Please configure it first!\n"
  exit 1
fi

# Check if br-int is configured
if ! ip link show br-int > /dev/null 2>&1; then
  echo -e "\nBridge br-int is not found. Please configure it first!\n"
  exit 1
fi

if [[ $DISTRO_NAME == "debian" ]] || [[ $DISTRO_NAME == "ubuntu" ]]; then
  if ! dpkg -l | grep -q "network-manager"; then
    echo -e "\nPackage network-manger is not installed. Please install and configure network-manager first!\n"
    exit 1
  fi
  if ! dpkg -l | grep -q "firewalld"; then
    echo -e "\nPackage firewalld is not installed. Please install firewall first!\n"
    exit 1
  fi
fi

# Install libvirt and dependencies based on distro
echo -e "\nInstalling libvirt and dependencies..."
if [[ $DISTRO_NAME == "rhel" ]]; then
  dnf install -y epel-release
  dnf install -y wget tuned libvirt qemu-kvm xmlstarlet cyrus-sasl-md5 qemu-guest-agent libguestfs-tools libguestfs-rescue libguestfs-winsupport libguestfs-bash-completion
elif [[ $DISTRO_NAME == "debian" ]] || [[ $DISTRO_NAME == "ubuntu" ]]; then
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y wget tuned libvirt-daemon-system qemu-kvm xmlstarlet sasl2-bin qemu-guest-agent libguestfs-tools libguestfs-rescue guestfs-tools
fi
echo -e "Installing libvirt and dependencies... - Done!\n"

echo -e "\nConfiguring libvirt..."

# Enable SASL for qemu
sed -i 's/#vnc_sasl/vnc_sasl/g' /etc/libvirt/qemu.conf

# Allow VNC connections to qemu
sed -i 's/#vnc_listen/vnc_listen/g' /etc/libvirt/qemu.conf

# Enable virt-host profile if applicable
if command -v tuned-adm &> /dev/null; then
  tuned-adm profile virtual-host
fi

# Add sysctl parameters
cat << EOF >> /etc/sysctl.d/99-bridge.conf
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.bridge.bridge-nf-call-arptables=1
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
EOF

# Apply sysctl parameters
sysctl --system

# Enable and start libvirtd - handle different service names/sockets
systemctl enable --now libvirtd
systemctl enable --now libvirt-guests
systemctl disable --now libvirtd-tcp.socket

# Create storage pool for images
virsh pool-define-as images dir - - - - "/var/lib/libvirt/images"
virsh pool-build images && virsh pool-start images && virsh pool-autostart images

# Create storage pool for ISOs
mkdir -p /var/lib/libvirt/isos
virsh pool-define-as isos dir - - - - "/var/lib/libvirt/isos"
virsh pool-build isos && virsh pool-start isos && virsh pool-autostart isos

# Create storage pool for backups
mkdir -p /var/lib/libvirt/backups
virsh pool-define-as backups dir - - - - "/var/lib/libvirt/backups"
virsh pool-build backups && virsh pool-start backups && virsh pool-autostart backups

# Try to remove network pool default if it exists
if virsh net-info default > /dev/null 2>&1; then
  if virsh net-info default | grep -q "Active"; then
    virsh net-destroy default || true
  fi
  virsh net-undefine default || true
fi

# Create network pool public
cat <<EOF | virsh net-define /dev/stdin
<network>
    <name>public</name>
    <forward mode='bridge'/>
    <bridge name='br-ext'/>
</network>
EOF
virsh net-start public && virsh net-autostart public

# Create network pool private
cat <<EOF | virsh net-define /dev/stdin
<network>
    <name>private</name>
    <forward mode='bridge'/>
    <bridge name='br-int'/>
</network>
EOF
virsh net-start private && virsh net-autostart private

# Create nwfiler rule for IPv6
cat <<EOF | virsh nwfilter-define /dev/stdin
<filter name='clean-traffic-ipv6' chain='root'>
    <filterref filter='no-mac-spoofing'/>
    <filterref filter='no-ip-spoofing'/>
    <rule action='accept' direction='out' priority='-650'>
        <mac protocolid='ipv4'/>
    </rule>
    <filterref filter='no-ipv6-spoofing'/>
    <rule action='accept' direction='out' priority='-650'>
        <mac protocolid='ipv6'/>
    </rule>
    <filterref filter='allow-incoming-ipv4'/>
    <filterref filter='allow-incoming-ipv6'/>
    <filterref filter='no-arp-spoofing'/>
    <rule action='accept' direction='inout' priority='-500'>
        <mac protocolid='arp'/>
    </rule>
    <filterref filter='no-other-l2-traffic'/>
    <filterref filter='qemu-announce-self'/>
</filter>
EOF
echo -e "Configuring libvirt... - Done!\n"

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
        echo "CDN available, using CDN"
    else
        echo "No CDN available, no use CDN"
    fi
}

# Download recovery image
echo -e "\nDownloading recovery image..."
cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn1.spiritlhl.net/" "http://cdn2.spiritlhl.net/" "http://cdn3.spiritlhl.net/" "http://cdn4.spiritlhl.net/")
check_cdn_file
# https://www.finnix.org/releases/125/finnix-125.iso
wget -O /var/lib/libvirt/isos/finnix-125.iso ${cdn_success_url}https://github.com/oneclickvirt/webvirtcloud/releases/download/webvirtcloud_dep/finnix-125.iso
echo -e "Downloading recovery image... - Done!\n"

# Enable firewall
systemctl enable --now firewalld

echo -e "\nLibvirt installation and configuring is complete!\n"

exit 0