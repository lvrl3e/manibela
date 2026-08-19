import type { ReactNode } from 'react';

// Icon-in-a-ring, same visual language as StatCard's outlined variant —
// keeps a routine "are you sure?" prompt feeling like part of this app
// instead of a browser-native window.confirm().
const TONE = {
  warning: {
    ring: 'border-status-warning/40 text-status-warning',
    button: 'bg-status-warning text-white hover:brightness-110',
  },
  neutral: {
    ring: 'border-blue-200 text-brand-blue',
    button: 'bg-brand-blue text-white hover:brightness-110',
  },
  danger: {
    ring: 'border-status-critical/40 text-status-critical',
    button: 'bg-brand-red text-white hover:brightness-110',
  },
} as const;

export function ConfirmDialog({
  icon,
  title,
  message,
  confirmLabel,
  cancelLabel = 'Cancel',
  tone = 'neutral',
  isSubmitting = false,
  onConfirm,
  onCancel,
}: {
  icon: ReactNode;
  title: string;
  message: string;
  confirmLabel: string;
  cancelLabel?: string;
  tone?: keyof typeof TONE;
  isSubmitting?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  const t = TONE[tone];
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-black/50" onClick={onCancel} />
      <div className="relative w-full max-w-xs rounded-2xl bg-white p-5 text-center shadow-xl">
        <div className={`mx-auto flex h-11 w-11 items-center justify-center rounded-full border-2 ${t.ring}`}>
          {icon}
        </div>
        <h2 className="mt-3 text-base font-semibold text-gray-900">{title}</h2>
        <p className="mt-1.5 text-xs text-gray-500">{message}</p>
        <div className="mt-4 flex gap-2.5">
          <button
            onClick={onCancel}
            disabled={isSubmitting}
            className="flex-1 rounded-lg border border-border-subtle py-2 text-sm font-semibold text-gray-700 transition hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {cancelLabel}
          </button>
          <button
            onClick={onConfirm}
            disabled={isSubmitting}
            className={`flex-1 rounded-lg py-2 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-50 ${t.button}`}
          >
            {isSubmitting ? 'Please wait...' : confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
