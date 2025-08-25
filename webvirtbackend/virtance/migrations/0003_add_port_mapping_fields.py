# Generated manually for port mapping fields

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('virtance', '0002_virtance_type'),
    ]

    operations = [
        migrations.AddField(
            model_name='virtance',
            name='public_ip',
            field=models.GenericIPAddressField(blank=True, help_text='公网IP地址', null=True),
        ),
        migrations.AddField(
            model_name='virtance',
            name='ssh_port',
            field=models.IntegerField(blank=True, help_text='SSH端口映射', null=True),
        ),
        migrations.AddField(
            model_name='virtance',
            name='port_range_start',
            field=models.IntegerField(blank=True, help_text='端口范围起始', null=True),
        ),
        migrations.AddField(
            model_name='virtance',
            name='port_range_end',
            field=models.IntegerField(blank=True, help_text='端口范围结束', null=True),
        ),
    ]