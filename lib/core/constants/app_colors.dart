import 'package:flutter/material.dart';

class AppColors {
  // Brand Base Colors
  static const Color splashBackground = Color(0xFFEAB308); // Primary Yellow
  static const Color logoBlue = Color(0xFF0B57D0);        // Secondary Blue
  static const Color logoRed = Color(0xFFDC2626);         // Primary Red

  // Semantic aliases — yellow leads as the main brand color, blue is the
  // secondary/accent color. Prefer these in new code over reaching for
  // splashBackground/logoBlue directly so the hierarchy stays explicit.
  static const Color primary = splashBackground;    // Yellow — primary buttons, active states, main CTAs
  static const Color onPrimary = Color(0xFF92600A); // Dark amber text/icons for yellow surfaces
  static const Color secondary = logoBlue;          // Blue — secondary actions, links, accents
  static const Color onSecondary = Color(0xFFFFFFFF); // White text/icons for blue surfaces

  // Role Selection & Button Colors
  static const Color primaryButtonRed = Color(0xFFB91C1C); // Deep Red Button
  static const Color selectedCardBg = Color(0xFFFEE2E2);   // Light Red Tint
  static const Color selectedCardBorder = Color(0xFFEF4444); // Selection Border
  static const Color unselectedCardBorder = Color(0xFFE5E7EB); // Light Grey Border
  
  // Form Input & Container Colors
  static const Color inputFieldFill = Color(0xFFF5F5F5);    // Light Grey Field Fill
  static const Color iconBoxBg = Color(0xFFE5E7EB);        // Grey Icon Container Background
  static const Color errorRed = Color(0xFFDC2626);         // Validation Error Border & Text
  
  // Settings / Drawer Menu Button Colors (Matching UI reference)
  static const Color settingsTileBg = Color(0xFFDCDDF1);     // Light Blue Tint
  static const Color settingsTileBorder = Color(0xFFBCC0E7); // Blue Border
  static const Color settingsIconColor = Color(0xFF253B9E);   // Blue Icon

  static const Color qrTileBg = Color(0xFFFEF3C7);           // Light Yellow Tint
  static const Color qrTileBorder = Color(0xFFFCD34D);       // Yellow Border
  static const Color qrIconColor = Color(0xFF92600A);         // Amber Icon & Text

  static const Color logoutTileBg = Color(0xFFF9D8CE);       // Light Red/Peach Tint
  static const Color logoutTileBorder = Color(0xFFF3B4A2);   // Peach Border
  static const Color logoutIconColor = Color(0xFFC82A1C);     // Red Icon & Text

  // Neutral Colors
  static const Color textPrimary = Color(0xFF111827);      // Dark Body/Heading Text
  static const Color textSecondary = Color(0xFF6B7280);    // Grey Subtitles/Hints
  static const Color white = Color(0xFFFFFFFF);            // Clean White
}