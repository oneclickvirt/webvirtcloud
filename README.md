# webvirtcloud

Controller安装

至少1核1G内存10G空的硬盘

username: ```admin@webvirt.cloud```

password: ```admin```

```
curl -slk https://raw.githubusercontent.com/oneclickvirt/webvirtcloud/main/scripts/install_webvirt_cloud.sh -o install_webvirt_cloud.sh && chmod 777 install_webvirt_cloud.sh && bash install_webvirt_cloud.sh ctl
```

Hypervisor 安装

```
curl -slk https://raw.githubusercontent.com/oneclickvirt/webvirtcloud/main/scripts/install_hypervisor1.sh -o install_hypervisor1.sh && chmod 777 install_hypervisor1.sh && bash install_hypervisor1.sh
```

安装完毕后会显示backend的ip和token，这是需要在Controller的Admin面板中添加的节点信息
