import { useEffect } from 'react';
import { Controller, useFormContext } from 'react-hook-form';
import { Checkbox } from 'ui/components/checkbox';
import { Label } from 'ui/components/label';
import { cx } from 'ui/lib';

import type { CreateVirtanceForm } from './types';

export function VirtanceCreateIPv6Settings() {
  const { register, control, setValue, watch } = useFormContext<CreateVirtanceForm>();
  const region = watch('region');
  const isAvailable = region?.features.includes('ipv6') ?? false;

  useEffect(() => {
    if (!isAvailable) {
      setValue('ipv6', false);
    }
  }, [isAvailable, setValue]);

  if (!isAvailable) return null;

  return (
    <Controller
      name="ipv6"
      control={control}
      defaultValue={false}
      render={({ field }) => (
        <div className="space-y-2">
          <h2 className="text-lg font-medium">IPv6</h2>
          <div className="flex gap-2">
            <Label
              htmlFor="ipv6"
              className={cx([
                'bg-card flex w-full max-w-sm items-center gap-4 rounded-md border p-4',
                field.value ? 'border-ring ring-ring ring-1' : '',
              ])}
            >
              <Checkbox
                {...field}
                value={undefined}
                checked={field.value}
                onCheckedChange={field.onChange}
                id="ipv6"
                {...register('ipv6')}
              />

              <p>Enable public IPv6</p>
            </Label>
          </div>
        </div>
      )}
    />
  );
}
