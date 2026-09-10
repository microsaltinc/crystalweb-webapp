import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/user_facing_error.dart';
import '../models/batch.dart';
import '../models/campaign_locking.dart';
import '../providers/campaign_locking_provider.dart';

typedef RegistrationConflictRetryCallback =
    Future<RegistrationConflictRetry> Function(
      String conflictId,
      int expectedEditStateVersion,
    );

/// Persistent operational surface for legacy registrations preserved while a
/// campaign was locked.
class CampaignRegistrationConflictsSection extends ConsumerStatefulWidget {
  const CampaignRegistrationConflictsSection({
    super.key,
    required this.batch,
    this.retryConflict,
  });

  final Batch batch;
  final RegistrationConflictRetryCallback? retryConflict;

  @override
  ConsumerState<CampaignRegistrationConflictsSection> createState() =>
      _CampaignRegistrationConflictsSectionState();
}

class _CampaignRegistrationConflictsSectionState
    extends ConsumerState<CampaignRegistrationConflictsSection> {
  final Set<String> _retrying = {};
  final Map<String, String> _retryErrors = {};

  Future<void> _retry(RegistrationConflict conflict) async {
    setState(() {
      _retrying.add(conflict.id);
      _retryErrors.remove(conflict.id);
    });
    try {
      String? selectedBagId;
      if (conflict.reasonCode == 'structure_mapping_ambiguous') {
        selectedBagId = await showDialog<String>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: const Text('Select the stable Bag'),
            children: [
              for (final candidate in conflict.structureCandidates)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    candidate['bag_id'] as String?,
                  ),
                  child: Text(
                    'Sublot ${candidate['sublot_identifier'] ?? candidate['sublot_id']} · '
                    'Bag ${candidate['bag_number'] ?? ''}'
                    '${candidate['archived'] == true ? ' (Archived)' : ''}',
                  ),
                ),
            ],
          ),
        );
        if (selectedBagId == null) return;
      }
      final callback = widget.retryConflict;
      final result = callback != null
          ? await callback(conflict.id, widget.batch.editStateVersion)
          : await ref
                .read(campaignLockingActionsProvider)
                .retryConflict(
                  widget.batch.id,
                  conflict.id,
                  expectedEditStateVersion: widget.batch.editStateVersion,
                  expectedContentRevision:
                      conflict.reasonCode == 'structure_mapping_ambiguous'
                      ? widget.batch.contentRevision
                      : null,
                  selectedBagId: selectedBagId,
                );
      if (!mounted) return;
      if (result.resolved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration conflict resolved.')),
        );
      } else {
        setState(() {
          _retryErrors[conflict.id] =
              'The preserved upload is still unresolved. Refresh and try again.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      final message = userFacingError(error, action: 'retry registration');
      setState(() => _retryErrors[conflict.id] = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      ref.invalidate(registrationConflictsProvider(widget.batch.id));
      if (mounted) setState(() => _retrying.remove(conflict.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final conflictsAsync = ref.watch(
      registrationConflictsProvider(widget.batch.id),
    );
    final conflicts = conflictsAsync.valueOrNull;

    // The initial request has no conflict evidence yet. Keep the operational warning hidden
    // until the server returns actual conflicts or an actionable load error.
    if ((conflicts == null && conflictsAsync.isLoading) ||
        (conflicts != null && conflicts.isEmpty && !conflictsAsync.hasError)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Card(
      key: const Key('registration-conflicts-section'),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Preserved upload conflicts',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                if (conflicts != null)
                  Badge(label: Text('${conflicts.length}')),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'These uploads were preserved without changing the campaign. '
              'Unlock the campaign before retrying them.',
            ),
            if (conflicts == null && conflictsAsync.isLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (conflictsAsync.hasError) ...[
              const SizedBox(height: 12),
              Text(
                userFacingError(
                  conflictsAsync.error!,
                  action: 'load registration conflicts',
                ),
                key: const Key('registration-conflicts-load-error'),
              ),
              TextButton.icon(
                onPressed: () => ref.invalidate(
                  registrationConflictsProvider(widget.batch.id),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry loading'),
              ),
            ],
            if (conflicts != null)
              for (final conflict in conflicts) ...[
                const Divider(height: 24),
                _ConflictDetails(
                  conflict: conflict,
                  editable: !widget.batch.isLocked,
                  retrying: _retrying.contains(conflict.id),
                  retryError: _retryErrors[conflict.id],
                  onRetry: () => _retry(conflict),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _ConflictDetails extends StatelessWidget {
  const _ConflictDetails({
    required this.conflict,
    required this.editable,
    required this.retrying,
    required this.retryError,
    required this.onRetry,
  });

  final RegistrationConflict conflict;
  final bool editable;
  final bool retrying;
  final String? retryError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final detected = conflict.firstDetectedAt == null
        ? 'Detection time unavailable'
        : 'Detected ${DateFormat.yMMMd().add_jm().format(conflict.firstDetectedAt!.toLocal())}';
    final version = conflict.object.versionOrEtag;
    final canRetry = editable && conflict.canRetry && !retrying;
    return Semantics(
      label: 'Unresolved preserved upload ${conflict.object.key}',
      child: Column(
        key: Key('registration-conflict-${conflict.id}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            '${conflict.object.bucket}/${conflict.object.key}',
            key: Key('registration-conflict-object-${conflict.id}'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (version != null && version.isNotEmpty)
            Text('Object version: $version'),
          Text(detected),
          Text(conflict.safeReason),
          if (conflict.occurrenceCount > 1)
            Text('Observed ${conflict.occurrenceCount} times'),
          if (!editable)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Retry is available after this campaign is unlocked.',
              ),
            ),
          if (retryError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                retryError!,
                key: Key('registration-conflict-error-${conflict.id}'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: Key('retry-registration-conflict-${conflict.id}'),
              onPressed: canRetry ? onRetry : null,
              icon: retrying
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(retrying ? 'Retrying…' : 'Retry'),
            ),
          ),
        ],
      ),
    );
  }
}
