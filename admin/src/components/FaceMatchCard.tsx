// Mirrors FACE_MATCH_AUTO_CLEAR_SCORE in backend/src/lib/faceMatch.ts — the
// score at/above which a signup/license submission auto-clears without an
// admin ever seeing it. Keep these two in sync if that threshold changes.
const FACE_MATCH_AUTO_CLEAR_SCORE = 70;

/** Shows the automated selfie-vs-document face-match result on a detail
 * panel — used by both CommuterDetailPanel (selfie vs. ID front) and
 * DriverDetailPanel (selfie vs. license front), which only differ in what
 * the document is called. */
export function FaceMatchCard({ score, documentLabel }: { score: number | null; documentLabel: string }) {
  if (score === null) {
    return (
      <div className="mt-2.5 rounded-[10px] border border-gray-200 bg-gray-50 px-3.5 py-3">
        <p className="text-[10.5px] font-semibold uppercase tracking-wide text-gray-400">Face Match</p>
        <p className="mt-1 text-xs text-gray-500">
          Not available — no face could be confidently found in the selfie or {documentLabel.toLowerCase()}. Compare
          them yourself below.
        </p>
      </div>
    );
  }

  const cleared = score >= FACE_MATCH_AUTO_CLEAR_SCORE;
  const tone = cleared
    ? { border: 'border-[#bfe8bf]', bg: 'bg-status-good-bg', text: 'text-status-good', fill: '#0ca30c' }
    : { border: 'border-[#f3d9b1]', bg: 'bg-status-warning-bg', text: 'text-status-warning', fill: '#b45309' };

  return (
    <div className={`mt-2.5 rounded-[10px] border ${tone.border} ${tone.bg} px-3.5 py-3.5`}>
      <div className="flex items-end justify-between">
        <div>
          <p className={`text-[10.5px] font-semibold uppercase tracking-wide ${tone.text}`}>Face Match</p>
          <p className={`font-display text-[28px] font-bold leading-none ${tone.text}`}>{score}%</p>
        </div>
        <span className={`inline-flex items-center gap-1 rounded-full bg-white px-2.5 py-1 text-xs font-semibold ${tone.text}`}>
          {cleared ? (
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6"><path d="M5 13l4 4L19 7" /></svg>
          ) : (
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4"><path d="M12 9v4M12 17h.01M10.3 3.9 2.5 18a1.7 1.7 0 0 0 1.5 2.5h16a1.7 1.7 0 0 0 1.5-2.5L13.7 3.9a1.7 1.7 0 0 0-3.4 0Z" /></svg>
          )}
          {cleared ? 'Auto-cleared' : 'Below threshold'}
        </span>
      </div>
      <div className="relative mt-2.5 h-1.5 rounded-full" style={{ background: cleared ? '#bfe8bf' : '#f3d9b1' }}>
        <div className="absolute inset-y-0 left-0 rounded-full" style={{ width: `${score}%`, background: tone.fill }} />
        <div
          className="absolute top-[-3px] h-3 w-0.5 bg-ink opacity-35"
          style={{ left: `${FACE_MATCH_AUTO_CLEAR_SCORE}%` }}
        />
      </div>
      <p className={`mt-2 text-[11px] ${cleared ? 'text-[#3f7d3f]' : 'text-[#92651f]'}`}>
        Selfie vs. {documentLabel} &middot; threshold {FACE_MATCH_AUTO_CLEAR_SCORE}%
        {cleared ? ' · well above threshold, no review needed' : ' · review the photos below before deciding'}
      </p>
    </div>
  );
}
