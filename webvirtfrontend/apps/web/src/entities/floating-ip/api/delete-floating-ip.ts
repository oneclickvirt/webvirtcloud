import request from '@/shared/api/request';

export const deleteFloatingIP = async (ip: string): Promise<void> => {
  await request.delete(`floating_ips/${ip}`);
};
