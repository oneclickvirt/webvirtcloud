from decimal import Decimal
from django.utils import timezone

from webvirtcloud.celery import app
from compute.webvirt import WebVirtCompute
from compute.models import Compute
from .models import Image, SnapshotCounter
from .utils import image_error


def _fail_image_delete(image, message):
    image_error(image.id, message, f"delete_image_{image.type}")
    image.reset_event()
    return False


def response_detail(res):
    if res is None:
        return "Compute returned no response."
    if isinstance(res, dict):
        return res.get("detail")
    return "Compute returned an invalid response."


@app.task
def image_delete(image_id):
    image = Image.objects.get(pk=image_id)
    image.event = Image.DELETE
    image.save()

    if image.type == Image.SNAPSHOT or image.type == Image.BACKUP:
        for region in image.regions.all():
            computes = Compute.objects.filter(region=region, is_active=True, is_deleted=False).order_by("?")
            deleted_or_missing = False
            last_error = "No active compute found in region."
            for compute in computes:
                wvcomp = WebVirtCompute(compute.token, compute.hostname)
                storages_res = wvcomp.get_storages()
                error = response_detail(storages_res)
                if error:
                    last_error = error
                    continue

                storages = storages_res.get("storages", [])
                if not storages:
                    deleted_or_missing = True

                inspected_storage = False
                storage_error = False
                volume_found = False
                for storage_summary in storages:
                    storage_res = wvcomp.get_storage(storage_summary.get("name"))
                    error = response_detail(storage_res)
                    if error:
                        last_error = error
                        storage_error = True
                        continue

                    inspected_storage = True
                    storage = storage_res.get("storage") or {}
                    for vol in storage.get("volumes", []):
                        if vol.get("name") != image.file_name:
                            continue
                        volume_found = True
                        delete_res = wvcomp.delete_storage_volume(storage.get("name"), vol.get("name"))
                        error = response_detail(delete_res)
                        if error:
                            last_error = error
                            storage_error = True
                        else:
                            deleted_or_missing = True
                        break

                    if deleted_or_missing is True:
                        break

                if inspected_storage is True and storage_error is False and volume_found is False:
                    deleted_or_missing = True

                if deleted_or_missing is True:
                    image.regions.remove(region)
                    break

            if deleted_or_missing is False:
                return _fail_image_delete(image, f"Region: {region}, Error:{last_error}")

        if image.regions.count() == 0:
            image.delete()

    return True


@app.task
def snapshot_counter():
    new_period = False
    current_time = timezone.now()
    current_day = current_time.day
    current_hour = current_time.hour
    first_day_current_month = current_time.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    if current_day == 1 and current_hour == 0:
        new_period = True

    for image in Image.objects.filter(type=Image.SNAPSHOT, is_deleted=False):
        try:
            SnapshotCounter.objects.get(started__gt=first_day_current_month, stopped=None, image=image)
        except SnapshotCounter.DoesNotExist:
            period_start = current_time - timezone.timedelta(hours=1)
            if new_period is True:
                period_start = first_day_current_month
            SnapshotCounter.objects.create(image=image, amount=0.0, started=period_start)

    if new_period is True:
        prev_month = current_time - timezone.timedelta(days=1)
        last_day_prev_month = prev_month.replace(hour=23, minute=59, second=59, microsecond=999999)
        first_day_prev_month = prev_month.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        snapshot_counters = SnapshotCounter.objects.filter(started__gt=first_day_prev_month, stopped=None)
        snapshot_counters.update(stopped=last_day_prev_month)
    else:
        snapshot_counters = SnapshotCounter.objects.filter(started__gt=first_day_current_month, stopped=None)
        for snap_count in snapshot_counters:
            snap_count.amount += Decimal(0.0)
            snap_count.save()
