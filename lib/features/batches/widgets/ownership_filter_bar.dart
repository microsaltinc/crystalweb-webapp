import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../operators/providers/operator_provider.dart';
import '../providers/campaign_ownership_filter_provider.dart';

class OwnershipFilterBar extends ConsumerWidget {
  const OwnershipFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operators = ref.watch(operatorListProvider).valueOrNull ?? [];
    final filter = ref.watch(campaignOwnershipFilterProvider);
    final activeOperators = operators
        .where((operator) => operator.active)
        .toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(
          Icons.assignment_ind,
          size: 18,
          color: Theme.of(context).colorScheme.outline,
        ),
        ChoiceChip(
          label: const Text('All'),
          selected: filter.kind == OwnershipFilterKind.all,
          onSelected: (_) =>
              ref.read(campaignOwnershipFilterProvider.notifier).state =
                  const OwnershipFilter.all(),
        ),
        ChoiceChip(
          label: const Text('Mine'),
          selected: filter.kind == OwnershipFilterKind.mine,
          onSelected: (_) =>
              ref.read(campaignOwnershipFilterProvider.notifier).state =
                  const OwnershipFilter.mine(),
        ),
        ChoiceChip(
          label: const Text('Unassigned'),
          selected: filter.kind == OwnershipFilterKind.unassigned,
          onSelected: (_) =>
              ref.read(campaignOwnershipFilterProvider.notifier).state =
                  const OwnershipFilter.unassigned(),
        ),
        PopupMenuButton<String>(
          tooltip: 'Filter by owner',
          onSelected: (id) =>
              ref.read(campaignOwnershipFilterProvider.notifier).state =
                  OwnershipFilter.specificOwner(id),
          itemBuilder: (context) => [
            for (final operator in activeOperators)
              PopupMenuItem(
                value: operator.id,
                child: Text(operator.ownershipLabel),
              ),
          ],
          child: InputChip(
            avatar: const Icon(Icons.people_outline, size: 16),
            label: Text(
              filter.kind == OwnershipFilterKind.specificOwner
                  ? filter.label(operators)
                  : 'Owner',
            ),
            selected: filter.kind == OwnershipFilterKind.specificOwner,
            onPressed: null,
          ),
        ),
      ],
    );
  }
}
