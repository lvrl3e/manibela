import { LogoMark } from './Logo';

// One shared full-screen takeover for every auth transition (initial
// session check, signing in, signing out) instead of each one rendering
// its own blank/white gap — reuses the same dark gradient as the sidebar/
// header/login panel so the app never flashes an unbranded screen between
// "you had a session" and "here's your dashboard."
export function LoadingScreen({ label }: { label: string }) {
  return (
    <div className="fixed inset-0 z-[100] flex flex-col items-center justify-center gap-5 bg-gradient-to-br from-[#111c4d] via-ink to-black">
      <LogoMark size={64} />
      <div className="h-7 w-7 animate-spin rounded-full border-[3px] border-white/15 border-t-white" />
      <p className="font-display text-sm font-medium text-white/70">{label}</p>
    </div>
  );
}
