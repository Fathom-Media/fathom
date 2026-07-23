import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper over flutter_local_notifications for system notifications
/// (download complete, a Seerr request becoming available). Best-effort: if the
/// platform can't initialize, every call is a silent no-op. Linux + Android are
/// wired now; Windows is added when that target lands.
class AppNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _id = 100;

  static Future<void> init() async {
    try {
      const settings = InitializationSettings(
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  static Future<void> show(String title, String body) async {
    if (!_ready) return;
    try {
      const details = NotificationDetails(
        linux: LinuxNotificationDetails(),
        android: AndroidNotificationDetails(
          'fathom_general',
          'Fathom',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      );
      await _plugin.show(_id++, title, body, details);
    } catch (_) {}
  }
}
