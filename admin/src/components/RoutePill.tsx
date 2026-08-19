// Route pills reuse the app's already-validated categorical pair (the same
// blue/orange the trend chart's Drivers/Commuters lines use) instead of
// inventing a third ad-hoc color scheme — fixed order, just two directions.
const ROUTE_TONE: Record<string, { bg: string; color: string }> = {
  'Pasig – Quiapo': { bg: 'bg-blue-50', color: 'var(--color-series-drivers)' },
  'Quiapo – Pasig': { bg: 'bg-orange-50', color: 'var(--color-series-commuters)' },
};

export function RoutePill({ route }: { route: string | null }) {
  if (!route) return <span className="text-gray-400">—</span>;
  const tone = ROUTE_TONE[route] ?? { bg: 'bg-gray-100', color: '#6b7280' };
  return (
    <span
      className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold ${tone.bg}`}
      style={{ color: tone.color }}
    >
      {route}
    </span>
  );
}
