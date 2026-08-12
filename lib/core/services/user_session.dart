import 'package:shared_preferences/shared_preferences.dart';

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

  /// Local filesystem path to the picked profile photo (from image_picker),
  /// not a remote URL. Once photo upload exists, this should become an
  /// uploaded photo URL instead.
  String? photoPath;

  /// JWT from a successful signup/login, sent as a Bearer token on
  /// authenticated backend requests.
  String? authToken;

  // Change-password (change_password_screen.dart) still checks the
  // "current password" locally rather than against the backend — this
  // keeps that working. Set from whatever the commuter last typed at
  // signup/login, never returned by the backend itself.
  String? password;

  static const _kFullName = 'session_fullName';
  static const _kMobileNumber = 'session_mobileNumber';
  static const _kPassword = 'session_password';
  static const _kCommuterId = 'session_commuterId';
  static const _kDateOfBirth = 'session_dateOfBirth';
  static const _kPhotoPath = 'session_photoPath';
  static const _kAuthToken = 'session_authToken';
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
    authToken = prefs.getString(_kAuthToken);
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
    if (authToken != null) {
      await prefs.setString(_kAuthToken, authToken!);
    } else {
      await prefs.remove(_kAuthToken);
    }
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
    String? password,
  }) async {
    this.mobileNumber = mobileNumber;
    this.authToken = authToken;
    this.commuterId = commuterId;
    this.fullName = fullName;
    this.dateOfBirth = dateOfBirth;
    if (password != null) this.password = password;

    // The backend doesn't return a photo (no upload support yet), and
    // signOut() clears photoPath from memory (though not from disk) — so
    // without this, _persist() below would see photoPath == null and wipe
    // out whatever was actually saved on a previous login.
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

  /// Ends the current session WITHOUT deleting the account. Only the
  /// in-memory fields (so `isSignedIn` flips to false right away) and the
  /// "logged in" flag get cleared — the persisted copy stays on disk so
  /// [loadFromPrefs] can find it again next time someone logs back in.
  Future<void> signOut() async {
    fullName = null;
    mobileNumber = null;
    dateOfBirth = null;
    password = null;
    commuterId = null;
    photoPath = null;
    authToken = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoggedInFlag, false);
  }
}
