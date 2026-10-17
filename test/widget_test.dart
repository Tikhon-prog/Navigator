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
}
