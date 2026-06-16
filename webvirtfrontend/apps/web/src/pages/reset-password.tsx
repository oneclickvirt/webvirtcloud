import { useParams } from 'react-router-dom';

import { ResetPasswordConfirmForm, ResetPasswordForm } from '@/features/auth';

export default function ResetPassword() {
  const { hash } = useParams();

  return (
    <>
      <h1 className="mb-8 text-center text-2xl font-medium">Reset password</h1>
      {hash ? <ResetPasswordConfirmForm hash={hash} /> : <ResetPasswordForm />}
    </>
  );
}
