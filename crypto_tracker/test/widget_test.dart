import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_tracker/main.dart';

void main() {
  testWidgets('app builds', (tester) async {
    final c = ThemeController();
    await c.load();
    await tester.pumpWidget(CryptoApp(controller: c));
    expect(find.text('Крипто‑трекер'), findsOneWidget);
  });
}
