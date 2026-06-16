import request from '@/shared/api/request';

export const deleteFirewall = async (uuid: string): Promise<void> => {
  await request.delete(`firewalls/${uuid}`);
};
