/// Browser-only fallback. Windows selects desktop_notification_polling_io.dart
/// and uses real Windows toast notifications; Android/iOS use FCM.
Future<void> startDesktopNotificationPolling() async {}

Future<void> stopDesktopNotificationPolling() async {}
