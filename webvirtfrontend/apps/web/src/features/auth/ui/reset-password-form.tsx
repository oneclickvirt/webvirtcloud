import { useForm } from 'react-hook-form';
import { Link } from 'react-router-dom';
import { toast } from 'sonner';
import { Button } from 'ui/components/button';
import { Error } from 'ui/components/error';
import { Input } from 'ui/components/input';

import { requestPasswordReset } from '@/entities/auth';
import { getHTTPErrorMessage } from '@/shared/api/errors';

interface IFormInputs {
  email: string;
}

export function ResetPasswordForm() {
  const {
    register,
    handleSubmit,
    setError,
    formState: { isSubmitting, errors },
  } = useForm<IFormInputs>();

  async function onSubmit(data: IFormInputs) {
    try {
      await requestPasswordReset(data);
      toast.success('Password reset email sent', {
        description: 'Check your inbox for the reset link.',
      });
    } catch (error) {
      const message = await getHTTPErrorMessage(error);
      setError('root', { message });
      toast.error('Bad request', { description: message });
    }
  }

  return (
    <>
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        <div>
          <Input
            id="email"
            type="email"
            placeholder="Ex. account@gmail.com"
            {...register('email', {
              pattern: {
                value: /\S+@\S+\.\S+/,
                message: 'Entered value does not match email format',
              },
              required: 'Email is required.',
            })}
            error={!!errors.email}
          />
          {errors.email && <Error className="mt-1">{errors.email.message}</Error>}
        </div>
        <Button type="submit" className="w-full" disabled={isSubmitting}>
          {isSubmitting ? 'Sending...' : 'Send reset link'}
        </Button>
      </form>
      <p className="text-muted-foreground mt-4 text-center">
        Or try to{' '}
        <Link className="font-medium text-sky-500" to="/sign-in">
          Sign in
        </Link>{' '}
        again
      </p>
    </>
  );
}
