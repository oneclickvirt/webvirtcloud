from decimal import Decimal
from ipaddress import IPv4Network
from django.utils import timezone

from webvirtcloud.celery import app
from compute.webvirt import WebVirtCompute
from virtance.utils import virtance_error
from .utils import floatip_error
from .models import FloatIP, FloatIPCounter
from network.models import Network, IPAddress
from virtance.models import Virtance


def _reset_floatip_event(floatip):
    if floatip.event is not None:
        floatip.reset_event()


def _reset_virtance_event(virtance):
    if virtance and virtance.event is not None:
        virtance.reset_event()


def _record_floatip_virtance_error(floatip, virtance, message, event):
    floatip_error(floatip.id, message, event)
    if virtance is not None:
        virtance_error(virtance.id, message, event)
    _reset_floatip_event(floatip)
    _reset_virtance_event(virtance)
    return False


def response_detail(res):
    if res is None:
        return "Compute returned no response."
    if isinstance(res, dict):
        return res.get("detail")
    return "Compute returned an invalid response."


@app.task
def assign_floating_ip(floating_ip_id, virtance_id):
    floatip = FloatIP.objects.select_related("ipaddress", "ipaddress__network").get(
        id=floating_ip_id, is_deleted=False
    )
    virtance = Virtance.objects.select_related("compute").get(id=virtance_id, is_deleted=False)
    ipaddress = floatip.ipaddress
    if ipaddress is None:
        message = "Floating IP has no allocated address."
        _record_floatip_virtance_error(floatip, virtance, message, "assign_floating_ip")
        return
    ipv4_float = IPAddress.objects.get(id=ipaddress.id)
    ipv4_compute = IPAddress.objects.filter(virtance=virtance, network__type=Network.COMPUTE).first()
    if virtance.compute is None:
        _record_floatip_virtance_error(
            floatip, virtance, "Virtance has no compute assigned.", "assign_floating_ip"
        )
        return
    if ipv4_compute is None:
        message = "Virtance has no compute network IP address."
        _record_floatip_virtance_error(floatip, virtance, message, "assign_floating_ip")
        return

    floatip.event = FloatIP.ASSIGN
    floatip.save()

    wvcomp = WebVirtCompute(virtance.compute.token, virtance.compute.hostname)
    ipv4_compute_prefix = IPv4Network(f"{ipv4_float.address}/{ipv4_float.network.netmask}", strict=False).prefixlen
    res = wvcomp.float_ip_assign(
        ipv4_compute.address, ipv4_float.address, ipv4_compute_prefix, ipv4_float.network.gateway
    )
    error = response_detail(res)
    if error:
        floatip_error(floatip.id, error, "assign_floating_ip")
        virtance_error(virtance.id, error, "assign_floating_ip")
        _reset_floatip_event(floatip)
        _reset_virtance_event(virtance)
    else:
        if ipaddress.virtance is None:
            ipaddress.virtance = virtance
            ipaddress.save()

        virtance.reset_event()
        floatip.reset_event()


@app.task
def unassign_floating_ip(floating_ip_id, virtance_reset_event=True):
    floatip = FloatIP.objects.select_related("ipaddress", "ipaddress__network").get(
        id=floating_ip_id, is_deleted=False
    )
    ipaddress = floatip.ipaddress
    if ipaddress is None:
        message = "Floating IP has no allocated address."
        floatip_error(floatip.id, message, "unassign_floating_ip")
        _reset_floatip_event(floatip)
        return
    virtance = ipaddress.virtance
    if virtance is None:
        floatip_error(floatip.id, "Floating IP is not assigned to a virtance.", "unassign_floating_ip")
        _reset_floatip_event(floatip)
        return
    ipv4_float = IPAddress.objects.get(id=ipaddress.id)
    ipv4_compute = IPAddress.objects.filter(virtance=virtance, network__type=Network.COMPUTE).first()
    if virtance.compute is None:
        _record_floatip_virtance_error(
            floatip, virtance, "Virtance has no compute assigned.", "unassign_floating_ip"
        )
        return
    if ipv4_compute is None:
        message = "Virtance has no compute network IP address."
        _record_floatip_virtance_error(floatip, virtance, message, "unassign_floating_ip")
        return

    wvcomp = WebVirtCompute(virtance.compute.token, virtance.compute.hostname)
    ipv4_compute_prefix = IPv4Network(f"{ipv4_float.address}/{ipv4_float.network.netmask}", strict=False).prefixlen
    res = wvcomp.float_ip_unassign(
        ipv4_compute.address, ipv4_float.address, ipv4_compute_prefix, ipv4_float.network.gateway
    )
    error = response_detail(res)
    if error:
        floatip_error(floatip.id, error, "unassign_floating_ip")
        virtance_error(virtance.id, error, "unassign_floating_ip")
        _reset_floatip_event(floatip)
        _reset_virtance_event(virtance)
    else:
        ipaddress.virtance = None
        ipaddress.save()

        if virtance_reset_event is True:
            virtance.reset_event()
        floatip.reset_event()


@app.task
def reassign_floating_ip(floating_ip_id, virtance_id):
    floatip = FloatIP.objects.select_related("ipaddress", "ipaddress__network").get(
        id=floating_ip_id, is_deleted=False
    )
    ipaddress = floatip.ipaddress
    virtance_new = Virtance.objects.select_related("compute").get(id=virtance_id, is_deleted=False)
    if ipaddress is None:
        message = "Floating IP has no allocated address."
        _record_floatip_virtance_error(floatip, virtance_new, message, "reassign_floating_ip")
        return
    virtance_old = ipaddress.virtance
    ipv4_float = IPAddress.objects.get(id=ipaddress.id)
    if virtance_old is None:
        floatip_error(floatip.id, "Floating IP is not assigned to a virtance.", "reassign_floating_ip")
        _reset_floatip_event(floatip)
        _reset_virtance_event(virtance_new)
        return

    floatip.event = FloatIP.UNASSIGN
    floatip.save()

    virtance_old.event = Virtance.UNASSIGN_FLOATING_IP
    virtance_old.save()

    ipv4_compute = IPAddress.objects.filter(virtance=virtance_old, network__type=Network.COMPUTE).first()
    if virtance_old.compute is None:
        _record_floatip_virtance_error(
            floatip, virtance_old, "Old virtance has no compute assigned.", "reassign_floating_ip"
        )
        _reset_virtance_event(virtance_new)
        return
    if ipv4_compute is None:
        message = "Old virtance has no compute network IP address."
        _record_floatip_virtance_error(floatip, virtance_old, message, "reassign_floating_ip")
        _reset_virtance_event(virtance_new)
        return
    wvcomp = WebVirtCompute(virtance_old.compute.token, virtance_old.compute.hostname)
    ipv4_compute_prefix = IPv4Network(f"{ipv4_float.address}/{ipv4_float.network.netmask}", strict=False).prefixlen
    res = wvcomp.float_ip_unassign(
        ipv4_compute.address, ipv4_float.address, ipv4_compute_prefix, ipv4_float.network.gateway
    )
    error = response_detail(res)
    if error:
        floatip_error(floatip.id, error, "reassign_floating_ip")
        virtance_error(virtance_old.id, error, "reassign_floating_ip")
        _reset_floatip_event(floatip)
        _reset_virtance_event(virtance_old)
        _reset_virtance_event(virtance_new)
    else:
        ipaddress.virtance = None
        ipaddress.save()

        floatip.event = FloatIP.ASSIGN
        floatip.save()

        virtance_old.reset_event()

        ipv4_compute_new = IPAddress.objects.filter(virtance=virtance_new, network__type=Network.COMPUTE).first()
        if virtance_new.compute is None:
            _record_floatip_virtance_error(
                floatip, virtance_new, "New virtance has no compute assigned.", "reassign_floating_ip"
            )
            return
        if ipv4_compute_new is None:
            message = "New virtance has no compute network IP address."
            _record_floatip_virtance_error(floatip, virtance_new, message, "reassign_floating_ip")
            return

        wvcomp = WebVirtCompute(virtance_new.compute.token, virtance_new.compute.hostname)
        ipv4_compute_prefix = IPv4Network(f"{ipv4_float.address}/{ipv4_float.network.netmask}", strict=False).prefixlen
        res = wvcomp.float_ip_assign(
            ipv4_compute_new.address, ipv4_float.address, ipv4_compute_prefix, ipv4_float.network.gateway
        )
        error = response_detail(res)
        if error:
            floatip_error(floatip.id, error, "reassign_floating_ip")
            virtance_error(virtance_new.id, error, "reassign_floating_ip")
            _reset_floatip_event(floatip)
            _reset_virtance_event(virtance_new)
        else:
            ipaddress.virtance = virtance_new
            ipaddress.save()

            virtance_new.reset_event()
            floatip.reset_event()


@app.task
def delete_floating_ip(floating_ip_id):
    error = False
    floatip = FloatIP.objects.select_related("ipaddress", "ipaddress__network").get(
        id=floating_ip_id, is_deleted=False
    )
    ipaddress = floatip.ipaddress
    if ipaddress is None:
        floatip_error(floatip.id, "Floating IP has no allocated address.", "delete_floating_ip")
        _reset_floatip_event(floatip)
        return
    virtance = ipaddress.virtance
    ipv4_float = IPAddress.objects.get(id=ipaddress.id)

    current_time = timezone.now()
    first_day_month = current_time.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    try:
        floatip_counter = FloatIPCounter.objects.get(started__gt=first_day_month, floatip=floatip, stopped=None)
    except FloatIPCounter.DoesNotExist:
        floatip_counter = FloatIPCounter.objects.create(
            floatip=floatip,
            amount=0.0,
            started=current_time - timezone.timedelta(hours=1),
        )

    if ipaddress.virtance:
        virtance = ipaddress.virtance
        virtance.event = Virtance.UNASSIGN_FLOATING_IP
        virtance.save()
        ipv4_compute = IPAddress.objects.filter(virtance=virtance, network__type=Network.COMPUTE).first()
        if virtance.compute is None:
            error = True
            _record_floatip_virtance_error(
                floatip, virtance, "Virtance has no compute assigned.", "delete_floating_ip"
            )
        elif ipv4_compute is None:
            error = True
            message = "Virtance has no compute network IP address."
            _record_floatip_virtance_error(floatip, virtance, message, "delete_floating_ip")
        else:
            wvcomp = WebVirtCompute(virtance.compute.token, virtance.compute.hostname)
            ipv4_compute_prefix = IPv4Network(
                f"{ipv4_float.address}/{ipv4_float.network.netmask}", strict=False
            ).prefixlen
            res = wvcomp.float_ip_unassign(
                ipv4_compute.address, ipv4_float.address, ipv4_compute_prefix, ipv4_float.network.gateway
            )
            detail = response_detail(res)
            if detail:
                error = True
                floatip_error(floatip.id, detail, "delete_floating_ip")
                virtance_error(virtance.id, detail, "delete_floating_ip")
                _reset_floatip_event(floatip)
                _reset_virtance_event(virtance)
            else:
                virtance.reset_event()

    if error is False:
        floatip_counter.stop()
        floatip.delete()
        ipaddress.delete()
    else:
        _reset_floatip_event(floatip)


@app.task
def floating_ip_counter():
    new_period = False
    current_time = timezone.now()
    current_day = current_time.day
    current_hour = current_time.hour
    first_day_current_month = current_time.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    if current_day == 1 and current_hour == 0:
        new_period = True

    for floatip in FloatIP.objects.filter(is_deleted=False):
        if floatip.ipaddress is None:
            floatip_error(floatip.id, "Floating IP has no allocated address.", "floating_ip_counter")
            continue
        try:
            FloatIPCounter.objects.get(started__gt=first_day_current_month, stopped=None, floatip=floatip)
        except FloatIPCounter.DoesNotExist:
            period_start = current_time - timezone.timedelta(hours=1)
            if new_period is True:
                period_start = first_day_current_month
            FloatIPCounter.objects.create(
                floatip=floatip, ipaddress=floatip.ipaddress.address, amount=0.0, started=period_start
            )

    if new_period is True:
        prev_month = current_time - timezone.timedelta(days=1)
        last_day_prev_month = prev_month.replace(hour=23, minute=59, second=59, microsecond=999999)
        first_day_prev_month = prev_month.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        floating_ip_counters = FloatIPCounter.objects.filter(started__gt=first_day_prev_month, stopped=None)
        floating_ip_counters.update(stopped=last_day_prev_month)
    else:
        floating_ip_counters = FloatIPCounter.objects.filter(started__gt=first_day_current_month, stopped=None)
        for floatip_count in floating_ip_counters:
            floatip_count.amount += Decimal(0.0)
            floatip_count.save()
