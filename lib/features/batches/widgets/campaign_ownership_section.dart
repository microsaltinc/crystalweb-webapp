import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/user_facing_error.dart';
import '../../../core/auth/auth_provider.dart';
import '../models/batch.dart';
import '../providers/campaign_collaboration_provider.dart';
import 'campaign_owner_chip.dart';
import 'transfer_owner_dialog.dart';

class CampaignOwnershipSection extends ConsumerStatefulWidget {
  const CampaignOwnershipSection({super.key, required this.batch});

  final Batch batch;

  @override
  ConsumerState<CampaignOwnershipSection> createState() =>
      _CampaignOwnershipSectionState();
}

class _CampaignOwnershipSectionState
    extends ConsumerState<CampaignOwnershipSection> {
  bool _pending = false;
  String? _error;

  Future<void> _run(Future<void> Function() action, String actionLabel) async {
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _error = userFacingError(error, action: actionLabel));
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;
    final activeOperator = ref.watch(authStateProvider).activeOperator;
    final canAssign = activeOperator != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Ownership',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 12),
                CampaignOwnerChip(batch: batch),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              batch.hasOwner
                  ? 'Primary responsibility is assigned to this operator.'
                  : 'This campaign is Unassigned.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canAssign)
                  ElevatedButton.icon(
                    onPressed: _pending
                        ? null
                        : () async {
                            final target = await CampaignAssignmentDialog.show(
                              context,
                              batchId: batch.id,
                              currentOwnerId: batch.ownerOperatorId,
                            );
                            if (target == null || !context.mounted) return;
                            if (batch.hasOwner) {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Confirm reassignment'),
                                  content: Text(
                                    'Reassign from ${batch.ownerOperatorName ?? 'Unknown owner'} '
                                    'to ${target.name}?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('Reassign'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true || !context.mounted) return;
                            }
                            await _run(
                              () => assignCampaign(
                                ref,
                                batch.id,
                                targetOperatorId: target.id,
                                expectedOwnershipVersion:
                                    batch.ownershipVersion,
                              ),
                              batch.hasOwner
                                  ? 'reassign campaign'
                                  : 'assign campaign',
                            );
                          },
                    icon: Icon(
                      batch.hasOwner
                          ? Icons.swap_horiz
                          : Icons.assignment_ind,
                    ),
                    label: Text(batch.hasOwner ? 'Reassign' : 'Assign'),
                  ),
                if (_pending)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
