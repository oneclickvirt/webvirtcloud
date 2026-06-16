import request from '@/shared/api/request';
import { API_DOMAIN } from '@/shared/constants';

export function requestPasswordReset(payload: { email: string }): Promise<unknown> {
  return request
    .post('account/reset_password', {
      json: payload,
      prefixUrl: API_DOMAIN,
    })
    .json();
}

export function resetPassword(
  hash: string,
  payload: { password: string; password_confirm: string },
): Promise<unknown> {
  return request
    .post(`account/reset_password/${hash}`, {
      json: payload,
      prefixUrl: API_DOMAIN,
    })
    .json();
}
