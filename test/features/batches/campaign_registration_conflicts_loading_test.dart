import 'dart:async';

import 'package:crystalapp/features/batches/models/batch.dart';
import 'package:crystalapp/features/batches/providers/campaign_locking_provider.dart';
import 'package:crystalapp/features/batches/widgets/campaign_registration_conflicts_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Batch _batch() => Batch(
  id: 'batch-1',
  lotCode: 'LOT-1',
  formulaCode: 'FORMULA',
  dryerCode: 'D1',
  campaignNum: 1,
  sublotCount: 1,
  imageCount: 1,
  status: 'complete',
  createdAt: DateTime(2026),
);

void main() {
  testWidgets('does not flash a red conflict warning during initial load', (
    tester,
  ) async {
    final pending = Completer<List<Never>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          registrationConflictsProvider.overrideWith(
            (ref, id) => pending.future,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CampaignRegistrationConflictsSection(batch: _batch()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('registration-conflicts-section')),
      findsNothing,
    );
    expect(find.text('Preserved upload conflicts'), findsNothing);
  });
}
