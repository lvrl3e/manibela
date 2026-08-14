/** Bounded set of page numbers to render around the current page, so a
 * dataset with hundreds of pages doesn't render hundreds of buttons —
 * e.g. for page 8 of 20 this renders [6, 7, 8, 9, 10]. */
function pageNumbersAround(current: number, total: number): number[] {
  const span = 2;
  const start = Math.max(1, Math.min(current - span, total - span * 2));
  const end = Math.min(total, Math.max(current + span, span * 2 + 1));
  const pages: number[] = [];
  for (let p = Math.max(1, start); p <= end; p++) pages.push(p);
  return pages;
}

/** Previous / page-numbers / Next — shared across every paginated admin
 * list (Commuters, Drivers, Incident Reports, Trip History, ...) so the
 * control itself, and its "which pages to show" logic, stays consistent. */
export function PaginationControls({
  currentPage,
  totalPages,
  hasNextPage,
  onPageChange,
}: {
  currentPage: number;
  totalPages: number;
  hasNextPage: boolean;
  onPageChange: (page: number) => void;
}) {
  if (totalPages <= 1) return null;

  return (
    <div className="mt-4 flex flex-wrap items-center justify-center gap-1.5">
      <button
        onClick={() => onPageChange(Math.max(1, currentPage - 1))}
        disabled={currentPage <= 1}
        className="rounded-lg border border-border-subtle px-3 py-1.5 text-sm font-semibold text-gray-600 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50"
      >
        Previous
      </button>
      {pageNumbersAround(currentPage, totalPages).map((p) => (
        <button
          key={p}
          onClick={() => onPageChange(p)}
          className={`rounded-lg px-3 py-1.5 text-sm font-semibold ${
            p === currentPage ? 'bg-brand-blue text-white' : 'text-gray-600 hover:bg-gray-100'
          }`}
        >
          {p}
        </button>
      ))}
      <button
        onClick={() => onPageChange(hasNextPage ? currentPage + 1 : currentPage)}
        disabled={!hasNextPage}
        className="rounded-lg border border-border-subtle px-3 py-1.5 text-sm font-semibold text-gray-600 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50"
      >
        Next
      </button>
    </div>
  );
}
