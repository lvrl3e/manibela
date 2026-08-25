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
      // drop-shadow (not box-shadow) since the PNG itself is a circle on a
      // transparent background — box-shadow would draw a square shadow
      // behind it. Reads fine at every size in use (login page down to the
      // mobile top-bar icon) on both the dark sidebar and white panels.
      className="rounded-full object-contain drop-shadow-[0_2px_4px_rgba(0,0,0,0.35)]"
    />
  );
}
