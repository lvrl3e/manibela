/// Every phone entry field in this app (login, signup, forgot password,
/// settings) collects the local `09XXXXXXXXX` form — the one PH mobile
/// users actually type from muscle memory — and normalizes it here before
/// it ever reaches the backend, which stores/compares everything as
/// canonical `+63XXXXXXXXXX` (E.164). [toE164] also accepts an
/// already-`+63` string unchanged, so it's safe to call on values that
/// went through this conversion already (e.g. re-displaying a saved
/// number in an editable field).
class PhoneUtils {
  const PhoneUtils._();

  /// Converts a PH mobile number in either local (`09XXXXXXXXX`) or
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
}