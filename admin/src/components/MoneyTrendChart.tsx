import { useEffect, useMemo, useRef, useState } from 'react';

export interface MoneyPoint {
  date: string; // "YYYY-MM-DD"
  earnings: number;
  expenses: number;
  netIncome: number;
}

const WIDTH = 720;
const HEIGHT = 260;
const PAD = { top: 16, right: 16, bottom: 28, left: 44 };

function niceMax(max: number): number {
  if (max <= 0) return 100;
  const magnitude = 10 ** Math.floor(Math.log10(max));
  const normalized = max / magnitude;
  const step = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 5 ? 5 : 10;
  return step * magnitude;
}

function formatDateShort(iso: string): string {
  const d = new Date(`${iso}T00:00:00Z`);
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', timeZone: 'UTC' });
}

function formatPeso(n: number): string {
  return `₱${Math.round(n).toLocaleString('en-PH')}`;
}

/** Compact axis label — ₱1.2k instead of ₱1,200, so labels don't crowd
 * the narrow left gutter. */
function formatPesoCompact(n: number): string {
  if (n >= 1000) {
    const thousands = n / 1000;
    return `₱${thousands >= 10 ? Math.round(thousands) : thousands.toFixed(1)}k`;
  }
  return `₱${Math.round(n)}`;
}

/** Earnings vs. expenses over time — a two-series line chart, same form
 * and validated categorical pair as TrendChart. Net income (the derived
 * third figure) isn't plotted here — see the "Net Income" stat tile on
 * ReportsPage for that headline number instead of a 3rd, redundant line. */
export function MoneyTrendChart({ series }: { series: MoneyPoint[] }) {
  const [hoverIndex, setHoverIndex] = useState<number | null>(null);
  const [showTable, setShowTable] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollLeft = el.scrollWidth;
  }, [series]);

  const plotW = WIDTH - PAD.left - PAD.right;
  const plotH = HEIGHT - PAD.top - PAD.bottom;

  const maxValue = useMemo(() => {
    const rawMax = Math.max(1, ...series.map((p) => Math.max(p.earnings, p.expenses)));
    return niceMax(rawMax);
  }, [series]);

  const xFor = (i: number) => (series.length <= 1 ? PAD.left : PAD.left + (i / (series.length - 1)) * plotW);
  const yFor = (v: number) => PAD.top + plotH - (v / maxValue) * plotH;

  const linePath = (key: 'earnings' | 'expenses') =>
    series.map((p, i) => `${i === 0 ? 'M' : 'L'} ${xFor(i)} ${yFor(p[key])}`).join(' ');

  const yTicks = [...new Set([0, Math.round(maxValue / 2), maxValue])];
  const xLabelStep = Math.max(1, Math.ceil(series.length / 6));

  function handlePointerMove(e: React.PointerEvent<SVGRectElement>) {
    const rect = e.currentTarget.getBoundingClientRect();
    const relX = e.clientX - rect.left;
    const ratio = Math.min(1, Math.max(0, (relX - PAD.left) / plotW));
    const index = Math.round(ratio * (series.length - 1));
    setHoverIndex(Math.min(series.length - 1, Math.max(0, index)));
  }

  const hovered = hoverIndex !== null ? series[hoverIndex] : null;

  if (series.length === 0) {
    return <p className="py-8 text-center text-sm text-gray-400">No daily logs in this range yet.</p>;
  }

  return (
    <div>
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-5 text-xs font-medium text-gray-600">
          <span className="flex items-center gap-1.5">
            <span className="h-0.5 w-4 rounded-full" style={{ backgroundColor: 'var(--color-series-drivers)' }} />
            Earnings
          </span>
          <span className="flex items-center gap-1.5">
            <span className="h-0.5 w-4 rounded-full" style={{ backgroundColor: 'var(--color-series-commuters)' }} />
            Expenses
          </span>
        </div>
        <button
          onClick={() => setShowTable((v) => !v)}
          className="text-xs font-semibold text-brand-blue hover:underline"
        >
          {showTable ? 'View as chart' : 'View as table'}
        </button>
      </div>

      {showTable ? (
        <div className="mt-4 max-h-80 overflow-y-auto rounded-lg border border-border-subtle">
          <table className="w-full text-left text-sm">
            <thead className="sticky top-0 bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-4 py-2">Date</th>
                <th className="px-4 py-2 text-right">Earnings</th>
                <th className="px-4 py-2 text-right">Expenses</th>
                <th className="px-4 py-2 text-right">Net</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {[...series].reverse().map((p) => (
                <tr key={p.date}>
                  <td className="px-4 py-2 text-gray-600">{formatDateShort(p.date)}</td>
                  <td className="tabular-nums px-4 py-2 text-right text-gray-900">{formatPeso(p.earnings)}</td>
                  <td className="tabular-nums px-4 py-2 text-right text-gray-900">{formatPeso(p.expenses)}</td>
                  <td className="tabular-nums px-4 py-2 text-right font-medium text-gray-900">{formatPeso(p.netIncome)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="relative mt-3">
          <div ref={scrollRef} className="overflow-x-auto">
            <svg
              viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
              className="block"
              style={{ minWidth: WIDTH, width: '100%' }}
              role="img"
              aria-label="Earnings versus expenses over time"
            >
              {yTicks.map((t) => (
                <g key={t}>
                  <line x1={PAD.left} x2={WIDTH - PAD.right} y1={yFor(t)} y2={yFor(t)} stroke="#e5e7eb" strokeWidth={1} />
                  <text x={PAD.left - 8} y={yFor(t)} textAnchor="end" dominantBaseline="middle" fontSize={10} fill="#9ca3af">
                    {formatPesoCompact(t)}
                  </text>
                </g>
              ))}

              {series.map((p, i) =>
                i % xLabelStep === 0 ? (
                  <text key={p.date} x={xFor(i)} y={HEIGHT - 8} textAnchor="middle" fontSize={10} fill="#9ca3af">
                    {formatDateShort(p.date)}
                  </text>
                ) : null,
              )}

              {hoverIndex !== null && (
                <line x1={xFor(hoverIndex)} x2={xFor(hoverIndex)} y1={PAD.top} y2={PAD.top + plotH} stroke="#c3c2b7" strokeWidth={1} />
              )}

              <path d={linePath('earnings')} fill="none" stroke="var(--color-series-drivers)" strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
              <path d={linePath('expenses')} fill="none" stroke="var(--color-series-commuters)" strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />

              {series.length > 0 && (
                <>
                  <circle cx={xFor(series.length - 1)} cy={yFor(series[series.length - 1].earnings)} r={4} fill="var(--color-series-drivers)" stroke="#fff" strokeWidth={2} />
                  <circle cx={xFor(series.length - 1)} cy={yFor(series[series.length - 1].expenses)} r={4} fill="var(--color-series-commuters)" stroke="#fff" strokeWidth={2} />
                </>
              )}

              {hovered && (
                <>
                  <circle cx={xFor(hoverIndex!)} cy={yFor(hovered.earnings)} r={4} fill="var(--color-series-drivers)" stroke="#fff" strokeWidth={2} />
                  <circle cx={xFor(hoverIndex!)} cy={yFor(hovered.expenses)} r={4} fill="var(--color-series-commuters)" stroke="#fff" strokeWidth={2} />
                </>
              )}

              <rect
                x={PAD.left}
                y={PAD.top}
                width={plotW}
                height={plotH}
                fill="transparent"
                onPointerMove={handlePointerMove}
                onPointerLeave={() => setHoverIndex(null)}
              />
            </svg>
          </div>

          {hovered && (
            <div
              className="pointer-events-none absolute top-2 rounded-lg border border-gray-200 bg-white px-3 py-2 text-xs shadow-lg"
              style={{
                left: `${(xFor(hoverIndex!) / WIDTH) * 100}%`,
                transform: xFor(hoverIndex!) > WIDTH * 0.7 ? 'translateX(-105%)' : 'translateX(12px)',
              }}
            >
              <p className="mb-1 font-semibold text-gray-700">{formatDateShort(hovered.date)}</p>
              <p className="flex items-center gap-1.5">
                <span className="h-0.5 w-3 rounded-full" style={{ backgroundColor: 'var(--color-series-drivers)' }} />
                <span className="font-semibold text-gray-900">{formatPeso(hovered.earnings)}</span>
                <span className="text-gray-500">earnings</span>
              </p>
              <p className="flex items-center gap-1.5">
                <span className="h-0.5 w-3 rounded-full" style={{ backgroundColor: 'var(--color-series-commuters)' }} />
                <span className="font-semibold text-gray-900">{formatPeso(hovered.expenses)}</span>
                <span className="text-gray-500">expenses</span>
              </p>
              <p className="mt-1 border-t border-gray-100 pt-1 text-gray-500">
                Net: <span className="font-semibold text-gray-900">{formatPeso(hovered.netIncome)}</span>
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
