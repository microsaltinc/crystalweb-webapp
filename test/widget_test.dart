import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crystalapp/main.dart';

void main() {
  testWidgets('CrystalApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: CrystalApp()));
    await tester.pumpAndSettle();
    // App starts and shows Login screen (unauthenticated redirect)
    expect(find.text('CrystalApp'), findsOneWidget);
    expect(find.text('Sign in with Microsalt SSO'), findsOneWidget);
  });
}
