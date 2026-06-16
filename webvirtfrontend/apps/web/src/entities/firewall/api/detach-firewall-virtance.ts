import request from '@/shared/api/request';

export const detachFirewallVirtance = (
  uuid: string,
  payload: {
    virtance_ids: number[];
  },
): Promise<void> => {
  return request.delete(`firewalls/${uuid}/virtances`, { json: { ...payload } }).then(() => undefined);
};
