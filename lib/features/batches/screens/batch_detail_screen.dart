import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../images/providers/image_provider.dart';
import '../../images/widgets/image_grid.dart';
import '../../reports/widgets/report_section.dart';
import '../models/batch.dart';
import '../providers/batch_provider.dart';
import '../providers/campaign_locking_provider.dart';
import '../providers/campaign_qualification_provider.dart';
import '../providers/campaign_structure_provider.dart';
import '../widgets/campaign_comments_section.dart';
import '../widgets/campaign_locking_section.dart';
import '../widgets/campaign_qualification_section.dart';
import '../widgets/campaign_structure_section.dart';
import '../widgets/campaign_registration_conflicts_section.dart';
import '../widgets/campaign_ownership_section.dart';
import '../widgets/campaign_workflow_section.dart';
import '../services/batch_download_service.dart';
import '../widgets/download_format_dialog.dart';

class BatchDetailScreen extends ConsumerWidget {
  const BatchDetailScreen({
    super.key,
    required this.batchId,
    this.routeRoot = '/batches',
  });

  final String batchId;
  final String routeRoot;

  Color _statusColor(String status) {
    switch (status) {
      case 'processing':
        return AppColors.statusProcessing;
      case 'complete':
        return AppColors.statusComplete;
      case 'failed':
        return AppColors.statusFailed;
      default:
        return AppColors.statusPending;
    }
  }

  Future<void> _downloadImages(
    BuildContext context,
    WidgetRef ref,
    Batch batch,
  ) async {
    final format = await DownloadFormatDialog.show(context);
    if (format == null || !context.mounted) return;

    final client = ref.read(apiClientProvider);
    final service = BatchDownloadService(dio: client.dio);

    // Show a progress snackbar
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Downloading images...'),
          ],
        ),
        duration: Duration(minutes: 5),
      ),
    );

    try {
      final path = await service.downloadBatchImages(
        batchId: batch.id,
        format: format,
        lotCode: batch.lotCode,
        campaignNum: batch.campaignNum,
      );

      messenger.hideCurrentSnackBar();
      if (path != null && context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Images saved to: $path')),
        );
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(userFacingError(e, action: 'download images')),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _downloadImages(context, ref, batch),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batchAsync = ref.watch(batchDetailProvider(batchId));
    final imagesAsync = ref.watch(imagesForBatchProvider(batchId));
    final structureAsync = ref.watch(campaignStructureProvider(batchId));
    final theme = Theme.of(context);

    // Use .valueOrNull so we show previous data during refreshes
    // instead of a full-screen spinner. Only show spinner on very first load.
    final batch = batchAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          routeRoot == '/rnd' ? 'R&D Experiment Detail' : 'Campaign Detail',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            key: const Key('campaign-structure-help'),
            tooltip: 'How campaign structure works',
            onPressed: () => showCampaignStructureHelp(context),
          ),
          if (batch != null && batch.processedCount > 0)
            IconButton(
              key: const Key('download-campaign-images'),
              icon: const Icon(Icons.download),
              tooltip: 'Download Images',
              onPressed: () => _downloadImages(context, ref, batch),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(batchDetailProvider(batchId));
              ref.invalidate(imagesForBatchProvider(batchId));
              ref.invalidate(registrationConflictsProvider(batchId));
              ref.invalidate(campaignQualificationProvider(batchId));
              ref.invalidate(campaignStructureProvider(batchId));
            },
          ),
        ],
      ),
      body: batch == null
          ? batchAsync.when(
              data: (_) => const SizedBox.shrink(), // won't hit — batch != null
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Text(userFacingError(err, action: 'load batch')),
              ),
            )
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              batch.displayName,
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                          _CampaignInfoButton(batch: batch),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(
                              batch.status,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            backgroundColor: _statusColor(batch.status),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Lot Code: ${batch.lotCode}'),
                      Text('Formula: ${batch.formulaCode}'),
                      Text('Dryer: ${batch.dryerCode}'),
                      Text('Campaign: ${batch.campaignNum}'),
                      Text('Sublots: ${batch.sublotCount}'),
                      const SizedBox(height: 12),
                      CampaignLockingSection(batch: batch),
                      const SizedBox(height: 12),
                      CampaignQualificationSection(
                        batchId: batchId,
                        readOnly: batch.isLocked,
                      ),
                      const SizedBox(height: 12),
                      CampaignStructureSection(
                        batchId: batchId,
                        readOnly: batch.isLocked,
                      ),
                      const SizedBox(height: 12),
                      CampaignRegistrationConflictsSection(batch: batch),
                      if (batch.unresolvedRegistrationConflictCount > 0)
                        const SizedBox(height: 12),
                      CampaignWorkflowSection(batch: batch),
                      if (batch.purchaseOrderCode != null)
                        Text('PO: ${batch.purchaseOrderCode}'),
                      const SizedBox(height: 16),
                      Text(
                        'Images: ${batch.processedCount} / ${batch.imageCount} processed',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: batch.processingProgress,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Created: ${batch.createdAt.toLocal().toString().split('.')[0]}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 24),
                      CampaignOwnershipSection(batch: batch),
                      const SizedBox(height: 24),
                      CampaignCommentsSection(batchId: batchId),
                      const SizedBox(height: 24),
                      // Report section
                      ReportSection(
                        batchId: batchId,
                        batchStatus: batch.status,
                        lotCode: batch.lotCode,
                        editable: !batch.isLocked,
                        expectedEditStateVersion: batch.editStateVersion,
                      ),
                      const SizedBox(height: 24),
                      // Image grid section
                      Text('Images', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      imagesAsync.when(
                        data: (allImages) {
                          final validImages = allImages
                              .where((img) => !img.isInvalidated)
                              .toList();
                          final invalidatedImages = allImages
                              .where((img) => img.isInvalidated)
                              .toList();
                          return ImageGrid(
                            images: validImages,
                            invalidatedImages: invalidatedImages,
                            lotCode: batch.lotCode,
                            onImageTap: (image) {
                              context.go(
                                '$routeRoot/$batchId/images/${image.id}',
                              );
                            },
                            relocationDestinations:
                                structureAsync
                                    .valueOrNull
                                    ?.activeBagDestinations ??
                                const [],
                            onRelocate:
                                batch.isLocked ||
                                    structureAsync.valueOrNull == null
                                ? null
                                : (image, destination) async {
                                    try {
                                      await ref
                                          .read(imageRelocationActionsProvider)
                                          .relocate(
                                            image.id,
                                            batchId: batchId,
                                            destinationBagId:
                                                destination.bag.id,
                                            expectedEditStateVersion:
                                                structureAsync
                                                    .valueOrNull
                                                    ?.editStateVersion ??
                                                batch.editStateVersion,
                                            expectedContentRevision:
                                                structureAsync
                                                    .valueOrNull
                                                    ?.contentRevision ??
                                                batch.contentRevision,
                                          );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Image relocated to ${destination.label}.',
                                            ),
                                          ),
                                        );
                                      }
                                    } catch (error) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              userFacingError(
                                                error,
                                                action: 'relocate image',
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                            onInvalidate: batch.isLocked
                                ? null
                                : (image) async {
                                    await invalidateImage(ref, image.id);
                                    ref.invalidate(
                                      imagesForBatchProvider(batchId),
                                    );
                                  },
                            onRevalidate: batch.isLocked
                                ? null
                                : (image) async {
                                    await revalidateImage(ref, image.id);
                                    ref.invalidate(
                                      imagesForBatchProvider(batchId),
                                    );
                                  },
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (err, stack) => Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            userFacingError(err, action: 'load images'),
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Subtle refresh indicator at top when reloading
                if (batchAsync.isLoading)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
    );
  }
}

/// [+More] button that shows campaign details with copy functionality.
class _CampaignInfoButton extends StatelessWidget {
  const _CampaignInfoButton({required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _showInfoPanel(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 2),
            Text(
              'More',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showInfoPanel(BuildContext context) {
    final fields = <String, String>{
      'Campaign ID': batch.id,
      'Lot Code': batch.lotCode,
      'Formula': batch.formulaCode,
      'Dryer': batch.dryerCode,
      'Campaign #': batch.campaignNum.toString(),
      'Sublots': batch.sublotCount.toString(),
      'Images': '${batch.processedCount} / ${batch.imageCount}',
      'Status': batch.status,
      'Owner': batch.ownerDisplayWithStatus,
      'Created': _formatDateTime(batch.createdAt.toLocal()),
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Campaign Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: fields.entries
              .map((e) => _CampaignInfoRow(label: e.key, value: e.value))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final text = fields.entries
                  .map((e) => '${e.key}: ${e.value}')
                  .join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text('All fields copied'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: const Text('Copy All'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _CampaignInfoRow extends StatelessWidget {
  const _CampaignInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: 'Copy $label',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label copied'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
