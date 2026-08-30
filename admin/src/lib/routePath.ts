// Mirrors lib/core/constants/route_path.dart — same real, road-following
// coordinates (simplified via Douglas-Peucker from an actual driving
// route), kept in sync by hand since these are fixed, rarely-changing
// corridors. Used to draw each route on the admin Live Map so the fleet's
// markers have road context, and to filter markers down to just one
// corridor when its toggle is on.

const PASIG_QUIAPO_ROUTE: [number, number][] = [
  [14.576390, 121.085118],
  [14.568189, 121.080947],
  [14.567158, 121.080039],
  [14.566122, 121.077661],
  [14.566379, 121.071275],
  [14.566108, 121.070269],
  [14.564475, 121.069680],
  [14.563259, 121.068828],
  [14.562917, 121.067894],
  [14.562978, 121.066536],
  [14.563254, 121.065682],
  [14.563649, 121.065446],
  [14.569953, 121.066539],
  [14.570341, 121.066472],
  [14.580629, 121.054540],
  [14.581289, 121.053561],
  [14.578580, 121.051537],
  [14.578889, 121.051101],
  [14.579575, 121.045686],
  [14.581159, 121.044968],
  [14.581759, 121.044499],
  [14.581454, 121.043740],
  [14.582355, 121.042936],
  [14.582417, 121.042326],
  [14.581899, 121.041826],
  [14.580673, 121.042159],
  [14.581272, 121.043403],
  [14.581033, 121.043578],
  [14.581138, 121.043871],
  [14.581425, 121.043753],
  [14.581657, 121.044345],
  [14.578955, 121.044262],
  [14.578180, 121.042828],
  [14.575843, 121.041107],
  [14.576596, 121.039941],
  [14.576633, 121.039500],
  [14.575831, 121.035794],
  [14.576283, 121.035134],
  [14.576803, 121.034766],
  [14.577491, 121.034902],
  [14.578169, 121.034466],
  [14.578431, 121.033659],
  [14.578148, 121.033089],
  [14.581205, 121.029545],
  [14.584880, 121.027279],
  [14.585979, 121.025907],
  [14.589691, 121.023223],
  [14.584326, 121.017236],
  [14.582185, 121.013415],
  [14.581946, 121.013279],
  [14.580141, 121.007427],
  [14.585617, 121.006076],
  [14.586668, 121.005338],
  [14.587975, 121.006531],
  [14.588698, 121.006572],
  [14.589619, 121.006165],
  [14.589061, 121.005228],
  [14.589758, 121.004398],
  [14.590320, 121.004849],
  [14.590656, 121.005688],
  [14.592018, 121.005162],
  [14.592595, 121.004608],
  [14.592974, 121.003374],
  [14.592862, 121.001673],
  [14.597450, 121.001284],
  [14.600972, 120.999547],
  [14.600627, 120.999366],
  [14.597919, 120.996357],
  [14.597421, 120.995260],
  [14.596648, 120.994721],
  [14.596570, 120.992275],
  [14.597216, 120.991973],
  [14.597016, 120.991464],
  [14.597438, 120.991291],
  [14.597016, 120.991464],
  [14.596844, 120.991011],
  [14.596527, 120.990992],
  [14.596522, 120.989567],
  [14.597729, 120.989640],
  [14.600378, 120.991030],
  [14.603258, 120.984948],
  [14.603531, 120.983710],
  [14.603181, 120.984871],
  [14.603029, 120.984893],
  [14.599519, 120.984250],
  [14.599665, 120.983213],
  [14.599501, 120.983192],
];

// A second, genuinely different physical corridor between the same two
// endpoints — a real documented jeepney route ("Pasig (TP) to Quiapo
// (Echague) via Sta. Mesa and C. Palanca"), traced via Mapbox's
// Directions API with Sta. Mesa and Carlos Palanca St as waypoints so it
// actually follows Ramon Magsaysay Blvd through Sta. Mesa rather than
// PASIG_QUIAPO_ROUTE's more northern path through Mandaluyong/San Juan.
const PASIG_QUIAPO_STA_MESA_ROUTE: [number, number][] = [
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

export interface RouteDefinition {
  id: string;
  /** Shown on the legend/toggle button. */
  legendLabel: string;
  /** The exact two directional strings this corridor is recorded as
   * everywhere else (see DRIVER_ROUTES in backend/src/routes/admin.ts) —
   * both map to the same physical line for drawing purposes. */
  directions: [string, string];
  path: [number, number][];
  color: string;
  caseColor: string;
}

// Adding a third corridor later is just adding a fourth entry here (plus
// the matching RoutePath.forRoute case on the Flutter side, and the two
// new direction strings in every kDriverRoutes-equivalent list) — nothing
// about how LiveMap draws or filters routes needs to change.
export const ROUTES: RouteDefinition[] = [
  {
    id: 'original',
    legendLabel: 'Pasig ↔ Quiapo (Shaw Blvd)',
    directions: ['Pasig – Quiapo (Shaw Blvd)', 'Quiapo – Pasig (Shaw Blvd)'],
    path: PASIG_QUIAPO_ROUTE,
    color: '#EAB308',
    caseColor: '#92600A',
  },
  {
    id: 'sta-mesa',
    legendLabel: 'Pasig ↔ Quiapo (Sta. Mesa)',
    directions: ['Pasig – Quiapo (Sta. Mesa)', 'Quiapo – Pasig (Sta. Mesa)'],
    path: PASIG_QUIAPO_STA_MESA_ROUTE,
    color: '#0B57D0',
    caseColor: '#083D94',
  },
];

/** Whether `route` belongs to any of the given route ids (both directions
 * count) — the filtering rule behind "only show markers on the corridors
 * currently toggled on". */
export function matchesAnyRoute(route: string | null | undefined, routeIds: Set<string>): boolean {
  if (!route) return false;
  return ROUTES.some((r) => routeIds.has(r.id) && (r.directions[0] === route || r.directions[1] === route));
}
