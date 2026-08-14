const PH_PLATE_REGEX = /^[A-Z]{3}[0-9]{3,4}$/;

/**
 * Strips whitespace/dashes and uppercases, so "ngp-123" or "ngp 123"
 * typed by whoever's creating the account still comes out as the
 * canonical "NGP123" — PH plate shape (3 letters, 3 or 4 digits, no
 * separator).
 */
export function normalizePlateNumber(raw: string): string {
  return raw.replace(/[^a-zA-Z0-9]/g, '').toUpperCase();
}

export function isValidPlateNumber(plateNumber: string): boolean {
  return PH_PLATE_REGEX.test(plateNumber);
}
