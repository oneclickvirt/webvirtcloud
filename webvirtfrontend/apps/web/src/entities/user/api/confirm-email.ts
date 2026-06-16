import request from '@/shared/api/request';
import { API_DOMAIN } from '@/shared/constants';

export function confirmEmail(token: string): Promise<unknown> {
  return request.get(`account/verify_email/${token}`, { prefixUrl: API_DOMAIN }).json();
}
