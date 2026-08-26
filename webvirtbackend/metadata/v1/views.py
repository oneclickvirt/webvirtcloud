from django.http import HttpResponse, JsonResponse

from lbaas.models import LBaaS
from keypair.models import KeyPairVirtance
from network.models import Network, IPAddress
from virtance.utils import decrypt_data, make_ssh_public
from .utils import MetadataMixin


def not_found_response():
    return HttpResponse("Not Found", status=404)


def get_virtance_ip(virtance, network_type, version=Network.IPv4):
    if virtance is None:
        return None
    return IPAddress.objects.select_related("network").filter(
        virtance=virtance, network__type=network_type, network__version=version
    ).first()


def ip_metadata(ipaddr):
    if ipaddr is None:
        return None
    return {
        "ip_address": ipaddr.address,
        "netmask": ipaddr.network.netmask,
        "gateway": ipaddr.network.gateway,
    }


class MetadataV1Json(MetadataMixin):
    def get(self, request, *args, **kwargs):
        """
        Retrieve an Metadata JSON for a Virtance
        """
        vendor_data = ""
        nameservers = []
        public_keys = []

        if self.virtance is None:
            return not_found_response()

        for i in KeyPairVirtance.objects.filter(virtance=self.virtance):
            public_keys.append(i.keypair.public_key)

        if self.virtance.type == self.virtance.LBAAS:
            lbaas = LBaaS.objects.filter(virtance_id=self.virtance.id, is_deleted=False).first()
            if lbaas is None:
                return not_found_response()
            private_key = decrypt_data(lbaas.private_key)
            public_keys.append(make_ssh_public(private_key))

        compute_ip = get_virtance_ip(self.virtance, Network.COMPUTE)
        public_ip = get_virtance_ip(self.virtance, Network.PUBLIC)
        private_ip = get_virtance_ip(self.virtance, Network.PRIVATE)

        if compute_ip is None or public_ip is None or private_ip is None:
            return not_found_response()

        interfaces = {
            "public": [
                {
                    "compute_ipv4": ip_metadata(compute_ip),
                    "ipv4": ip_metadata(public_ip),
                    "mac": "00:00:00:00:00:00",
                    "type": "public",
                }
            ],
            "private": [
                {
                    "ipv4": ip_metadata(private_ip),
                    "mac": "00:00:00:00:00:00",
                    "type": "private",
                }
            ],
        }

        nameservers = [public_ip.network.dns1, public_ip.network.dns2]

        response = {
            "id": self.virtance.id,
            "hostname": self.virtance.name,
            "user-data": self.virtance.user_data,
            "vendor-data": vendor_data,
            "public-keys": public_keys,
            "region": self.virtance.region.slug,
            "interfaces": interfaces,
            "dns": {
                "nameservers": nameservers,
            },
        }
        return JsonResponse(response)


class MetadataIndex(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        data = ["id", "hostname", "user-data", "vendor-data", "public-keys", "region", "interfaces/", "dns/"]
        response = "\n".join(data)
        return HttpResponse(response)


class MetadataID(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        return HttpResponse(self.virtance.id)


class MetadataHostname(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        return HttpResponse(self.virtance.name)


class MetadataUserData(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        user_data = self.virtance.user_data if self.virtance.user_data else ""
        return HttpResponse(user_data)


class MetadataVendorData(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        vendor_data = ""
        return HttpResponse(vendor_data)


class MetadataPublicKeys(MetadataMixin):
    def get(self, request, *args, **kwargs):
        public_Keys = ""
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        for i in KeyPairVirtance.objects.filter(virtance=self.virtance):
            if public_Keys:
                public_Keys += "\n"
            public_Keys += i.keypair.public_key
        return HttpResponse(public_Keys)


class MetadataInterfaces(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        data = ["public/", "private/"]
        response = "\n".join(data)
        return HttpResponse(response)


class MetadataInterfacesPublic(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        data = ["0/"]
        response = "\n".join(data)
        return HttpResponse(response)


class MetadataInterfacesPublicData(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        data = ["mac", "type", "compute_ipv4/", "ipv4/"]
        response = "\n".join(data)
        return HttpResponse(response)


class MetadataInterfacesPublicMAC(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        mac = "00:00:00:00:00:00"
        return HttpResponse(mac)


class MetadataInterfacesPublicType(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        return HttpResponse("public")


class MetadataInterfacesPublicIPv4(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        data = ["address", "netmask", "gateway"]
        response = "\n".join(data)
        return HttpResponse(response)


class MetadataInterfacesPublicIPv4Address(MetadataMixin):
    def get(self, request, *args, **kwargs):
        ipaddr = get_virtance_ip(self.virtance, Network.PUBLIC)
        if self.virtance is None or ipaddr is None:
            return not_found_response()
        return HttpResponse(ipaddr.address)


class MetadataInterfacesPublicIPv4Netmask(MetadataMixin):
    def get(self, request, *args, **kwargs):
        ipaddr = get_virtance_ip(self.virtance, Network.PUBLIC)
        if self.virtance is None or ipaddr is None:
            return not_found_response()
        return HttpResponse(ipaddr.network.netmask)


class MetadataInterfacesPublicIPv4Gateway(MetadataMixin):
    def get(self, request, *args, **kwargs):
        ipaddr = get_virtance_ip(self.virtance, Network.PUBLIC)
        if self.virtance is None or ipaddr is None:
            return not_found_response()
        return HttpResponse(ipaddr.network.gateway)


class MetadataInterfacesPublicComputeIPv4(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        data = ["address", "netmask", "gateway"]
        response = "\n".join(data)
        return HttpResponse(response)


class MetadataInterfacesPublicComputeIPv4Address(MetadataMixin):
    def get(self, request, *args, **kwargs):
        ipaddr = get_virtance_ip(self.virtance, Network.COMPUTE)
        if self.virtance is None or ipaddr is None:
            return not_found_response()
        return HttpResponse(ipaddr.address)


class MetadataInterfacesPublicComputeIPv4Netmask(MetadataMixin):
    def get(self, request, *args, **kwargs):
        ipaddr = get_virtance_ip(self.virtance, Network.COMPUTE)
        if self.virtance is None or ipaddr is None:
            return not_found_response()
        return HttpResponse(ipaddr.network.netmask)


class MetadataInterfacesPublicComputeIPv4Gateway(MetadataMixin):
    def get(self, request, *args, **kwargs):
        ipaddr = get_virtance_ip(self.virtance, Network.COMPUTE)
        if self.virtance is None or ipaddr is None:
            return not_found_response()
        return HttpResponse(ipaddr.network.gateway)


class MetadataInterfacesPrivate(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        data = ["0/"]
        response = "\n".join(data)
        return HttpResponse(response)


class MetadataInterfacesPrivateData(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        data = ["mac", "type", "ipv4/"]
        response = "\n".join(data)
        return HttpResponse(response)


class MetadataInterfacesPrivateMAC(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        mac = "00:00:00:00:00:00"
        return HttpResponse(mac)


class MetadataInterfacesPrivateType(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        return HttpResponse("private")


class MetadataInterfacesPrivateIPv4(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        data = ["address", "netmask", "gateway"]
        response = "\n".join(data)
        return HttpResponse(response)


class MetadataInterfacesPrivateIPv4Address(MetadataMixin):
    def get(self, request, *args, **kwargs):
        ipaddr = get_virtance_ip(self.virtance, Network.PRIVATE)
        if self.virtance is None or ipaddr is None:
            return not_found_response()
        return HttpResponse(ipaddr.address)


class MetadataInterfacesPrivateIPv4Netmask(MetadataMixin):
    def get(self, request, *args, **kwargs):
        ipaddr = get_virtance_ip(self.virtance, Network.PRIVATE)
        if self.virtance is None or ipaddr is None:
            return not_found_response()
        return HttpResponse(ipaddr.network.netmask)


class MetadataInterfacesPrivateIPv4Gateway(MetadataMixin):
    def get(self, request, *args, **kwargs):
        ipaddr = get_virtance_ip(self.virtance, Network.PRIVATE)
        if self.virtance is None or ipaddr is None:
            return not_found_response()
        return HttpResponse(ipaddr.network.gateway)


class MetadataDNS(MetadataMixin):
    def get(self, request, *args, **kwargs):
        if self.virtance is None:
            return HttpResponse("Not Found", status=404)
        data = ["nameservers"]
        response = "\n".join(data)
        return HttpResponse(response)


class MetadataDNSNameservers(MetadataMixin):
    def get(self, request, *args, **kwargs):
        ipaddr = get_virtance_ip(self.virtance, Network.PUBLIC)
        if self.virtance is None or ipaddr is None:
            return not_found_response()
        response = "\n".join([ipaddr.network.dns1, ipaddr.network.dns2])
        return HttpResponse(response)
