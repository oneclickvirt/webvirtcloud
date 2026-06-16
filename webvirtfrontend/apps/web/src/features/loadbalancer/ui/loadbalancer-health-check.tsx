import { useEffect } from 'react';
import { useFormContext } from 'react-hook-form';
import { Input } from 'ui/components/input';
import { Label } from 'ui/components/label';

export function LoadbalancerHealthCheck() {
  const {
    register,
    unregister,
    watch,
    setValue,
    formState: { errors },
  } = useFormContext<{
    health_check: {
      protocol: 'tcp' | 'http' | 'https';
      port: number;
      path?: string;
      check_interval_seconds: number;
      response_timeout_seconds: number;
      healthy_threshold: number;
      unhealthy_threshold: number;
    };
  }>();

  const protocol = watch('health_check.protocol');

  useEffect(() => {
    if (protocol === 'tcp') {
      unregister('health_check.path');
    } else {
      register('health_check.path');
      setValue('health_check.path', '/');
    }
  }, [protocol, register, setValue, unregister]);

  return (
    <div>
      <div className="mb-4 space-y-2">
        <h2 className="text-lg font-semibold">Health check</h2>
        <p className="text-muted-foreground max-w-prose">
          Set how often the Load Balancer checks if Virtances are responding. It will
          automatically stop sending traffic to unresponsive Virtances.
        </p>
      </div>
      <div className="mb-4 grid gap-4 md:max-w-2xl md:grid-cols-4">
        <div className="space-y-1">
          <Label htmlFor="health-check-protocol">Protocol</Label>
          <select
            id="health-check-protocol"
            {...register('health_check.protocol')}
            className="border-border h-10 w-full rounded-md border bg-transparent shadow-sm"
          >
            <option disabled>Protocol</option>
            <option value="tcp">TCP</option>
            <option value="http">HTTP</option>
            <option value="https">HTTPS</option>
          </select>
        </div>
        <div className="space-y-1">
          <Label htmlFor="health-check-port">Port</Label>
          <Input
            id="health-check-port"
            {...register('health_check.port')}
            className="border-border h-10 w-full rounded-md border bg-transparent shadow-sm"
          />
          {errors?.health_check?.port && (
            <p className="text-sm font-medium text-red-500">
              {errors?.health_check?.port?.message}
            </p>
          )}
        </div>
        {protocol !== 'tcp' && (
          <div className="space-y-1">
            <Label htmlFor="health-check-path">Path</Label>
            <Input
              id="health-check-path"
              {...register('health_check.path')}
              className="border-border h-10 w-full rounded-md border bg-transparent shadow-sm"
            />
            {errors?.health_check?.path && (
              <p className="text-sm font-medium text-red-500">
                {errors?.health_check?.path?.message}
              </p>
            )}
          </div>
        )}
      </div>
      <div className="grid gap-4 md:max-w-2xl md:grid-cols-4">
        <div className="space-y-1">
          <Label htmlFor="healthcheck-interval">Check interval (in s)</Label>
          <Input
            id="healthcheck-interval"
            {...register('health_check.check_interval_seconds')}
            className="border-border h-10 w-full rounded-md border bg-transparent shadow-sm"
          />
          {errors?.health_check?.check_interval_seconds && (
            <p className="text-sm font-medium text-red-500">
              {errors?.health_check?.check_interval_seconds?.message}
            </p>
          )}
        </div>
        <div className="space-y-1">
          <Label htmlFor="healthcheck-timeout">Response timeout (in s)</Label>
          <Input
            id="healthcheck-timeout"
            {...register('health_check.response_timeout_seconds')}
            className="border-border h-10 w-full rounded-md border bg-transparent shadow-sm"
          />
          {errors?.health_check?.response_timeout_seconds && (
            <p className="text-sm font-medium text-red-500">
              {errors?.health_check?.response_timeout_seconds?.message}
            </p>
          )}
        </div>
        <div className="space-y-1">
          <Label htmlFor="healthcheck-unhealthy">Unhealthy threshold</Label>
          <Input
            id="healthcheck-unhealthy"
            {...register('health_check.unhealthy_threshold')}
            className="border-border h-10 w-full rounded-md border bg-transparent shadow-sm"
          />
          {errors?.health_check?.unhealthy_threshold && (
            <p className="text-sm font-medium text-red-500">
              {errors?.health_check?.unhealthy_threshold?.message}
            </p>
          )}
        </div>
        <div className="space-y-1">
          <Label htmlFor="healthcheck-healthy">Healthy threshold</Label>
          <Input
            id="healthcheck-healthy"
            {...register('health_check.healthy_threshold')}
            className="border-border h-10 w-full rounded-md border bg-transparent shadow-sm"
          />
          {errors?.health_check?.healthy_threshold && (
            <p className="text-sm font-medium text-red-500">
              {errors?.health_check?.healthy_threshold?.message}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
