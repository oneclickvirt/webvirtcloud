import request from '@/shared/api/request';

export async function deleteVirtance(id: number): Promise<void> {
  await request.delete(`virtances/${id}`);
}
