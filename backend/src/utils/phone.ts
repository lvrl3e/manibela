/**
 * Converts a PH mobile number in either local (09XXXXXXXXX) or
 * international (+63XXXXXXXXXX) form into a canonical +63XXXXXXXXXX
 * (E.164) string. Mirrors lib/core/utils/phone_utils.dart on the Flutter
 * side so both ends agree on the same stored/compared format.
 */
export function toE164(phone: string): string {
  const trimmed = phone.trim();

  if (trimmed.startsWith('+63')) {
    return `+63${trimmed.slice(3).replace(/\D/g, '')}`;
  }

  const digitsOnly = trimmed.replace(/\D/g, '');

  if (digitsOnly.startsWith('63')) {
    return `+${digitsOnly}`;
  }
  if (digitsOnly.startsWith('0')) {
    return `+63${digitsOnly.slice(1)}`;
  }
  return `+63${digitsOnly}`;
}

/**
 * If `search` looks like a PH mobile number typed in local 0-prefixed
 * form (e.g. "0917..."), returns the +63-equivalent to also search for —
 * mobileNumber is stored in E.164 (+639171234567), so a literal "0917..."
 * substring search would otherwise never match. Returns null for
 * anything that isn't phone-shaped (names, IDs, plates, etc.), so callers
 * only widen their search when it's actually useful.
 */
export function phoneSearchVariant(search: string): string | null {
  const trimmed = search.trim();
  if (!/^0\d+$/.test(trimmed)) return null;
  return `+63${trimmed.slice(1)}`;
}
