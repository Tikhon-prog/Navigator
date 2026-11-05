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
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PokolenieApp());
    await tester.pump();

    // The bottom navigation keeps inactive labels hidden. Tap the third of
    // four equal destinations through the actual NavigationBar bounds.
    final navigationBar = find.byType(NavigationBar);
    expect(navigationBar, findsOneWidget);
    final bounds = tester.getRect(navigationBar);
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 0.625, bounds.center.dy),
    );
    await tester.pump();

    expect(find.text('Расписание'), findsWidgets);
    expect(find.text('ДОПы'), findsWidgets);
    expect(find.byType(TabBar), findsOneWidget);
  });
}
