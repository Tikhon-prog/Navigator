import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigator/main.dart';

void main() {
  testWidgets('Поколение app mounts its Material application', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PokolenieApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
  testWidgets('Study Hub combines schedule and DOPs into one section', (tester) async {
    SharedPreferences.setMockInitialValues({
      'student_class_name': '8В',
      'student_class_id': '8В',
      'student_class_group_8В': 1,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: StudyHubPage(
          initialTab: 0,
          onMenu: () {},
          onNotes: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Учёба'), findsOneWidget);
    expect(find.text('Расписание'), findsOneWidget);
    expect(find.text('ДОПы'), findsOneWidget);

    await tester.tap(find.text('ДОПы'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Расписание ДОПов'), findsOneWidget);
  });

  testWidgets('About page explains who the app is for', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AboutPage()),
    );

    expect(
      find.text('Приложение создано для учеников и учителей школы «Поколение».'),
      findsOneWidget,
    );
    expect(find.text('Навигация по школе'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Школьная жизнь'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Школьная жизнь'), findsOneWidget);
  });

}
