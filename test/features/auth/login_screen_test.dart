import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crystalapp/features/auth/screens/login_screen.dart';
import 'package:crystalapp/features/auth/screens/operator_pin_screen.dart';

void main() {
  group('LoginScreen', () {
    testWidgets('shows SSO sign in button', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LoginScreen())),
      );
      expect(find.text('Sign in with Microsalt SSO'), findsOneWidget);
    });

    testWidgets('shows app title', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LoginScreen())),
      );
      expect(find.text('CrystalApp'), findsOneWidget);
    });

    testWidgets('shows microsalt domain hint', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LoginScreen())),
      );
      expect(find.textContaining('Microsalt Google account'), findsOneWidget);
    });

    testWidgets('does not expose the removed development login controls', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LoginScreen())),
      );

      expect(find.textContaining('Dev Login'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('OperatorPinScreen', () {
    testWidgets('shows PIN input field', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: OperatorPinScreen(
              operatorId: 'op-123',
              operatorName: 'Test Operator',
            ),
          ),
        ),
      );
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows operator name', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: OperatorPinScreen(
              operatorId: 'op-123',
              operatorName: 'Test Operator',
            ),
          ),
        ),
      );
      expect(find.text('Test Operator'), findsOneWidget);
    });

    testWidgets('verify button disabled with empty PIN', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: OperatorPinScreen(
              operatorId: 'op-123',
              operatorName: 'Test Operator',
            ),
          ),
        ),
      );
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Verify'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('verify button enabled with 4+ digit PIN', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: OperatorPinScreen(
              operatorId: 'op-123',
              operatorName: 'Test Operator',
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Verify'),
      );
      expect(button.onPressed, isNotNull);
    });
  });
}
