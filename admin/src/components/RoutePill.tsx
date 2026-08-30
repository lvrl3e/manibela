// Route pills reuse the app's categorical pair (the same yellow/orange the
// trend chart's Drivers/Commuters lines use) instead of inventing a third
// ad-hoc color scheme — fixed order, just two directions.
const ROUTE_TONE: Record<string, { bg: string; color: string }> = {
  'Pasig – Quiapo (Shaw Blvd)': { bg: 'bg-yellow-50', color: 'var(--color-series-drivers)' },
  'Quiapo – Pasig (Shaw Blvd)': { bg: 'bg-orange-50', color: 'var(--color-series-commuters)' },
  'Pasig – Quiapo (Sta. Mesa)': { bg: 'bg-blue-50', color: '#0B57D0' },
  'Quiapo – Pasig (Sta. Mesa)': { bg: 'bg-blue-50', color: '#083D94' },
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
