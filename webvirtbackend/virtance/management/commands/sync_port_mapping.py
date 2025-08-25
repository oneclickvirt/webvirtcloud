from django.core.management.base import BaseCommand
from virtance.models import Virtance
from virtance.port_mapping import update_virtance_port_mapping, read_port_mapping_file, get_public_ip


class Command(BaseCommand):
    help = '同步虚拟机端口映射信息到数据库'

    def add_arguments(self, parser):
        parser.add_argument(
            '--vm-name',
            type=str,
            help='指定要同步的虚拟机名称，不指定则同步所有虚拟机',
        )

    def handle(self, *args, **options):
        vm_name = options.get('vm_name')
        
        if vm_name:
            # 同步指定虚拟机
            try:
                virtance = Virtance.objects.get(name=vm_name, is_deleted=False)
                if update_virtance_port_mapping(virtance):
                    self.stdout.write(
                        self.style.SUCCESS(f'成功同步虚拟机 {vm_name} 的端口映射信息')
                    )
                else:
                    self.stdout.write(
                        self.style.WARNING(f'虚拟机 {vm_name} 没有找到端口映射信息')
                    )
            except Virtance.DoesNotExist:
                self.stdout.write(
                    self.style.ERROR(f'虚拟机 {vm_name} 不存在')
                )
        else:
            # 同步所有虚拟机
            mapping_data = read_port_mapping_file()
            public_ip = get_public_ip()
            
            if not public_ip:
                self.stdout.write(
                    self.style.ERROR('无法获取公网IP地址')
                )
                return
            
            updated_count = 0
            for vm_name, mapping_info in mapping_data.items():
                try:
                    virtance = Virtance.objects.get(name=vm_name, is_deleted=False)
                    virtance.public_ip = public_ip
                    virtance.ssh_port = mapping_info['ssh_port']
                    virtance.port_range_start = mapping_info['port_start']
                    virtance.port_range_end = mapping_info['port_end']
                    virtance.save()
                    updated_count += 1
                    self.stdout.write(f'已同步虚拟机 {vm_name}')
                except Virtance.DoesNotExist:
                    self.stdout.write(
                        self.style.WARNING(f'数据库中未找到虚拟机 {vm_name}')
                    )
            
            self.stdout.write(
                self.style.SUCCESS(f'成功同步 {updated_count} 个虚拟机的端口映射信息')
            )