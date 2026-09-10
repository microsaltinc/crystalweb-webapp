import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/user_facing_error.dart';
import '../models/campaign_comment.dart';
import '../providers/campaign_collaboration_provider.dart';

class CampaignCommentsSection extends ConsumerStatefulWidget {
  const CampaignCommentsSection({super.key, required this.batchId});

  final String batchId;

  @override
  ConsumerState<CampaignCommentsSection> createState() =>
      _CampaignCommentsSectionState();
}

class _CampaignCommentsSectionState
    extends ConsumerState<CampaignCommentsSection> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Enter a comment before posting.');
      return;
    }
    if (text.length > 2000) {
      setState(() => _error = 'Comments must be 2,000 characters or fewer.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await createCampaignComment(ref, widget.batchId, text: text);
      _controller.clear();
    } catch (error) {
      if (mounted) {
        setState(() => _error = userFacingError(error, action: 'post comment'));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(campaignCommentsProvider(widget.batchId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Comments',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  tooltip: 'Refresh comments',
                  onPressed: () =>
                      ref.invalidate(campaignCommentsProvider(widget.batchId)),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            commentsAsync.when(
              data: (comments) => _CommentList(comments: comments),
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text(
                userFacingError(error, action: 'load comments'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Add a comment',
                border: OutlineInputBorder(),
              ),
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: const Icon(Icons.send),
                  label: const Text('Post comment'),
                ),
                if (_submitting) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
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

class _CommentList extends StatelessWidget {
  const _CommentList({required this.comments});

  static final _format = DateFormat('yyyy-MM-dd HH:mm');

  final List<CampaignComment> comments;

  @override
  Widget build(BuildContext context) {
    if (comments.isEmpty) {
      return Text(
        'No comments yet.',
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      );
    }
    return Column(
      children: [
        for (final comment in comments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.comment_outlined),
            title: Text(comment.authorDisplayWithStatus),
            subtitle: Text(comment.text),
            trailing: Text(_format.format(comment.createdAt.toLocal())),
          ),
      ],
    );
  }
}
