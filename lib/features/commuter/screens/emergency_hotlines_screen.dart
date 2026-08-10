import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';

class _Hotline {
  final String name;
  final String number;
  final String description;
  final IconData icon;
  final Color color;

  const _Hotline({
    required this.name,
    required this.number,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class EmergencyHotlinesScreen extends StatelessWidget {
  const EmergencyHotlinesScreen({super.key});

  static const List<_Hotline> _hotlines = [
    _Hotline(
      name: 'National Emergency Hotline',
      number: '911',
      description: 'Police, fire, and medical emergencies',
      icon: Icons.emergency_rounded,
      color: Color(0xFFE23F3F),
    ),
    _Hotline(
      name: 'Philippine National Police',
      number: '117',
      description: 'Report crimes or request police assistance',
      icon: Icons.local_police_rounded,
      color: Color(0xFF2E5FE5),
    ),
    _Hotline(
      name: 'Bureau of Fire Protection',
      number: '(02) 8426-0219',
      description: 'Fire emergencies and rescue',
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFE5A800),
    ),
    _Hotline(
      name: 'Red Cross Ambulance',
      number: '143',
      description: 'Medical emergencies and ambulance dispatch',
      icon: Icons.medical_services_rounded,
      color: Color(0xFF2E9E6D),
    ),
    _Hotline(
      name: 'LTFRB Hotline',
      number: '1342',
      description: 'Report jeepney or driver violations',
      icon: Icons.directions_bus_rounded,
      color: AppColors.logoBlue,
    ),
  ];

  Future<void> _confirmAndCall(
    BuildContext context,
    _Hotline hotline,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Call ${hotline.name}?',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'You are about to dial ${hotline.number}. '
            'Only use this for a genuine emergency.',
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          actionsPadding: const EdgeInsets.only(
            right: 12,
            bottom: 8,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE23F3F),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Call Now',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    // Remove formatting from numbers such as:
    // (02) 8426-0219 -> 0284260219
    final phoneNumber = hotline.number
        .replaceAll(' ', '')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll('-', '');

    final Uri phoneUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );

    try {
      final canCall = await canLaunchUrl(phoneUri);

      if (!canCall) {
        if (!context.mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unable to open the phone dialer for ${hotline.number}.',
            ),
          ),
        );

        return;
      }

      await launchUrl(phoneUri);
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to make the call. Please try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeader(context),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // Emergency information
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFBDADA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFF1BABA),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFE23F3F),
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tap a hotline to call. You will be asked to confirm before the call is placed.',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7A1F1F),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            const SizedBox(height: 10),

            ..._hotlines.map(
              (hotline) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _HotlineCard(
                    hotline: hotline,
                    onTap: () {
                      _confirmAndCall(
                        context,
                        hotline,
                      );
                    },
                  ),
                );
              },
            ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // HEADER
  // ===============================================================
  // Scrolls away with the rest of the content — same yellow banner +
  // back button + title/subtitle convention used across the other
  // commuter screens (see ChangePasswordScreen).

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, Color(0xFFFFDE7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_back, size: 18, color: Colors.black87),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Emergency Hotlines',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.onPrimary,
                  ),
                ),
                const SizedBox(height: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HotlineCard extends StatelessWidget {
  final _Hotline hotline;
  final VoidCallback onTap;

  const _HotlineCard({
    required this.hotline,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // Hotline icon
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: hotline.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hotline.icon,
                  color: hotline.color,
                  size: 23,
                ),
              ),

              const SizedBox(width: 13),

              // Name and description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hotline.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      hotline.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: Colors.black45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Number and call icon
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hotline.number,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.logoBlue,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8F6EF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.call_rounded,
                      size: 16,
                      color: Color(0xFF2E9E6D),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}