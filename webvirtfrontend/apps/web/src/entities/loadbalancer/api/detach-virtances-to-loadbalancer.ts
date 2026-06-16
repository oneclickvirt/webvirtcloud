import request from '@/shared/api/request';

export async function detachVirtanceFromLoadbalancer(uuid: string, payload: number[]): Promise<void> {
  await request.delete(`load_balancers/${uuid}/virtances`, {
    json: { virtance_ids: payload },
  });
}
