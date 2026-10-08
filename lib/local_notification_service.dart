import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Надёжный локальный планировщик уведомлений Navigator.
/// Расписание школы хранится в локальном времени школы (Москва/Краснодар).
class LocalNotificationService {
  static final LocalNotificationService _instance = LocalNotificationService._();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const String channelId = 'navigator_lessons';
  static const String channelName = 'Уроки';
  static const String channelDescription = 'Напоминания о ближайших уроках';

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    // Школа находится в Краснодаре; расписание работает по московскому времени.
    tz.setLocalLocation(tz.getLocation('Europe/Moscow'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await plugin.initialize(settings);

    final androidPlugin = plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.high,
      ),
    );

    await androidPlugin?.requestNotificationsPermission();
    _initialized = true;
  }

  Future<void> cancelAll() => plugin.cancelAll();

  Future<void> scheduleNextLesson({
    required int id,
    required DateTime start,
    required String subject,
    required String room,
  }) async {
    await initialize();
    final scheduled = tz.TZDateTime.from(start, tz.local);
    if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) return;

    await plugin.zonedSchedule(
      id,
      'Следующий урок',
      '$subject → кабинет $room',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          ticker: 'Navigator',
          autoCancel: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> scheduleUpcomingLessons({
    required List<({String id, int day, String time, String subject, String room})>
        entries,
  }) async {
    await initialize();
    await cancelAll();

    final now = tz.TZDateTime.now(tz.local);
    var notificationId = 1000;

    // Планируем ближайшие 7 календарных дней, а не только следующий урок
    // сегодня. Поэтому после закрытия приложения уведомления продолжают работать.
    for (var offset = 0; offset < 7; offset++) {
      final date = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + offset,
      );
      final weekday = date.weekday;

      final dayEntries = entries
          .where((e) => e.day == weekday && e.time.contains(':'))
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));

      for (final e in dayEntries) {
        final parts = e.time.split(':');
        final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '');
        final minute = int.tryParse(parts.length > 1 ? parts[1] : '');
        if (hour == null || minute == null || hour < 0 || hour > 23 ||
            minute < 0 || minute > 59) {
          continue;
        }

        final lessonStart = tz.TZDateTime(
          tz.local,
          date.year,
          date.month,
          date.day,
          hour,
          minute,
        );
        final notifyAt = lessonStart.subtract(const Duration(minutes: 5));

        if (notifyAt.isAfter(now)) {
          await scheduleNextLesson(
            id: notificationId++,
            start: notifyAt,
            subject: e.subject,
            room: e.room,
          );
        }
      }
    }
  }
}
