import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/user_facing_error.dart';
import '../models/campaign_qualification.dart';
import '../providers/campaign_qualification_provider.dart';

class CampaignQualificationSection extends ConsumerWidget {
  const CampaignQualificationSection({
    super.key,
    required this.batchId,
    required this.readOnly,
  });
  final String batchId;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(campaignQualificationProvider(batchId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: state.when(
          loading: () => const LinearProgressIndicator(
            semanticsLabel: 'Loading campaign qualification',
          ),
          error: (error, _) =>
              Text(userFacingError(error, action: 'load qualification')),
          data: (qualification) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Campaign Qualification',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Semantics(
                label:
                    'Campaign disposition ${qualification.campaign.status.label}',
                child: Chip(label: Text(qualification.campaign.status.label)),
              ),
              if (qualification.isLocked || readOnly)
                const Text('Locked — qualification is read-only.'),
              if (qualification.finalizationBlockers.isNotEmpty)
                Text(
                  '${qualification.pendingBagIds.length} Bag decision(s) still pending.',
                ),
              _QualificationSublotList(
                batchId: batchId,
                qualification: qualification,
                readOnly: readOnly,
              ),
              if (!readOnly && !qualification.isLocked)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final status in qualification.canFinalizeAs)
                      FilledButton.tonal(
                        onPressed: () =>
                            status == CampaignQualificationStatus.rejected
                            ? _rejectCampaign(context, ref, qualification)
                            : _finalize(context, ref, qualification, status),
                        child: Text(
                          status == CampaignQualificationStatus.rejected
                              ? 'Reject Campaign'
                              : 'Finalize ${status.label}',
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _finalize(
    BuildContext context,
    WidgetRef ref,
    CampaignQualification qualification,
    CampaignQualificationStatus status,
  ) async {
    try {
      await ref
          .read(campaignQualificationActionsProvider)
          .finalizeCampaign(
            batchId,
            status: status,
            editStateVersion: qualification.editStateVersion,
            contentRevision: qualification.contentRevision,
          );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(error, action: 'finalize qualification'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _rejectCampaign(
    BuildContext context,
    WidgetRef ref,
    CampaignQualification qualification,
  ) async {
    var selected = QualificationReason.values.first;
    var busy = false;
    String? submitError;
    final notes = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Reject Campaign'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<QualificationReason>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: [
                  for (final reason in QualificationReason.values)
                    DropdownMenuItem(value: reason, child: Text(reason.label)),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => selected = value!),
              ),
              if (selected.key == 'other')
                TextField(
                  controller: notes,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Notes required for Other',
                  ),
                ),
              if (submitError != null)
                Text(
                  submitError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (selected.key == 'other' &&
                          notes.text.trim().isEmpty) {
                        setState(
                          () => submitError = 'Notes are required for Other.',
                        );
                        return;
                      }
                      setState(() {
                        busy = true;
                        submitError = null;
                      });
                      try {
                        await ref
                            .read(campaignQualificationActionsProvider)
                            .finalizeCampaign(
                              batchId,
                              status: CampaignQualificationStatus.rejected,
                              editStateVersion: qualification.editStateVersion,
                              contentRevision: qualification.contentRevision,
                              reasonCode: selected.key,
                              notes: notes.text,
                            );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setState(() {
                            busy = false;
                            submitError = userFacingError(
                              error,
                              action: 'reject campaign',
                            );
                          });
                        }
                      }
                    },
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Reject Campaign'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => notes.dispose());
  }
}

class _QualificationSublotList extends ConsumerStatefulWidget {
  const _QualificationSublotList({
    required this.batchId,
    required this.qualification,
    required this.readOnly,
  });

  final String batchId;
  final CampaignQualification qualification;
  final bool readOnly;

  @override
  ConsumerState<_QualificationSublotList> createState() =>
      _QualificationSublotListState();
}

class _QualificationSublotListState
    extends ConsumerState<_QualificationSublotList> {
  final Set<String> _expandedSublotIds = {};
  final Set<String> _busySublotIds = {};

  @override
  Widget build(BuildContext context) {
    final bagsBySublot = <String, List<BagQualification>>{};
    for (final bag in widget.qualification.allBags) {
      bagsBySublot.putIfAbsent(bag.sublotId, () => []).add(bag);
    }
    final groups = bagsBySublot.entries.toList()
      ..sort((left, right) {
        final identifierComparison = left.value.first.sublotIdentifier
            .compareTo(right.value.first.sublotIdentifier);
        return identifierComparison != 0
            ? identifierComparison
            : left.key.compareTo(right.key);
      });

    if (groups.isEmpty) return const Text('No active Bags.');

    return Column(
      children: [
        for (final group in groups)
          _buildSublot(
            context,
            group.key,
            group.value
              ..sort((left, right) => left.number.compareTo(right.number)),
          ),
      ],
    );
  }

  Widget _buildSublot(
    BuildContext context,
    String sublotId,
    List<BagQualification> bags,
  ) {
    final expanded = _expandedSublotIds.contains(sublotId);
    final identifier = bags.first.sublotIdentifier;
    final ready =
        bags.isNotEmpty &&
        bags.every((bag) => bag.status == BagQualificationStatus.accepted);
    final hasReviewedBagToAccept = bags.any(
      (bag) =>
          bag.operatorReviewed && bag.status != BagQualificationStatus.accepted,
    );
    void toggleExpanded() => setState(() {
      if (!_expandedSublotIds.remove(sublotId)) {
        _expandedSublotIds.add(sublotId);
      }
    });

    return Column(
      children: [
        ListTile(
          key: ValueKey('qualification-sublot-$sublotId'),
          contentPadding: EdgeInsets.zero,
          onTap: toggleExpanded,
          title: Row(
            children: [
              Text('Sublot $identifier'),
              if (ready) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'All Bags accepted',
                  child: Semantics(
                    label: 'All Bags accepted',
                    child: Container(
                      key: ValueKey('qualification-sublot-$sublotId-ready'),
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _QualificationCount(
                sublotId: sublotId,
                status: BagQualificationStatus.accepted,
                count: bags
                    .where(
                      (bag) => bag.status == BagQualificationStatus.accepted,
                    )
                    .length,
              ),
              _QualificationCount(
                sublotId: sublotId,
                status: BagQualificationStatus.pendingReview,
                count: bags
                    .where(
                      (bag) =>
                          bag.status == BagQualificationStatus.pendingReview,
                    )
                    .length,
              ),
              _QualificationCount(
                sublotId: sublotId,
                status: BagQualificationStatus.rejected,
                count: bags
                    .where(
                      (bag) => bag.status == BagQualificationStatus.rejected,
                    )
                    .length,
              ),
              IconButton(
                key: ValueKey('expand-qualification-sublot-$sublotId'),
                tooltip: expanded ? 'Hide Bags' : 'Show Bags',
                icon: Icon(expanded ? Icons.remove : Icons.add),
                onPressed: toggleExpanded,
              ),
            ],
          ),
        ),
        if (expanded) ...[
          if (!widget.readOnly && !widget.qualification.isLocked)
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 8, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: 'Accept all Bags reviewed by an operator',
                  child: OutlinedButton(
                    key: ValueKey('accept-operator-reviewed-sublot-$sublotId'),
                    onPressed:
                        !hasReviewedBagToAccept ||
                            _busySublotIds.contains(sublotId)
                        ? null
                        : () => _acceptOperatorReviewedBags(sublotId),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                    ),
                    child: _busySublotIds.contains(sublotId)
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const _AcceptReviewedBagsLabel(),
                  ),
                ),
              ),
            ),
          for (final bag in bags)
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: _BagCard(
                batchId: widget.batchId,
                bag: bag,
                qualification: widget.qualification,
                readOnly: widget.readOnly,
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _acceptOperatorReviewedBags(String sublotId) async {
    setState(() => _busySublotIds.add(sublotId));
    try {
      await ref
          .read(campaignQualificationActionsProvider)
          .acceptOperatorReviewedBags(
            widget.batchId,
            sublotId,
            editStateVersion: widget.qualification.editStateVersion,
            contentRevision: widget.qualification.contentRevision,
          );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(error, action: 'accept operator-reviewed Bags'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busySublotIds.remove(sublotId));
      }
    }
  }
}

class _AcceptReviewedBagsLabel extends StatelessWidget {
  const _AcceptReviewedBagsLabel();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Accept all'),
      SizedBox(width: 1),
      Icon(Icons.check_circle, size: 16, color: Colors.green),
      SizedBox(width: 1),
      Icon(Icons.person_outline, size: 16),
    ],
  );
}

class _QualificationCount extends StatelessWidget {
  const _QualificationCount({
    required this.sublotId,
    required this.status,
    required this.count,
  });

  final String sublotId;
  final BagQualificationStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      BagQualificationStatus.accepted => (
        Icons.check_circle_outline,
        Colors.green,
      ),
      BagQualificationStatus.pendingReview => (
        Icons.pending_actions_outlined,
        Colors.orange,
      ),
      BagQualificationStatus.rejected => (
        Icons.cancel_outlined,
        Theme.of(context).colorScheme.error,
      ),
    };

    return Tooltip(
      message: '$count ${status.label}',
      child: Semantics(
        label: '$count ${status.label}',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            key: ValueKey(
              'qualification-sublot-$sublotId-summary-${status.key}',
            ),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 2),
              Text('$count'),
            ],
          ),
        ),
      ),
    );
  }
}

class _BagCard extends ConsumerWidget {
  const _BagCard({
    required this.batchId,
    required this.bag,
    required this.qualification,
    required this.readOnly,
  });
  final String batchId;
  final BagQualification bag;
  final CampaignQualification qualification;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    label:
        'Sublot ${bag.sublotIdentifier} Bag ${bag.number}, ${bag.status.label}',
    child: ListTile(
      key: ValueKey('qualification-bag-${bag.id}'),
      title: Text('Bag ${bag.number}'),
      subtitle: Text(
        [
          bag.status.label,
          if (bag.reason != null) bag.reason!.label,
          if (bag.notes != null) bag.notes!,
        ].join(' — '),
      ),
      trailing: readOnly || qualification.isLocked
          ? null
          : Wrap(
              spacing: 4,
              children: [
                Tooltip(
                  message: bag.operatorReviewed
                      ? 'Accept Bag'
                      : 'Add an operator-created annotation before accepting this Bag',
                  child: TextButton(
                    key: ValueKey('accept-qualification-bag-${bag.id}'),
                    onPressed:
                        bag.status == BagQualificationStatus.accepted ||
                            !bag.operatorReviewed
                        ? null
                        : () => _decide(
                            context,
                            ref,
                            BagQualificationStatus.accepted,
                          ),
                    child: const Text('Accept'),
                  ),
                ),
                TextButton(
                  onPressed: () => _reject(context, ref),
                  child: const Text('Reject & Exclude'),
                ),
                if (bag.status != BagQualificationStatus.pendingReview)
                  TextButton(
                    onPressed: () => _decide(
                      context,
                      ref,
                      BagQualificationStatus.pendingReview,
                    ),
                    child: const Text('Return to Pending'),
                  ),
              ],
            ),
    ),
  );

  Future<bool> _decide(
    BuildContext context,
    WidgetRef ref,
    BagQualificationStatus status, {
    String? reason,
    String? notes,
  }) async {
    try {
      await ref
          .read(campaignQualificationActionsProvider)
          .decideBag(
            batchId,
            bag.id,
            status: status,
            editStateVersion: qualification.editStateVersion,
            contentRevision: qualification.contentRevision,
            reasonCode: reason,
            notes: notes,
          );
      return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(error, action: 'change Bag decision'),
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    var selected = QualificationReason.values.first;
    var busy = false;
    String? submitError;
    final notes = TextEditingController();
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Reject & Exclude'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<QualificationReason>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: [
                  for (final reason in QualificationReason.values)
                    DropdownMenuItem(value: reason, child: Text(reason.label)),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => selected = value ?? selected),
              ),
              TextField(
                controller: notes,
                enabled: !busy,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: selected.key == 'other'
                      ? 'Notes (required)'
                      : 'Notes',
                ),
              ),
              if (submitError != null)
                Text(
                  submitError!,
                  key: const Key('qualification-late-conflict-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  busy || (selected.key == 'other' && notes.text.trim().isEmpty)
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        submitError = null;
                      });
                      final success = await _decide(
                        dialogContext,
                        ref,
                        BagQualificationStatus.rejected,
                        reason: selected.key,
                        notes: notes.text,
                      );
                      if (!dialogContext.mounted) return;
                      if (success) {
                        Navigator.pop(dialogContext, true);
                      } else {
                        setState(() {
                          busy = false;
                          submitError =
                              'Campaign changed. Your reason and notes were retained; refresh and retry.';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Reject & Exclude'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => notes.dispose());
  }
}
