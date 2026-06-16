from rest_framework.authentication import TokenAuthentication as BaseTokenAuthentication
from rest_framework.exceptions import AuthenticationFailed

from account.models import Token


class TokenAuthentication(BaseTokenAuthentication):
    model = Token
    keyword = "Bearer"

    def authenticate_credentials(self, key):
        user, token = super().authenticate_credentials(key)
        if token.is_expired():
            raise AuthenticationFailed("Token has expired.")
        return user, token
