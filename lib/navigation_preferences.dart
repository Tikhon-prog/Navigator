import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'dop_parser.dart';

/// Local, user-scoped navigation preferences and route feedback.
class NavigationPreferences {
  static const _avoidKey = 'navigation_avoid_locations_v1';
  static const _feedbackKey = 'navigation_route_feedback_v1';

  static String _userId(SharedPreferences prefs) {
    final raw = prefs.getString('school_user_v1');
    if (raw == null) return '';
    try {
      final user = jsonDecode(raw);
      if (user is Map && user['id'] != null) {
        return user['id'].toString().trim();
      }
    } catch (_) {}
    return '';
  }

  static Future<Set<String>> loadAvoidedLocations() async {
    final prefs = await _prefs();
    final raw = prefs.getString(
      studentProfilePreferenceKey(_avoidKey, userId: _userId(prefs)),
    );
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return (jsonDecode(raw) as List)
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> avoid(String locationId) async {
    final prefs = await _prefs();
    final key = studentProfilePreferenceKey(
      _avoidKey,
      userId: _userId(prefs),
    );
    final current = await loadAvoidedLocations();
    current.add(locationId);
    await prefs.setString(key, jsonEncode(current.toList()..sort()));
  }

  static Future<void> allow(String locationId) async {
    final prefs = await _prefs();
    final key = studentProfilePreferenceKey(
      _avoidKey,
      userId: _userId(prefs),
    );
    final current = await loadAvoidedLocations();
    current.remove(locationId);
    await prefs.setString(key, jsonEncode(current.toList()..sort()));
  }

  static Future<void> saveLastRoute({
    required String destinationId,
    String? startLocationId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = studentProfilePreferenceKey(
      'navigation_last_route_v1',
      userId: _userId(prefs),
    );
    await prefs.setString(key, jsonEncode({
      'destination_id': destinationId,
      'start_location_id': startLocationId,
    }));
  }

  static Future<Map<String, String?>> loadLastRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final key = studentProfilePreferenceKey(
      'navigation_last_route_v1',
      userId: _userId(prefs),
    );
    final raw = prefs.getString(key);
    if (raw == null) return const {};
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return const {};
      final destination = value['destination_id']?.toString().trim() ?? '';
      if (destination.isEmpty) return const {};
      final start = value['start_location_id']?.toString().trim();
      return {
        'destination_id': destination,
        'start_location_id': start == null || start.isEmpty ? null : start,
      };
    } catch (_) {
      return const {};
    }
  }

  static Future<void> saveFeedback({
    required String locationId,
    required String message,
  }) async {
    final prefs = await _prefs();
    final key = studentProfilePreferenceKey(
      _feedbackKey,
      userId: _userId(prefs),
    );
    final entries = <Map<String, dynamic>>[];
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        entries.addAll(
          (jsonDecode(raw) as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item)),
        );
      } catch (_) {}
    }
    entries.add({
      'location_id': locationId,
      'message': message.trim(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (entries.length > 50) {
      entries.removeRange(0, entries.length - 50);
    }
    await prefs.setString(key, jsonEncode(entries));
  }
}
