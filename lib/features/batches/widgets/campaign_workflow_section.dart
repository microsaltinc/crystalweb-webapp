import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/batch.dart';
import '../providers/campaign_lock_coordinator.dart';
import '../providers/campaign_workflow_provider.dart';
import 'campaign_workflow_status_chip.dart';
import 'workflow_status_picker_dialog.dart';

class CampaignWorkflowSection extends ConsumerWidget {
  const CampaignWorkflowSection({super.key, required this.batch});
  final Batch batch;

  Future<void> _change(BuildContext context, WidgetRef ref) async {
    final catalog = await ref.read(campaignWorkflowCatalogProvider.future);
    if (!context.mounted) return;
    final target = await showWorkflowStatusPicker(context, catalog.statuses);
    if (target == null ||
        target.id == batch.workflowStatusId ||
        !context.mounted) {
      return;
    }
    try {
      bool lockAfter = false;
      if (target.key == 'done') {
        final choice = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Campaign complete'),
            content: const Text(
              'Since you are done with this campaign, do you want to lock it so it cannot be edited?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not Now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Lock'),
              ),
            ],
          ),
        );
        if (choice == null || !context.mounted) return;
        lockAfter = choice;
      }
      final updated = await transitionCampaignWorkflowStatus(
        ref,
        batchId: batch.id,
        workflowStatusId: target.id,
        expectedEditStateVersion: batch.editStateVersion,
      );
      if (!lockAfter || updated.workflowStatusKey != 'done') return;
      final result = await ref
          .read(campaignLockCoordinatorProvider)
          .lockCampaignIfReady(batch.id);
      if (!context.mounted) return;
      final message = switch (result) {
        CampaignLockSuccess() => 'Campaign locked.',
        CampaignLockBlocked(:final blockers) =>
          'Done saved. Cannot lock: ${blockers.join(', ')}',
        CampaignLockUnavailable() =>
          'Done saved. Campaign locking is not available yet.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(campaignWorkflowErrorMessage(error))),
        );
        ref.invalidate(campaignWorkflowCatalogProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    runSpacing: 4,
    children: [
      const Text('Workflow: '),
      CampaignWorkflowStatusChip(
        label: batch.workflowStatusLabel,
        colorToken: batch.workflowStatusColor,
      ),
      OutlinedButton(
        onPressed: batch.isLocked ? null : () => _change(context, ref),
        child: const Text('Change'),
      ),
    ],
  );
}
