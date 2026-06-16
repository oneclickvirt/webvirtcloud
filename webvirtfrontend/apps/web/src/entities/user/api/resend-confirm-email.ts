import request from '@/shared/api/request';
import { API_DOMAIN } from '@/shared/constants';

export function resendConfirmEmail(): Promise<unknown> {
  return request.post('account/verify_email', { prefixUrl: API_DOMAIN }).json();
}
