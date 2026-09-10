import 'package:crystalapp/core/api/api_error.dart';
import 'package:crystalapp/features/batches/models/batch.dart';
import 'package:crystalapp/features/batches/models/campaign_locking.dart';
import 'package:crystalapp/features/batches/providers/campaign_locking_provider.dart';
import 'package:crystalapp/features/batches/widgets/campaign_registration_conflicts_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Batch _batch({String state = 'editable', int version = 4}) => Batch.fromJson({
  'id': 'batch-1',
  'lot_code': 'LOT-1',
  'created_at': '2026-08-12T00:00:00Z',
  'edit_state': state,
  'edit_state_version': version,
  'unresolved_registration_conflict_count': 1,
});

RegistrationConflict _conflict() => RegistrationConflict(
  id: 'conflict-1',
  batchId: 'batch-1',
  operationKind: 'register_image',
  source: 'lambda',
  object: const RegistrationObjectReference(
    bucket: 'microscope-input',
    key: 'microscope-1/2026/LOT-1/image.tif',
    versionOrEtag: 'v-safe',
  ),
  safeReason: 'The upload was preserved because this campaign is Locked.',
  firstDetectedAt: DateTime.utc(2026, 8, 12, 14, 30),
  lastSeenAt: DateTime.utc(2026, 8, 12, 14, 35),
  occurrenceCount: 2,
  canRetry: true,
);

Widget _app({
  required Batch batch,
  required Future<List<RegistrationConflict>> Function() load,
  RegistrationConflictRetryCallback? retry,
}) => ProviderScope(
  overrides: [registrationConflictsProvider.overrideWith((ref, id) => load())],
  child: MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CampaignRegistrationConflictsSection(
          batch: batch,
          retryConflict: retry,
        ),
      ),
    ),
  ),
);

RegistrationConflictRetry _resolved() => const RegistrationConflictRetry(
  conflictId: 'conflict-1',
  resolved: true,
  contentRevision: 8,
  resultImageId: 'image-1',
  registrationAction: 'created',
);

void main() {
  testWidgets(
    'shows one persistent actionable section with safe object details',
    (tester) async {
      await tester.pumpWidget(
        _app(batch: _batch(), load: () async => [_conflict()]),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('registration-conflicts-section')),
        findsOneWidget,
      );
      expect(
        find.text('microscope-input/microscope-1/2026/LOT-1/image.tif'),
        findsOneWidget,
      );
      expect(find.text('Object version: v-safe'), findsOneWidget);
      expect(find.textContaining('Detected'), findsOneWidget);
      expect(
        find.text('The upload was preserved because this campaign is Locked.'),
        findsOneWidget,
      );
      expect(find.text('Observed 2 times'), findsOneWidget);
    },
  );

  testWidgets('Retry is disabled while Locked and explains how to proceed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        batch: _batch(state: 'locked'),
        load: () async => [_conflict()],
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('retry-registration-conflict-conflict-1')),
    );
    expect(button.onPressed, isNull);
    expect(
      find.textContaining('available after this campaign is unlocked'),
      findsOneWidget,
    );
  });

  testWidgets(
    'failed or re-locked retry stays visible with a safe inline error',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _app(
          batch: _batch(),
          load: () async => [_conflict()],
          retry: (id, version) async {
            calls++;
            throw const ApiError(
              code: 'campaign_locked',
              message:
                  'Campaign was locked elsewhere. Refresh before retrying.',
              details: {'diagnostic': 'must-not-be-rendered'},
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('retry-registration-conflict-conflict-1')),
      );
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(
        find.byKey(const Key('registration-conflict-conflict-1')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Campaign was locked elsewhere'),
        findsWidgets,
      );
      expect(find.textContaining('must-not-be-rendered'), findsNothing);
    },
  );

  testWidgets(
    'committed resolution refreshes and removes the warning section',
    (tester) async {
      var loads = 0;
      int? sentVersion;
      await tester.pumpWidget(
        _app(
          batch: _batch(version: 7),
          load: () async => loads++ == 0 ? [_conflict()] : [],
          retry: (id, version) async {
            sentVersion = version;
            return _resolved();
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('retry-registration-conflict-conflict-1')),
      );
      await tester.pumpAndSettle();

      expect(sentVersion, 7);
      expect(loads, greaterThanOrEqualTo(2));
      expect(
        find.byKey(const Key('registration-conflicts-section')),
        findsNothing,
      );
      expect(find.text('Registration conflict resolved.'), findsOneWidget);
    },
  );
}
