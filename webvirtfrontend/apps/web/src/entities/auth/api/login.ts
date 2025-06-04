import { type AuthPayload } from '@/entities/auth';
import request from '@/shared/api/request';
import { API_DOMAIN, API_PREFIX } from '@/shared/constants';

export function login(payload: AuthPayload): Promise<{ token: string }> {
  return request
    .post('account/login', {
      json: payload,
      prefixUrl: `${API_DOMAIN}${API_PREFIX}`,
    })
    .json();
}
