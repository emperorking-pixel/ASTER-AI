// notification_buffer_service.dart
//
// Wraps notification_listener_service (Android's NotificationListenerService).
// This is one of Android's most sensitive permissions — once granted, it can
// technically see every notification from every app, including banking and
// 2FA codes. To keep this safe by default:
//
//   1. It's opt-in per app: nothing is captured until you add that app's
//      package name to `allowedPackages` below (or via the UI you wire up).
//   2. Captured notifications are only ever buffered LOCALLY on the phone.
//      Nothing is sent to Anthropic (or anywhere) automatically — only when
//      the user explicitly taps "What did I miss?" in the chat screen, which
//      is the "only acts with user authorization" behavior you asked for.
//
// Find a package name via Android's own App Info screen, or
// `adb shell pm list packages` on a connected phone.

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:notification_listener_service/notification_event.dart';

class BufferedNotification {
  final String packageName;
  final String title;
  final String content;
  final DateTime receivedAt;

  BufferedNotification({
    required this.packageName,
    required this.title,
    required this.content,
    required this.receivedAt,
  });

  Map<String, dynamic> toJson() => {
        'packageName': packageName,
        'title': title,
        'content': content,
        'receivedAt': receivedAt.toIso8601String(),
      };

  factory BufferedNotification.fromJson(Map<String, dynamic> j) => BufferedNotification(
        packageName: j['packageName'] ?? '',
        title: j['title'] ?? '',
        content: j['content'] ?? '',
        receivedAt: DateTime.tryParse(j['receivedAt'] ?? '') ?? DateTime.now(),
      );
}

class NotificationBufferService {
  // Edit this list to opt specific apps in. Empty = nothing is captured.
  // Example: {'com.whatsapp', 'com.google.android.gm'}
  static Set<String> allowedPackages = {};

  static const _maxBuffered = 50;
  static final List<BufferedNotification> _buffer = [];

  static Future<File> _storeFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/aster_notification_buffer.json');
  }

  static Future<void> _persist() async {
    try {
      final file = await _storeFile();
      final data = _buffer.map((n) => n.toJson()).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (_) {
      // Non-fatal — buffer just won't survive an app restart this time.
    }
  }

  static Future<void> loadPersisted() async {
    try {
      final file = await _storeFile();
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      _buffer
        ..clear()
        ..addAll(raw.map((j) => BufferedNotification.fromJson(j as Map<String, dynamic>)));
    } catch (_) {
      // Ignore a corrupt/missing buffer file.
    }
  }

  static Future<bool> hasPermission() => NotificationListenerService.isPermissionGranted();

  /// Opens Android's special "Notification access" settings screen.
  /// Returns true once the user has granted it.
  static Future<bool> requestPermission() => NotificationListenerService.requestPermission();

  static void startListening() {
    NotificationListenerService.notificationsStream.listen((event) {
      _handleEvent(event);
    });
  }

  static void _handleEvent(ServiceNotificationEvent event) {
    if (event.hasRemoved == true) return;
    final pkg = event.packageName ?? '';
    if (!allowedPackages.contains(pkg)) return;

    _buffer.add(BufferedNotification(
      packageName: pkg,
      title: event.title ?? '',
      content: event.content ?? '',
      receivedAt: DateTime.now(),
    ));
    while (_buffer.length > _maxBuffered) {
      _buffer.removeAt(0);
    }
    _persist();
  }

  static List<BufferedNotification> unreadSince(DateTime? since) {
    if (since == null) return List.unmodifiable(_buffer);
    return _buffer.where((n) => n.receivedAt.isAfter(since)).toList();
  }

  static void clear() {
    _buffer.clear();
    _persist();
  }
}
