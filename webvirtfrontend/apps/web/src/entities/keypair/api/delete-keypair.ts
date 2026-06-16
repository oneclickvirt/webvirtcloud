import request from '@/shared/api/request';

export const deleteKeypair = async (id: number): Promise<void> => {
  await request.delete(`keypairs/${id}`);
};
