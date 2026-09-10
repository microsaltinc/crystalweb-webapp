import 'package:flutter/material.dart';

import '../models/batch.dart';

class CampaignOwnerChip extends StatelessWidget {
  const CampaignOwnerChip({
    super.key,
    required this.batch,
    this.compact = false,
  });

  final Batch batch;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnassigned = !batch.hasOwner;
    final label = batch.ownerDisplayWithStatus;
    final color = isUnassigned
        ? theme.colorScheme.outline
        : batch.ownerInactive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    final background = isUnassigned
        ? theme.colorScheme.surfaceContainerHighest
        : color.withValues(alpha: 0.12);

    return Semantics(
      label: 'Campaign owner: $label',
      child: Chip(
        avatar: Icon(
          isUnassigned ? Icons.person_off_outlined : Icons.assignment_ind,
          size: compact ? 14 : 16,
          color: color,
        ),
        label: Text(
          label,
          style: TextStyle(fontSize: compact ? 11 : 12, color: color),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: background,
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      ),
    );
  }
}
