import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/microscope_file_set.dart';
import '../models/microscope_upload_feedback.dart';
import '../providers/microscope_upload_provider.dart';

Future<void> showMicroscopeUploadDialog(
  BuildContext context, {
  required String batchId,
  required String bagId,
  required int bagNumber,
  String? destinationLabel,
  required int editStateVersion,
  required int contentRevision,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => MicroscopeUploadDialog(
    args: MicroscopeUploadArgs(
      batchId: batchId,
      bagId: bagId,
      editStateVersion: editStateVersion,
      contentRevision: contentRevision,
    ),
    bagNumber: bagNumber,
    destinationLabel: destinationLabel,
  ),
);

class MicroscopeUploadDialog extends ConsumerWidget {
  const MicroscopeUploadDialog({
    super.key,
    required this.args,
    required this.bagNumber,
    this.destinationLabel,
  });

  final MicroscopeUploadArgs args;
  final int bagNumber;
  final String? destinationLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(microscopeUploadProvider(args));
    final notifier = ref.read(microscopeUploadProvider(args).notifier);
    final uploadComplete =
        state.sets.isNotEmpty &&
        state.uploadedCount == state.sets.length &&
        !state.uploading;
    final destination = destinationLabel ?? 'Bag $bagNumber';
    return PopScope<Object?>(
      canPop: uploadComplete || (!state.uploading && !state.hasRetainedWork),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (state.uploading) await notifier.pause();
        if (!context.mounted) return;
        if (state.hasRetainedWork) {
          final close = await _confirmCloseForNow(context, state.expiresAt);
          if (!close || !context.mounted) return;
        }
        Navigator.pop(context);
      },
      child: AlertDialog(
        title: Text('Add microscope files to Bag $bagNumber'),
        content: SizedBox(
          width: 820,
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: CustomScrollView(
            key: const ValueKey('microscope-upload-set-list'),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DestinationContext(
                      label: destination,
                      expiresAt: state.expiresAt,
                      sessionId: state.sessionId,
                      hasSession: state.hasRetainedWork,
                    ),
                    const SizedBox(height: 10),
                    const _NamingHelp(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (!uploadComplete) ...[
                          FilledButton.icon(
                            onPressed: state.selecting || state.uploading
                                ? null
                                : notifier.pickFiles,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: Text(
                              state.sets.isEmpty ? 'Select files' : 'Add files',
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(child: _Summary(state: state)),
                        Tooltip(
                          message: 'Filter file sets',
                          child: DropdownButton<MicroscopeUploadFilter>(
                            value: state.filter,
                            onChanged: state.uploading
                                ? null
                                : (value) {
                                    if (value != null) {
                                      notifier.setFilter(value);
                                    }
                                  },
                            items: [
                              for (final filter
                                  in MicroscopeUploadFilter.values)
                                DropdownMenuItem(
                                  value: filter,
                                  child: Text(_filterLabel(filter)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (state.notice != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: _InfoBanner(message: state.notice!),
                      ),
                    ],
                    if (state.issue != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: _IssueBanner(issue: state.issue!),
                      ),
                    ] else if (state.error != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: _InfoBanner(message: state.error!, error: true),
                      ),
                    ],
                    if (state.uploading) ...[
                      const SizedBox(height: 8),
                      _UploadSummary(state: state),
                    ],
                    if (uploadComplete) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          'Upload complete — ${state.uploadedCount} '
                          'image${state.uploadedCount == 1 ? '' : 's'} added to $destination and queued for analysis.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              if (state.visibleSets.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'Select matching TIFF and TXT files to build upload sets.',
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: state.visibleSets.length,
                  itemBuilder: (context, index) => _SetCard(
                    set: state.visibleSets[index],
                    uploading: state.uploading,
                    onRemoveSet: notifier.removeSet,
                    onRemoveFile: notifier.removeFile,
                    onReplaceFile: notifier.replaceFile,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (!uploadComplete && state.uploading)
            OutlinedButton.icon(
              onPressed: notifier.pause,
              icon: const Icon(Icons.pause),
              label: const Text('Pause safely'),
            ),
          if (!uploadComplete && !state.uploading)
            TextButton(
              onPressed: () async {
                if (state.hasRetainedWork) {
                  final close = await _confirmCloseForNow(
                    context,
                    state.expiresAt,
                  );
                  if (!close) return;
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(state.hasRetainedWork ? 'Close for now' : 'Close'),
            ),
          if (!uploadComplete && !state.uploading && state.sessionId != null)
            TextButton.icon(
              onPressed: () async {
                final discard = await _confirmDiscardCurrentUpload(context);
                if (!discard) return;
                final cancelled = await notifier.cancel();
                if (cancelled && context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Discard unfinished upload'),
            ),
          if (!uploadComplete && state.recoverySessionId != null)
            OutlinedButton.icon(
              onPressed: state.uploading
                  ? null
                  : () async {
                      final confirmed = await _confirmDiscardPreviousUpload(
                        context,
                      );
                      if (confirmed) await notifier.discardPreviousAndRetry();
                    },
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Discard previous upload and retry'),
            ),
          if (!uploadComplete)
            FilledButton.icon(
              onPressed: state.actionableCount == 0 || state.uploading
                  ? null
                  : notifier.uploadReady,
              icon: state.uploading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      state.failedCount > 0
                          ? Icons.restart_alt
                          : Icons.cloud_upload_outlined,
                    ),
              label: Text(_primaryActionLabel(state)),
            ),
          if (uploadComplete)
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check),
              label: const Text('Done'),
            ),
        ],
      ),
    );
  }
}

String _primaryActionLabel(MicroscopeUploadState state) {
  if (state.uploading) return 'Working safely…';
  if (state.failedCount > 0) {
    return 'Resume ${state.failedCount} failed set${state.failedCount == 1 ? '' : 's'}';
  }
  if (state.resumeCount > 0) {
    return 'Resume ${state.resumeCount} paused set${state.resumeCount == 1 ? '' : 's'}';
  }
  if (state.queuedCount > 0) {
    return 'Upload next ${state.actionableCount} set${state.actionableCount == 1 ? '' : 's'}';
  }
  return 'Upload ${state.readyCount} ready set${state.readyCount == 1 ? '' : 's'}';
}

class _DestinationContext extends StatelessWidget {
  const _DestinationContext({
    required this.label,
    required this.hasSession,
    this.expiresAt,
    this.sessionId,
  });

  final String label;
  final bool hasSession;
  final DateTime? expiresAt;
  final String? sessionId;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Files stay in this Bag. CrystalApp will not move them when another operator or Campaign is active.',
                ),
                if (hasSession && expiresAt != null)
                  Text(
                    'Unfinished verified parts are retained until ${_formatExpiry(expiresAt!)}.',
                  ),
                if (sessionId != null)
                  Text(
                    'Safe reference: Session ${_shortReference(sessionId!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(error ? Icons.error_outline : Icons.info_outline),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

class _IssueBanner extends StatelessWidget {
  const _IssueBanner({required this.issue});

  final MicroscopeUploadIssue issue;

  @override
  Widget build(BuildContext context) {
    final isError = issue.severity == MicroscopeUploadMessageSeverity.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isError
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(isError ? Icons.error_outline : Icons.warning_amber_rounded),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    issue.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  Text(issue.message),
                  const SizedBox(height: 3),
                  Text(
                    issue.recommendedAction,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (issue.reference != null) ...[
                    const SizedBox(height: 3),
                    SelectableText(
                      issue.reference!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortReference(String value) =>
    value.substring(0, value.length < 8 ? value.length : 8);

String _formatExpiry(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

Future<bool> _confirmCloseForNow(
  BuildContext context,
  DateTime? expiresAt,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close and continue later?'),
        content: Text(
          'No uploaded part will be discarded. To continue, reopen this Bag and select the exact same TIFF and TXT files.'
          '${expiresAt == null ? '' : ' Verified parts are retained until ${_formatExpiry(expiresAt)}.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep upload open'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Close for now'),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> _confirmDiscardCurrentUpload(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard unfinished upload?'),
        content: const Text(
          'This permanently removes only unfinished staged parts in this session. Already registered Images and other operators’ uploads are unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep upload'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard unfinished parts'),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> _confirmDiscardPreviousUpload(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard previous unfinished upload?'),
        content: const Text(
          'This discards all unfinished sets in the previous upload session. '
          'Already finalized microscope images are not changed. The currently '
          'selected files will then be retried with their original names.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep previous upload'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard and retry'),
          ),
        ],
      ),
    ) ??
    false;

class _NamingHelp extends StatelessWidget {
  const _NamingHelp();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Padding(
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Each set must have the same logical base name:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 6),
          SelectableText('Sample-001.tif\nSample-001.txt'),
          SizedBox(height: 6),
          Text(
            'Select many files at once. CrystalApp groups matching files into one row per image before anything uploads.',
          ),
        ],
      ),
    ),
  );
}

class _UploadSummary extends StatelessWidget {
  const _UploadSummary({required this.state});

  final MicroscopeUploadState state;

  @override
  Widget build(BuildContext context) {
    int count(MicroscopeUploadPhase phase) =>
        state.sets.where((set) => set.activity.phase == phase).length;
    final facts = <String>[
      if (count(MicroscopeUploadPhase.preparing) > 0)
        '${count(MicroscopeUploadPhase.preparing)} preparing',
      if (count(MicroscopeUploadPhase.recovering) > 0)
        '${count(MicroscopeUploadPhase.recovering)} recovering',
      if (count(MicroscopeUploadPhase.uploading) > 0)
        '${count(MicroscopeUploadPhase.uploading)} uploading',
      if (count(MicroscopeUploadPhase.verifying) > 0)
        '${count(MicroscopeUploadPhase.verifying)} verifying',
      if (count(MicroscopeUploadPhase.registering) > 0)
        '${count(MicroscopeUploadPhase.registering)} registering',
      '${state.uploadedCount} registered',
      if (state.queuedCount > 0) '${state.queuedCount} queued next',
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            const Icon(Icons.sync, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Working on up to 4 sets at a time • ${facts.join(' • ')}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.state});
  final MicroscopeUploadState state;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      Chip(label: Text('${state.sets.length} sets')),
      Chip(label: Text('${state.readyCount} ready')),
      if (state.queuedCount > 0)
        Chip(label: Text('${state.queuedCount} queued next')),
      Chip(label: Text('${state.incompleteCount} incomplete')),
      Chip(label: Text('${state.resumeCount} paused / needs attention')),
      Chip(label: Text('${state.uploadedCount} registered')),
    ],
  );
}

class _SetCard extends StatelessWidget {
  const _SetCard({
    required this.set,
    required this.uploading,
    required this.onRemoveSet,
    required this.onRemoveFile,
    required this.onReplaceFile,
  });

  final MicroscopeFileSet set;
  final bool uploading;
  final void Function(String clientSetId) onRemoveSet;
  final void Function(String clientSetId, String path) onRemoveFile;
  final Future<void> Function(String clientSetId, MicroscopeFileRole role)
  onReplaceFile;

  @override
  Widget build(BuildContext context) {
    final status = _setStatus(set);
    final color = switch (set.selectionStatus) {
      MicroscopeSetSelectionStatus.ready =>
        set.uploadError == null
            ? Colors.green
            : Theme.of(context).colorScheme.error,
      MicroscopeSetSelectionStatus.incomplete => Colors.orange,
      MicroscopeSetSelectionStatus.ambiguous => Theme.of(
        context,
      ).colorScheme.error,
    };
    final percent = (set.uploadProgress * 100).round();
    return Semantics(
      container: true,
      label:
          '${set.logicalBaseName}, ${set.activity.headline}, $percent% complete',
      child: Card(
        key: ValueKey('microscope-set-${set.clientSetId}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      set.logicalBaseName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Icon(Icons.circle, size: 10, color: color),
                  const SizedBox(width: 6),
                  Text(status),
                  IconButton(
                    tooltip: 'Remove set',
                    onPressed: uploading || set.uploaded
                        ? null
                        : () => onRemoveSet(set.clientSetId),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (set.uploadProgress > 0 && !set.uploaded)
                LinearProgressIndicator(
                  value: set.uploadProgress,
                  semanticsLabel:
                      '${set.logicalBaseName} ${set.activity.headline}',
                ),
              if (set.activity.phase != MicroscopeUploadPhase.idle) ...[
                const SizedBox(height: 6),
                Text(
                  set.activity.headline,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(set.activity.detail),
              ],
              if (set.issue != null) ...[
                const SizedBox(height: 4),
                Text(
                  set.issue!.message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                Text(
                  set.issue!.recommendedAction,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ] else if (set.uploadError != null)
                Text(
                  set.uploadError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              for (final issue in set.issues)
                Text(
                  issue,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final role in MicroscopeFileRole.values)
                    _FileSlot(
                      role: role,
                      file: set.files[role],
                      enabled: !uploading && !set.uploaded,
                      onRemove: (file) =>
                          onRemoveFile(set.clientSetId, file.path),
                      onReplace: () => onReplaceFile(set.clientSetId, role),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileSlot extends StatelessWidget {
  const _FileSlot({
    required this.role,
    required this.file,
    required this.enabled,
    required this.onRemove,
    required this.onReplace,
  });

  final MicroscopeFileRole role;
  final MicroscopeLocalFile? file;
  final bool enabled;
  final void Function(MicroscopeLocalFile file) onRemove;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final label = file == null
        ? '${microscopeRoleLabel(role)} missing'
        : '${microscopeRoleLabel(role)}: ${file!.name}';
    return InputChip(
      avatar: Icon(file == null ? Icons.warning_amber : Icons.check, size: 16),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Text(
          label,
          semanticsLabel: label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      tooltip: file == null ? 'Add ${microscopeRoleLabel(role)}' : file!.path,
      onPressed: enabled ? onReplace : null,
      onDeleted: enabled && file != null ? () => onRemove(file!) : null,
      deleteIcon: const Icon(Icons.close, size: 16),
    );
  }
}

String _setStatus(MicroscopeFileSet set) {
  if (set.uploaded) return 'Registered';
  final active = switch (set.activity.phase) {
    MicroscopeUploadPhase.waiting => 'Queued for next batch',
    MicroscopeUploadPhase.preparing => 'Preparing',
    MicroscopeUploadPhase.reserving => 'Reserving',
    MicroscopeUploadPhase.recovering => 'Recovering',
    MicroscopeUploadPhase.uploading => 'Uploading',
    MicroscopeUploadPhase.retrying => 'Retrying',
    MicroscopeUploadPhase.verifying => 'Verifying',
    MicroscopeUploadPhase.registering => 'Registering',
    MicroscopeUploadPhase.queued => 'Queued for analysis',
    MicroscopeUploadPhase.paused => 'Paused',
    MicroscopeUploadPhase.idle => null,
  };
  if (active != null) return active;
  if (set.uploadError != null) return 'Needs attention';
  return switch (set.selectionStatus) {
    MicroscopeSetSelectionStatus.ready => 'Ready',
    MicroscopeSetSelectionStatus.incomplete => 'Incomplete',
    MicroscopeSetSelectionStatus.ambiguous => 'Needs attention',
  };
}

String _filterLabel(MicroscopeUploadFilter filter) => switch (filter) {
  MicroscopeUploadFilter.all => 'All',
  MicroscopeUploadFilter.ready => 'Ready',
  MicroscopeUploadFilter.incomplete => 'Incomplete',
  MicroscopeUploadFilter.failed => 'Failed',
  MicroscopeUploadFilter.uploaded => 'Uploaded',
};
