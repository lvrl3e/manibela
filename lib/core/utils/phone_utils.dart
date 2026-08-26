/// Every phone entry field in this app (login, signup, forgot password,
/// settings) shows a fixed `+63` prefix and collects just the 10-digit
/// national number after it (`9XXXXXXXXX`) — see [national] — and
/// normalizes it here before it ever reaches the backend, which stores/
/// compares everything as canonical `+63XXXXXXXXXX` (E.164). [toE164]
/// also accepts an already-`+63` string unchanged, so it's safe to call
/// on values that went through this conversion already (e.g.
/// re-displaying a saved number in an editable field).
class PhoneUtils {
  const PhoneUtils._();

  /// Converts a PH mobile number in local (`09XXXXXXXXX`), bare national
  /// (`9XXXXXXXXX` — what every phone field's controller actually holds
  /// now, typed after the field's own fixed `+63` prefix), or
  /// international (`+63XXXXXXXXXX`) form into a canonical
  /// `+63XXXXXXXXXX` (E.164) string. Non-digit characters (spaces,
  /// dashes) are stripped first.
  static String toE164(String phone) {
    final trimmed = phone.trim();
    if (trimmed.startsWith('+63')) {
      return '+63${trimmed.substring(3).replaceAll(RegExp(r'\D'), '')}';
    }

    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');

    if (digitsOnly.startsWith('63')) {
      return '+$digitsOnly';
    }
    if (digitsOnly.startsWith('0')) {
      return '+63${digitsOnly.substring(1)}';
    }
    return '+63$digitsOnly';
  }

  /// Converts a PH mobile number into just the 10-digit national number
  /// (`9XXXXXXXXX`) that every phone field's controller now actually
  /// holds — the value to show after the field's own fixed, non-editable
  /// `+63` prefix. Accepts local, bare-national, or international input,
  /// same tolerance as [toE164] (built on top of it, so it inherits that
  /// exact parsing rather than duplicating it). Used to re-populate a
  /// field with a previously-saved number (e.g. suggesting the last
  /// account used on this device) without the `+63` appearing twice.
  static String national(String phone) {
    return toE164(phone).substring(3);
  }
}