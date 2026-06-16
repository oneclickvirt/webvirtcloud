from webvirtcloud.celery import app

from compute.webvirt import WebVirtCompute
from virtance.utils import virtance_error
from .utils import firewall_error
from .models import Firewall, FirewallVirtance, Rule, Cidr
from network.models import Network, IPAddress
from virtance.models import Virtance


def fail_firewall_task(firewall, virtance, message, event, virtance_reset_event=True):
    firewall_error(firewall.id, message, event)
    virtance_error(virtance.id, message, event)
    if virtance_reset_event is True:
        virtance.reset_event()
    firewall.reset_event()
    return False


def response_detail(res):
    if res is None:
        return "Compute returned no response."
    if isinstance(res, dict):
        return res.get("detail")
    return "Compute returned an invalid response."


@app.task
def firewall_attach(firewall_id, virtance_id, virtance_reset_event=True):
    inbound_rules = []
    outbound_rules = []
    virtance = Virtance.objects.select_related("compute").get(id=virtance_id, is_deleted=False)
    firewall = Firewall.objects.get(id=firewall_id, is_deleted=False)
    firewall_rules = Rule.objects.filter(firewall=firewall)
    ipv4_public = IPAddress.objects.filter(virtance=virtance, network__type=Network.PUBLIC, is_float=False).first()
    ipv4_private = IPAddress.objects.filter(virtance=virtance, network__type=Network.PRIVATE).first()

    if virtance.compute is None or ipv4_public is None or ipv4_private is None:
        return fail_firewall_task(
            firewall,
            virtance,
            "Virtance is missing compute, public IP, or private IP for firewall attach.",
            "firewall_attach",
            virtance_reset_event=virtance_reset_event,
        )

    for rule in firewall_rules:
        cidrs = Cidr.objects.filter(rule=rule)
        if rule.direction == Rule.INBOUND:
            inbound_rules.append(
                {
                    "protocol": rule.protocol,
                    "action": rule.action,
                    "ports": rule.ports,
                    "addresses": [f"{i.address}/{i.prefix}" for i in cidrs],
                }
            )
        if rule.direction == Rule.OUTBOUND:
            outbound_rules.append(
                {
                    "protocol": rule.protocol,
                    "action": rule.action,
                    "ports": rule.ports,
                    "addresses": [f"{i.address}/{i.prefix}" for i in cidrs],
                }
            )

    wvcomp = WebVirtCompute(virtance.compute.token, virtance.compute.hostname)
    res = wvcomp.firewall_attach(firewall.id, ipv4_public.address, ipv4_private.address, inbound_rules, outbound_rules)
    error = response_detail(res)
    if error:
        return fail_firewall_task(
            firewall, virtance, error, "firewall_attach", virtance_reset_event=virtance_reset_event
        )
    else:
        if virtance_reset_event is True:
            virtance.reset_event()
        firewall.reset_event()
        return True


@app.task
def firewall_detach(firewall_id, virtance_id, virtance_reset_event=True, unlink_db=True):
    virtance = Virtance.objects.select_related("compute").get(id=virtance_id, is_deleted=False)
    firewall = Firewall.objects.get(id=firewall_id, is_deleted=False)
    ipv4_public = IPAddress.objects.filter(virtance=virtance, network__type=Network.PUBLIC, is_float=False).first()
    ipv4_private = IPAddress.objects.filter(virtance=virtance, network__type=Network.PRIVATE).first()

    if virtance.compute is None or ipv4_public is None or ipv4_private is None:
        return fail_firewall_task(
            firewall,
            virtance,
            "Virtance is missing compute, public IP, or private IP for firewall detach.",
            "firewall_detach",
            virtance_reset_event=virtance_reset_event,
        )

    wvcomp = WebVirtCompute(virtance.compute.token, virtance.compute.hostname)
    res = wvcomp.firewall_detach(firewall.id, ipv4_public.address, ipv4_private.address)
    error = response_detail(res)
    if error:
        return fail_firewall_task(
            firewall, virtance, error, "firewall_detach", virtance_reset_event=virtance_reset_event
        )
    else:
        if unlink_db is True:
            FirewallVirtance.objects.filter(firewall=firewall, virtance=virtance).delete()
        if virtance_reset_event is True:
            virtance.reset_event()
        if firewall.event == Firewall.DELETE and not FirewallVirtance.objects.filter(firewall=firewall).exists():
            firewall.delete()
        else:
            firewall.reset_event()
        return True


@app.task
def firewall_update(firewall_id, virtance_id):
    # Detach firewall first
    detached = firewall_detach(firewall_id, virtance_id, virtance_reset_event=False, unlink_db=False)

    # Attach firewall with new rules
    if detached:
        return firewall_attach(firewall_id, virtance_id)
    return False
