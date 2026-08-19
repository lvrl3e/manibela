function LogoutIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
      <path d="M16 17l5-5-5-5M21 12H9" />
    </svg>
  );
}

/** Confirmation before actually logging an admin out — a stray click on the
 * sidebar's Log Out button used to end the session immediately with no way
 * back. Centered modal (not the slide-in side-panel pattern the detail
 * panels use) since this blocks the whole app, not one record.
 *
 * The top band reuses the sidebar/header's own dark gradient rather than a
 * generic pastel icon-in-a-circle — this is the one moment the admin is
 * stepping out of the app entirely, so it borrows the same chrome that
 * frames every other screen instead of looking like a stock confirm dialog. */
export function LogoutConfirmDialog({ onCancel, onConfirm }: { onCancel: () => void; onConfirm: () => void }) {
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-black/50" onClick={onCancel} />
      <div className="relative w-full max-w-xs overflow-hidden rounded-2xl bg-white shadow-xl">
        <div className="flex flex-col items-center gap-2 bg-gradient-to-b from-[#111c4d] via-ink to-black px-5 pb-4 pt-5">
          <div className="flex h-9 w-9 items-center justify-center rounded-full border border-white/15 bg-white/10 text-white">
            <LogoutIcon />
          </div>
          <h2 className="text-base font-semibold text-white">Log Out?</h2>
        </div>
        <div className="px-5 pb-5 pt-4 text-center">
          <p className="text-xs text-gray-500">You'll need to sign back in to access the dashboard.</p>
          <div className="mt-4 flex gap-2.5">
            <button
              onClick={onCancel}
              className="flex-1 rounded-lg border border-border-subtle py-2 text-sm font-semibold text-gray-700 transition hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              onClick={onConfirm}
              className="flex-1 rounded-lg bg-brand-red py-2 text-sm font-semibold text-white transition hover:brightness-110"
            >
              Log Out
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
