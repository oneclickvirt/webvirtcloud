import request from '@/shared/api/request';

export const deleteImage = async (id: number): Promise<void> => {
  await request.delete(`images/${id}/`);
};
