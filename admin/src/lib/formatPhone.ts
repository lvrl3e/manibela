/** Displays a PH mobile number stored in E.164 (+639171234567) in the
 * local 0-prefixed form (09171234567) admins actually recognize — the
 * inverse of the backend's toE164. Falls back to the raw string
 * unchanged if it isn't in the expected +63 shape. */
export function formatPhone(mobileNumber: string): string {
  return mobileNumber.startsWith('+63') ? `0${mobileNumber.slice(3)}` : mobileNumber;
}
