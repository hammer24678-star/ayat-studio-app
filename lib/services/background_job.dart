// PATCH_S163_BACKGROUND_JOBS
// Keeps long jobs (auto-sync, detect-from-video, export) alive when the app is
// minimized or the screen turns off: an Android foreground service holds the
// process + a CPU wake lock, and its notification shows live status/percent.
// Every call is best-effort - a failure here must never break the job itself.
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class BackgroundJob {
  static const int _serviceId = 7461;
  static const String _title = 'استوديو الآيات';
  static bool _inited = false;
  static bool _active = false;
  static String _text = '';
  static DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);

  static void _init() {
    if (_inited) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ayat_studio_jobs',
        channelName: 'Ayat Studio background jobs',
        channelDescription:
            'Keeps long jobs running while the app is minimized',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions:
          const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _inited = true;
  }

  static Future<void> start([String text = 'جارٍ المعالجة…']) async {
    if (!Platform.isAndroid || _active) return;
    try {
      _init();
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      _text = text;
      _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
      final r = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        notificationTitle: _title,
        notificationText: text,
      );
      _active = r is ServiceRequestSuccess;
    } catch (_) {
      _active = false;
    }
  }

  /// [text] null keeps the last status line; [progress] is 0..1 or null.
  /// Throttled to ~1 push/second so a fast progress callback can't spam it.
  static void update(String? text, double? progress) {
    if (!_active) return;
    if (text != null && text.trim().isNotEmpty) {
      _text = text.split('\n').first;
    }
    final now = DateTime.now();
    if (now.difference(_lastPush) < const Duration(milliseconds: 1200)) return;
    _lastPush = now;
    final pct = progress == null ? '' : ' — ${(progress * 100).round()}٪';
    try {
      FlutterForegroundTask.updateService(
        notificationTitle: _title,
        notificationText: '$_text$pct',
      ).then((_) {}, onError: (_) {});
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!_active) return;
    _active = false;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}
