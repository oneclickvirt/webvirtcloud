#!/usr/bin/env bash
set -e

DISTRO_NAME=""
DISTRO_VERSION=""
OS_RELEASE="/etc/os-release"

if [[ -f $OS_RELEASE ]]; then
  source $OS_RELEASE
  if [[ $ID == "rocky" ]]; then
    DISTRO_NAME="rockylinux"
  elif [[ $ID == "centos" ]]; then
    DISTRO_NAME="centos"
  elif [[ $ID == "almalinux" ]]; then
    DISTRO_NAME="almalinux"
  fi
    DISTRO_VERSION=$(echo "$VERSION_ID" | awk -F. '{print $1}')
fi

# Check if release file is recognized
if [[ -z $DISTRO_NAME ]]; then
  echo -e "\nDistro is not recognized. Supported releases: Rocky Linux 8-9, CentOS 8-9, AlmaLinux 8-9.\n"
  exit 1
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

# Update webvirtcompute
echo -e "\nUpdating webvirtcompute..."
cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn1.spiritlhl.net/" "http://cdn2.spiritlhl.net/" "http://cdn3.spiritlhl.net/" "http://cdn4.spiritlhl.net/")
check_cdn_file
wget -O /tmp/webvirtcompute-$DISTRO_NAME$DISTRO_VERSION-amd64.tar.gz "${cdn_success_url}https://github.com/oneclickvirt/webvirtcloud/releases/download/webvirtcloud_dep/webvirtcompute-$DISTRO_NAME$DISTRO_VERSION-amd64.tar.gz"
tar -xvf /tmp/webvirtcompute-$DISTRO_NAME$DISTRO_VERSION-amd64.tar.gz -C /tmp
systemctl stop webvirtcompute
cp /tmp/webvirtcompute/webvirtcompute /usr/local/bin/webvirtcompute
chmod +x /usr/local/bin/webvirtcompute
restorecon -v /usr/local/bin/webvirtcompute
systemctl start webvirtcompute
echo -e "Updating webvirtcompute... - Done!\n"

# Cleanup
rm -rf /tmp/webvirtcompute*

exit 0
