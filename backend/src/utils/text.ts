/**
 * Normalizes a person's name to Title Case regardless of how it was
 * typed ("juan DELA cruz" -> "Juan Dela Cruz"), so admin lists and every
 * screen that displays a name stay consistent without relying on
 * whoever typed it to have used proper capitalization. Splits on spaces
 * and hyphens, and capitalizes after an apostrophe too (e.g. "o'brien"
 * -> "O'Brien"), matching how PH names are typically written.
 */
export function toTitleCase(input: string): string {
  return input
    .trim()
    .replace(/\s+/g, ' ')
    .split(' ')
    .map((word) => word.split('-').map(capitalizeSegment).join('-'))
    .join(' ');
}

function capitalizeSegment(segment: string): string {
  return segment
    .split("'")
    .map((piece) => (piece.length === 0 ? piece : piece[0].toUpperCase() + piece.slice(1).toLowerCase()))
    .join("'");
}
