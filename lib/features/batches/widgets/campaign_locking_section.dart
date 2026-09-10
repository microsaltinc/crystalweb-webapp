import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/user_facing_error.dart';
import '../models/batch.dart';
import '../models/campaign_locking.dart';
import '../providers/campaign_locking_provider.dart';
import 'campaign_edit_state_chip.dart';

class CampaignLockingSection extends ConsumerStatefulWidget {
  const CampaignLockingSection({super.key, required this.batch});
  final Batch batch;

  @override
  ConsumerState<CampaignLockingSection> createState() =>
      _CampaignLockingSectionState();
}

class _CampaignLockingSectionState
    extends ConsumerState<CampaignLockingSection> {
  bool _submitting = false;

  Future<void> _lock() async {
    ref.invalidate(campaignLockReadinessProvider(widget.batch.id));
    CampaignLockReadiness readiness;
    try {
      readiness = await ref.read(
        campaignLockReadinessProvider(widget.batch.id).future,
      );
    } catch (error) {
      _message(userFacingError(error, action: 'check lock readiness'));
      return;
    }
    if (!mounted) return;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lock campaign?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                readiness.ready
                    ? 'The campaign is ready. Locking makes campaign content read-only.'
                    : 'The campaign cannot be locked until every blocker is resolved.',
              ),
              if (readiness.blockers.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...readiness.blockers.map(
                  (blocker) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.error_outline),
                    title: Text(blocker.message),
                    subtitle: Text('${blocker.category} · ${blocker.count}'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Consequences: annotations, review changes, metadata, assignments, and new reports are disabled until Unlock.',
              ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: readiness.ready
                ? () => Navigator.pop(context, true)
                : null,
            child: const Text('Lock'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _transition(
      lock: true,
      reason: reason.text,
      expectedEditStateVersion: readiness.editStateVersion,
    );
  }

  Future<void> _unlock() async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlock campaign?'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _transition(
        lock: false,
        reason: reason.text,
        expectedEditStateVersion: widget.batch.editStateVersion,
      );
    }
  }

  Future<void> _transition({
    required bool lock,
    required String reason,
    required int expectedEditStateVersion,
  }) async {
    setState(() => _submitting = true);
    try {
      final actions = ref.read(campaignLockingActionsProvider);
      final result = lock
          ? await actions.lock(
              widget.batch.id,
              expectedEditStateVersion: expectedEditStateVersion,
              reason: reason,
            )
          : await actions.unlock(
              widget.batch.id,
              expectedEditStateVersion: expectedEditStateVersion,
              reason: reason,
            );
      _message(
        result.changed
            ? 'Campaign ${lock ? 'locked' : 'unlocked'}.'
            : 'Campaign was already ${lock ? 'locked' : 'editable'}.',
      );
    } catch (error) {
      ref.invalidate(campaignLockReadinessProvider(widget.batch.id));
      final structured = ApiError.tryParse(error);
      String? lockTimeBlockers;
      final rawReadiness = structured?.details['readiness'];
      if (lock &&
          structured?.code == 'campaign_not_ready' &&
          rawReadiness is Map) {
        final latest = CampaignLockReadiness.fromJson(
          Map<String, dynamic>.from(rawReadiness),
        );
        if (latest.blockers.isNotEmpty) {
          lockTimeBlockers = latest.blockers
              .map((blocker) => blocker.message)
              .join(' · ');
        }
      }
      _message(
        lockTimeBlockers == null
            ? userFacingError(
                error,
                action: lock ? 'lock campaign' : 'unlock campaign',
              )
            : 'The campaign changed before Lock. $lockTimeBlockers',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;
    final actor =
        batch.editStateChangedByOperatorName ??
        batch.editStateChangedBySessionEmail;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Campaign editing',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                CampaignEditStateChip(batch: batch),
              ],
            ),
            if (batch.editStateChangedAt != null)
              Text(
                '${batch.isLocked ? 'Locked' : 'Unlocked'} ${DateFormat.yMMMd().add_jm().format(batch.editStateChangedAt!.toLocal())}${actor == null ? '' : ' by $actor'}',
              ),
            if (batch.editStateChangeReason?.isNotEmpty == true)
              Text('Reason: ${batch.editStateChangeReason}'),
            const SizedBox(height: 8),
            Text(
              batch.isLocked
                  ? 'Campaign content is read-only. Viewing, downloads, comments, and Unlock remain available.'
                  : 'Check readiness to review every blocker before locking.',
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: Key(batch.isLocked ? 'unlock-campaign' : 'lock-campaign'),
                onPressed: _submitting
                    ? null
                    : (batch.isLocked ? _unlock : _lock),
                icon: Icon(batch.isLocked ? Icons.lock_open : Icons.lock),
                label: Text(
                  batch.isLocked ? 'Unlock' : 'Check readiness & Lock',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
