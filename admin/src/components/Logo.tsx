import logoSrc from '../assets/logo.png';

/** The real ManibelApp emblem (sunburst + jeepney + PH flag colors) — the
 * exact same asset as the mobile app's AppAssets.jeepneyLogo
 * (assets/images/jeepneyLogo.png), not a separate admin-only copy, so a
 * rebrand only ever needs updating in one place. It's a plain circular
 * badge with nothing outside it (no wordmark baked in, unlike the old
 * admin-only logo), so `rounded-full` here is just a safety net — the
 * PNG's own transparent corners already read as a circle on any
 * background (dark sidebar, login panel, plain page) without a visible
 * box around it. */
export function LogoMark({ size = 96 }: { size?: number }) {
  return (
    <img
      src={logoSrc}
      width={size}
      height={size}
      alt="ManibelApp"
      className="rounded-full object-contain"
    />
  );
}
