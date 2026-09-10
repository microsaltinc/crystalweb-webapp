import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/campaign_workflow_filter_provider.dart';
import '../providers/campaign_workflow_provider.dart';
import 'campaign_workflow_status_chip.dart';

class CampaignWorkflowFilterBar extends ConsumerWidget {
  const CampaignWorkflowFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(campaignWorkflowCatalogProvider);
    final selectedId = ref.watch(campaignWorkflowFilterProvider);
    return catalog.when(
      data: (value) {
        final selected = value.statuses
            .where((status) => status.id == selectedId)
            .firstOrNull;
        return Semantics(
          container: true,
          label: selected == null
              ? 'Workflow status filter, all statuses'
              : 'Workflow status filter, ${selected.label}',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                key: const Key('workflow-status-filter'),
                tooltip: 'Filter by workflow status',
                icon: selected == null
                    ? const Icon(Icons.flag_outlined)
                    : CampaignWorkflowStatusChip(
                        label: selected.label,
                        colorToken: selected.color,
                      ),
                onSelected: (id) =>
                    ref.read(campaignWorkflowFilterProvider.notifier).state =
                        id,
                itemBuilder: (context) => value.statuses
                    .map(
                      (status) => PopupMenuItem<String>(
                        value: status.id,
                        child: Row(
                          children: [
                            CampaignWorkflowStatusChip(
                              label: status.label,
                              colorToken: status.color,
                            ),
                            if (selectedId == status.id) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.check, size: 18),
                            ],
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
              if (selected != null)
                IconButton(
                  key: const Key('clear-workflow-status-filter'),
                  tooltip: 'Clear workflow status filter',
                  onPressed: () =>
                      ref.read(campaignWorkflowFilterProvider.notifier).state =
                          null,
                  icon: const Icon(Icons.clear),
                ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => IconButton(
        tooltip: 'Retry workflow statuses',
        onPressed: () => ref.invalidate(campaignWorkflowCatalogProvider),
        icon: const Icon(Icons.refresh),
      ),
    );
  }
}
