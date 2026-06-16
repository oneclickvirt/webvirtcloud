from django.views.generic import View

from virtance.models import Virtance
from network.models import IPAddress


class MetadataMixin(View):
    virtance = None

    def dispatch(self, request, *args, **kwargs):
        x_instance_id = request.META.get("HTTP_X_INSTANCE_ID")
        x_forwarded_for = request.META.get("HTTP_X_FORWARDED_FOR")

        # Get by header ID
        if x_instance_id:
            self.virtance = Virtance.objects.filter(pk=x_instance_id, is_deleted=False).first()

        # Get by IP address
        if not x_instance_id:
            if x_forwarded_for:
                remote_address = x_forwarded_for.split(",")[0]
            else:
                remote_address = request.META.get("REMOTE_ADDR")

            remote_address = remote_address.strip() if remote_address else remote_address
            ip = (
                IPAddress.objects.select_related("virtance")
                .filter(address=remote_address, virtance__is_deleted=False)
                .first()
            )
            if ip and ip.virtance:
                self.virtance = ip.virtance

        return super(MetadataMixin, self).dispatch(request, *args, **kwargs)
