import 'package:geolocator/geolocator.dart';

/// Opens the OS screen that actually fixes a location problem — the
/// device-wide Location Services toggle when GPS itself is off, or this
/// app's own permission page when the app was denied access (a device
/// settings shortcut wouldn't help there; the toggle to fix that lives in
/// the app's permission page instead). Used so a "location is off" banner
/// can take the user straight to the fix in one tap instead of just
/// re-running the same check that already failed.
Future<void> openRelevantLocationSettings({required bool isServiceDisabled}) {
  return isServiceDisabled
      ? Geolocator.openLocationSettings()
      : Geolocator.openAppSettings();
}
