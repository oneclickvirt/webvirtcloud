from http import HTTPStatus
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler
from django.http import JsonResponse
from django.urls import reverse_lazy
from django.shortcuts import render, redirect
from django.views.generic.base import TemplateView
from django.utils.decorators import method_decorator
from django.views.decorators.csrf import ensure_csrf_cookie


def _as_text(value):
    if value is None:
        return ""
    if isinstance(value, (list, tuple)):
        return _as_text(value[0]) if value else ""
    if isinstance(value, dict):
        return _as_text(next(iter(value.values()))) if value else ""
    return str(value)


def _error_details(data, prefix=None):
    if data is None:
        return {}

    if isinstance(data, dict):
        errors = {}
        for key, value in data.items():
            field_name = f"{prefix}.{key}" if prefix else key
            if key == "detail":
                continue
            if isinstance(value, dict):
                errors.update(_error_details(value, field_name))
            elif isinstance(value, (list, tuple)):
                errors[field_name] = [_as_text(item) for item in value] or [""]
            else:
                errors[field_name] = [_as_text(value)]
        return errors

    if isinstance(data, (list, tuple)):
        return {"non_field_errors": [_as_text(item) for item in data] or [""]}

    return {"non_field_errors": [_as_text(data)]}


def _api_error_payload(message, status_code, errors=None):
    payload = {
        "message": _as_text(message) or HTTPStatus(status_code).description,
        "status_code": status_code,
    }
    if errors:
        payload["errors"] = errors
    return payload


def success_message_response(message):
    status_code = status.HTTP_200_OK
    success_payload = {
        "message": message,
        "status_code": status_code,
    }
    return Response(success_payload, status=status_code)


def error_message_response(message, status_code=status.HTTP_400_BAD_REQUEST, errors=None):
    return Response(_api_error_payload(message, status_code, errors), status=status_code)


def app_exception_handler(exc, context):
    response = exception_handler(exc, context)

    if response is not None:
        status_code = response.status_code
        error_message = None

        if isinstance(response.data, dict):
            detail_error = response.data.get("detail")
            non_field_error = response.data.get("non_field_errors")

            if detail_error:
                error_message = detail_error
                if status_code == HTTPStatus.NOT_FOUND:
                    error_message = "The resource you were accessing could not be found."
                if status_code == HTTPStatus.INTERNAL_SERVER_ERROR:
                    error_message = "The resource you were accessing got internal error."

            if non_field_error:
                error_message = non_field_error[0]

        if isinstance(response.data, list):
            error_message = response.data[0]

        if not error_message:
            error_message = HTTPStatus(status_code).description

        response.data = _api_error_payload(error_message, status_code, _error_details(response.data))
    return response


def app_exception_handler403(request, exception):
    status_code = 403

    if "api/" in request.META["PATH_INFO"]:
        response = JsonResponse(
            {
                "status_code": status_code,
                "message": "Forbidden",
            },
            content_type="application/json",
            status=status_code,
        )
        return response

    return render(request, "403.html", status=status_code)


def app_exception_handler404(request, exception):
    status_code = 404

    if "api/" in request.META["PATH_INFO"]:
        response = JsonResponse(
            {
                "status_code": status_code,
                "message": "The resource you were accessing could not be found.",
            },
            content_type="application/json",
            status=status_code,
        )
        return response

    return render(request, "404.html", status=status_code)


def app_exception_handler500(request):
    status_code = 500

    if "api/" in request.META["PATH_INFO"]:
        response = JsonResponse(
            {
                "status_code": status_code,
                "message": "The resource you were accessing got internal error.",
            },
            content_type="application/json",
            status=status_code,
        )
        return response

    return render(request, "500.html", status=status_code)


class IndexView(TemplateView):
    template_name = "client/index.html"

    @method_decorator(ensure_csrf_cookie, name="dispatch")
    def dispatch(self, request, *args, **kwargs):
        if request.user and request.user.is_superuser:
            return redirect(reverse_lazy("admin_index"))
        return super(IndexView, self).dispatch(request, *args, **kwargs)
