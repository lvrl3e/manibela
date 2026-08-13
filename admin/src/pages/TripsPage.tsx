import { ComingSoon } from '../components/ComingSoon';

function RouteIcon() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="5" cy="6" r="2.2" />
      <circle cx="19" cy="18" r="2.2" />
      <path d="M5 8.2V13a4 4 0 0 0 4 4h6" strokeDasharray="1 3.2" />
    </svg>
  );
}

export default function TripsPage() {
  return (
    <ComingSoon
      title="Trips"
      icon={<RouteIcon />}
      description="Trip tracking isn't wired up on the backend yet — QR scans and driver trips aren't persisted anywhere today. This page will show live and completed trips once that's built."
    />
  );
}
