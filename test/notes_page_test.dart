import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigator/notes_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('personal notes can be created and persist locally', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: PersonalNotesPage()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Добавить заметку'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note-title-input')), 'Контрольная');
    await tester.enterText(find.byKey(const Key('note-body-input')), 'Повторить дроби');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(find.text('Контрольная'), findsOneWidget);
    expect(find.text('Повторить дроби'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('pokolenie_personal_notes_v1_local');
    expect(stored, isNotNull);
    expect((jsonDecode(stored!) as List).length, 1);
  });
}
