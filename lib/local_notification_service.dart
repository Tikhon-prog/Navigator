import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Надёжный локальный планировщик уведомлений «Поколение».
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
  static const String supplementsChannelId = 'pokolenie_supplements';
  static const String supplementsChannelName = 'ДОПы';
  static const String supplementsChannelDescription = 'Напоминания о дополнительных занятиях';

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
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        supplementsChannelId,
        supplementsChannelName,
        description: supplementsChannelDescription,
        importance: Importance.high,
      ),
    );

    await androidPlugin?.requestNotificationsPermission();
    _initialized = true;
  }

  Future<void> cancelAll() => plugin.cancelAll();

  Future<void> _cancelNotificationRange(int from, int to) async {
    final pending = await plugin.pendingNotificationRequests();
    for (final notification in pending) {
      if (notification.id >= from && notification.id <= to) {
        await plugin.cancel(notification.id);
      }
    }
  }

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
          ticker: 'Поколение',
          autoCancel: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> scheduleNextSupplement({
    required int id,
    required DateTime remindAt,
    required String title,
    required String room,
  }) async {
    await initialize();
    final scheduled = tz.TZDateTime.from(remindAt, tz.local);
    if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) return;
    final destination = room.trim().isEmpty ? title : '$title • кабинет $room';
    await plugin.zonedSchedule(
      id,
      'Скоро дополнительное занятие',
      destination,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          supplementsChannelId,
          supplementsChannelName,
          channelDescription: supplementsChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          ticker: 'Поколение',
          autoCancel: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> scheduleUpcomingSupplements({
    required List<({String id, int day, String time, String title, String room})> entries,
  }) async {
    await initialize();
    await _cancelNotificationRange(2000, 2999);
    final now = tz.TZDateTime.now(tz.local);
    var notificationId = 2000;

    // Only schedule records with a real HH:mm time. Imported records that contain
    // a lesson number (for example "урок 3") are deliberately skipped.
    for (var offset = 0; offset < 7 && notificationId <= 2999; offset++) {
      final date = tz.TZDateTime(tz.local, now.year, now.month, now.day + offset);
      for (final entry in entries.where((e) => e.day == date.weekday)) {
        if (notificationId > 2999) break;
        final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(entry.time);
        final hour = int.tryParse(match?.group(1) ?? '');
        final minute = int.tryParse(match?.group(2) ?? '');
        if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
          continue;
        }
        final startsAt = tz.TZDateTime(tz.local, date.year, date.month, date.day, hour, minute);
        final remindAt = startsAt.subtract(const Duration(minutes: 15));
        if (remindAt.isAfter(now)) {
          await scheduleNextSupplement(
            id: notificationId++,
            remindAt: remindAt,
            title: entry.title,
            room: entry.room,
          );
        }
      }
    }
  }

  Future<void> scheduleUpcomingLessons({
    required List<({String id, int day, String time, String subject, String room})>
        entries,
  }) async {
    await initialize();
    // Leave DOP reminders and other notification types intact.
    await _cancelNotificationRange(1000, 1999);

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
        // Встроенное расписание хранит время как «08:30 - 09:10».
        // Берём первое HH:mm — это фактическое начало урока.
        final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(e.time);
        final hour = int.tryParse(match?.group(1) ?? '');
        final minute = int.tryParse(match?.group(2) ?? '');
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
