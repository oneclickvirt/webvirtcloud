import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { Link } from 'react-router-dom';
import { toast } from 'sonner';
import { Button } from 'ui/components/button';
import { Error } from 'ui/components/error';
import { Input } from 'ui/components/input';

import { resetPassword } from '@/entities/auth';
import { getHTTPErrorMessage } from '@/shared/api/errors';

interface IFormInputs {
  password: string;
  password_confirm: string;
}

interface Props {
  hash: string;
}

export function ResetPasswordConfirmForm({ hash }: Props) {
  const [isComplete, setIsComplete] = useState(false);
  const {
    register,
    handleSubmit,
    setError,
    watch,
    formState: { isSubmitting, errors },
  } = useForm<IFormInputs>();

  async function onSubmit(data: IFormInputs) {
    try {
      await resetPassword(hash, data);
      setIsComplete(true);
      toast.success('Password updated', {
        description: 'You can sign in with your new password.',
      });
    } catch (error) {
      const message = await getHTTPErrorMessage(error);
      setError('root', { message });
      toast.error('Bad request', { description: message });
    }
  }

  if (isComplete) {
    return (
      <p className="text-muted-foreground text-center">
        Password updated.{' '}
        <Link className="font-medium text-sky-500" to="/sign-in">
          Sign in
        </Link>
      </p>
    );
  }

  return (
    <>
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        <div>
          <Input
            id="password"
            type="password"
            placeholder="Enter new secure password"
            {...register('password', {
              minLength: {
                value: 8,
                message: 'Password should be at least 8 characters.',
              },
              required: 'Password is required.',
            })}
            error={!!errors.password}
          />
          {errors.password && <Error className="mt-1">{errors.password.message}</Error>}
        </div>
        <div>
          <Input
            id="password_confirm"
            type="password"
            placeholder="Confirm new secure password"
            {...register('password_confirm', {
              validate: (value) => value === watch('password') || 'Passwords do not match.',
              required: 'Password confirmation is required.',
            })}
            error={!!errors.password_confirm}
          />
          {errors.password_confirm && (
            <Error className="mt-1">{errors.password_confirm.message}</Error>
          )}
        </div>
        <Button type="submit" className="w-full" disabled={isSubmitting}>
          {isSubmitting ? 'Updating...' : 'Update password'}
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
