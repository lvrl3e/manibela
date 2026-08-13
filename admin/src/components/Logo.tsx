import logoSrc from '../assets/logo.png';

/** The real ManibelaApp emblem (sunburst + jeepney + PH flag colors),
 * matching the mark used across the mobile app. Transparent PNG, so it
 * drops onto any background — dark sidebar, login panel, or a plain
 * page — without a visible box around it. */
export function LogoMark({ size = 96 }: { size?: number }) {
  return <img src={logoSrc} width={size} height={size} alt="ManibelaApp" className="object-contain" />;
}
