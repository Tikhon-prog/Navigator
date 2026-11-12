import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigator/announcements_page.dart';

void main() {
  testWidgets('announcements screen shows a clean empty state without a configured source', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: SchoolAnnouncementsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Новости школы'), findsOneWidget);
    expect(find.text('Объявления появятся здесь'), findsOneWidget);
    expect(find.textContaining('интранет'), findsNothing);
    expect(find.textContaining('офлайн'), findsNothing);
  });

  testWidgets('announcements screen shows cached school-wide notices offline', (tester) async {
    SharedPreferences.setMockInitialValues({
      'school_announcements_cache_v2': jsonEncode([
        {
          'id': 'notice-1',
          'title': 'Завтра школьное мероприятие',
          'body': 'Начало в 10:00',
          'published_at': '2026-10-17T12:00:00+03:00',
          'target_class_id': '',
          'severity': 'info',
          'expires_at': '',
        },
      ]),
    });
    await tester.pumpWidget(const MaterialApp(home: SchoolAnnouncementsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Завтра школьное мероприятие'), findsOneWidget);
    expect(find.text('Начало в 10:00'), findsOneWidget);
    expect(find.textContaining('сохранённая копия'), findsNothing);
  });
}
