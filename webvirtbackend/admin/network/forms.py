from django import forms
from crispy_forms.helper import FormHelper
from ipaddress import ip_address
from region.models import Region
from network.models import Network
from network.ipv6 import network_from_values


class CustomModelChoiceField(forms.ModelChoiceField):
    type_input = "select"

    def label_from_instance(self, item):
        return f"{item.name}"


class FormNetwork(forms.ModelForm):
    # Network.netmask is retained as a GenericIPAddressField for compatibility,
    # but operators commonly enter IPv6 prefix lengths such as "64".
    netmask = forms.CharField(max_length=39)

    def __init__(self, *args, **kwargs):
        super(FormNetwork, self).__init__(*args, **kwargs)
        self.helper = FormHelper()
        self.helper.form_tag = False
        self.fields["region"] = CustomModelChoiceField(queryset=Region.objects.filter(is_deleted=False))
        self.fields["region"].empty_label = None

    class Meta:
        model = Network
        fields = ["cidr", "netmask", "dns1", "dns2", "type", "region"]

    def clean(self):
        super().clean()
        cidr = self.cleaned_data.get("cidr")
        netmask = self.cleaned_data.get("netmask")
        dns1 = self.cleaned_data.get("dns1")
        dns2 = self.cleaned_data.get("dns2")
        region = self.cleaned_data.get("region")
        net_type = self.cleaned_data.get("type")

        # Validate CIDR
        try:
            subnet = network_from_values(cidr, netmask)
        except (TypeError, ValueError) as err:
            raise forms.ValidationError(err)

        if subnet.version == 6 and subnet.num_addresses < 3:
            raise forms.ValidationError("IPv6 network must leave addresses for a gateway and a guest")

        # Check if CIDR already exists
        if Network.objects.filter(cidr=cidr, netmask=netmask, region=region, is_deleted=True).exists():
            raise forms.ValidationError("Network already exists in this region")

        # Check if CIDR compute already exists in the region
        if net_type == Network.COMPUTE:
            if cidr != "10.255.0.0" and netmask != "255.255.0.0":
                raise forms.ValidationError("Compute network must be '10.255.0.0/255.255.0.0'")

        # Validate DNS
        if net_type == Network.PUBLIC:
            if not dns1 or not dns2:
                raise forms.ValidationError("DNS1 and DNS2 are required for public network")
            if dns1 == dns2:
                raise forms.ValidationError("DNS1 and DNS2 cannot be the same")
            if dns1 == "0.0.0.0" and dns2 == "0.0.0.0":
                raise forms.ValidationError("DNS1 and DNS2 cannot be 0.0.0.0")
            try:
                dns1_address = ip_address(dns1)
                dns2_address = ip_address(dns2)
            except ValueError as err:
                raise forms.ValidationError(err)
            if dns1_address.version != subnet.version or dns2_address.version != subnet.version:
                raise forms.ValidationError("Public DNS servers must use the same address family as the network")

        return self.cleaned_data

    def save(self, commit=True):
        cidr = self.cleaned_data.get("cidr")
        netmask = self.cleaned_data.get("netmask")
        dns1 = self.cleaned_data.get("dns1")
        dns2 = self.cleaned_data.get("dns2")
        region = self.cleaned_data.get("region")
        net_type = self.cleaned_data.get("type")
        subnet = network_from_values(cidr, netmask)

        network = Network.objects.create(
            cidr=str(subnet.network_address),
            netmask=str(subnet.netmask),
            gateway=str(subnet[1]),
            type=net_type,
            version=subnet.version,
            dns1=dns1,
            dns2=dns2,
            region=region,
        )

        return network


class FormNetworkUpdate(forms.ModelForm):
    netmask = forms.CharField(max_length=39)

    class Meta:
        model = Network
        fields = ["cidr", "netmask", "dns1", "dns2", "is_active"]

    def clean(self):
        cleaned_data = super().clean()
        cidr = cleaned_data.get("cidr")
        netmask = cleaned_data.get("netmask")

        try:
            subnet = network_from_values(cidr, netmask)
        except (TypeError, ValueError) as err:
            raise forms.ValidationError(err)

        if subnet.version == 6 and subnet.num_addresses < 3:
            raise forms.ValidationError("IPv6 network must leave addresses for a gateway and a guest")

        return cleaned_data

    def save(self, commit=True):
        network = super().save(commit=False)
        subnet = network_from_values(self.cleaned_data["cidr"], self.cleaned_data["netmask"])
        network.cidr = str(subnet.network_address)
        network.netmask = str(subnet.netmask)
        network.gateway = str(subnet[1])
        network.version = subnet.version
        if commit:
            network.save()
        return network
