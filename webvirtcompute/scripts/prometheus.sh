#!/usr/bin/env bash
set -e

DISTRO_NAME=""
DISTRO_VERSION=""
OS_RELEASE="/etc/os-release"
PKG_MANAGER="dnf"

if [[ -f $OS_RELEASE ]]; then
  source $OS_RELEASE
  DISTRO_VERSION=$(echo "$VERSION_ID" | awk -F. '{print $1}')
  if [[ "$ID" =~ ^(rhel|rocky|centos|almalinux)$ ]] && [[ $VERSION_ID == [89]* ]]; then
    DISTRO_NAME="rhel"
    PKG_MANAGER="dnf"
  elif [[ $ID == "debian" ]] && [[ $VERSION_ID == "12" ]]; then
    DISTRO_NAME="debian"
    PKG_MANAGER="apt"
  elif [[ $ID == "ubuntu" ]] && [[ $VERSION_ID == "22.04" || $VERSION_ID == "24.04" ]]; then
    DISTRO_VERSION=$(echo "$VERSION_ID" | awk -F. '{print $1$2}')
    DISTRO_NAME="ubuntu"
    PKG_MANAGER="apt"
  else
    echo -e "\nUnsupported distribution or version! Supported releases: Rocky Linux 8-9, CentOS 8-9, AlmaLinux 8-9, Debian 12, Ubuntu 22.04 and Ubuntu 24.04.\n"
    exit 1
  fi
fi

# Check if libvirt is installed
if [[ $DISTRO_NAME == "rhel" ]]; then
  if ! dnf list installed libvirt > /dev/null 2>&1; then
    echo -e "\nPackage libvirt is not installed. Please install and configure libvirt first!\n"
    exit 1
  fi
elif [[ $DISTRO_NAME == "debian" ]] || [[ $DISTRO_NAME == "ubuntu" ]]; then
  if ! dpkg -l | grep -q "libvirt-daemon-system"; then
    echo -e "\nPackage libvirt-daemon-system is not installed. Please install and configure libvirt first!\n"
    exit 1
  fi
fi

# Install prometheus
echo -e "\nInstalling and configuring prometheus..."
if [[ $DISTRO_NAME == "rhel" ]]; then
  dnf install -y epel-release
  dnf install -y golang-github-prometheus golang-github-prometheus-node-exporter
elif [[ $DISTRO_NAME == "debian" ]] || [[ $DISTRO_NAME == "ubuntu" ]]; then
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y prometheus prometheus-node-exporter
fi

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

# Download and install libvirt exporter
cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn1.spiritlhl.net/" "http://cdn2.spiritlhl.net/" "http://cdn3.spiritlhl.net/" "http://cdn4.spiritlhl.net/")
check_cdn_file
wget -O /tmp/prometheus-libvirt-exporter.tar.gz ${cdn_success_url}https://github.com/oneclickvirt/webvirtcloud/releases/download/webvirtcloud_dep/prometheus-libvirt-exporter-$DISTRO_NAME$DISTRO_VERSION-amd64.tar.gz
tar -xvf /tmp/prometheus-libvirt-exporter.tar.gz -C /tmp
cp /tmp/prometheus-libvirt-exporter/prometheus-libvirt-exporter /usr/local/bin/
chmod +x /usr/local/bin/prometheus-libvirt-exporter

# Apply SELinux context if applicable
if [[ $DISTRO_NAME == "rhel" ]] && command -v restorecon &> /dev/null; then
  restorecon -v /usr/local/bin/prometheus-libvirt-exporter
fi

# Configure Prometheus libvirt exporter service
cp /tmp/prometheus-libvirt-exporter/prometheus-libvirt-exporter.service /etc/systemd/system/prometheus-libvirt-exporter.service

# Add libvirt exporter to prometheus config
cat << EOF >> /etc/prometheus/prometheus.yml

  - job_name: libvirt
    # Libvirt exporter
    static_configs:
      - targets: ['localhost:9177']
EOF

# Reload systemd and enable services
systemctl daemon-reload
systemctl enable --now prometheus-libvirt-exporter

# Enable and start services based on distro-specific names
systemctl enable --now prometheus-node-exporter
systemctl enable --now prometheus

echo -e "\nInstalling and configuring prometheus... - Done!\n"

# Clean up
rm -rf /tmp/prometheus-libvirt-exporter*

exit 0
