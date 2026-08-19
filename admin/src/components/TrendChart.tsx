import { useEffect, useId, useMemo, useRef, useState } from 'react';

export interface TrendPoint {
  date: string; // "YYYY-MM-DD"
  drivers: number;
  commuters: number;
}

const WIDTH = 720;
const HEIGHT = 260;
const PAD = { top: 16, right: 16, bottom: 28, left: 32 };

function niceMax(max: number): number {
  if (max <= 0) return 4;
  const magnitude = 10 ** Math.floor(Math.log10(max));
  const normalized = max / magnitude;
  const step = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 5 ? 5 : 10;
  return step * magnitude;
}

function formatDateShort(iso: string): string {
  const d = new Date(`${iso}T00:00:00Z`);
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', timeZone: 'UTC' });
}

export function TrendChart({ series }: { series: TrendPoint[] }) {
  const [hoverIndex, setHoverIndex] = useState<number | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  // Unique per instance so two TrendCharts on one page don't fight over the
  // same <filter>/<linearGradient> id.
  const uid = useId();
  const glowFilterId = `trend-glow-${uid}`;
  const driversAreaId = `trend-area-drivers-${uid}`;
  const commutersAreaId = `trend-area-commuters-${uid}`;

  // When the chart is wider than its card (narrow/mobile screens), start
  // scrolled to the most recent days — that's the part of the story
  // worth seeing first, not the oldest.
  useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollLeft = el.scrollWidth;
  }, [series]);

  const plotW = WIDTH - PAD.left - PAD.right;
  const plotH = HEIGHT - PAD.top - PAD.bottom;

  const maxValue = useMemo(() => {
    const rawMax = Math.max(1, ...series.map((p) => Math.max(p.drivers, p.commuters)));
    return niceMax(rawMax);
  }, [series]);

  const xFor = (i: number) => (series.length <= 1 ? PAD.left : PAD.left + (i / (series.length - 1)) * plotW);
  const yFor = (v: number) => PAD.top + plotH - (v / maxValue) * plotH;

  const linePath = (key: 'drivers' | 'commuters') =>
    series.map((p, i) => `${i === 0 ? 'M' : 'L'} ${xFor(i)} ${yFor(p[key])}`).join(' ');

  // Same line, closed down to the baseline — the soft gradient fill under
  // each line that gives the chart its glow.
  const areaPath = (key: 'drivers' | 'commuters') =>
    series.length === 0
      ? ''
      : `${linePath(key)} L ${xFor(series.length - 1)} ${PAD.top + plotH} L ${xFor(0)} ${PAD.top + plotH} Z`;

  // Dedupe after rounding — for a small maxValue (e.g. 1), a naive
  // [0, max/2, max] can round two different ticks to the same label
  // (0.5 → 1, colliding with the real 1).
  const yTicks = [...new Set([0, Math.round(maxValue / 2), maxValue])];

  // Show at most ~6 x-axis labels so dates don't collide on narrow screens.
  const xLabelStep = Math.max(1, Math.ceil(series.length / 6));

  function handlePointerMove(e: React.PointerEvent<SVGRectElement>) {
    const rect = e.currentTarget.getBoundingClientRect();
    const relX = e.clientX - rect.left;
    const ratio = Math.min(1, Math.max(0, (relX - PAD.left) / plotW));
    const index = Math.round(ratio * (series.length - 1));
    setHoverIndex(Math.min(series.length - 1, Math.max(0, index)));
  }

  const hovered = hoverIndex !== null ? series[hoverIndex] : null;

  return (
    <div className="relative">
      {/* Legend — line-key swatches, always present for 2 series */}
      <div className="mb-3 flex items-center gap-5 text-xs font-medium text-gray-600">
        <span className="flex items-center gap-1.5">
          <span className="h-0.5 w-4 rounded-full" style={{ backgroundColor: 'var(--color-series-drivers)' }} />
          Drivers
        </span>
        <span className="flex items-center gap-1.5">
          <span className="h-0.5 w-4 rounded-full" style={{ backgroundColor: 'var(--color-series-commuters)' }} />
          Commuters
        </span>
      </div>

      {/* min-w matches the viewBox so text never shrinks below legible
          size on narrow screens — it scrolls horizontally instead, same
          pattern as the data tables elsewhere in this app. */}
      <div ref={scrollRef} className="overflow-x-auto">
      <svg viewBox={`0 0 ${WIDTH} ${HEIGHT}`} className="block" style={{ minWidth: WIDTH, width: '100%' }} role="img" aria-label="Registrations over time">
        <defs>
          <filter id={glowFilterId} x="-60%" y="-60%" width="220%" height="220%">
            <feGaussianBlur stdDeviation="4" />
          </filter>
          <linearGradient id={driversAreaId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--color-series-drivers)" stopOpacity={0.22} />
            <stop offset="100%" stopColor="var(--color-series-drivers)" stopOpacity={0} />
          </linearGradient>
          <linearGradient id={commutersAreaId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--color-series-commuters)" stopOpacity={0.22} />
            <stop offset="100%" stopColor="var(--color-series-commuters)" stopOpacity={0} />
          </linearGradient>
        </defs>

        {/* Gridlines — hairline, recessive */}
        {yTicks.map((t) => (
          <g key={t}>
            <line
              x1={PAD.left}
              x2={WIDTH - PAD.right}
              y1={yFor(t)}
              y2={yFor(t)}
              stroke="#e5e7eb"
              strokeWidth={1}
            />
            <text x={PAD.left - 8} y={yFor(t)} textAnchor="end" dominantBaseline="middle" fontSize={10} fill="#9ca3af">
              {Math.round(t)}
            </text>
          </g>
        ))}

        {/* X-axis labels */}
        {series.map((p, i) =>
          i % xLabelStep === 0 ? (
            <text key={p.date} x={xFor(i)} y={HEIGHT - 8} textAnchor="middle" fontSize={10} fill="#9ca3af">
              {formatDateShort(p.date)}
            </text>
          ) : null,
        )}

        {/* Crosshair */}
        {hoverIndex !== null && (
          <line
            x1={xFor(hoverIndex)}
            x2={xFor(hoverIndex)}
            y1={PAD.top}
            y2={PAD.top + plotH}
            stroke="#c3c2b7"
            strokeWidth={1}
          />
        )}

        {/* Soft gradient fill under each line — glow rising from the baseline */}
        <path d={areaPath('drivers')} fill={`url(#${driversAreaId})`} stroke="none" />
        <path d={areaPath('commuters')} fill={`url(#${commutersAreaId})`} stroke="none" />

        {/* Blurred backing stroke — the actual "glow", sitting behind the crisp line */}
        <path
          d={linePath('drivers')}
          fill="none"
          stroke="var(--color-series-drivers)"
          strokeWidth={5}
          strokeLinejoin="round"
          strokeLinecap="round"
          opacity={0.55}
          filter={`url(#${glowFilterId})`}
        />
        <path
          d={linePath('commuters')}
          fill="none"
          stroke="var(--color-series-commuters)"
          strokeWidth={5}
          strokeLinejoin="round"
          strokeLinecap="round"
          opacity={0.55}
          filter={`url(#${glowFilterId})`}
        />

        {/* Lines */}
        <path d={linePath('drivers')} fill="none" stroke="var(--color-series-drivers)" strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
        <path d={linePath('commuters')} fill="none" stroke="var(--color-series-commuters)" strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />

        {/* End-of-line markers, with a surface ring so they read where lines cross */}
        {series.length > 0 && (
          <>
            <circle cx={xFor(series.length - 1)} cy={yFor(series[series.length - 1].drivers)} r={7} fill="var(--color-series-drivers)" opacity={0.35} filter={`url(#${glowFilterId})`} />
            <circle cx={xFor(series.length - 1)} cy={yFor(series[series.length - 1].commuters)} r={7} fill="var(--color-series-commuters)" opacity={0.35} filter={`url(#${glowFilterId})`} />
            <circle cx={xFor(series.length - 1)} cy={yFor(series[series.length - 1].drivers)} r={4} fill="var(--color-series-drivers)" stroke="#fff" strokeWidth={2} />
            <circle cx={xFor(series.length - 1)} cy={yFor(series[series.length - 1].commuters)} r={4} fill="var(--color-series-commuters)" stroke="#fff" strokeWidth={2} />
          </>
        )}

        {/* Hover marker dots on both series at the hovered X */}
        {hovered && (
          <>
            <circle cx={xFor(hoverIndex!)} cy={yFor(hovered.drivers)} r={4} fill="var(--color-series-drivers)" stroke="#fff" strokeWidth={2} />
            <circle cx={xFor(hoverIndex!)} cy={yFor(hovered.commuters)} r={4} fill="var(--color-series-commuters)" stroke="#fff" strokeWidth={2} />
          </>
        )}

        {/* Hit layer — the crosshair finds the X, per dataviz interaction spec */}
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
          className="pointer-events-none absolute top-8 rounded-lg border border-gray-200 bg-white px-3 py-2 text-xs shadow-lg"
          style={{
            left: `${(xFor(hoverIndex!) / WIDTH) * 100}%`,
            transform: xFor(hoverIndex!) > WIDTH * 0.7 ? 'translateX(-105%)' : 'translateX(12px)',
          }}
        >
          <p className="mb-1 font-semibold text-gray-700">{formatDateShort(hovered.date)}</p>
          <p className="flex items-center gap-1.5">
            <span className="h-0.5 w-3 rounded-full" style={{ backgroundColor: 'var(--color-series-drivers)' }} />
            <span className="font-semibold text-gray-900">{hovered.drivers}</span>
            <span className="text-gray-500">drivers</span>
          </p>
          <p className="flex items-center gap-1.5">
            <span className="h-0.5 w-3 rounded-full" style={{ backgroundColor: 'var(--color-series-commuters)' }} />
            <span className="font-semibold text-gray-900">{hovered.commuters}</span>
            <span className="text-gray-500">commuters</span>
          </p>
        </div>
      )}
    </div>
  );
}
