import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/driver_session.dart';
import 'driver_daily_operations_screen.dart';
import 'driver_history_screen.dart';
import 'driver_monthly_analytics_screen.dart';
import 'driver_settings_screen.dart';
import 'driver_weekly_analytics_screen.dart';

/// Notifications feed for the driver — entirely backend-driven. Every
/// notification is a server-triggered event the driver might not be
/// looking at the app for (trip started/completed, account deactivated, a
/// complaint filed against them, plate number edited — see Notification's
/// doc comment in schema.prisma), fetched via [fetchRemote]. There used
/// to also be a local, client-generated half (pushed the instant
/// something happened in-session) — removed once every one of those
/// events got a real backend trigger, so there was nothing left for it to
/// carry. Kept separate from the commuter [NotificationsScreen]/
/// [AppNotification] pair so the two feeds never mix.
const int _kNotificationsPageSize = 50;

class DriverNotificationsScreen extends StatefulWidget {
  const DriverNotificationsScreen({super.key});

  static List<_RemoteNotification> _remote = [];

  /// Whether page 1 (the [_remote] page — the only one [fetchRemote]
  /// itself ever loads) has more notifications beyond it — read by the
  /// Notifications screen to decide whether to show "Load More" before
  /// the driver has tapped it even once.
  static bool hasMoreThanFirstPage = false;

  /// Best-effort — pulls the latest server-triggered notifications (page
  /// 1 only; see [_fetchPage] for later pages). Safe to call often, e.g.
  /// from the dashboard's own polling for the bell badge — failures just
  /// leave whatever was fetched last.
  static Future<void> fetchRemote() async {
    final result = await _fetchPage(1);
    if (result == null) return;
    _remote = result.notifications;
    hasMoreThanFirstPage = result.hasNextPage;
  }

  /// Fetches one page of this driver's notifications directly — used by
  /// [fetchRemote] for page 1 and by the Notifications screen's own "Load
  /// More" for anything beyond it. Null on failure (caller keeps whatever
  /// it already has).
  static Future<_NotificationPage?> _fetchPage(int page) async {
    final token = DriverSession.instance.authToken;
    if (token == null) return null;
    try {
      final response = await ApiClient.get(
        '/api/driver/notifications?page=$page&pageSize=$_kNotificationsPageSize',
        token: token,
      );
      final raw = response['notifications'] as List<dynamic>? ?? const [];
      return _NotificationPage(
        notifications: raw.map((j) => _RemoteNotification._fromJson(j as Map<String, dynamic>)).toList(),
        hasNextPage: response['hasNextPage'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  /// How many notifications haven't been seen yet — drives the badge on
  /// the dashboard's bell icon.
  static int get unreadCount => _remote.where((n) => !n.isRead).length;

  /// Marks every notification as read, clearing the badge. Called right
  /// when the bell icon is tapped, before the feed screen even opens.
  static Future<void> markAllRead() async {
    if (_remote.any((n) => !n.isRead)) {
      for (final n in _remote) {
        n.isRead = true;
      }
      final token = DriverSession.instance.authToken;
      if (token != null) {
        unawaited(
          ApiClient.post('/api/driver/notifications/mark-read', {}, token: token).catchError(
            (_) => <String, dynamic>{},
          ),
        );
      }
    }
  }

  static List<_NotificationGroup> _groupedNotifications(List<_RemoteNotification> source) {
    final all = source.map((r) => r._toAppNotification()).toList()..sort((a, b) => b.time.compareTo(a.time));
    if (all.isEmpty) return [];

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
    for (final notification in all) {
      groups.putIfAbsent(labelFor(notification.time), () => []).add(notification);
    }

    return groups.entries
        .map((entry) => _NotificationGroup(label: entry.key, items: entry.value))
        .toList();
  }

  @override
  State<DriverNotificationsScreen> createState() => _DriverNotificationsScreenState();
}

class _DriverNotificationsScreenState extends State<DriverNotificationsScreen> {
  /// Pages beyond the first — [DriverNotificationsScreen._remote] (page 1)
  /// stays the dashboard-badge's own live cache, refreshed independently;
  /// this screen layers "Load More" on top of it rather than owning page 1
  /// itself, so the badge polling elsewhere keeps working unchanged.
  final List<_RemoteNotification> _extra = [];
  int _loadedPages = 1;
  bool _hasNextPage = false;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    DriverNotificationsScreen.fetchRemote().then((_) {
      if (!mounted) return;
      setState(() => _hasNextPage = DriverNotificationsScreen.hasMoreThanFirstPage);
    });
  }

  List<_RemoteNotification> get _allLoaded => [...DriverNotificationsScreen._remote, ..._extra];

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasNextPage) return;
    setState(() => _isLoadingMore = true);
    final nextPage = _loadedPages + 1;
    final result = await DriverNotificationsScreen._fetchPage(nextPage);
    if (!mounted) return;
    if (result == null) {
      setState(() => _isLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't load more notifications. Please try again.")),
      );
      return;
    }
    setState(() {
      _extra.addAll(result.notifications);
      _loadedPages = nextPage;
      _hasNextPage = result.hasNextPage;
      _isLoadingMore = false;
    });
  }

  /// Trip-related notification types — [DriverAppNotification.referenceId]
  /// is that trip's id for all three (see Notification's doc comment in
  /// schema.prisma).
  static const _kTripNotificationTypes = {'TRIP_SHORT_FLAGGED', 'TRIP_REVIEWED', 'TRIP_COMPLETED'};

  /// Navigates to whatever [item] points at — fetches that one trip
  /// directly by id (see fetchDriverTripById) rather than syncing this
  /// driver's whole trip history just to find it.
  Future<void> _openNotificationTarget(DriverAppNotification item) async {
    if (item.type == 'PLATE_NUMBER_UPDATED') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverSettingsScreen()));
      return;
    }
    if (item.type == 'DAILY_LOG_REMINDER') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverDailyOperationsScreen()));
      return;
    }
    if (item.type == 'WEEKLY_REPORT_AVAILABLE') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverWeeklyAnalyticsScreen()));
      return;
    }
    if (item.type == 'MONTHLY_REPORT_AVAILABLE') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverMonthlyAnalyticsScreen()));
      return;
    }

    if (item.type == null || !_kTripNotificationTypes.contains(item.type) || item.referenceId == null) {
      return;
    }

    final trip = await fetchDriverTripById(item.referenceId!);
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => trip != null ? DriverTripDetailsScreen(trip: trip) : const DriverHistoryScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = DriverNotificationsScreen._groupedNotifications(_allLoaded);

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
                      itemCount: groups.length + 1,
                      itemBuilder: (context, index) {
                        if (index == groups.length) {
                          if (!_hasNextPage) return const SizedBox.shrink();
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: OutlinedButton(
                                onPressed: _isLoadingMore ? null : _loadMore,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.logoBlue,
                                  side: const BorderSide(color: AppColors.logoBlue),
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: Text(
                                  _isLoadingMore ? 'Loading...' : 'Load More',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          );
                        }
                        final groupIndex = index;
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
                                child: _NotificationCard(
                                  item: item,
                                  onTap: () => _openNotificationTarget(item),
                                ),
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

  /// What screen tapping this notification opens — e.g. "TRIP_SHORT_FLAGGED",
  /// "TRIP_REVIEWED" (see Notification's doc comment in schema.prisma).
  /// Null for a notification with nothing to navigate to.
  final String? type;

  /// An id [type] tells the reader how to interpret — for these driver
  /// notifications, always a Trip id. Null alongside a null [type].
  final String? referenceId;

  /// Not final — flipped in place by
  /// [DriverNotificationsScreen.markAllRead] rather than reconstructing
  /// every entry in the feed.
  bool isRead;

  DriverAppNotification({
    required this.icon,
    required this.iconBackground,
    required this.title,
    required this.message,
    required this.time,
    this.type,
    this.referenceId,
    this.isRead = false,
  });

  String get timeLabel {
    final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $period';
  }
}

/// One page of GET /api/driver/notifications — see
/// [DriverNotificationsScreen._fetchPage].
class _NotificationPage {
  final List<_RemoteNotification> notifications;
  final bool hasNextPage;

  const _NotificationPage({required this.notifications, required this.hasNextPage});
}

/// A server-triggered notification fetched from GET /api/driver/
/// notifications (see Notification's doc comment in schema.prisma) —
/// converted to a [DriverAppNotification] with a default icon/color for
/// display, since the backend doesn't carry Flutter-specific styling.
class _RemoteNotification {
  final String id;
  final String title;
  final String message;
  bool isRead;
  final DateTime createdAt;
  final String? type;
  final String? referenceId;

  _RemoteNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.type,
    this.referenceId,
  });

  factory _RemoteNotification._fromJson(Map<String, dynamic> json) => _RemoteNotification(
        id: json['id'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
        isRead: json['isRead'] as bool,
        createdAt: DateTime.parse(json['createdAt'] as String),
        type: json['type'] as String?,
        referenceId: json['referenceId'] as String?,
      );

  DriverAppNotification _toAppNotification() => DriverAppNotification(
        icon: Icons.notifications_rounded,
        iconBackground: AppColors.logoBlue,
        title: title,
        message: message,
        time: createdAt,
        isRead: isRead,
        type: type,
        referenceId: referenceId,
      );
}

class _NotificationGroup {
  final String label;
  final List<DriverAppNotification> items;

  const _NotificationGroup({required this.label, required this.items});
}

class _NotificationCard extends StatelessWidget {
  final DriverAppNotification item;
  final VoidCallback onTap;

  const _NotificationCard({required this.item, required this.onTap});

  /// Kept in sync with what [_DriverNotificationsScreenState.
  /// _openNotificationTarget] actually knows how to handle — a type this
  /// list doesn't include falls through to a no-op tap there, so it
  /// shouldn't be drawn as tappable here either.
  static const _navigableTypes = {
    'TRIP_SHORT_FLAGGED',
    'TRIP_REVIEWED',
    'TRIP_COMPLETED',
    'PLATE_NUMBER_UPDATED',
  };

  bool get _isNavigable => item.type != null && _navigableTypes.contains(item.type);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _isNavigable ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
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
              if (_isNavigable) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: Colors.black26, size: 20),
              ],
            ],
          ),
        ),
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
