import 'package:flutter/material.dart';

import '../../features/auth/screens/role_selection_screen.dart';
import 'api_client.dart';
import 'driver_session.dart';
import 'user_session.dart';

/// Wires [ApiClient.onAccountDeactivated] to a forced logout — call
/// [install] once at app startup (see main.dart). Lives outside
/// DriverSession/UserSession/ApiClient themselves because the trigger can
/// come from *any* authenticated call, including a background polling
/// Timer with no BuildContext of its own, so the navigation has to go
/// through [navigatorKey] rather than a widget's own Navigator — neither
/// session class nor ApiClient has one.
class SessionGuard {
  SessionGuard._();

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static bool _handling = false;

  static void install() {
    ApiClient.onAccountDeactivated = _handle;
  }

  static Future<void> _handle() async {
    // Multiple in-flight requests (e.g. several polling timers) can all
    // discover the deactivation within the same event-loop turn — this
    // guard collapses them into a single sign-out + navigation instead of
    // one per failed request.
    if (_handling) return;
    _handling = true;
    try {
      if (DriverSession.instance.isSignedIn) {
        await DriverSession.instance.signOut();
      }
      if (UserSession.instance.isSignedIn) {
        await UserSession.instance.signOut();
      }

      final navigator = navigatorKey.currentState;
      navigator?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        (route) => false,
      );

      final messengerContext = navigatorKey.currentContext;
      if (messengerContext != null) {
        ScaffoldMessenger.of(messengerContext).showSnackBar(
          const SnackBar(content: Text('Your account has been deactivated.')),
        );
      }
    } finally {
      _handling = false;
    }
  }
}
