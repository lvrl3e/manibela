function LogoutIcon() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
      <path d="M16 17l5-5-5-5M21 12H9" />
    </svg>
  );
}

/** Confirmation before actually logging an admin out — a stray click on the
 * sidebar's Log Out button used to end the session immediately with no way
 * back. Centered modal (not the slide-in side-panel pattern the detail
 * panels use) since this blocks the whole app, not one record. */
export function LogoutConfirmDialog({ onCancel, onConfirm }: { onCancel: () => void; onConfirm: () => void }) {
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-black/50" onClick={onCancel} />
      <div className="relative w-full max-w-sm rounded-2xl bg-white p-6 text-center shadow-xl">
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-brand-red/10 text-brand-red">
          <LogoutIcon />
        </div>
        <h2 className="mt-4 text-lg font-semibold text-gray-900">Log Out?</h2>
        <p className="mt-1.5 text-sm text-gray-500">You'll need to sign back in to access the dashboard.</p>
        <div className="mt-6 flex gap-3">
          <button
            onClick={onCancel}
            className="flex-1 rounded-lg border border-border-subtle py-2.5 text-sm font-semibold text-gray-700 transition hover:bg-gray-50"
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            className="flex-1 rounded-lg bg-brand-red py-2.5 text-sm font-semibold text-white transition hover:brightness-110"
          >
            Log Out
          </button>
        </div>
      </div>
    </div>
  );
}
