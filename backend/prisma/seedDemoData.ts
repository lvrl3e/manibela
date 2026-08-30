import 'dotenv/config';
import bcrypt from 'bcryptjs';
import { prisma } from '../src/lib/prisma';
import { generateQrToken } from '../src/utils/qrToken';

// Fills the dev database with a realistic-looking fleet, rider base, trip
// history, complaints, and live demand so every admin screen has something
// worth looking at — the real accounts (DR-00001, CM-00002, and both admin
// logins) are untouched throughout. Idempotent: reruns wipe only the
// DR-DEMO-*/CM-DEMO-* rows (and everything hanging off them) before
// recreating, so tweaking this file and rerunning is safe.

const ROUTES = ['Pasig – Quiapo (Shaw Blvd)', 'Quiapo – Pasig (Shaw Blvd)'] as const;
// The admin whose JWT this session has been using — attributed as the
// reviewer on already-reviewed trips so Trip History reads as a real
// reviewer having looked at them, not a placeholder.
const REVIEWER_ADMIN_ID = 'cmsyk7ybc001duwx4bajwncla';

// Roughly the real Pasig -> Quiapo corridor, Pasig end to Quiapo end, so
// jittered points along it land somewhere plausible and cluster the way an
// actual route would on the live map.
const ROUTE_POINTS: [number, number][] = [
  [14.5764, 121.0851],
  [14.582, 121.043],
  [14.5891, 121.005],
  [14.5975, 120.9915],
  [14.5995, 120.9832],
];

function pick<T>(arr: readonly T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

function randInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function daysAgo(n: number, hour = 9, minute = 0): Date {
  const d = new Date();
  d.setDate(d.getDate() - n);
  d.setHours(hour, minute, 0, 0);
  return d;
}

function jitter([lat, lng]: [number, number], spread = 0.006): [number, number] {
  return [lat + (Math.random() - 0.5) * spread, lng + (Math.random() - 0.5) * spread];
}

const DRIVER_NAMES = [
  'Mark Anthony Santos',
  'Ana Liza Cruz',
  'Roberto Villanueva',
  'Cristina Bautista',
  'Eduardo Reyes',
  'Marites Fernandez',
  'Ferdinand Aquino',
  'Rosalinda Torres',
  'Benjamin Garcia',
];
const DRIVER_PLATES = ['NDX234', 'PSG456', 'QPO789', 'MNL321', 'RXV654', 'TLK987', 'BGC159', 'CAV753', 'LGN864'];

const COMMUTER_NAMES = [
  'Jasmine Reyes',
  'Paolo Mendoza',
  'Katrina Dizon',
  'Ryan Ocampo',
  'Bea Salvador',
  'Michael Tan',
  'Angelica Pascual',
  'Joshua Ramos',
  'Nicole Aguilar',
  'Vincent Castillo',
  'Samantha Lopez',
  'Christian Navarro',
  'Erika Domingo',
  'Kevin Manalo',
  'Danica Flores',
  'Patrick Gonzales',
  'Alyssa Ramirez',
  'Miguel Soriano',
];
const ID_TYPES = ["Driver's License", 'UMID', 'Passport', 'Postal ID'];

// Matches COMPLAINT_TYPES in backend/src/routes/commuter.ts and admin.ts
// exactly — this seed script writes complaintType straight to the
// database via Prisma, bypassing the API's Zod validation, so a value
// outside that enum would produce a demo complaint no real commuter
// could ever file and the admin website's own filter couldn't match.
const COMPLAINT_TYPES = ['Reckless Driving', 'Overcharging', 'Rude Behavior', 'Route Deviation', 'Other'];
const COMPLAINT_DESCRIPTIONS: Record<string, string[]> = {
  'Reckless Driving': [
    'Driver was swerving between lanes near Ortigas Ave and braking suddenly.',
    'Overtook another jeepney on a blind curve, passengers were thrown forward.',
  ],
  Overcharging: [
    'Charged ₱15 instead of the ₱13 fare and refused to give change.',
    'Asked for extra payment for a bag that fit on my lap.',
  ],
  'Rude Behavior': [
    'Driver shouted at an elderly passenger for not having exact change.',
    'Ignored my "Para po" twice and I had to bang on the roof.',
  ],
  'Route Deviation': [
    'Took a side street detour without announcing it, made the trip much longer.',
    'Ended the route two blocks early and told everyone to walk the rest.',
  ],
  Other: [
    'No functioning door handle on the passenger side, had to climb over.',
    'Played loud music the entire ride despite passengers asking to lower it.',
  ],
};

async function wipeDemoData() {
  const demoDrivers = await prisma.driver.findMany({ where: { driverId: { startsWith: 'DR-DEMO-' } }, select: { id: true } });
  const demoCommuters = await prisma.commuter.findMany({ where: { commuterId: { startsWith: 'CM-DEMO-' } }, select: { id: true } });
  const driverIds = demoDrivers.map((d) => d.id);
  const commuterIds = demoCommuters.map((c) => c.id);

  if (driverIds.length === 0 && commuterIds.length === 0) return;

  console.log(`Clearing previous demo data (${driverIds.length} drivers, ${commuterIds.length} commuters)...`);
  await prisma.rating.deleteMany({ where: { OR: [{ driverId: { in: driverIds } }, { commuterId: { in: commuterIds } }] } });
  await prisma.tripBoarding.deleteMany({ where: { commuterId: { in: commuterIds } } });
  await prisma.complaint.deleteMany({ where: { OR: [{ driverId: { in: driverIds } }, { complainantId: { in: commuterIds } }] } });
  await prisma.demandSignal.deleteMany({ where: { commuterId: { in: commuterIds } } });
  await prisma.driverDailyLog.deleteMany({ where: { driverId: { in: driverIds } } });
  await prisma.trip.deleteMany({ where: { driverId: { in: driverIds } } });
  await prisma.driver.deleteMany({ where: { id: { in: driverIds } } });
  await prisma.commuter.deleteMany({ where: { id: { in: commuterIds } } });
}

async function seedDrivers() {
  const passwordHash = await bcrypt.hash('Demo@1234', 10);
  const licenseStatuses = [null, 'PENDING', 'APPROVED', 'APPROVED', 'APPROVED', 'REJECTED', 'APPROVED', 'PENDING', 'APPROVED'] as const;

  const drivers = [];
  for (let i = 0; i < DRIVER_NAMES.length; i++) {
    const n = i + 1;
    const driver = await prisma.driver.create({
      data: {
        driverId: `DR-DEMO-${String(n).padStart(2, '0')}`,
        fullName: DRIVER_NAMES[i],
        mobileNumber: `+63917${String(2000000 + n).padStart(7, '0')}`,
        passwordHash,
        plateNumber: DRIVER_PLATES[i],
        qrToken: await generateQrToken(),
        licenseNumber: licenseStatuses[i] ? `N${10000000 + n}` : null,
        licenseVerificationStatus: licenseStatuses[i],
        isActive: n !== DRIVER_NAMES.length,
        createdAt: daysAgo(randInt(0, 13), randInt(6, 20), randInt(0, 59)),
      },
    });
    drivers.push(driver);
  }
  return drivers;
}

async function seedCommuters() {
  const passwordHash = await bcrypt.hash('Demo@1234', 10);
  // null = not submitted, otherwise the review verdict.
  const statuses: (null | 'PENDING' | 'APPROVED' | 'REJECTED')[] = [
    null, null, null, null,
    'PENDING', 'PENDING', 'PENDING', 'PENDING',
    'APPROVED', 'APPROVED', 'APPROVED', 'APPROVED', 'APPROVED', 'APPROVED', 'APPROVED', 'APPROVED',
    'REJECTED', 'REJECTED',
  ];

  const commuters = [];
  for (let i = 0; i < COMMUTER_NAMES.length; i++) {
    const n = i + 1;
    const status = statuses[i];
    const submitted = status !== null;
    const commuter = await prisma.commuter.create({
      data: {
        commuterId: `CM-DEMO-${String(n).padStart(2, '0')}`,
        fullName: COMMUTER_NAMES[i],
        mobileNumber: `+63918${String(3000000 + n).padStart(7, '0')}`,
        passwordHash,
        dateOfBirth: new Date(1990 + randInt(0, 15), randInt(0, 11), randInt(1, 28)),
        phoneVerifiedAt: daysAgo(randInt(0, 13)),
        idType: submitted ? pick(ID_TYPES) : null,
        idFrontUrl: submitted ? '/uploads/demo-id-front.jpg' : null,
        idBackUrl: submitted ? '/uploads/demo-id-back.jpg' : null,
        selfieUrl: submitted ? '/uploads/demo-selfie.jpg' : null,
        verificationStatus: status,
        isActive: status === 'APPROVED',
        createdAt: daysAgo(randInt(0, 13), randInt(6, 22), randInt(0, 59)),
      },
    });
    commuters.push(commuter);
  }
  return commuters;
}

/** Trip history for the first 6 drivers over the last ~10 days, mostly
 * normal-length runs with a scattering of flagged short trips in varied
 * review states — gives Trip History / Jeepney Monitoring's flagged-review
 * workflow real rows to page through instead of an empty table. */
async function seedTripHistory(drivers: { id: string }[]) {
  let tripCount = 0;
  let flaggedCount = 0;

  for (const driver of drivers.slice(0, 6)) {
    for (let daysBack = 10; daysBack >= 1; daysBack--) {
      if (Math.random() > 0.65) continue; // not every driver runs every day

      const route = pick(ROUTES);
      const startedAt = daysAgo(daysBack, randInt(6, 19), randInt(0, 59));
      const isFlagged = Math.random() < 0.18;

      let endedAt: Date;
      let isShortTrip = false;
      let flagReason: string | null = null;
      if (isFlagged) {
        const immediateTap = Math.random() < 0.4;
        const seconds = immediateTap ? randInt(5, 55) : randInt(70, 280);
        endedAt = new Date(startedAt.getTime() + seconds * 1000);
        isShortTrip = true;
        flagReason = immediateTap
          ? `Trip lasted 0m ${seconds}s, below the 60-second minimum.`
          : `Trip lasted ${Math.floor(seconds / 60)}m ${seconds % 60}s — unusually brief for a completed Pasig–Quiapo run.`;
      } else {
        endedAt = new Date(startedAt.getTime() + randInt(25, 75) * 60 * 1000);
      }

      const point = jitter(pick(ROUTE_POINTS));
      let reviewStatus: 'PENDING' | 'REVIEWED' | 'VALID' | 'INVALID' = 'PENDING';
      let reviewedAt: Date | null = null;
      let reviewedBy: string | null = null;
      let adminReviewNote: string | null = null;
      let driverExplanation: string | null = null;
      let explanationSubmittedAt: Date | null = null;

      if (isFlagged) {
        if (Math.random() < 0.5) {
          driverExplanation = pick([
            'Passenger asked to be let off right away, mis-tapped End Trip after Start.',
            'Accidentally tapped Start Trip twice, ended the duplicate immediately.',
            'Had to cancel — jeepney had a flat tire right after starting.',
          ]);
          explanationSubmittedAt = new Date(endedAt.getTime() + randInt(1, 6) * 60 * 60 * 1000);
        }
        const verdict = pick(['PENDING', 'REVIEWED', 'VALID', 'INVALID'] as const);
        reviewStatus = verdict;
        if (verdict !== 'PENDING') {
          reviewedAt = new Date(endedAt.getTime() + randInt(2, 20) * 60 * 60 * 1000);
          reviewedBy = REVIEWER_ADMIN_ID;
          if (verdict === 'INVALID') adminReviewNote = 'Confirmed accidental tap from driver explanation — no action needed.';
          else if (verdict === 'VALID') adminReviewNote = 'Genuinely aborted trip, flagged correctly.';
        }
        flaggedCount++;
      }

      await prisma.trip.create({
        data: {
          driverId: driver.id,
          route,
          status: 'COMPLETED',
          currentLat: point[0],
          currentLng: point[1],
          locationUpdatedAt: endedAt,
          startedAt,
          endedAt,
          isShortTrip,
          flagReason,
          driverExplanation,
          explanationSubmittedAt,
          reviewStatus,
          reviewedAt,
          reviewedBy,
          adminReviewNote,
        },
      });
      tripCount++;
    }
  }

  console.log(`Seeded ${tripCount} completed trips (${flaggedCount} flagged).`);
}

/** A handful of jeepneys on the road right now — Active Trips / Jeepney
 * Monitoring's Online count, and what the live map actually plots. Two
 * more drivers get a "last seen today" completed trip so View Location
 * still works for an offline unit. */
async function seedLiveState(drivers: { id: string }[]) {
  const now = new Date();
  const activeTrips = [];

  for (const driver of drivers.slice(0, 3)) {
    const point = jitter(pick(ROUTE_POINTS));
    const trip = await prisma.trip.create({
      data: {
        driverId: driver.id,
        route: pick(ROUTES),
        status: 'ACTIVE',
        currentLat: point[0],
        currentLng: point[1],
        locationUpdatedAt: now,
        startedAt: new Date(now.getTime() - randInt(10, 50) * 60 * 1000),
      },
    });
    activeTrips.push(trip);
  }

  for (const driver of drivers.slice(3, 5)) {
    const point = jitter(pick(ROUTE_POINTS));
    const startedAt = new Date(now.getTime() - randInt(2, 5) * 60 * 60 * 1000);
    await prisma.trip.create({
      data: {
        driverId: driver.id,
        route: pick(ROUTES),
        status: 'COMPLETED',
        currentLat: point[0],
        currentLng: point[1],
        locationUpdatedAt: new Date(startedAt.getTime() + randInt(30, 60) * 60 * 1000),
        startedAt,
        endedAt: new Date(startedAt.getTime() + randInt(30, 60) * 60 * 1000),
      },
    });
  }

  console.log(`Seeded ${activeTrips.length} active trips + 2 offline-but-located drivers.`);
  return activeTrips;
}

async function seedBoardings(activeTrips: { id: string }[], commuters: { id: string }[]) {
  let count = 0;
  for (const trip of activeTrips) {
    const riders = commuters.slice(randInt(0, 6), randInt(0, 6) + randInt(2, 4));
    for (const commuter of riders) {
      await prisma.tripBoarding.create({
        data: {
          tripId: trip.id,
          commuterId: commuter.id,
          boardedAt: new Date(Date.now() - randInt(2, 25) * 60 * 1000),
          riders: randInt(1, 4),
        },
      });
      count++;
    }
  }
  console.log(`Seeded ${count} trip boardings.`);
}

async function seedComplaints(drivers: { id: string }[], commuters: { id: string }[]) {
  const statuses = ['PENDING', 'PENDING', 'PENDING', 'INVESTIGATING', 'INVESTIGATING', 'RESOLVED', 'RESOLVED', 'REJECTED'] as const;
  for (const status of statuses) {
    const type = pick(COMPLAINT_TYPES);
    await prisma.complaint.create({
      data: {
        complainantId: pick(commuters).id,
        driverId: pick(drivers).id,
        complaintType: type,
        description: pick(COMPLAINT_DESCRIPTIONS[type]),
        status,
        createdAt: daysAgo(randInt(0, 9), randInt(6, 21), randInt(0, 59)),
      },
    });
  }
  console.log(`Seeded ${statuses.length} complaints.`);
}

async function seedDemandSignals(commuters: { id: string }[]) {
  const hotspots: [number, number][] = [ROUTE_POINTS[0], ROUTE_POINTS[2], ROUTE_POINTS[4]];
  let count = 0;
  for (const hotspot of hotspots) {
    const pingCount = randInt(2, 5);
    for (let i = 0; i < pingCount; i++) {
      const point = jitter(hotspot, 0.0015);
      await prisma.demandSignal.create({
        data: {
          commuterId: pick(commuters).id,
          lat: point[0],
          lng: point[1],
          route: pick(ROUTES),
          partySize: randInt(1, 4),
          createdAt: new Date(Date.now() - randInt(1, 40) * 60 * 1000),
        },
      });
      count++;
    }
  }
  console.log(`Seeded ${count} live demand signals.`);
}

async function main() {
  await wipeDemoData();

  const drivers = await seedDrivers();
  const commuters = await seedCommuters();
  console.log(`Seeded ${drivers.length} drivers, ${commuters.length} commuters.`);

  await seedTripHistory(drivers);
  const activeTrips = await seedLiveState(drivers);
  await seedBoardings(activeTrips, commuters);
  await seedComplaints(drivers, commuters);
  await seedDemandSignals(commuters);

  console.log('\nDemo data ready. Demo accounts use password Demo@1234 (bcrypt-hashed, not real logins in prod).');
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
