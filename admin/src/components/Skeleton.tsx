// Loading placeholders — shaped like the content they'll be replaced by, so
// the initial load (and any slow refetch) doesn't read as "blank page" or
// pop the layout into existence once data arrives.

export function StatCardSkeleton() {
  return (
    <div className="overflow-hidden rounded-xl border border-border-subtle bg-surface-card shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
      <div className="h-[3px] w-full bg-gray-100" />
      <div className="animate-pulse p-5">
        <div className="flex items-start justify-between">
          <div className="space-y-2">
            <div className="h-3 w-20 rounded bg-gray-200" />
            <div className="h-7 w-12 rounded bg-gray-200" />
          </div>
          <div className="h-9 w-9 rounded-full bg-gray-100" />
        </div>
      </div>
    </div>
  );
}

// Matches the shell a data table renders in elsewhere (rounded-xl white
// card) so swapping to the real table doesn't shift layout.
export function TableSkeleton({ columns, rows = 5 }: { columns: number; rows?: number }) {
  return (
    <div className="mt-4 overflow-hidden rounded-xl border border-border-subtle bg-surface-card shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
      <div className="h-10 bg-gray-50" />
      <div className="divide-y divide-gray-100">
        {Array.from({ length: rows }).map((_, r) => (
          <div key={r} className="flex items-center gap-6 px-5 py-4">
            {Array.from({ length: columns }).map((_, c) => (
              <div key={c} className="h-3.5 flex-1 animate-pulse rounded bg-gray-100" />
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}
