import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/campaign_assignment_candidate.dart';
import '../providers/campaign_collaboration_provider.dart';

class CampaignAssignmentDialog extends ConsumerWidget {
  const CampaignAssignmentDialog({
    super.key,
    required this.batchId,
    required this.currentOwnerId,
  });

  final String batchId;
  final String? currentOwnerId;

  static Future<CampaignAssignmentCandidate?> show(
    BuildContext context, {
    required String batchId,
    required String? currentOwnerId,
  }) => showDialog<CampaignAssignmentCandidate>(
    context: context,
    builder: (_) => CampaignAssignmentDialog(
      batchId: batchId,
      currentOwnerId: currentOwnerId,
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidatesAsync = ref.watch(
      campaignAssignmentCandidatesProvider(batchId),
    );
    return AlertDialog(
      title: Text(
        currentOwnerId == null ? 'Assign campaign' : 'Reassign campaign',
      ),
      content: SizedBox(
        width: 480,
        child: candidatesAsync.when(
          data: (items) {
            final candidates = [...items]
              ..sort((a, b) {
                final byName = a.name.toLowerCase().compareTo(
                  b.name.toLowerCase(),
                );
                return byName != 0 ? byName : a.id.compareTo(b.id);
              });
            if (candidates.isEmpty) {
              return const Text('No active eligible operators are available.');
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text('Operator')),
                      Expanded(child: Text('Account')),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final candidate = candidates[index];
                      final isCurrent = candidate.id == currentOwnerId;
                      return ListTile(
                        onTap: () => Navigator.of(context).pop(candidate),
                        title: Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(child: Text(candidate.name)),
                                  if (isCurrent) ...[
                                    const SizedBox(width: 8),
                                    const Chip(label: Text('Current')),
                                  ],
                                ],
                              ),
                            ),
                            Expanded(child: Text(candidate.accountLabel)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) =>
              const Text('Could not load eligible operators.'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
