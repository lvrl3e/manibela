// Mirrors lib/core/constants/route_path.dart — the real, officially-
// registered LTFRB route ("Pasig (TP) - Quiapo (Echague) via Sta. Mesa,
// C. Palanca", confirmed against the public GTFS feed at
// github.com/sakayph/gtfs), traced via Mapbox's Directions API since that
// feed has no shape data for this specific route to trace exactly. Kept
// in sync with the Flutter constant by hand since this is a fixed,
// rarely-changing corridor. Used to draw the route on the admin Live Map
// so the fleet's markers have road context, and to filter markers down
// to just this corridor when its toggle is on. A second, unverified
// corridor briefly lived here alongside this one; removed once this one
// was confirmed as the actual registered route and the other wasn't.

const PASIG_QUIAPO_ROUTE: [number, number][] = [
  [14.576409, 121.085129],
  [14.575961, 121.084898],
  [14.578373, 121.081715],
  [14.575236, 121.079447],
  [14.573591, 121.078534],
  [14.574876, 121.076296],
  [14.577512, 121.073278],
  [14.576327, 121.072742],
  [14.569717, 121.070941],
  [14.571393, 121.068744],
  [14.572115, 121.067436],
  [14.572240, 121.066871],
  [14.571925, 121.064579],
  [14.584205, 121.050221],
  [14.587374, 121.046289],
  [14.588956, 121.042398],
  [14.589476, 121.040430],
  [14.589449, 121.035326],
  [14.590450, 121.033945],
  [14.592243, 121.029964],
  [14.593258, 121.028130],
  [14.596162, 121.020429],
  [14.596764, 121.021471],
  [14.597273, 121.021296],
  [14.596764, 121.021471],
  [14.595949, 121.020022],
  [14.595973, 121.019832],
  [14.597610, 121.017616],
  [14.603012, 121.015881],
  [14.602679, 121.014956],
  [14.601137, 120.998635],
  [14.600590, 120.996179],
  [14.601600, 120.992786],
  [14.601001, 120.991606],
  [14.600431, 120.990967],
  [14.603258, 120.984948],
  [14.603531, 120.983710],
  [14.603429, 120.983695],
  [14.603272, 120.984630],
  [14.603083, 120.984897],
  [14.598268, 120.984006],
  [14.596904, 120.983622],
  [14.596703, 120.983439],
  [14.596382, 120.983674],
  [14.597368, 120.984017],
  [14.607630, 120.985976],
  [14.607887, 120.986283],
  [14.608100, 120.985930],
  [14.599519, 120.984250],
  [14.599665, 120.983213],
  [14.599501, 120.983192],
];

// The real Quiapo→Pasig return leg — deliberately *not* the outbound
// array reversed. Confirmed via Mapbox Directions that downtown Manila's
// one-way streets mean the return trip genuinely takes different roads
// (crosses the Legarda-Magsaysay Flyover and Old Santa Mesa St rather
// than retracing the outbound Magsaysay Blvd leg), not a mirror image.
const QUIAPO_PASIG_ROUTE: [number, number][] = [
  [14.599501, 120.983192],
  [14.599665, 120.983213],
  [14.600090, 120.981504],
  [14.602353, 120.981905],
  [14.603675, 120.981965],
  [14.603272, 120.984630],
  [14.600601, 120.990570],
  [14.600315, 120.990962],
  [14.600948, 120.991647],
  [14.601528, 120.992782],
  [14.600496, 120.996186],
  [14.601069, 120.998653],
  [14.602077, 121.010046],
  [14.602087, 121.011896],
  [14.600689, 121.013364],
  [14.597469, 121.015705],
  [14.597408, 121.016321],
  [14.597660, 121.017601],
  [14.595928, 121.019935],
  [14.596764, 121.021471],
  [14.597273, 121.021296],
  [14.596764, 121.021471],
  [14.596162, 121.020429],
  [14.593258, 121.028130],
  [14.592243, 121.029964],
  [14.590450, 121.033945],
  [14.589449, 121.035326],
  [14.589550, 121.039927],
  [14.588594, 121.040118],
  [14.587666, 121.039698],
  [14.586388, 121.041493],
  [14.586645, 121.043198],
  [14.585913, 121.044491],
  [14.587264, 121.046408],
  [14.584876, 121.049362],
  [14.571825, 121.064544],
  [14.572166, 121.066043],
  [14.572240, 121.066871],
  [14.572115, 121.067436],
  [14.571393, 121.068744],
  [14.569717, 121.070941],
  [14.567598, 121.070377],
  [14.566009, 121.070250],
  [14.566278, 121.071291],
  [14.565984, 121.076121],
  [14.565253, 121.075990],
  [14.565260, 121.076102],
  [14.566122, 121.077661],
  [14.567271, 121.080225],
  [14.567972, 121.080844],
  [14.576409, 121.085129],
];

export interface RouteDefinition {
  id: string;
  /** Shown on the legend/toggle button. */
  legendLabel: string;
  /** The exact two directional strings this corridor is recorded as
   * everywhere else (see DRIVER_ROUTES in backend/src/routes/admin.ts). */
  directions: [string, string];
  /** [outbound, return] — drawn as two separate lines, not one, since the
   * two directions are genuinely different streets (one-way restrictions
   * through downtown Manila), not a mirror image of each other. */
  paths: [[number, number][], [number, number][]];
  color: string;
  caseColor: string;
}

// A second corridor later is just adding another entry here (plus the
// matching RoutePath.forRoute case on the Flutter side, and the two new
// direction strings in every kDriverRoutes-equivalent list) — nothing
// about how LiveMap draws or filters routes needs to change. Only re-add
// one once it's independently confirmed as an actual registered route,
// the same way this one was checked against the public GTFS feed.
export const ROUTES: RouteDefinition[] = [
  {
    id: 'pasig-quiapo',
    legendLabel: 'Pasig ↔ Quiapo',
    directions: ['Pasig – Quiapo', 'Quiapo – Pasig'],
    paths: [PASIG_QUIAPO_ROUTE, QUIAPO_PASIG_ROUTE],
    color: '#EAB308',
    caseColor: '#92600A',
  },
];

/** Whether `route` belongs to any of the given route ids (both directions
 * count) — the filtering rule behind "only show markers on the corridors
 * currently toggled on". */
export function matchesAnyRoute(route: string | null | undefined, routeIds: Set<string>): boolean {
  if (!route) return false;
  return ROUTES.some((r) => routeIds.has(r.id) && (r.directions[0] === route || r.directions[1] === route));
}
