from django.conf import settings
from webvirtcloud.celery import app

from .models import LBaaS, LBaaSForwadRule, LBaaSVirtance
from network.models import Network, IPAddress
from virtance.tasks import create_virtance, delete_virtance
from virtance.provision import ansible_play
from virtance.utils import check_ssh_connect, decrypt_data, virtance_error


provision_tasks = [
    {
        "name": "Template HAProxy configuration",
        "action": {
            "module": "template",
            "args": {
                "src": "ansible/lbaas/haproxy.cfg.j2",
                "dest": "/etc/haproxy/haproxy.cfg",
                "owner": "root",
                "group": "root",
                "mode": "0644",
            },
        },
    },
    {
        "name": "Restart haproxy service",
        "action": {
            "module": "systemd",
            "args": {"name": "haproxy", "state": "restarted", "enabled": "yes"},
        },
    },
    {
        "name": "Create iptables rules",
        "action": {
            "module": "template",
            "args": {
                "src": "ansible/lbaas/rules.v4.j2",
                "dest": "/etc/iptables/rules.v4",
                "owner": "root",
                "group": "root",
                "mode": "0644",
            },
        },
    },
    {
        "name": "Restart iptables service",
        "action": {
            "module": "systemd",
            "args": {
                "name": "netfilter-persistent",
                "state": "restarted",
                "enabled": "yes",
            },
        },
    },
    {
        "name": "Change prometheus listen address",
        "action": {
            "module": "replace",
            "args": {
                "dest": "/etc/default/prometheus",
                "regexp": 'ARGS=""',
                "replace": 'ARGS="--web.listen-address={{ ipv4_private_address }}:9090"',
            },
        },
    },
    {
        "name": "Restart prometheus service",
        "action": {"module": "systemd", "args": {"name": "prometheus", "state": "restarted"}},
    },
    {
        "name": "Disable systemd-resolved service",
        "action": {
            "module": "systemd",
            "args": {"name": "systemd-resolved", "state": "stopped", "enabled": "no"},
        },
    },
    {
        "name": "Remove resolv.conf symlink",
        "action": {
            "module": "file",
            "args": {
                "path": "/etc/resolv.conf",
                "state": "absent",
            },
        },
    },
    {
        "name": "Create resolv.conf",
        "action": {
            "module": "template",
            "args": {
                "src": "ansible/lbaas/resolv.conf.j2",
                "dest": "/etc/resolv.conf",
                "owner": "root",
                "group": "root",
                "mode": "0644",
            },
        },
    },
    {
        "name": "Listen SSH on private IP address",
        "action": {
            "module": "replace",
            "args": {
                "dest": "/etc/ssh/sshd_config",
                "regexp": "#ListenAddress 0.0.0.0",
                "replace": "ListenAddress {{ ipv4_private_address }}",
            },
        },
    },
    {"name": "Restart SSH service", "action": {"module": "systemd", "args": {"name": "sshd", "state": "reloaded"}}},
]


reload_tasks = [
    {
        "name": "Template HAProxy configuration",
        "action": {
            "module": "template",
            "args": {
                "src": "ansible/lbaas/haproxy.cfg.j2",
                "dest": "/etc/haproxy/haproxy.cfg",
                "owner": "root",
                "group": "root",
                "mode": "0644",
            },
        },
    },
    {
        "name": "Restart haproxy service",
        "action": {
            "module": "systemd",
            "args": {"name": "haproxy", "state": "restarted", "enabled": "yes"},
        },
    },
]


def provision_lbaas(host, private_key, tasks, lbaas_vars=None):
    task = None
    error = None

    res = ansible_play(private_key=private_key, hosts=host, tasks=tasks, extra_vars=lbaas_vars)

    if res.host_failed.items():
        for host, result in res.host_failed.items():
            task = result.task_name
            error = result._result["msg"]

    if res.host_unreachable.items():
        error = "Host unreachable."

    if res.host_ok.items():
        pass

    return error, task


def fail_lbaas_task(lbaas, message, event):
    if lbaas.virtance is not None:
        virtance_error(lbaas.virtance.id, message, event=event)
    lbaas.reset_event()
    if lbaas.virtance is not None and lbaas.virtance.event is not None:
        lbaas.virtance.reset_event()
    return False


def lbaas_member_vars_or_fail(lbaas, event):
    virtances = []
    for l_v in LBaaSVirtance.objects.filter(lbaas=lbaas, virtance__is_deleted=False, is_deleted=False):
        ipv4_private = IPAddress.objects.filter(
            virtance=l_v.virtance,
            network__type=Network.PRIVATE,
            network__version=Network.IPv4,
            is_float=False,
        ).first()
        if ipv4_private is None:
            fail_lbaas_task(
                lbaas,
                f"Virtance {l_v.virtance.id} is missing a private IP address.",
                event,
            )
            return None
        virtances.append(
            {
                "id": l_v.virtance.id,
                "ipv4_address": ipv4_private.address,
            }
        )
    return virtances


@app.task
def create_lbaas(lbaas_id):
    lbaas = LBaaS.objects.get(id=lbaas_id)
    private_key = decrypt_data(lbaas.private_key)

    if not create_virtance(lbaas.virtance.id, send_email=False):
        return fail_lbaas_task(lbaas, "Load balancer backing virtance creation failed.", "lbaas_create")

    ipv4_public = IPAddress.objects.filter(
        virtance=lbaas.virtance,
        network__type=Network.PUBLIC,
        network__version=Network.IPv4,
        is_float=False,
    ).first()
    ipv4_private = IPAddress.objects.filter(
        virtance=lbaas.virtance,
        network__type=Network.PRIVATE,
        network__version=Network.IPv4,
        is_float=False,
    ).first()
    if not ipv4_public or not ipv4_private:
        return fail_lbaas_task(lbaas, "Load balancer backing virtance is missing required IP addresses.", "lbaas_create")

    if not check_ssh_connect(ipv4_public.address, private_key=private_key):
        return fail_lbaas_task(lbaas, "Unable to connect to load balancer backing virtance over SSH.", "lbaas_create")

    health = {
        "check_protocol": lbaas.check_protocol,
        "check_port": lbaas.check_port,
        "check_path": lbaas.check_path,
        "check_interval_seconds": lbaas.check_interval_seconds,
        "check_timeout_seconds": lbaas.check_timeout_seconds,
        "check_unhealthy_threshold": lbaas.check_unhealthy_threshold,
        "check_healthy_threshold": lbaas.check_healthy_threshold,
    }

    forwarding_rules = []
    for rule in LBaaSForwadRule.objects.filter(lbaas=lbaas, is_deleted=False):
        forwarding_rules.append(
            {
                "entry_port": rule.entry_port,
                "entry_protocol": rule.entry_protocol,
                "target_port": rule.target_port,
                "target_protocol": rule.target_protocol,
            }
        )

    sticky_sessions = {}
    if lbaas.sticky_sessions:
        sticky_sessions = {
            "cookie_ttl": lbaas.sticky_sessions_cookie_ttl,
            "cookie_name": lbaas.sticky_sessions_cookie_name,
        }

    virtances = lbaas_member_vars_or_fail(lbaas, "lbaas_create")
    if virtances is None:
        return False

    lbaas_vars = {
        "health": health,
        "virtances": virtances,
        "sticky_sessions": sticky_sessions,
        "forwarding_rules": forwarding_rules,
        "redirect_to_https": lbaas.redirect_http_to_https,
        "ipv4_public_address": ipv4_public.address,
        "ipv4_private_address": ipv4_private.address,
        "ipv4_private_gateway": ipv4_private.network.gateway,
        "ipv4_lbaas_access_list": settings.LBAAS_IPV4_ACCESS_LIST,
    }
    error, task = provision_lbaas(ipv4_public.address, private_key, provision_tasks, lbaas_vars=lbaas_vars)
    if error:
        error_message = error
        if task:
            error_message = f"Task: {task}. Error: {error}"
        return fail_lbaas_task(lbaas, error_message, "lbaas_provision")
    lbaas.reset_event()
    return True


@app.task
def reload_lbaas(lbaas_id):
    lbaas = LBaaS.objects.get(id=lbaas_id)
    private_key = decrypt_data(lbaas.private_key)
    ipv4_public = IPAddress.objects.filter(
        virtance=lbaas.virtance,
        network__type=Network.PUBLIC,
        network__version=Network.IPv4,
        is_float=False,
    ).first()
    ipv4_private = IPAddress.objects.filter(
        virtance=lbaas.virtance,
        network__type=Network.PRIVATE,
        network__version=Network.IPv4,
        is_float=False,
    ).first()

    if not ipv4_public or not ipv4_private:
        return fail_lbaas_task(lbaas, "Load balancer backing virtance is missing required IP addresses.", "lbaas_reload")

    if not check_ssh_connect(ipv4_private.address, private_key=private_key):
        return fail_lbaas_task(lbaas, "Unable to connect to load balancer backing virtance over SSH.", "lbaas_reload")

    health = {
        "check_protocol": lbaas.check_protocol,
        "check_port": lbaas.check_port,
        "check_path": lbaas.check_path,
        "check_interval_seconds": lbaas.check_interval_seconds,
        "check_timeout_seconds": lbaas.check_timeout_seconds,
        "check_unhealthy_threshold": lbaas.check_unhealthy_threshold,
        "check_healthy_threshold": lbaas.check_healthy_threshold,
    }

    forwarding_rules = []
    for rule in LBaaSForwadRule.objects.filter(lbaas=lbaas, is_deleted=False):
        forwarding_rules.append(
            {
                "entry_port": rule.entry_port,
                "entry_protocol": rule.entry_protocol,
                "target_port": rule.target_port,
                "target_protocol": rule.target_protocol,
            }
        )

    sticky_sessions = {}
    if lbaas.sticky_sessions:
        sticky_sessions = {
            "cookie_ttl": lbaas.sticky_sessions_cookie_ttl,
            "cookie_name": lbaas.sticky_sessions_cookie_name,
        }

    virtances = lbaas_member_vars_or_fail(lbaas, "lbaas_reload")
    if virtances is None:
        return False

    lbaas_vars = {
        "health": health,
        "virtances": virtances,
        "sticky_sessions": sticky_sessions,
        "forwarding_rules": forwarding_rules,
        "redirect_to_https": lbaas.redirect_http_to_https,
        "ipv4_public_address": ipv4_public.address,
        "ipv4_private_address": ipv4_private.address,
        "ipv4_private_gateway": ipv4_private.network.gateway,
        "ipv4_lbaas_access_list": settings.LBAAS_IPV4_ACCESS_LIST,
    }
    error, task = provision_lbaas(ipv4_private.address, private_key, reload_tasks, lbaas_vars=lbaas_vars)
    if error:
        error_message = error
        if task:
            error_message = f"Task: {task}. Error: {error}"
        return fail_lbaas_task(lbaas, error_message, "lbaas_reload")
    lbaas.reset_event()
    return True


@app.task
def delete_lbaas(lbaas_id):
    lbaas = LBaaS.objects.get(id=lbaas_id)

    if delete_virtance(lbaas.virtance.id):
        lbaas.reset_event()
        lbaas.delete()
        return True
    return fail_lbaas_task(lbaas, "Load balancer backing virtance deletion failed.", "lbaas_delete")
