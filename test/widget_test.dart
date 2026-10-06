import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/main.dart';

void main() {
  testWidgets('Navigator starts', (tester) async {
    await tester.pumpWidget(const NavigatorApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Navigator'), findsOneWidget);
  });
}
