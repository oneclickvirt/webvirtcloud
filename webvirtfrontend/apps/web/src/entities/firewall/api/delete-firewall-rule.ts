import { type FirewallInboundRule, type FirewallOutboundRule } from '@/entities/firewall';
import request from '@/shared/api/request';

export const deleteFirewallRule = (
  uuid: string,
  payload: {
    inbound_rules?: FirewallInboundRule[];
    outbound_rules?: FirewallOutboundRule[];
  },
): Promise<void> => {
  return request.delete(`firewalls/${uuid}/rules`, { json: { ...payload } }).then(() => undefined);
};
