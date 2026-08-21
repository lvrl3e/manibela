import 'package:flutter/material.dart';
import '../constants/app_assets.dart';
import '../constants/app_colors.dart';

/// Shown immediately after a confirmed logout, while the actual sign-out
/// work (clearing the session, but not the account data that persists
/// across logout — trip history, notifications) runs in the background.
/// Self-contained, same pattern as LoadingScreen's own boot-time
/// navigation: does its work in [initState], then swaps itself out for
/// [destinationBuilder] — the caller never needs to touch this screen's
/// context again after pushing it.
///
/// Held for a minimum visible duration so it never flashes for an
/// imperceptible instant on a fast device — signOut() is a local disk
/// write, often faster than a human can register a screen change.
class SigningOutScreen extends StatefulWidget {
  final Future<void> Function() signOut;
  final WidgetBuilder destinationBuilder;

  const SigningOutScreen({
    super.key,
    required this.signOut,
    required this.destinationBuilder,
  });

  @override
  State<SigningOutScreen> createState() => _SigningOutScreenState();
}

class _SigningOutScreenState extends State<SigningOutScreen> {
  static const _minimumVisible = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final stopwatch = Stopwatch()..start();
    try {
      await widget.signOut();
    } catch (_) {
      // Already committed to showing this screen — proceed to the login
      // screen regardless, same reasoning as the callers' own pre-existing
      // "navigate first" fallback for a failed signOut().
    }

    final remaining = _minimumVisible - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: widget.destinationBuilder),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.splashBackground,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                AppAssets.jeepneyLogo,
                width: 100,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.directions_bus_filled_rounded,
                    size: 72,
                    color: AppColors.logoBlue,
                  );
                },
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.onPrimary),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Signing you out...',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.onPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
