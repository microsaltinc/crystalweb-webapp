import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/batches/providers/batch_provider.dart';
import 'package:crystalapp/features/batches/screens/batch_list_screen.dart';
import 'package:crystalapp/features/formulas/providers/formula_provider.dart';
import 'package:crystalapp/features/projects/providers/project_provider.dart';
import 'package:crystalapp/features/rnd/providers/rnd_batch_provider.dart';
import 'package:crystalapp/features/rnd/screens/rnd_batch_list_screen.dart';

void main() {
  test('suite executes in the Web runtime', () {
    expect(kIsWeb, isTrue);
  }, skip: !kIsWeb);

  testWidgets('Web creates a server-owned production destination', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          batchListProvider.overrideWith((_) async => []),
          formulaListProvider.overrideWith((_) async => []),
          dryerListProvider.overrideWith((_) async => []),
        ],
        child: const MaterialApp(home: BatchListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Create a direct-upload destination to begin'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('New Campaign'));
    await tester.pumpAndSettle();
    expect(find.text('New Campaign'), findsOneWidget);
    expect(
      find.textContaining('uploaded directly from the browser'),
      findsOneWidget,
    );
  }, skip: !kIsWeb);

  testWidgets('Web creates a server-owned R&D destination', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rndBatchListProvider.overrideWith((_) async => []),
          projectListProvider.overrideWith((_) async => []),
          formulaListProvider.overrideWith((_) async => []),
          dryerListProvider.overrideWith((_) async => []),
        ],
        child: const MaterialApp(home: RndBatchListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Create a direct-upload destination to begin'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('New R&D experiment'));
    await tester.pumpAndSettle();
    expect(find.text('New R&D experiment'), findsOneWidget);
    expect(
      find.textContaining('uploaded directly from the browser'),
      findsOneWidget,
    );
  }, skip: !kIsWeb);
}
