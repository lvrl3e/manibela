import 'package:flutter/material.dart';
import 'core/services/session_guard.dart';
import 'features/splash/screens/loading_screen.dart';

void main() {
  SessionGuard.install();
  runApp(const ManibelaApp());
}

class ManibelaApp extends StatelessWidget {
  const ManibelaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: SessionGuard.navigatorKey,
      title: 'ManibelaApp',
      debugShowCheckedModeBanner: false,
      home: const LoadingScreen(),
    );
  }
}
