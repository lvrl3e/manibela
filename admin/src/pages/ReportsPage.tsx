import { ComingSoon } from '../components/ComingSoon';

function ReportIcon() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <rect x="4" y="3.5" width="16" height="17" rx="2" />
      <path d="M8 13v4M12 9.5v7.5M16 11.5v5.5" />
    </svg>
  );
}

export default function ReportsPage() {
  return (
    <ComingSoon
      title="Reports"
      icon={<ReportIcon />}
      description="No report types have been scoped yet. Let the team know what you need — e.g. CSV exports, signup trends, or KYC approval rates — and it'll be built here."
    />
  );
}
