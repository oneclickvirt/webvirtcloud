from django.db.models import Q
from django.http import Http404
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response

from webvirtcloud.views import error_message_response
from .models import Image
from .tasks import image_delete
from .serializers import ImageSerializer, ImageActionSerializer, SnapshotsSerializer


class ImageListAPI(APIView):
    class_serializer = ImageSerializer

    def get_queryset(self):
        user = self.request.user
        i_type = self.request.query_params.get("type", None)
        public_types = (Image.DISTRIBUTION, Image.APPLICATION)
        user_types = (Image.CUSTOM, Image.BACKUP, Image.SNAPSHOT)

        if i_type:
            if i_type == Image.LBAAS:
                return Image.objects.none()
            if i_type in public_types:
                return Image.objects.filter(type=i_type, user=None, is_deleted=False)
            if i_type in user_types:
                return Image.objects.filter(type=i_type, user=user, is_deleted=False)
            return Image.objects.none()

        return Image.objects.filter(
            Q(type__in=public_types, user=None) | Q(type__in=user_types, user=user),
            is_deleted=False,
        )

    def get(self, request, *args, **kwargs):
        """
        List of All Types of Images
        ---
        """
        serilizator = self.class_serializer(self.get_queryset(), many=True)
        return Response({"images": serilizator.data})


class ImageDataAPI(APIView):
    class_serializer = ImageSerializer

    def get_object(self):
        image = get_object_or_404(Image, pk=self.kwargs.get("id"), is_deleted=False)
        if image.type == Image.LBAAS:
            raise Http404
        if image.type == Image.SNAPSHOT or image.type == Image.BACKUP or image.type == Image.CUSTOM:
            if image.user != self.request.user:
                raise Http404
        return image

    def get(self, request, *args, **kwargs):
        """
        Retrieve an Existing Image
        ---
        """
        serilizator = self.class_serializer(self.get_object(), many=False)
        return Response({"image": serilizator.data})

    def put(self, request, *args, **kwargs):
        """
        Update the Image (Only for snapshot image)
        ---
        """
        image = self.get_object()
        if image.type != Image.SNAPSHOT:
            return error_message_response("Only snapshot image can be updated.")
        serilizator = self.class_serializer(image, data=request.data)
        serilizator.is_valid(raise_exception=True)
        serilizator.save()
        serilizator = self.class_serializer(image, many=False)
        return Response({"image": serilizator.data})

    def delete(self, request, *args, **kwargs):
        """
        Delete the User Image
        ---
        """
        image = self.get_object()

        if image.event is not None:
            return error_message_response("The image already has event.")

        if image.type != Image.CUSTOM and image.type != Image.SNAPSHOT:
            raise Http404
        image_delete.delay(image.id)
        return Response(status=status.HTTP_204_NO_CONTENT)


class ImageActionAPI(APIView):
    class_serializer = ImageActionSerializer

    def get_object(self):
        image = get_object_or_404(Image, pk=self.kwargs.get("id"), is_deleted=False)
        if image.type == Image.LBAAS:
            raise Http404
        if image.type == Image.SNAPSHOT or image.type == Image.BACKUP or image.type == Image.CUSTOM:
            if image.user != self.request.user:
                raise Http404
        return image

    def post(self, request, *args, **kwargs):
        """
        Image Actions
        ---
            parameters:
                - name: action
                  description: Action type ("convert" or "transfer")
                  required: true
                  type: string

                - name: region
                  description: Region slug for transfer action
                  required: false
                  type: string
        """
        image = self.get_object()

        if image.event is not None:
            return error_message_response("The image already has event.")

        serilizator = self.class_serializer(data=request.data, context={"image": image})
        serilizator.is_valid(raise_exception=True)
        serilizator.save()
        return Response(serilizator.data)


class ImageSnapshotsAPI(APIView):
    class_serializer = SnapshotsSerializer

    def get_queryset(self):
        return Image.objects.filter(type=Image.SNAPSHOT, user=self.request.user, is_deleted=False)

    def get(self, request, *args, **kwargs):
        """
        List all User Snapshots
        ---
        """
        serilizator = self.class_serializer(self.get_queryset(), many=True)
        return Response({"snapshots": serilizator.data})
