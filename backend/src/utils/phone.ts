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
