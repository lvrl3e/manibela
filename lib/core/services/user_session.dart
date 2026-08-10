import 'package:shared_preferences/shared_preferences.dart';

/// Session store for the logged-in commuter.
///
/// There's still no backend — this now persists to on-device storage via
/// shared_preferences so a signed-up user's data survives closing and
/// reopening the app, instead of vanishing whenever the process dies.
/// When a real backend/auth service exists, replace the bodies of these
/// methods with actual API calls, swap plaintext `password` for a proper
/// token-based session, and consider moving off a raw singleton onto
/// Provider/Riverpod/Bloc so widgets can listen for changes instead of
/// reading a static field once at build time.
class UserSession {
  UserSession._internal();

  static final UserSession instance = UserSession._internal();

  String? fullName;

  /// Always stored/compared in canonical `+63XXXXXXXXXX` form — see
  /// [PhoneUtils.toE164] wherever a raw user-entered number needs
  /// converting before it's compared against this.
  String? mobileNumber;

  DateTime? dateOfBirth;
  String? commuterId;

  /// Local filesystem path to the picked profile photo (from image_picker),
  /// not a remote URL. Once a real backend/auth service exists, this
  /// should probably become an uploaded photo URL instead.
  String? photoPath;

  // TODO: NEVER keep plaintext passwords once a backend exists. This only
  // exists so login/change-password have something to check against while
  // everything is still mocked locally.
  String? password;

  static const _kFullName = 'session_fullName';
  static const _kMobileNumber = 'session_mobileNumber';
  static const _kPassword = 'session_password';
  static const _kCommuterId = 'session_commuterId';
  static const _kDateOfBirth = 'session_dateOfBirth';
  static const _kPhotoPath = 'session_photoPath';
  static const _kLoggedInFlag = 'commuterLoggedIn';

  bool get isSignedIn => fullName != null;

  /// Loads whatever was previously persisted into the in-memory fields.
  /// Call this before relying on session data anywhere the app might have
  /// just cold-started (e.g. at the top of login, or on a splash screen
  /// that auto-navigates a "remembered" user straight to the dashboard).
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    fullName = prefs.getString(_kFullName);
    mobileNumber = prefs.getString(_kMobileNumber);
    password = prefs.getString(_kPassword);
    commuterId = prefs.getString(_kCommuterId);
    photoPath = prefs.getString(_kPhotoPath);
    final dobIso = prefs.getString(_kDateOfBirth);
    dateOfBirth = dobIso != null ? DateTime.tryParse(dobIso) : null;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (fullName != null) await prefs.setString(_kFullName, fullName!);
    if (mobileNumber != null) {
      await prefs.setString(_kMobileNumber, mobileNumber!);
    }
    if (password != null) await prefs.setString(_kPassword, password!);
    if (commuterId != null) await prefs.setString(_kCommuterId, commuterId!);
    if (photoPath != null) {
      await prefs.setString(_kPhotoPath, photoPath!);
    } else {
      await prefs.remove(_kPhotoPath);
    }
    if (dateOfBirth != null) {
      await prefs.setString(_kDateOfBirth, dateOfBirth!.toIso8601String());
    } else {
      await prefs.remove(_kDateOfBirth);
    }
  }

  /// Called after a successful sign-up. [mobileNumber] should already be
  /// normalized to `+63XXXXXXXXXX` (PhoneUtils.toE164).
  ///
  /// This always starts the account with no profile photo and a fresh
  /// commuter ID — a device's previous account (whoever was signed up
  /// before) must never leak its photo/ID into a brand-new signup.
  Future<void> signUp({
    required String fullName,
    required String mobileNumber,
    required String password,
  }) async {
    this.fullName = fullName;
    this.mobileNumber = mobileNumber;
    this.password = password;
    photoPath = null;
    commuterId = _generateCommuterId();
    await _persist();
  }

  /// Whether [mobileNumber] (already normalized to `+63XXXXXXXXXX`) matches
  /// the account currently on file. Since this app only stores one local
  /// account, this is really "does *any* registered account match" — use
  /// it to show "this number isn't registered" before even checking the
  /// password, so that error doesn't get conflated with "wrong password".
  bool isRegistered(String mobileNumber) {
    return this.mobileNumber != null && this.mobileNumber == mobileNumber;
  }

  /// Checks a login attempt against whatever account is on file.
  /// [mobileNumber] should already be normalized to `+63XXXXXXXXXX`.
  /// Returns false if there's no account stored at all (nobody has signed
  /// up locally yet) or if either value doesn't match.
  bool verifyCredentials({
    required String mobileNumber,
    required String password,
  }) {
    if (this.mobileNumber == null || this.password == null) return false;
    return this.mobileNumber == mobileNumber && this.password == password;
  }

  /// Called after a successful login. Assumes [loadFromPrefs] has already
  /// populated the account being logged into (or that [verifyCredentials]
  /// was checked first) — this mainly exists to explicitly mark who's
  /// currently signed in.
  Future<void> logIn({
    required String mobileNumber,
    String? fullName,
    String? password,
  }) async {
    this.mobileNumber = mobileNumber;
    if (fullName != null) this.fullName = fullName;
    if (password != null) this.password = password;
    commuterId ??= _generateCommuterId();
    await _persist();
  }

  /// Called from SettingsScreen when the user saves profile changes.
  Future<void> updateProfile({
    String? fullName,
    String? mobileNumber,
    DateTime? dateOfBirth,
  }) async {
    if (fullName != null && fullName.isNotEmpty) this.fullName = fullName;
    if (mobileNumber != null) this.mobileNumber = mobileNumber;
    this.dateOfBirth = dateOfBirth;
    await _persist();
  }

  /// Called from SettingsScreen when the user picks/removes a profile
  /// photo. Pass null to remove the current photo.
  Future<void> updatePhoto(String? path) async {
    photoPath = path;
    await _persist();
  }

  /// Returns false if [currentPassword] doesn't match what's on file, so
  /// the caller can show an error instead of silently "succeeding".
  Future<bool> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (password != null && currentPassword != password) {
      return false;
    }
    password = newPassword;
    await _persist();
    return true;
  }

  /// Ends the current session WITHOUT deleting the account. This app has
  /// no backend yet, so the SharedPreferences copy of fullName/
  /// mobileNumber/password/commuterId *is* the account record — wiping it
  /// here would mean the next login has nothing left to verify against,
  /// even with the correct credentials.
  ///
  /// Only the in-memory fields (so `isSignedIn` flips to false right away)
  /// and the "logged in" flag get cleared. The persisted account data
  /// stays on disk so [loadFromPrefs] can find it again next time someone
  /// logs back in.
  /// Called from the forgot-password flow after OTP verification. Unlike
  /// [updatePassword], this doesn't require the current password — OTP
  /// verification is what proves ownership of the account here instead.
  /// Returns false if [mobileNumber] doesn't match the account on file, so
  /// the caller can show an error instead of silently doing nothing.
  Future<bool> resetPassword({
    required String mobileNumber,
    required String newPassword,
  }) async {
    if (this.mobileNumber == null || this.mobileNumber != mobileNumber) {
      return false;
    }
    password = newPassword;
    await _persist();
    return true;
  }

  Future<void> signOut() async {
    fullName = null;
    mobileNumber = null;
    dateOfBirth = null;
    password = null;
    commuterId = null;
    photoPath = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoggedInFlag, false);
  }

  String _generateCommuterId() {
    final suffix = (DateTime.now().millisecondsSinceEpoch % 100000)
        .toString()
        .padLeft(5, '0');
    return 'CM-$suffix';
  }
}