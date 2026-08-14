import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import 'commuter_history_screen.dart';

/// Notifications feed — merges two sources:
///  - Local, client-generated notifications (trip completed, rating
///    submitted, etc.) pushed via [NotificationsScreen.push] the instant
///    something happens in this session.
///  - Server-triggered notifications for async events the commuter might
///    not be looking at the app for (account deactivated, a complaint
///    resolved/rejected — see Notification's doc comment in
///    schema.prisma), fetched via [fetchRemote].
/// Both persist across logout (they're account data, same as the rest of
/// UserSession) and are shown together, sorted by time.
const int _kNotificationsPageSize = 50;

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  static const _kPrefsKey = 'commuter_notifications_v1';

  static final List<AppNotification> _notifications = [];
  static List<_RemoteNotification> _remote = [];
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
          ..addAll(raw.map((s) => AppNotification._fromJson(jsonDecode(s) as Map<String, dynamic>)));
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
  static Future<void> push(AppNotification notification) async {
    _notifications.insert(0, notification);
    await _persist();
  }

  /// Whether page 1 (the [_remote] page — the only one [fetchRemote]
  /// itself ever loads) has more notifications beyond it — read by the
  /// Notifications screen to decide whether to show "Load More" before
  /// the commuter has tapped it even once.
  static bool hasMoreThanFirstPage = false;

  /// Best-effort — pulls the latest server-triggered notifications (page
  /// 1 only; see [_fetchPage] for later pages). Safe to call often
  /// (dashboard load, opening the bell); failures just leave whatever
  /// was fetched last in place.
  static Future<void> fetchRemote() async {
    final result = await _fetchPage(1);
    if (result == null) return;
    _remote = result.notifications;
    hasMoreThanFirstPage = result.hasNextPage;
  }

  /// Fetches one page of this commuter's server-triggered notifications
  /// directly — used by [fetchRemote] for page 1 and by the Notifications
  /// screen's own "Load More" for anything beyond it. Null on failure
  /// (caller keeps whatever it already has).
  static Future<_NotificationPage?> _fetchPage(int page) async {
    final token = UserSession.instance.authToken;
    if (token == null) return null;
    try {
      final response = await ApiClient.get(
        '/api/commuter/notifications?page=$page&pageSize=$_kNotificationsPageSize',
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
  static int get unreadCount =>
      _notifications.where((n) => !n.isRead).length + _remote.where((n) => !n.isRead).length;

  /// Marks every notification as read, clearing the badge. Called right
  /// when the bell icon is tapped, before the feed screen even opens.
  static Future<void> markAllRead() async {
    for (final n in _notifications) {
      n.isRead = true;
    }
    await _persist();

    if (_remote.any((n) => !n.isRead)) {
      for (final n in _remote) {
        n.isRead = true;
      }
      final token = UserSession.instance.authToken;
      if (token != null) {
        unawaited(
          ApiClient.post('/api/commuter/notifications/mark-read', {}, token: token).catchError(
            (_) => <String, dynamic>{},
          ),
        );
      }
    }
  }

  static List<_NotificationGroup> _groupedNotifications(List<_RemoteNotification> remoteSource) {
    final all = [..._notifications, ...remoteSource.map((r) => r._toAppNotification())]
      ..sort((a, b) => b.time.compareTo(a.time));
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

    final groups = <String, List<AppNotification>>{};
    for (final notification in all) {
      groups.putIfAbsent(labelFor(notification.time), () => []).add(notification);
    }

    return groups.entries
        .map((entry) => _NotificationGroup(label: entry.key, items: entry.value))
        .toList();
  }

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// Pages beyond the first — [NotificationsScreen._remote] (page 1) stays
  /// the dashboard-badge's own live cache, refreshed independently; this
  /// screen layers "Load More" on top of it rather than owning page 1
  /// itself, so the badge polling elsewhere keeps working unchanged.
  final List<_RemoteNotification> _extra = [];
  int _loadedPages = 1;
  bool _hasNextPage = false;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    // The dashboard already kicks off a fetch+mark-read before pushing
    // this screen, but re-fetching here catches anything that arrived in
    // the gap and keeps this screen self-sufficient if reached another way.
    NotificationsScreen.fetchRemote().then((_) {
      if (!mounted) return;
      setState(() => _hasNextPage = NotificationsScreen.hasMoreThanFirstPage);
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasNextPage) return;
    setState(() => _isLoadingMore = true);
    final nextPage = _loadedPages + 1;
    final result = await NotificationsScreen._fetchPage(nextPage);
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

  /// Notification types with somewhere to navigate to — kept in sync with
  /// what [_NotificationCard] draws as tappable, same "shared allowlist"
  /// pattern as the driver app's own notifications screen.
  static const _navigableTypes = {'TRIP_COMPLETED'};

  void _openNotificationTarget(AppNotification item) {
    if (item.type == 'TRIP_COMPLETED') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const CommuterHistoryScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = NotificationsScreen._groupedNotifications([...NotificationsScreen._remote, ..._extra]);

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

  // ===============================================================
  // HEADER
  // ===============================================================
  // Same yellow banner + back button + title/subtitle convention used
  // across the other commuter screens (Settings, Change Password,
  // Emergency Hotlines, History). Fixed (not scrolling) since the body
  // below it swaps between a list and a centered empty state.

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
class AppNotification {
  final IconData icon;
  final Color iconBackground;
  final String title;
  final String message;
  final DateTime time;

  /// What screen tapping this notification opens, e.g. "TRIP_COMPLETED"
  /// (see Notification's doc comment in schema.prisma). Null for a
  /// notification with nothing to navigate to — always null for the
  /// local, client-generated notifications (rating/report confirmations),
  /// which fire on the same screen the commuter is already looking at.
  final String? type;

  /// An id [type] tells the reader how to interpret. Null alongside a
  /// null [type].
  final String? referenceId;

  /// Not final — flipped in place by [NotificationsScreen.markAllRead]
  /// rather than reconstructing every entry in the feed.
  bool isRead;

  AppNotification({
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

  // Icons are looked up by name, not by raw codePoint — a dynamically
  // constructed IconData (from a JSON int) defeats Flutter's icon
  // tree-shaking in release builds and can end up not rendering at all.
  // Every icon this app actually pushes into a commuter notification is
  // listed in [_iconRegistry] below.
  static const Map<String, IconData> _iconRegistry = {
    'star': Icons.star_rounded,
    'shield': Icons.shield_rounded,
    'directions_bus_filled': Icons.directions_bus_filled_rounded,
  };

  String get _iconKey => _iconRegistry.entries.firstWhere(
        (e) => e.value == icon,
        orElse: () => const MapEntry('directions_bus_filled', Icons.directions_bus_filled_rounded),
      ).key;

  Map<String, dynamic> _toJson() => {
        'icon': _iconKey,
        'iconBackground': iconBackground.toARGB32(),
        'title': title,
        'message': message,
        'time': time.toIso8601String(),
        'isRead': isRead,
        'type': type,
        'referenceId': referenceId,
      };

  static AppNotification _fromJson(Map<String, dynamic> json) => AppNotification(
        icon: _iconRegistry[json['icon'] as String] ?? Icons.notifications_rounded,
        iconBackground: Color(json['iconBackground'] as int),
        title: json['title'] as String,
        message: json['message'] as String,
        time: DateTime.parse(json['time'] as String),
        isRead: json['isRead'] as bool? ?? false,
        type: json['type'] as String?,
        referenceId: json['referenceId'] as String?,
      );
}

/// One page of GET /api/commuter/notifications — see
/// [NotificationsScreen._fetchPage].
class _NotificationPage {
  final List<_RemoteNotification> notifications;
  final bool hasNextPage;

  const _NotificationPage({required this.notifications, required this.hasNextPage});
}

/// A server-triggered notification fetched from GET /api/commuter/
/// notifications (see Notification's doc comment in schema.prisma) —
/// converted to an [AppNotification] with a default icon/color for
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

  AppNotification _toAppNotification() => AppNotification(
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
  final List<AppNotification> items;

  const _NotificationGroup({required this.label, required this.items});
}

class _NotificationCard extends StatelessWidget {
  final AppNotification item;
  final VoidCallback onTap;

  const _NotificationCard({required this.item, required this.onTap});

  /// Kept in sync with [_NotificationsScreenState._navigableTypes] — a
  /// type not in that set falls through to a no-op tap there, so it
  /// shouldn't be drawn as tappable here either.
  bool get _isNavigable =>
      item.type != null && _NotificationsScreenState._navigableTypes.contains(item.type);

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
                  color: AppColors.logoBlue,
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, color: AppColors.white, size: 20),
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