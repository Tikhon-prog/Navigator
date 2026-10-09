import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/main.dart';

void main() {
  testWidgets('Navigator app mounts its Material application', (tester) async {
    await tester.pumpWidget(const NavigatorApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
