import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'local_ai_chat_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bell_countdown.dart';
import 'schedule_time.dart';
import 'notes_page.dart';
import 'admin_panel.dart';
import 'announcements_page.dart';
import 'door_points.dart';
import 'corridor_roads.dart';
import 'local_notification_service.dart';
import 'security_service.dart';
import 'supplements_page.dart';
import 'school_account_service.dart';
import 'dop_parser.dart';
import 'school_portal_page.dart';
import 'mentor_mentees_page.dart';
import 'online_data_service.dart';
import 'desktop_notification_polling_stub.dart' if (dart.library.io) 'desktop_notification_polling_io.dart' as desktop_polling;

part 'src/school_models.dart';
part 'src/schedule_catalog.dart';
part 'src/student_dialogs.dart';
part 'src/school_data.dart';
part 'src/route_engine.dart';
part 'src/app_shell.dart';
part 'src/home_page.dart';
part 'src/all_features_page.dart';
part 'src/map_page.dart';
part 'src/schedule_page.dart';
part 'src/route_pages.dart';
part 'src/settings_page.dart';

const String _configuredApiBase = String.fromEnvironment('POKOLENIE_API_BASE_URL');

Future<void> _seedOnlineSettings() async {
  final base = _configuredApiBase.trim();
  if (!NavigatorApiConfig(baseUrl: base).enabled) return;
  final prefs = await SharedPreferences.getInstance();
  final savedBase = (prefs.getString('navigator_api_url') ?? '').trim();
  // A build-time URL is a default for new installs. Respect a user's explicit
  // existing configuration (including disabling online mode).
  if (savedBase.isEmpty) {
    await prefs.setString('navigator_api_url', base);
    if (prefs.getBool('navigator_api_enabled') == null) {
      await prefs.setBool('navigator_api_enabled', true);
    }
  }
  final selectedBase = (prefs.getString('navigator_api_url') ?? base).trim();
  if ((prefs.getString('school_api_base_url_v1') ?? '').trim().isEmpty &&
      NavigatorApiConfig(baseUrl: selectedBase).enabled) {
    await prefs.setString('school_api_base_url_v1', selectedBase);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {
      // This is a mobile-only system UI preference; desktop startup must proceed.
    }
  }
  try { await _seedOnlineSettings(); } catch (_) {}
  try { await LocalNotificationService().initialize(); } catch (_) {}
  runApp(const PokolenieApp());
  // Re-register FCM token/listeners in the background after a prior SSO login.
  unawaited(SchoolAccountService().restoreSession());
  unawaited(desktop_polling.startDesktopNotificationPolling());
}

enum AppThemeType { yellow, turquoise, darkBlue, violet, coral, green }

/// In-process signal that local AI actions changed data shared by app sections.
final ValueNotifier<int> schoolLocalDataRevision = ValueNotifier<int>(0);

void notifySchoolLocalDataChanged() {
  schoolLocalDataRevision.value++;
}

/// Desktop users can scroll with the wheel/trackpad and also drag scrollable
/// lists with the mouse, matching the expected Windows interaction.
class _PokolenieScrollBehavior extends MaterialScrollBehavior {
  const _PokolenieScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
      };
}

class AppPalette {
  static const yellow = [Color(0xFFFFC94D), Color(0xFFEADCC7)];
  static const turquoise = [Color(0xFF00BFAE), Color(0xFF79E2A0)];
  static const darkBlue = [Color(0xFF0B1633), Color(0xFF173A78), Color(0xFF3657B8)];
  static const violet = [Color(0xFF6D28D9), Color(0xFF9333EA), Color(0xFFC084FC)];
  static const coral = [Color(0xFFFF5B5B), Color(0xFFFF8A65), Color(0xFFFFC371)];
  static const green = [Color(0xFF087F5B), Color(0xFF12B886), Color(0xFF96F2D7)];

  static List<Color> gradient(AppThemeType type) => switch (type) {
    AppThemeType.yellow => yellow,
    AppThemeType.turquoise => turquoise,
    AppThemeType.darkBlue => darkBlue,
    AppThemeType.violet => violet,
    AppThemeType.coral => coral,
    AppThemeType.green => green,
  };

  static String name(AppThemeType type) => switch (type) {
    AppThemeType.yellow => 'Жёлтая',
    AppThemeType.turquoise => 'Бирюзовая',
    AppThemeType.darkBlue => 'Тёмно-синяя',
    AppThemeType.violet => 'Фиолетовая',
    AppThemeType.coral => 'Коралловая',
    AppThemeType.green => 'Зелёная',
  };
}
