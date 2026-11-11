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
  testWidgets('About page explains who the app is for', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AboutPage()),
    );

    expect(
      find.text('Приложение создано для учеников и учителей школы «Поколение».'),
      findsOneWidget,
    );
    expect(find.text('Навигация по школе'), findsOneWidget);
    expect(find.text('Школьная жизнь'), findsOneWidget);
  });

}
