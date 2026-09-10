import 'package:crystalapp/features/microscope_upload/models/microscope_file_set.dart';
import 'package:crystalapp/features/microscope_upload/models/microscope_upload_feedback.dart';
import 'package:crystalapp/features/microscope_upload/providers/microscope_upload_provider.dart';
import 'package:crystalapp/features/microscope_upload/services/microscope_file_source_base.dart';
import 'package:crystalapp/features/microscope_upload/widgets/microscope_upload_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SelectedFiles implements MicroscopeFileSource {
  @override
  Future<List<MicroscopeLocalFile>> pickFiles({
    bool allowMultiple = true,
  }) async => [
    _file('Sample-001.tif'),
    _file('Sample-001.txt'),
    _file('Sample-002.tif'),
  ];

  MicroscopeLocalFile _file(String name) =>
      MicroscopeLocalFile(path: '/tmp/$name', name: name, sizeBytes: 10);

  @override
  Future<MicroscopeLocalFile> hashFile(MicroscopeLocalFile file) async => file;

  @override
  void releaseFiles(Iterable<MicroscopeLocalFile> files) {}

  @override
  Stream<List<int>> openRead(
    MicroscopeLocalFile file, {
    int? start,
    int? end,
  }) => const Stream.empty();
}

class _RecoveryNotifier extends MicroscopeUploadNotifier {
  _RecoveryNotifier(super.ref, super.args) {
    state = const MicroscopeUploadState(
      error: 'An earlier unfinished upload is using Sample-001.',
      recoverySessionId: 'previous-session',
      recoveryIdentities: ['sample-001'],
    );
  }

  var discardCalls = 0;

  @override
  Future<void> discardPreviousAndRetry() async {
    discardCalls++;
  }
}

class _CommunicationNotifier extends MicroscopeUploadNotifier {
  _CommunicationNotifier(super.ref, super.args, {bool uploading = false}) {
    const issue = MicroscopeUploadIssue(
      title: 'Connection interrupted',
      message: 'The connection was lost while uploading TIFF.',
      recommendedAction:
          'Check the connection and choose Resume. Completed parts are safely retained.',
      source: MicroscopeUploadIssueSource.connection,
      severity: MicroscopeUploadMessageSeverity.warning,
      retryable: true,
      code: 'microscope_upload_connection_interrupted',
      reference: 'Image set 002 • Session 665a5cad',
    );
    state = MicroscopeUploadState(
      uploading: uploading,
      sessionId: '665a5cad-dc73-4d3a-a3cd-63231b1d2a0e',
      expiresAt: DateTime.utc(2026, 8, 21),
      issue: issue,
      error: '${issue.message} ${issue.recommendedAction}',
      sets: const [
        MicroscopeFileSet(
          clientSetId: 'local-002',
          logicalBaseName: '002',
          canonicalBaseName: '002',
          normalizedMatchKey: '002',
          files: {
            MicroscopeFileRole.tiff: MicroscopeLocalFile(
              path: '/tmp/002.tif',
              name: '002.tif',
              sizeBytes: 83943688,
            ),
            MicroscopeFileRole.txt: MicroscopeLocalFile(
              path: '/tmp/002.txt',
              name: '002.txt',
              sizeBytes: 1615,
            ),
          },
          uploadProgress: 0.6,
          uploadError:
              'The connection was lost. Completed parts are safely retained.',
          issue: issue,
          activity: MicroscopeUploadActivity(
            phase: MicroscopeUploadPhase.retrying,
            role: MicroscopeFileRole.tiff,
            completedBytes: 48 * 1024 * 1024,
            totalBytes: 83943688,
            currentPart: 7,
            totalParts: 11,
            savedParts: 6,
            retryNumber: 2,
            maxRetries: 3,
          ),
        ),
      ],
    );
  }

  var pauseCalls = 0;
  var cancelCalls = 0;

  @override
  Future<void> pause() async {
    pauseCalls++;
    state = state.copyWith(uploading: false);
  }

  @override
  Future<bool> cancel() async {
    cancelCalls++;
    return true;
  }
}

class _LongNameNotifier extends MicroscopeUploadNotifier {
  _LongNameNotifier(super.ref, super.args) {
    final stem = 'Campaign-operator-scan-${List.filled(180, 'x').join()}-001';
    state = MicroscopeUploadState(
      sets: [
        MicroscopeFileSet(
          clientSetId: 'long-set',
          logicalBaseName: stem,
          canonicalBaseName: stem,
          normalizedMatchKey: stem,
          files: {
            MicroscopeFileRole.tiff: MicroscopeLocalFile(
              path: '/tmp/$stem.tif',
              name: '$stem.tif',
              sizeBytes: 10,
            ),
            MicroscopeFileRole.txt: MicroscopeLocalFile(
              path: '/tmp/$stem.txt',
              name: '$stem.txt',
              sizeBytes: 10,
            ),
          },
        ),
      ],
    );
  }
}

class _CompletedNotifier extends MicroscopeUploadNotifier {
  _CompletedNotifier(super.ref, super.args) {
    const tiff = MicroscopeLocalFile(
      path: '/tmp/001.tif',
      name: '001.tif',
      sizeBytes: 10,
    );
    const txt = MicroscopeLocalFile(
      path: '/tmp/001.txt',
      name: '001.txt',
      sizeBytes: 10,
    );
    state = const MicroscopeUploadState(
      sessionId: 'completed-session',
      sets: [
        MicroscopeFileSet(
          clientSetId: 'set-001',
          logicalBaseName: '001',
          canonicalBaseName: '001',
          normalizedMatchKey: '001',
          files: {MicroscopeFileRole.tiff: tiff, MicroscopeFileRole.txt: txt},
          uploaded: true,
          imageId: 'image-001',
        ),
      ],
    );
  }
}

void main() {
  testWidgets('explains naming and groups many selected files into rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          microscopeFileSourceProvider.overrideWithValue(_SelectedFiles()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MicroscopeUploadDialog(
              args: MicroscopeUploadArgs(
                batchId: 'batch-1',
                bagId: 'bag-1',
                editStateVersion: 2,
                contentRevision: 7,
              ),
              bagNumber: 12,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add microscope files to Bag 12'), findsOneWidget);
    expect(
      find.text('Each set must have the same logical base name:'),
      findsOneWidget,
    );
    expect(find.text('Sample-001.tif\nSample-001.txt'), findsOneWidget);
    expect(find.textContaining('JEOL'), findsNothing);

    await tester.tap(find.text('Select files'));
    await tester.pumpAndSettle();

    expect(find.text('2 sets'), findsOneWidget);
    expect(find.text('1 ready'), findsOneWidget);
    expect(find.text('1 incomplete'), findsOneWidget);
    expect(find.text('Sample-001'), findsOneWidget);
    expect(find.text('Sample-002'), findsOneWidget);
    expect(find.text('TXT missing'), findsOneWidget);
    expect(find.text('Upload 1 ready set'), findsOneWidget);
  });

  testWidgets('shows an explicit terminal success state with Done', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          microscopeUploadProvider.overrideWith(
            (ref, args) => _CompletedNotifier(ref, args),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MicroscopeUploadDialog(
              args: MicroscopeUploadArgs(
                batchId: 'batch-1',
                bagId: 'bag-1',
                editStateVersion: 2,
                contentRevision: 7,
              ),
              bagNumber: 79,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Upload complete — 1 image added to Bag 79 and queued for analysis.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
    expect(find.text('Cancel session'), findsNothing);
    expect(find.text('Add files'), findsNothing);
    expect(find.textContaining('Upload 0 ready'), findsNothing);
  });

  testWidgets('reflows long names at 200 percent text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          microscopeUploadProvider.overrideWith(
            (ref, args) => _LongNameNotifier(ref, args),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: MicroscopeUploadDialog(
              args: MicroscopeUploadArgs(
                batchId: 'batch-1',
                bagId: 'bag-1',
                editStateVersion: 2,
                contentRevision: 7,
              ),
              bagNumber: 120,
              destinationLabel: 'Campaign PO772 › Sublot A › Bag 120',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('microscope-upload-set-list')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Campaign-operator-scan-'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('communicates destination, phase, retry, and safe next action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          microscopeUploadProvider.overrideWith(
            (ref, args) => _CommunicationNotifier(ref, args),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MicroscopeUploadDialog(
              args: MicroscopeUploadArgs(
                batchId: 'batch-1',
                bagId: 'bag-1',
                editStateVersion: 2,
                contentRevision: 7,
              ),
              bagNumber: 120,
              destinationLabel: 'Campaign PO772 › Sublot A › Bag 120',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Campaign PO772 › Sublot A › Bag 120'), findsOneWidget);
    expect(find.textContaining('Files stay in this Bag'), findsOneWidget);
    expect(find.text('Connection interrupted'), findsOneWidget);
    expect(find.textContaining('choose Resume'), findsWidgets);
    expect(find.text('Image set 002 • Session 665a5cad'), findsOneWidget);
    expect(find.text('Connection interrupted — retrying TIFF'), findsOneWidget);
    expect(find.textContaining('Retry 2 of 3'), findsOneWidget);
    expect(
      find.textContaining('6 completed parts remain safely stored'),
      findsOneWidget,
    );
    expect(find.text('Resume 1 failed set'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('002.*retrying TIFF.*60%')),
      findsOneWidget,
    );
  });

  testWidgets('pause and close-for-now preserve unfinished server work', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late _CommunicationNotifier notifier;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          microscopeUploadProvider.overrideWith((ref, args) {
            notifier = _CommunicationNotifier(ref, args, uploading: true);
            return notifier;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MicroscopeUploadDialog(
              args: MicroscopeUploadArgs(
                batchId: 'batch-1',
                bagId: 'bag-1',
                editStateVersion: 2,
                contentRevision: 7,
              ),
              bagNumber: 120,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Pause safely'));
    await tester.pumpAndSettle();
    expect(notifier.pauseCalls, 1);
    expect(find.text('Close for now'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Close and continue later?'), findsOneWidget);
    await tester.tap(find.text('Keep upload open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close for now'));
    await tester.pumpAndSettle();
    expect(find.text('Close and continue later?'), findsOneWidget);
    expect(
      find.textContaining('No uploaded part will be discarded'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Close for now'));
    await tester.pumpAndSettle();
    expect(notifier.cancelCalls, 0);
  });

  testWidgets('discard is separate, destructive, and confirmed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late _CommunicationNotifier notifier;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          microscopeUploadProvider.overrideWith((ref, args) {
            notifier = _CommunicationNotifier(ref, args);
            return notifier;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MicroscopeUploadDialog(
              args: MicroscopeUploadArgs(
                batchId: 'batch-1',
                bagId: 'bag-1',
                editStateVersion: 2,
                contentRevision: 7,
              ),
              bagNumber: 120,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Discard unfinished upload'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unfinished upload?'), findsOneWidget);
    expect(find.textContaining('registered Images'), findsOneWidget);
    expect(notifier.cancelCalls, 0);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Discard unfinished parts'),
    );
    await tester.pumpAndSettle();
    expect(notifier.cancelCalls, 1);
  });

  testWidgets('requires confirmation before discarding a previous session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late _RecoveryNotifier notifier;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          microscopeUploadProvider.overrideWith((ref, args) {
            notifier = _RecoveryNotifier(ref, args);
            return notifier;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MicroscopeUploadDialog(
              args: MicroscopeUploadArgs(
                batchId: 'batch-1',
                bagId: 'bag-1',
                editStateVersion: 2,
                contentRevision: 7,
              ),
              bagNumber: 12,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Discard previous upload and retry'), findsOneWidget);
    await tester.tap(find.text('Discard previous upload and retry'));
    await tester.pumpAndSettle();

    expect(find.text('Discard previous unfinished upload?'), findsOneWidget);
    expect(find.textContaining('all unfinished sets'), findsOneWidget);
    expect(notifier.discardCalls, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Discard and retry'));
    await tester.pumpAndSettle();
    expect(notifier.discardCalls, 1);
  });
}
