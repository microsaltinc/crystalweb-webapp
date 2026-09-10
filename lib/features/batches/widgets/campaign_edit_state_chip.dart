import 'package:flutter/material.dart';

import '../models/batch.dart';

/// Accessible campaign edit-state indicator shared by production and R&D.
class CampaignEditStateChip extends StatelessWidget {
  const CampaignEditStateChip({super.key, required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final locked = batch.isLocked;
    final theme = Theme.of(context);
    final label = locked ? 'Locked' : 'Editable';
    final color = locked ? theme.colorScheme.error : theme.colorScheme.primary;
    return Semantics(
      label: 'Campaign edit state: $label',
      readOnly: locked,
      child: Chip(
        key: Key('campaign-edit-state-${batch.id}'),
        avatar: Icon(locked ? Icons.lock : Icons.edit, size: 16, color: color),
        label: Text(label),
        side: BorderSide(color: color),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class CampaignConflictWarning extends StatelessWidget {
  const CampaignConflictWarning({super.key, required this.batch});
  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final count = batch.unresolvedRegistrationConflictCount;
    if (count == 0) return const SizedBox.shrink();
    return Semantics(
      label:
          '$count unresolved registration ${count == 1 ? 'conflict' : 'conflicts'}',
      child: Tooltip(
        message:
            '$count unresolved registration ${count == 1 ? 'conflict' : 'conflicts'}',
        child: Badge(
          label: Text('$count'),
          child: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    );
  }
}
