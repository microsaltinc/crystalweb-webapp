import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/user_facing_error.dart';
import '../models/image_model.dart';
import '../providers/image_provider.dart';

class ImageReviewStatus extends ConsumerStatefulWidget {
  const ImageReviewStatus({
    super.key,
    required this.image,
    this.showActions = true,
    this.editable,
  });
  final ImageModel image;
  final bool showActions;
  final bool? editable;

  @override
  ConsumerState<ImageReviewStatus> createState() => _ImageReviewStatusState();
}

class _ImageReviewStatusState extends ConsumerState<ImageReviewStatus> {
  bool busy = false;

  Future<void> _change(bool complete) async {
    setState(() => busy = true);
    try {
      final actions = ref.read(imageReviewActionsProvider);
      if (complete) {
        await actions.complete(
          widget.image.id,
          batchId: widget.image.batchId,
          expectedEditStateVersion: widget.image.campaignEditStateVersion,
        );
      } else {
        await actions.clear(
          widget.image.id,
          batchId: widget.image.batchId,
          expectedEditStateVersion: widget.image.campaignEditStateVersion,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(complete ? 'Review completed.' : 'Review cleared.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(
                error,
                action: complete ? 'complete review' : 'clear review',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final complete = image.reviewComplete;
    final reviewer =
        image.reviewedByOperatorName ?? image.reviewedBySessionEmail;
    final canEdit = widget.editable ?? !image.campaignIsLocked;
    final eligible = image.isComplete && !image.isInvalidated && canEdit;
    final retained = image.isInvalidated && complete;
    final reviewedAt = image.reviewCompletedAt == null
        ? null
        : DateFormat.yMMMd().add_jm().format(
            image.reviewCompletedAt!.toLocal(),
          );
    final label = retained
        ? 'Review complete · retained but excluded'
        : complete
        ? 'Review complete'
        : image.isInvalidated
        ? 'Invalidated · excluded'
        : 'Review incomplete';
    final details = [?reviewer, ?reviewedAt].join(' · ');
    return Semantics(
      label: details.isEmpty ? label : '$label by $details',
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Tooltip(
            message: details.isEmpty ? label : details,
            child: Chip(
              key: Key('image-review-${image.id}'),
              avatar: Icon(
                complete ? Icons.verified : Icons.pending_actions,
                size: 16,
              ),
              label: Text(label),
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (widget.showActions && !complete)
            TextButton.icon(
              onPressed: eligible && !busy ? () => _change(true) : null,
              icon: const Icon(Icons.task_alt),
              label: const Text('Complete review'),
            ),
          if (widget.showActions && complete)
            TextButton.icon(
              onPressed: canEdit && !busy ? () => _change(false) : null,
              icon: const Icon(Icons.undo),
              label: const Text('Clear review'),
            ),
        ],
      ),
    );
  }
}
