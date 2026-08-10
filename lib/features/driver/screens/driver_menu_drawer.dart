import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import 'driver_history_screen.dart';

class DriverMenuDrawer extends StatelessWidget {
  final String driverName;
  final String driverId;
  final String? photoPath;

  final VoidCallback? onSettingsTap;
  final VoidCallback? onQrCodeTap;
  final VoidCallback? onLogoutTap;

  const DriverMenuDrawer({
    super.key,
    required this.driverName,
    required this.driverId,
    this.photoPath,
    this.onSettingsTap,
    this.onQrCodeTap,
    this.onLogoutTap,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.white,
      elevation: 0,
      width: MediaQuery.of(context).size.width * .78,

      child: SafeArea(
        bottom: false,

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [
            // ===========================================================
            // PROFILE HEADER
            // ===========================================================

            _buildProfileHeader(),

            // ===========================================================
            // MENU
            // ===========================================================

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 20,
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    // ===================================================
                    // SETTINGS
                    // ===================================================

                    _buildMenuButton(
                      context: context,
                      icon: Icons.settings_rounded,
                      label: 'Settings',
                      iconColor: AppColors.secondary,

                      onTap: () {
                        Navigator.pop(context);

                        if (onSettingsTap != null) {
                          onSettingsTap!();
                        }
                      },
                    ),

                    _buildMenuDivider(),

                    // ===================================================
                    // QR CODE
                    // ===================================================

                    _buildMenuButton(
                      context: context,
                      icon: Icons.qr_code_2_rounded,
                      label: 'Your QR Code',
                      iconColor: AppColors.secondary,

                      onTap: () {
                        Navigator.pop(context);

                        if (onQrCodeTap != null) {
                          onQrCodeTap!();
                        }
                      },
                    ),

                    _buildMenuDivider(),

                    // ===================================================
                    // TRIP HISTORY
                    // ===================================================

                    _buildMenuButton(
                      context: context,
                      icon: Icons.history_rounded,
                      label: 'Trip History',
                      iconColor: AppColors.secondary,

                      onTap: () {
                        Navigator.pop(context);

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const DriverHistoryScreen(),
                          ),
                        );
                      },
                    ),

                    _buildMenuDivider(),

                    // ===================================================
                    // LOGOUT
                    // ===================================================

                    _buildMenuButton(
                      context: context,
                      icon: Icons.output_rounded,
                      label: 'Logout',
                      iconColor: AppColors.logoutIconColor,

                      onTap: () {
                        Navigator.pop(context);

                        if (onLogoutTap != null) {
                          onLogoutTap!();
                        } else {
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        }
                      },
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // PROFILE HEADER
  // ===============================================================

  Widget _buildProfileHeader() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.fromLTRB(
        18,
        28,
        18,
        24,
      ),

      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            Color(0xFFFFDE7A),
          ],

          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),

        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),

      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),

        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,

          children: [
            // ---------------------------------------------------------
            // DECORATIVE CIRCLES
            // ---------------------------------------------------------

            Positioned(
              right: -36,
              top: -36,
              child: _decorativeCircle(
                120,
                Colors.white.withOpacity(0.14),
              ),
            ),

            Positioned(
              left: -30,
              bottom: -46,
              child: _decorativeCircle(
                90,
                Colors.white.withOpacity(0.12),
              ),
            ),

            Positioned(
              right: 30,
              bottom: -20,
              child: _decorativeCircle(
                40,
                Colors.white.withOpacity(0.16),
              ),
            ),

            // ---------------------------------------------------------
            // PROFILE
            // ---------------------------------------------------------

            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),

                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),

                  child: CircleAvatar(
                    radius: 38,

                    backgroundColor:
                        const Color(0xFFD9D9D9),

                    backgroundImage:
                        photoPath != null &&
                                photoPath!.isNotEmpty
                            ? FileImage(
                                File(photoPath!),
                              )
                            : null,

                    child:
                        photoPath == null ||
                                photoPath!.isEmpty
                            ? const Icon(
                                Icons.person,
                                size: 44,
                                color:
                                    AppColors
                                        .textSecondary,
                              )
                            : null,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  driverName,

                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,

                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onPrimary,
                  ),
                ),

                const SizedBox(height: 6),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),

                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.4),
                    borderRadius:
                        BorderRadius.circular(20),
                  ),

                  child: Text(
                    driverId,

                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,

                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // DECORATIVE CIRCLE
  // ===============================================================

  Widget _decorativeCircle(
    double size,
    Color color,
  ) {
    return Container(
      width: size,
      height: size,

      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }

  // ===============================================================
  // MENU BUTTON
  // ===============================================================

  Widget _buildMenuButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,

      child: InkWell(
        borderRadius: BorderRadius.circular(12),

        onTap: onTap,

        splashColor: Colors.black.withOpacity(0.06),
        highlightColor: Colors.black.withOpacity(0.04),

        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 13,
          ),

          child: Row(
            children: [
              Icon(
                icon,
                size: 26,
                color: iconColor,
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Text(
                  label,

                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,

                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),

              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color:
                    AppColors.onPrimary
                        .withOpacity(0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===============================================================
  // MENU DIVIDER
  // ===============================================================

  Widget _buildMenuDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.black.withOpacity(0.08),
    );
  }
}
