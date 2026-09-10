import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/batches/widgets/batch_list_filter_chips.dart';

void main() {
  testWidgets('date chip clamps its initial date to a selected lower bound', (
    tester,
  ) async {
    final now = DateTime.now();
    final lowerBound = DateTime(now.year, now.month, now.day);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BatchDateFilterChip(
            label: 'To',
            date: null,
            firstDate: lowerBound,
            lastDate: now,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('To'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('date chip clamps its initial date to an earlier upper bound', (
    tester,
  ) async {
    final upperBound = DateTime(2024);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BatchDateFilterChip(
            label: 'From',
            date: null,
            lastDate: upperBound,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('From'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
