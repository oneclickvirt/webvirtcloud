import { useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useNavigate, useParams } from 'react-router-dom';
import { toast } from 'sonner';
import { Spin } from 'ui/components/spin';

import { confirmEmail, userQueries } from '@/entities/user';

export default function ConfirmEmail() {
  const params = useParams();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const isAuthenticated = !!window.localStorage.getItem('token');

  useEffect(() => {
    let isMounted = true;

    async function confirmation(token: string) {
      try {
        await confirmEmail(token);
        toast.success('Your account confirmed', { description: 'Happy hacking' });

        if (isAuthenticated) {
          await queryClient.invalidateQueries({ queryKey: userQueries.user() });
        }

        if (isMounted) {
          navigate(isAuthenticated ? '/' : '/sign-in');
        }
      } catch (error) {
        toast.error('Something goes wrong', {
          description: 'Your link is wrong or it is expired',
        });

        if (isMounted) {
          navigate(isAuthenticated ? '/' : '/sign-in');
        }
      }
    }

    if (params.token) {
      confirmation(params.token);
    } else {
      navigate(isAuthenticated ? '/' : '/sign-in');
    }

    return () => {
      isMounted = false;
    };
  }, [isAuthenticated, navigate, params.token, queryClient]);

  return (
    <div className="flex min-h-screen items-center justify-center">
      <Spin size="default" />
    </div>
  );
}
