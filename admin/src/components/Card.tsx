import type { ReactNode } from 'react';

// Shared white-card shell used for the non-StatCard sections of a page
// (summary panels, tables, lists). No top border/accent here — that
// stripe means something specific on a StatCard (tone: blue vs. amber
// "needs attention"), so repeating it on every card on the page would be
// decoration with no payload, and would dilute the one place it's actually
// signaling something.
export function Card({ className = '', children }: { className?: string; children: ReactNode }) {
  return (
    <div
      className={`rounded-xl border border-border-subtle bg-surface-card p-5 shadow-[0_1px_2px_rgba(16,24,40,0.04)] ${className}`}
    >
      {children}
    </div>
  );
}

// Icon-chip + display-face title, used at the top of a Card so every
// section header across the app shares the same identity language as the
// StatCard icons instead of being a plain <h2>.
export function SectionHeader({ icon, title, action }: { icon: ReactNode; title: string; action?: ReactNode }) {
  return (
    <div className="flex items-center justify-between">
      <div className="flex items-center gap-2">
        <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full border-2 border-blue-200 text-brand-blue">
          {icon}
        </span>
        <h2 className="font-display text-sm font-semibold text-gray-900">{title}</h2>
      </div>
      {action}
    </div>
  );
}
