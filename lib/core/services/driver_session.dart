import 'package:shared_preferences/shared_preferences.dart';

/// Session store for the logged-in driver. Mirrors [UserSession] (the
/// commuter equivalent) but keeps its own prefs keys/prefix so a driver
/// account never collides with a commuter account on the same device.
///
/// Login/logout now goes through the real backend (see /backend and
/// ApiClient) — [authToken] is the JWT returned from `/api/driver/login`,
/// sent as a Bearer token on any authenticated request. Drivers still
/// don't self-register in the app; accounts are created via the backend's
/// seed script / an operator, not from here.
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

  DateTime? dateOfBirth;

  /// Local filesystem path to a photo picked in DriverSettingsScreen but
  /// not yet uploaded/saved — purely a staging value for that screen's
  /// own preview. [photoUrl] below is the actual profile picture
  /// everywhere else in the app.
  String? photoPath;

  /// Relative path (e.g. `/uploads/xyz.png`) returned by
  /// `POST /api/driver/me/photo` — resolve with [ApiClient.resolveUrl]
  /// before handing it to `Image.network`. This is the real profile
  /// picture; null means no photo has been uploaded.
  String? photoUrl;

  /// JWT from a successful `/api/driver/login`, sent as a Bearer token on
  /// authenticated backend requests.
  String? authToken;

  /// The token encoded into this driver's QR code (see
  /// DriverQrCodeScreen). Permanent for the account's lifetime, so it's
  /// fetched from `/api/driver/me/qr-token` once and cached here —
  /// persisted like everything else below, so it survives logout and
  /// doesn't need a fresh network call on every visit to the QR screen.
  String? qrToken;

  // Change-password (driver_change_password_screen.dart) still checks the
  // "current password" locally rather than against the backend — this
  // keeps that working. Set from whatever the driver last typed at
  // login/signup, never returned by the backend itself.
  String? password;

  static const _kFullName = 'driver_session_fullName';
  static const _kMobileNumber = 'driver_session_mobileNumber';
  static const _kPassword = 'driver_session_password';
  static const _kDriverId = 'driver_session_driverId';
  static const _kPlateNumber = 'driver_session_plateNumber';
  static const _kDateOfBirth = 'driver_session_dateOfBirth';
  static const _kPhotoPath = 'driver_session_photoPath';
  static const _kPhotoUrl = 'driver_session_photoUrl';
  static const _kAuthToken = 'driver_session_authToken';
  static const _kQrToken = 'driver_session_qrToken';
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
    photoUrl = prefs.getString(_kPhotoUrl);
    authToken = prefs.getString(_kAuthToken);
    qrToken = prefs.getString(_kQrToken);
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
    if (driverId != null) await prefs.setString(_kDriverId, driverId!);
    if (plateNumber != null) await prefs.setString(_kPlateNumber, plateNumber!);
    if (photoPath != null) {
      await prefs.setString(_kPhotoPath, photoPath!);
    } else {
      await prefs.remove(_kPhotoPath);
    }
    if (photoUrl != null) {
      await prefs.setString(_kPhotoUrl, photoUrl!);
    } else {
      await prefs.remove(_kPhotoUrl);
    }
    if (authToken != null) {
      await prefs.setString(_kAuthToken, authToken!);
    } else {
      await prefs.remove(_kAuthToken);
    }
    if (qrToken != null) await prefs.setString(_kQrToken, qrToken!);
    if (dateOfBirth != null) {
      await prefs.setString(_kDateOfBirth, dateOfBirth!.toIso8601String());
    } else {
      await prefs.remove(_kDateOfBirth);
    }
  }

  /// Caches the QR token fetched from `/api/driver/me/qr-token` so
  /// DriverQrCodeScreen only needs to hit the network once per device.
  Future<void> cacheQrToken(String token) async {
    qrToken = token;
    await _persist();
  }

  /// Called from DriverSettingsScreen when the driver saves profile
  /// changes.
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

  /// Called from DriverSettingsScreen when the driver picks a new profile
  /// photo but hasn't saved yet — purely a preview staging value. Pass
  /// null to clear the staged pick.
  Future<void> updatePhoto(String? path) async {
    photoPath = path;
    await _persist();
  }

  /// Called once `POST /api/driver/me/photo` succeeds (or after clearing
  /// the photo via PATCH /me) — this is the actual saved profile picture
  /// from here on, so the staged [photoPath] preview is cleared too.
  Future<void> updatePhotoUrl(String? url) async {
    photoUrl = url;
    photoPath = null;
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

  /// Called after a successful `POST /api/driver/login`. [mobileNumber]
  /// should already be normalized to `+63XXXXXXXXXX`; the rest of the
  /// fields come straight from the backend's response body.
  Future<void> logIn({
    required String mobileNumber,
    required String authToken,
    required String driverId,
    required String fullName,
    required String plateNumber,
    DateTime? dateOfBirth,
    String? photoUrl,
    String? password,
  }) async {
    this.mobileNumber = mobileNumber;
    this.authToken = authToken;
    this.driverId = driverId;
    this.fullName = fullName;
    this.plateNumber = plateNumber;
    this.dateOfBirth = dateOfBirth;
    this.photoUrl = photoUrl;
    if (password != null) this.password = password;

    final prefs = await SharedPreferences.getInstance();

    // signOut() clears photoPath from memory (though not from disk) — so
    // without this, _persist() below would see photoPath == null and wipe
    // out a photo staged-but-unsaved from before. (photoUrl needs no such
    // rescue — the backend always returns the real current value above.)
    photoPath ??= prefs.getString(_kPhotoPath);

    await _persist();
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
    dateOfBirth = null;
    photoPath = null;
    photoUrl = null;
    authToken = null;
    qrToken = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoggedInFlag, false);
  }
}
