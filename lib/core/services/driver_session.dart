import 'package:shared_preferences/shared_preferences.dart';

/// Session store for the logged-in driver. Mirrors [UserSession] (the
/// commuter equivalent) but keeps its own prefs keys/prefix so a driver
/// account never collides with a commuter account on the same device —
/// there's still no backend, so this is the source of truth for "is anyone
/// signed in as a driver right now".
class DriverSession {
  DriverSession._internal();

  static final DriverSession instance = DriverSession._internal();

  String? fullName;

  /// Always stored/compared in canonical `+63XXXXXXXXXX` form — see
  /// [PhoneUtils.toE164] wherever a raw user-entered number needs
  /// converting before it's compared against this.
  String? mobileNumber;

  String? driverId;

  /// The vehicle plate assigned to this driver. Set once when the account
  /// is created (by an operator/admin, in the real system) — never
  /// editable by the driver themselves, unlike name/mobile number.
  String? plateNumber;

  /// Local filesystem path to the picked profile photo (from image_picker),
  /// not a remote URL. Once a real backend/auth service exists, this
  /// should probably become an uploaded photo URL instead.
  String? photoPath;

  // TODO: NEVER keep plaintext passwords once a backend exists. This only
  // exists so driver login has something to check against while everything
  // is still mocked locally.
  String? password;

  static const _kFullName = 'driver_session_fullName';
  static const _kMobileNumber = 'driver_session_mobileNumber';
  static const _kPassword = 'driver_session_password';
  static const _kDriverId = 'driver_session_driverId';
  static const _kPlateNumber = 'driver_session_plateNumber';
  static const _kPhotoPath = 'driver_session_photoPath';
  static const _kLoggedInFlag = 'driverLoggedIn';

  bool get isSignedIn => fullName != null;

  /// Loads whatever was previously persisted into the in-memory fields.
  /// Call this before relying on session data anywhere the app might have
  /// just cold-started.
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    fullName = prefs.getString(_kFullName);
    mobileNumber = prefs.getString(_kMobileNumber);
    password = prefs.getString(_kPassword);
    driverId = prefs.getString(_kDriverId);
    plateNumber = prefs.getString(_kPlateNumber);
    photoPath = prefs.getString(_kPhotoPath);
  }

  /// Drivers don't self-register in the app — an operator/admin creates
  /// their account for them. Since there's no admin backend yet, this
  /// stands in for that: it seeds one demo driver account (once) so the
  /// login screen has something real to authenticate against. Call this
  /// after [loadFromPrefs]; it's a no-op once any account is on file.
  Future<void> ensureDemoAccountSeeded() async {
    if (mobileNumber != null) return;
    await signUp(
      fullName: 'Juan Dela Cruz',
      mobileNumber: '+639171234567',
      password: 'Driver@123',
    );
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (fullName != null) await prefs.setString(_kFullName, fullName!);
    if (mobileNumber != null) {
      await prefs.setString(_kMobileNumber, mobileNumber!);
    }
    if (password != null) await prefs.setString(_kPassword, password!);
    if (driverId != null) await prefs.setString(_kDriverId, driverId!);
    if (plateNumber != null) await prefs.setString(_kPlateNumber, plateNumber!);
    if (photoPath != null) {
      await prefs.setString(_kPhotoPath, photoPath!);
    } else {
      await prefs.remove(_kPhotoPath);
    }
  }

  /// Called after a successful sign-up. [mobileNumber] should already be
  /// normalized to `+63XXXXXXXXXX` (PhoneUtils.toE164).
  ///
  /// Always starts the account with a fresh driver ID and no photo — a
  /// device's previous driver account must never leak its ID/photo into a
  /// brand-new signup.
  Future<void> signUp({
    required String fullName,
    required String mobileNumber,
    required String password,
  }) async {
    this.fullName = fullName;
    this.mobileNumber = mobileNumber;
    this.password = password;
    photoPath = null;
    driverId = _generateDriverId();
    plateNumber ??= _generatePlateNumber();
    await _persist();
  }

  /// Called from DriverSettingsScreen when the driver saves profile
  /// changes.
  Future<void> updateProfile({
    String? fullName,
    String? mobileNumber,
  }) async {
    if (fullName != null && fullName.isNotEmpty) this.fullName = fullName;
    if (mobileNumber != null) this.mobileNumber = mobileNumber;
    await _persist();
  }

  /// Called from DriverSettingsScreen when the driver picks/removes a
  /// profile photo. Pass null to remove the current photo.
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

  /// Whether [mobileNumber] (already normalized to `+63XXXXXXXXXX`) matches
  /// the account currently on file. Since this app only stores one local
  /// driver account, this is really "does *any* registered account match".
  bool isRegistered(String mobileNumber) {
    return this.mobileNumber != null && this.mobileNumber == mobileNumber;
  }

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

  /// Checks a login attempt against whatever account is on file.
  /// [mobileNumber] should already be normalized to `+63XXXXXXXXXX`.
  bool verifyCredentials({
    required String mobileNumber,
    required String password,
  }) {
    if (this.mobileNumber == null || this.password == null) return false;
    return this.mobileNumber == mobileNumber && this.password == password;
  }

  /// Called after a successful login. Assumes [loadFromPrefs] has already
  /// populated the account being logged into (or that [verifyCredentials]
  /// was checked first).
  Future<void> logIn({required String mobileNumber}) async {
    this.mobileNumber = mobileNumber;
    driverId ??= _generateDriverId();
    plateNumber ??= _generatePlateNumber();
    await _persist();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoggedInFlag, true);
  }

  /// Ends the current session WITHOUT deleting the account, so the next
  /// login has something to verify against. Only the in-memory fields (so
  /// [isSignedIn] flips to false right away) and the "logged in" flag get
  /// cleared.
  Future<void> signOut() async {
    fullName = null;
    mobileNumber = null;
    password = null;
    driverId = null;
    plateNumber = null;
    photoPath = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoggedInFlag, false);
  }

  String _generateDriverId() {
    final suffix = (DateTime.now().millisecondsSinceEpoch % 100000)
        .toString()
        .padLeft(5, '0');
    return 'DR-$suffix';
  }

  String _generatePlateNumber() {
    final suffix = (DateTime.now().millisecondsSinceEpoch % 10000)
        .toString()
        .padLeft(4, '0');
    return 'NGP-$suffix';
  }
}
