import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';

/// Real, app-generated notifications for the driver (trip started/ended,
/// reports received, etc.) — pushed here via
/// [DriverNotificationsScreen.push] whenever one of those events actually
/// happens elsewhere in the app. Kept separate from the commuter
/// [NotificationsScreen]/[AppNotification] pair so the two feeds never mix.
/// Persisted to disk — logging out must never clear the feed.
class DriverNotificationsScreen extends StatelessWidget {
  const DriverNotificationsScreen({super.key});

  static const _kPrefsKey = 'driver_notifications_v1';

  static final List<DriverAppNotification> _notifications = [];
  static bool _loaded = false;

  /// Loads whatever was previously persisted, once. Safe to call
  /// repeatedly — a no-op after the first successful load.
  static Future<void> loadFromPrefs() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kPrefsKey);
    if (raw != null) {
      try {
        _notifications
          ..clear()
          ..addAll(raw.map((s) => DriverAppNotification._fromJson(jsonDecode(s) as Map<String, dynamic>)));
      } catch (_) {
        // Corrupt/old-format data on disk — start clean rather than crash.
      }
    }
    _loaded = true;
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kPrefsKey, _notifications.map((n) => jsonEncode(n._toJson())).toList());
  }

  /// Records a new notification at the top of the feed.
  static Future<void> push(DriverAppNotification notification) async {
    _notifications.insert(0, notification);
    await _persist();
  }

  /// Wipes notifications on logout, per request.
  static Future<void> clearOnLogout() async {
    _notifications.clear();
    await _persist();
  }

  static List<_NotificationGroup> get _groupedNotifications {
    if (_notifications.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    String labelFor(DateTime time) {
      final day = DateTime(time.year, time.month, time.day);
      if (day == today) return 'Today';
      if (day == yesterday) return 'Yesterday';
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[time.month - 1]} ${time.day}, ${time.year}';
    }

    final groups = <String, List<DriverAppNotification>>{};
    for (final notification in _notifications) {
      groups.putIfAbsent(labelFor(notification.time), () => []).add(notification);
    }

    return groups.entries
        .map((entry) => _NotificationGroup(label: entry.key, items: entry.value))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupedNotifications;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: groups.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      itemCount: groups.length,
                      itemBuilder: (context, groupIndex) {
                        final group = groups[groupIndex];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (groupIndex != 0) const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10, left: 2),
                              child: Text(
                                group.label,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            ...group.items.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _NotificationCard(item: item),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

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
                padding: EdgeInsets.all(13),
                child: Icon(Icons.arrow_back, size: 22, color: Colors.black87),
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
                  'Notifications',
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

/// A single real notification. [time] drives both the day grouping and the
/// displayed time-of-day.
class DriverAppNotification {
  final IconData icon;
  final Color iconBackground;
  final String title;
  final String message;
  final DateTime time;

  const DriverAppNotification({
    required this.icon,
    required this.iconBackground,
    required this.title,
    required this.message,
    required this.time,
  });

  String get timeLabel {
    final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $period';
  }

  // Icons are looked up by name, not by raw codePoint — a dynamically
  // constructed IconData (from a JSON int) defeats Flutter's icon
  // tree-shaking in release builds and can end up not rendering at all.
  // Every icon this app actually pushes into a driver notification is
  // listed in [_iconRegistry] below.
  static const Map<String, IconData> _iconRegistry = {
    'directions_bus': Icons.directions_bus_rounded,
    'check_circle': Icons.check_circle_rounded,
  };

  String get _iconKey => _iconRegistry.entries.firstWhere(
        (e) => e.value == icon,
        orElse: () => const MapEntry('check_circle', Icons.check_circle_rounded),
      ).key;

  Map<String, dynamic> _toJson() => {
        'icon': _iconKey,
        'iconBackground': iconBackground.toARGB32(),
        'title': title,
        'message': message,
        'time': time.toIso8601String(),
      };

  static DriverAppNotification _fromJson(Map<String, dynamic> json) => DriverAppNotification(
        icon: _iconRegistry[json['icon'] as String] ?? Icons.notifications_rounded,
        iconBackground: Color(json['iconBackground'] as int),
        title: json['title'] as String,
        message: json['message'] as String,
        time: DateTime.parse(json['time'] as String),
      );
}

class _NotificationGroup {
  final String label;
  final List<DriverAppNotification> items;

  const _NotificationGroup({required this.label, required this.items});
}

class _NotificationCard extends StatelessWidget {
  final DriverAppNotification item;

  const _NotificationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: item.iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.timeLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.message,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.black45,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.notifications_none_rounded,
            size: 56,
            color: Colors.black26,
          ),
          const SizedBox(height: 12),
          const Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black45,
            ),
          ),
        ],
      ),
    );
  }
}
