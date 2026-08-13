import type { ReactNode } from 'react';
import { DashboardLayout } from './DashboardLayout';

export function ComingSoon({ title, icon, description }: { title: string; icon: ReactNode; description: string }) {
  return (
    <DashboardLayout>
      <h1 className="text-2xl font-semibold tracking-tight text-gray-900">{title}</h1>

      <div className="mt-6 flex flex-col items-center justify-center rounded-xl border border-dashed border-border-subtle bg-surface-card px-6 py-20 text-center">
        <div className="flex h-14 w-14 items-center justify-center rounded-full bg-blue-50 text-brand-blue">
          {icon}
        </div>
        <h2 className="mt-4 text-base font-semibold text-gray-900">Coming soon</h2>
        <p className="mt-1.5 max-w-sm text-sm text-gray-500">{description}</p>
      </div>
    </DashboardLayout>
  );
}
