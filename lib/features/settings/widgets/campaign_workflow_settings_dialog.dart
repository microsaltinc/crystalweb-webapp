import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/user_facing_error.dart';
import '../../batches/models/campaign_workflow_status.dart';
import '../../batches/providers/campaign_workflow_provider.dart';
import '../../batches/widgets/campaign_workflow_status_chip.dart';

class CampaignWorkflowSettingsDialog extends ConsumerWidget {
  const CampaignWorkflowSettingsDialog({super.key});

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    CampaignWorkflowCatalog catalog,
  ) async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add workflow status'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Label'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (label == null) return;
    if (label.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workflow status label is required.')),
        );
      }
      return;
    }
    final duplicate = catalog.statuses.any(
      (status) => status.label.trim().toLowerCase() == label.toLowerCase(),
    );
    if (duplicate) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A workflow status with this label already exists.'),
          ),
        );
      }
      return;
    }
    try {
      await ref
          .read(campaignWorkflowControllerProvider)
          .create(
            label: label,
            color: 'blue',
            expectedCatalogVersion: catalog.version,
          );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(campaignWorkflowErrorMessage(error))),
        );
      }
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    CampaignWorkflowCatalog catalog,
    CampaignWorkflowStatus status,
  ) async {
    final controller = TextEditingController(text: status.label);
    var color = status.color;
    var makeDefault = status.isDefault;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Edit ${status.label}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              DropdownButtonFormField<String>(
                initialValue: color,
                decoration: const InputDecoration(labelText: 'Color'),
                items: CampaignWorkflowStatus.allowedColors
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => color = value ?? color),
              ),
              CheckboxListTile(
                value: makeDefault,
                title: const Text('Default for new campaigns'),
                onChanged: status.isDefault
                    ? null
                    : (value) => setState(() => makeDefault = value ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save != true) return;
    final label = controller.text.trim();
    if (label.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workflow status label is required.')),
        );
      }
      return;
    }
    final duplicate = catalog.statuses.any(
      (item) =>
          item.id != status.id &&
          item.label.trim().toLowerCase() == label.toLowerCase(),
    );
    if (duplicate) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A workflow status with this label already exists.'),
          ),
        );
      }
      return;
    }
    try {
      await ref
          .read(campaignWorkflowControllerProvider)
          .update(
            statusId: status.id,
            expectedCatalogVersion: catalog.version,
            label: label,
            color: color,
            isDefault: makeDefault && !status.isDefault ? true : null,
          );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(campaignWorkflowErrorMessage(error))),
        );
      }
    }
  }

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    CampaignWorkflowCatalog catalog,
    int index,
    int delta,
  ) async {
    final ids = catalog.statuses.map((item) => item.id).toList();
    final next = index + delta;
    if (next < 0 || next >= ids.length) return;
    final moved = ids.removeAt(index);
    ids.insert(next, moved);
    try {
      await ref
          .read(campaignWorkflowControllerProvider)
          .reorder(
            orderedStatusIds: ids,
            expectedCatalogVersion: catalog.version,
          );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(campaignWorkflowErrorMessage(error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(campaignWorkflowCatalogProvider);
    return AlertDialog(
      title: const Text('Campaign Workflow'),
      content: SizedBox(
        width: 600,
        child: catalog.when(
          data: (value) => ListView(
            shrinkWrap: true,
            children: value.statuses.asMap().entries.map((entry) {
              final index = entry.key;
              final status = entry.value;
              return Semantics(
                label:
                    '${status.label}, ${status.color}, position ${index + 1}, used by ${status.usageCount} campaigns${status.isDefault ? ', default' : ''}',
                child: ListTile(
                  leading: const Icon(Icons.drag_handle),
                  title: Align(
                    alignment: Alignment.centerLeft,
                    child: CampaignWorkflowStatusChip(
                      label: status.label,
                      colorToken: status.color,
                    ),
                  ),
                  subtitle: Text(
                    '${status.usageCount} campaigns${status.isDefault ? ' • Default' : ''}',
                  ),
                  onTap: () => _edit(context, ref, value, status),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Move up',
                        onPressed: index > 0
                            ? () => _move(context, ref, value, index, -1)
                            : null,
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: 'Move down',
                        onPressed: index < value.statuses.length - 1
                            ? () => _move(context, ref, value, index, 1)
                            : null,
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      IconButton(
                        tooltip:
                            status.deleteBlocker ?? 'Delete ${status.label}',
                        onPressed: status.canDelete
                            ? () async {
                                try {
                                  await ref
                                      .read(campaignWorkflowControllerProvider)
                                      .delete(
                                        statusId: status.id,
                                        expectedCatalogVersion: value.version,
                                      );
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          campaignWorkflowErrorMessage(error),
                                        ),
                                      ),
                                    );
                                  }
                                }
                              }
                            : null,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text(
              userFacingError(error, action: 'load workflow statuses'),
            ),
          ),
        ),
      ),
      actions: [
        if (catalog.hasValue)
          TextButton.icon(
            onPressed: () => _add(context, ref, catalog.requireValue),
            icon: const Icon(Icons.add),
            label: const Text('Add status'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
