import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'schedule_time.dart';

/// Надёжный локальный планировщик уведомлений «Поколение».
/// Расписание школы хранится в локальном времени школы (Москва/Краснодар).
class LocalNotificationService {
  static final LocalNotificationService _instance = LocalNotificationService._();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionsRequested = false;

  static const String channelId = 'navigator_lessons';
  static const String channelName = 'Уроки';
  static const String channelDescription = 'Напоминания о ближайших уроках';
  static const String supplementsChannelId = 'pokolenie_supplements';
  static const String supplementsChannelName = 'ДОПы';
  static const String supplementsChannelDescription = 'Напоминания о дополнительных занятиях';
  static const String schoolChannelId = 'pokolenie_school_alerts';
  static const String schoolChannelName = 'Школьные оповещения';
  static const String schoolChannelDescription = 'Общие, целевые и экстренные сообщения школы';
  static const String tasksChannelId = 'pokolenie_student_tasks';
  static const String tasksChannelName = 'Домашние задания';
  static const String tasksChannelDescription = 'Напоминания о сроках домашних заданий, контрольных и проектов';
  static const String _taskNotificationIdsKey = 'pokolenie_student_task_notification_ids_v1';

  Future<void> initialize({bool requestPermissions = true}) async {
    if (!_initialized) {

    tz_data.initializeTimeZones();
    // Школа находится в Краснодаре; расписание работает по московскому времени.
    tz.setLocalLocation(tz.getLocation('Europe/Moscow'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const windows = WindowsInitializationSettings(
      appName: 'Поколение',
      appUserModelId: 'Pokolenie.Navigator.Desktop',
      guid: '7b68277c-0c39-4f4c-94ce-4f899cc2f7d4',
    );
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      windows: windows,
    );
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

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        schoolChannelId,
        schoolChannelName,
        description: schoolChannelDescription,
        importance: Importance.max,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        tasksChannelId,
        tasksChannelName,
        description: tasksChannelDescription,
        importance: Importance.high,
      ),
    );

    _initialized = true;
    }

    // Queue cleanup must not open a system permission prompt. Ask only when a
    // caller is actually scheduling notifications for the active profile.
    if (requestPermissions && !_permissionsRequested) {
      final androidPlugin = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      final iosPlugin = plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      _permissionsRequested = true;
    }
  }

  Future<void> cancelAll() => plugin.cancelAll();

  Future<void> cancelDopReminders() async {
    // OS-scheduled reminders survive process restarts; initialize the plugin
    // before querying pending requests so sign-out can cancel them on cold start.
    await initialize();
    await _cancelNotificationRange(2000, 2999);
  }

  Future<void> showIncomingNotification({
    required String title,
    required String body,
  }) async {
    await initialize();
    final id = DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
    await plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          schoolChannelId,
          schoolChannelName,
          channelDescription: schoolChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          ticker: 'Поколение',
          autoCancel: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        windows: WindowsNotificationDetails(),
      ),
    );
  }

  Future<void> _cancelNotificationRange(int from, int to) async {
    final pending = await plugin.pendingNotificationRequests();
    for (final notification in pending) {
      if (notification.id >= from && notification.id <= to) {
        await plugin.cancel(notification.id);
      }
    }
  }

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduled,
    required NotificationDetails details,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    if (!scheduled.isAfter(now)) return;

    // Delegate to the operating system scheduler on every native platform.
    // In particular, Windows uses ScheduledToastNotification instead of a Dart
    // Timer, so reminders survive closing the app and restarting Windows.
    await plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
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

    await _scheduleNotification(
      id: id,
      title: 'Следующий урок',
      body: '$subject → кабинет $room',
      scheduled: scheduled,
      details: const NotificationDetails(
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
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        windows: WindowsNotificationDetails(),
      ),
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
    await _scheduleNotification(
      id: id,
      title: 'Скоро дополнительное занятие',
      body: destination,
      scheduled: scheduled,
      details: const NotificationDetails(
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
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        windows: WindowsNotificationDetails(),
      ),
    );
  }

  Future<void> scheduleUpcomingSupplements({
    required List<({String id, int day, String time, String title, String room})> entries,
  }) async {
    await initialize(requestPermissions: entries.isNotEmpty);
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

  /// Schedule one operating-system reminder for each active student task.
  /// IDs are saved so updates cancel only task reminders, not lessons, DOPs or
  /// incoming school announcements.
  Future<void> scheduleUpcomingStudentTasks({
    required List<({String id, DateTime dueAt, String title, String subject})> entries,
    String scopeKey = 'local',
  }) async {
    await initialize(requestPermissions: entries.isNotEmpty);
    final prefs = await SharedPreferences.getInstance();
    final safeScope = scopeKey.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final idsKey = safeScope.isEmpty || safeScope == 'local'
        ? _taskNotificationIdsKey
        : '${_taskNotificationIdsKey}_$safeScope';

    // Only the currently active profile should have task reminders scheduled
    // on this device. Cancel stale reminders belonging to another signed-in
    // account before scheduling the active profile's set.
    final profileKeys = prefs.getKeys().where((key) =>
        key == _taskNotificationIdsKey ||
        key.startsWith('${_taskNotificationIdsKey}_')).toList();
    for (final key in profileKeys) {
      final storedIds = prefs.getStringList(key) ?? const <String>[];
      for (final rawId in storedIds) {
        final id = int.tryParse(rawId);
        if (id != null) await plugin.cancel(id);
      }
      if (key != idsKey) await prefs.remove(key);
    }

    final previousIds = prefs.getStringList(idsKey) ?? const <String>[];
    for (final rawId in previousIds) {
      final id = int.tryParse(rawId);
      if (id != null) await plugin.cancel(id);
    }

    final now = tz.TZDateTime.now(tz.local);
    final nextIds = <String>[];
    final usedIds = <int>{};
    for (final entry in entries) {
      if (entry.id.isEmpty || entry.title.trim().isEmpty) continue;
      final dueAt = tz.TZDateTime.from(entry.dueAt, tz.local);
      if (!dueAt.isAfter(now)) continue;

      // Give a one-hour warning for planned work. Very short deadlines get
      // a five-minute warning instead, provided that time is still ahead.
      final preferred = dueAt.subtract(const Duration(hours: 1));
      final fallback = dueAt.subtract(const Duration(minutes: 5));
      final remindAt = preferred.isAfter(now) ? preferred : fallback;
      if (!remindAt.isAfter(now)) continue;

      // Stable FNV-1a ID in a dedicated range; the exact IDs are also persisted
      // and cancelled on the next reschedule.
      var hash = 2166136261;
      // Hash the profile together with the task ID so separate accounts cannot
      // accidentally schedule colliding notification IDs.
      for (final unit in '${safeScope.isEmpty ? 'local' : safeScope}:${entry.id}'.codeUnits) {
        hash ^= unit;
        hash = (hash * 16777619) & 0x7fffffff;
      }
      var notificationId = 3000 + (hash % 1000000);
      while (!usedIds.add(notificationId)) {
        notificationId++;
      }
      final taskLabel = entry.subject.trim().isEmpty
          ? entry.title
          : '${entry.subject}: ${entry.title}';
      final body = 'Срок сдачи: ${dueAt.toLocal().toString().substring(0, 16)}';

      await _scheduleNotification(
        id: notificationId,
        title: 'Не забудь про задание',
        body: '$taskLabel. $body',
        scheduled: remindAt,
        details: const NotificationDetails(
          android: AndroidNotificationDetails(
            tasksChannelId,
            tasksChannelName,
            channelDescription: tasksChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            ticker: 'Поколение',
            autoCancel: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          windows: WindowsNotificationDetails(),
        ),
      );
      nextIds.add(notificationId.toString());
    }
    await prefs.setStringList(idsKey, nextIds);
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
        ..sort((a, b) => compareLessonTimes(a.time, b.time));

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
