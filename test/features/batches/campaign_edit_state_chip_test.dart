import 'package:crystalapp/features/batches/models/batch.dart';
import 'package:crystalapp/features/batches/widgets/campaign_edit_state_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Batch batch({String editState = 'editable', int conflicts = 0}) =>
    Batch.fromJson({
      'id': 'b',
      'lot_code': 'LOT',
      'created_at': '2026-08-12T00:00:00Z',
      'edit_state': editState,
      'unresolved_registration_conflict_count': conflicts,
    });
void main() {
  testWidgets('shows accessible Editable and Locked state independently', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CampaignEditStateChip(batch: batch()),
              CampaignEditStateChip(batch: batch(editState: 'locked')),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Editable'), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });
  testWidgets('shows unresolved conflict count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CampaignConflictWarning(batch: batch(conflicts: 3)),
        ),
      ),
    );
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
