import 'package:shared_preferences/shared_preferences.dart';

import '../utils/date_only.dart';

/// Session store for the logged-in commuter.
///
/// Signup/login now go through the real backend (see /backend and
/// ApiClient) — [authToken] is the JWT returned from `/api/commuter/login`
/// or `/api/commuter/signup`, sent as a Bearer token on any authenticated
/// request. This still persists to on-device storage via shared_preferences
/// so the session survives closing and reopening the app.
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

  /// Local filesystem path to a photo picked in SettingsScreen but not yet
  /// uploaded/saved — purely a staging value for that screen's own
  /// preview. [photoUrl] below is the actual profile picture everywhere
  /// else in the app.
  String? photoPath;

  /// Relative path (e.g. `/uploads/xyz.png`) returned by
  /// `POST /api/commuter/me/photo` — resolve with [ApiClient.resolveUrl]
  /// before handing it to `Image.network`. This is the real profile
  /// picture; null means no photo has been uploaded.
  String? photoUrl;

  /// JWT from a successful signup/login, sent as a Bearer token on
  /// authenticated backend requests.
  String? authToken;

  // Change-password (change_password_screen.dart) still checks the
  // "current password" locally rather than against the backend — this
  // keeps that working. Set from whatever the commuter last typed at
  // signup/login, never returned by the backend itself.
  String? password;

  /// Set right after sign-up (or a login attempt blocked pending review)
  /// and cleared once the commuter either logs in successfully or
  /// explicitly backs out to role selection. Its presence is what lets
  /// the splash screen send a cold-started app straight back to
  /// AboutAppScreen instead of role selection — see LoadingScreen.
  String? pendingVerificationMobileNumber;

  /// True when the commuter checked "Remember Me" at login/signup — the
  /// splash screen only auto-signs a cold-started app into the dashboard
  /// when this is true *and* [authToken] is still on disk. Explicitly
  /// logging out always clears both, regardless of this flag, so "log
  /// out" reliably means "ask me to log in again next time."
  bool rememberMe = false;

  static const _kFullName = 'session_fullName';
  static const _kMobileNumber = 'session_mobileNumber';
  static const _kPassword = 'session_password';
  static const _kCommuterId = 'session_commuterId';
  static const _kDateOfBirth = 'session_dateOfBirth';
  static const _kPhotoPath = 'session_photoPath';
  static const _kPhotoUrl = 'session_photoUrl';
  static const _kAuthToken = 'session_authToken';
  static const _kLoggedInFlag = 'commuterLoggedIn';
  static const _kPendingVerificationMobileNumber = 'session_pendingVerificationMobileNumber';
  static const _kRememberMe = 'session_rememberMe';

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
    photoUrl = prefs.getString(_kPhotoUrl);
    authToken = prefs.getString(_kAuthToken);
    dateOfBirth = DateOnly.tryParse(prefs.getString(_kDateOfBirth));
    pendingVerificationMobileNumber = prefs.getString(_kPendingVerificationMobileNumber);
    rememberMe = prefs.getBool(_kRememberMe) ?? false;
  }

  /// True only when a cold-started app should skip straight to the
  /// dashboard instead of role selection/login.
  bool get hasRememberedSession => rememberMe && authToken != null;

  /// Marks [mobileNumber] as awaiting ID verification, so a cold-started
  /// app can be routed back to AboutAppScreen instead of role selection
  /// until this is cleared (see [clearPendingVerification]).
  Future<void> setPendingVerification(String mobileNumber) async {
    pendingVerificationMobileNumber = mobileNumber;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingVerificationMobileNumber, mobileNumber);
  }

  /// Called once the commuter either logs in successfully (verification
  /// is resolved) or explicitly chooses to go back to role selection.
  Future<void> clearPendingVerification() async {
    pendingVerificationMobileNumber = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingVerificationMobileNumber);
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
    if (photoUrl != null) {
      await prefs.setString(_kPhotoUrl, photoUrl!);
    } else {
      await prefs.remove(_kPhotoUrl);
    }
    if (dateOfBirth != null) {
      await prefs.setString(_kDateOfBirth, DateOnly.format(dateOfBirth!));
    } else {
      await prefs.remove(_kDateOfBirth);
    }
    if (authToken != null) {
      await prefs.setString(_kAuthToken, authToken!);
    } else {
      await prefs.remove(_kAuthToken);
    }
    await prefs.setBool(_kRememberMe, rememberMe);
  }

  /// Called after a successful `POST /api/commuter/signup`. [mobileNumber]
  /// should already be normalized to `+63XXXXXXXXXX`; [commuterId] and
  /// [authToken] come straight from the backend's response body.
  ///
  /// This always starts the account with no profile photo — a device's
  /// previous account (whoever was signed up before) must never leak its
  /// photo into a brand-new signup.
  Future<void> signUp({
    required String fullName,
    required String mobileNumber,
    required String password,
    required String commuterId,
    required String authToken,
  }) async {
    this.fullName = fullName;
    this.mobileNumber = mobileNumber;
    this.password = password;
    this.commuterId = commuterId;
    this.authToken = authToken;
    photoPath = null;
    photoUrl = null;
    await _persist();
  }

  /// Called after a successful `POST /api/commuter/login`. [mobileNumber]
  /// should already be normalized to `+63XXXXXXXXXX`; the rest of the
  /// fields come straight from the backend's response body.
  Future<void> logIn({
    required String mobileNumber,
    required String authToken,
    required String commuterId,
    required String fullName,
    DateTime? dateOfBirth,
    String? photoUrl,
    String? password,
    bool rememberMe = false,
  }) async {
    this.mobileNumber = mobileNumber;
    this.authToken = authToken;
    this.commuterId = commuterId;
    this.fullName = fullName;
    this.dateOfBirth = dateOfBirth;
    this.photoUrl = photoUrl;
    this.rememberMe = rememberMe;
    if (password != null) this.password = password;

    // A successful login only ever happens once verification is APPROVED
    // (see POST /api/commuter/login), so any pending-verification marker
    // from before is now stale.
    await clearPendingVerification();

    // signOut() clears photoPath from memory (though not from disk) — so
    // without this, _persist() below would see photoPath == null and wipe
    // out a photo staged-but-unsaved from before. (photoUrl needs no such
    // rescue — the backend always returns the real current value above.)
    if (photoPath == null) {
      final prefs = await SharedPreferences.getInstance();
      photoPath = prefs.getString(_kPhotoPath);
    }

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

  /// Called from SettingsScreen when the user picks a new profile photo
  /// but hasn't saved yet — purely a preview staging value. Pass null to
  /// clear the staged pick.
  Future<void> updatePhoto(String? path) async {
    photoPath = path;
    await _persist();
  }

  /// Called once `POST /api/commuter/me/photo` succeeds (or after clearing
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

  /// Ends the current session WITHOUT deleting the account. Most profile
  /// fields stay on disk (name, mobile, DOB, photo) so a quick re-login
  /// doesn't need retyping them — but [authToken] and [rememberMe] are
  /// explicitly wiped from disk too, not just memory, so "Log Out" always
  /// means the next app launch asks for a password again, remember-me or
  /// not. [loadFromPrefs] on next login still finds the rest.
  Future<void> signOut() async {
    fullName = null;
    mobileNumber = null;
    dateOfBirth = null;
    password = null;
    commuterId = null;
    photoPath = null;
    photoUrl = null;
    authToken = null;
    rememberMe = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoggedInFlag, false);
    await prefs.remove(_kAuthToken);
    await prefs.remove(_kRememberMe);
  }
}
