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

  testWidgets('Учёба объединяет расписание и дополнительные занятия', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PokolenieApp());
    await tester.pump();

    final studyDestination = find.byIcon(Icons.school_outlined);
    expect(studyDestination, findsOneWidget);
    await tester.tap(studyDestination);
    await tester.pump();

    expect(find.text('Расписание'), findsWidgets);
    expect(find.text('ДОПы'), findsWidgets);
    expect(find.byType(TabBar), findsOneWidget);
  });
}
