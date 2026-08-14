import 'package:flutter/material.dart';
import 'core/services/session_guard.dart';
import 'features/splash/screens/loading_screen.dart';

void main() {
  SessionGuard.install();
  runApp(const ManibelApp());
}

class ManibelApp extends StatelessWidget {
  const ManibelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: SessionGuard.navigatorKey,
      title: 'ManibelApp',
      debugShowCheckedModeBanner: false,
      home: const LoadingScreen(),
    );
  }
}