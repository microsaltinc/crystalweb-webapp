import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../batches/models/campaign_structure.dart';
import '../models/image_model.dart';
import 'image_review_status.dart';

/// Grid of image thumbnails grouped by sublot letter.
///
/// Shows valid images in their sublot sections, with an optional
/// "Discarded" section at the bottom for invalidated images.
Future<void> _showImageRelocationDialog(
  BuildContext context, {
  required ImageModel image,
  required List<CampaignBagDestination> destinations,
  required Future<void> Function(ImageModel, CampaignBagDestination) onRelocate,
}) async {
  final available = destinations
      .where((destination) => destination.bag.id != image.bagId)
      .toList(growable: false);
  final destinationsBySublot = <String, List<CampaignBagDestination>>{};
  for (final destination in available) {
    destinationsBySublot
        .putIfAbsent(destination.sublotIdentifier, () => [])
        .add(destination);
  }
  String? expandedSublot;

  final selected = await showDialog<CampaignBagDestination>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Relocate SEM Image'),
      content: SizedBox(
        width: 360,
        child: available.isEmpty
            ? const Text('No other active Bags are available in this campaign.')
            : StatefulBuilder(
                builder: (context, setDialogState) => ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in destinationsBySublot.entries) ...[
                      ListTile(
                        leading: const Icon(Icons.account_tree_outlined),
                        title: Text('Sublot ${entry.key}'),
                        subtitle: entry.value.first.sublotLabel == null
                            ? null
                            : Text(entry.value.first.sublotLabel!),
                        trailing: IconButton(
                          key: ValueKey('expand-relocate-sublot-${entry.key}'),
                          tooltip: expandedSublot == entry.key
                              ? 'Hide Bags'
                              : 'Show Bags',
                          icon: Icon(
                            expandedSublot == entry.key
                                ? Icons.remove
                                : Icons.add,
                          ),
                          onPressed: () => setDialogState(() {
                            expandedSublot = expandedSublot == entry.key
                                ? null
                                : entry.key;
                          }),
                        ),
                      ),
                      if (expandedSublot == entry.key)
                        for (final destination in entry.value)
                          ListTile(
                            key: ValueKey(
                              'relocate-destination-${destination.bag.id}',
                            ),
                            contentPadding: const EdgeInsets.only(
                              left: 56,
                              right: 16,
                            ),
                            leading: const Icon(Icons.inventory_2_outlined),
                            title: Text('Bag ${destination.bag.number}'),
                            onTap: () =>
                                Navigator.of(dialogContext).pop(destination),
                          ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  if (selected != null) await onRelocate(image, selected);
}

class ImageGrid extends StatelessWidget {
  const ImageGrid({
    super.key,
    required this.images,
    required this.onImageTap,
    this.lotCode,
    this.invalidatedImages = const [],
    this.onInvalidate,
    this.onRevalidate,
    this.relocationDestinations = const [],
    this.onRelocate,
    this.thumbnailWidth = 220,
  });

  final double thumbnailWidth;
  final List<ImageModel> images;
  final ValueChanged<ImageModel> onImageTap;
  final String? lotCode;

  /// Invalidated images to show in the discarded section.
  final List<ImageModel> invalidatedImages;

  /// Callback when operator invalidates an image.
  final ValueChanged<ImageModel>? onInvalidate;

  /// Callback when operator revalidates a discarded image.
  final ValueChanged<ImageModel>? onRevalidate;

  /// Active campaign Bags offered as logical relocation destinations.
  final List<CampaignBagDestination> relocationDestinations;

  /// Callback after an operator chooses a destination Bag.
  final Future<void> Function(ImageModel, CampaignBagDestination)? onRelocate;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty && invalidatedImages.isEmpty) {
      return Center(
        child: Text(
          'No images match this view',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }

    // Group valid images by sublot letter
    final grouped = <String, List<ImageModel>>{};
    for (final img in images) {
      grouped.putIfAbsent(img.sublotLetter, () => []).add(img);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Valid images grouped by sublot
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sortedKeys.length,
          itemBuilder: (context, index) {
            final letter = sortedKeys[index];
            final sublotImages = grouped[letter]!;
            sublotImages.sort((a, b) {
              final cmp = a.bagNumber.compareTo(b.bagNumber);
              return cmp != 0 ? cmp : a.imageNumber.compareTo(b.imageNumber);
            });

            return _SublotSection(
              letter: letter,
              lotCode: lotCode,
              images: sublotImages,
              onImageTap: onImageTap,
              onInvalidate: onInvalidate,
              relocationDestinations: relocationDestinations,
              onRelocate: onRelocate,
              thumbnailWidth: thumbnailWidth,
            );
          },
        ),
        // Discarded section (only if there are invalidated images)
        if (invalidatedImages.isNotEmpty)
          _DiscardedSection(
            images: invalidatedImages,
            lotCode: lotCode,
            onRevalidate: onRevalidate,
            relocationDestinations: relocationDestinations,
            onRelocate: onRelocate,
          ),
      ],
    );
  }
}

class _SublotSection extends StatelessWidget {
  const _SublotSection({
    required this.letter,
    this.lotCode,
    required this.images,
    required this.onImageTap,
    this.onInvalidate,
    required this.relocationDestinations,
    this.onRelocate,
    this.thumbnailWidth = 220,
  });

  final double thumbnailWidth;
  final String letter;
  final String? lotCode;
  final List<ImageModel> images;
  final ValueChanged<ImageModel> onImageTap;
  final ValueChanged<ImageModel>? onInvalidate;
  final List<CampaignBagDestination> relocationDestinations;
  final Future<void> Function(ImageModel, CampaignBagDestination)? onRelocate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Sublot $letter',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = (constraints.maxWidth / thumbnailWidth)
                .floor()
                .clamp(1, 8);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemCount: images.length,
              itemBuilder: (context, index) {
                return _ImageThumbnail(
                  image: images[index],
                  onTap: () => onImageTap(images[index]),
                  onInvalidate: onInvalidate != null
                      ? () => onInvalidate!(images[index])
                      : null,
                  relocationDestinations: relocationDestinations,
                  onRelocate: onRelocate,
                );
              },
            );
          },
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({
    required this.image,
    required this.onTap,
    this.onInvalidate,
    required this.relocationDestinations,
    this.onRelocate,
  });

  final ImageModel image;
  final VoidCallback onTap;
  final VoidCallback? onInvalidate;
  final List<CampaignBagDestination> relocationDestinations;
  final Future<void> Function(ImageModel, CampaignBagDestination)? onRelocate;

  Color _statusColor(String status) {
    switch (status) {
      case 'processing':
      case 'analyzing':
      case 'downloading':
        return AppColors.statusProcessing;
      case 'complete':
        return AppColors.statusComplete;
      case 'error':
      case 'failed':
        return AppColors.statusFailed;
      default:
        return AppColors.statusPending;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'processing':
      case 'analyzing':
      case 'downloading':
        return Icons.hourglass_bottom;
      case 'complete':
        return Icons.check_circle;
      case 'error':
      case 'failed':
        return Icons.error;
      default:
        return Icons.schedule;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(image.processingStatus);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail or placeholder — prefer small JPEG thumbnail over full PNG
            if (image.hasThumbnail || image.hasCroppedImage)
              CachedNetworkImage(
                imageUrl: image.thumbnailUrl ?? image.croppedImageUrl!,
                fit: BoxFit.contain,
                placeholder: (context, url) =>
                    _PlaceholderContent(image: image),
                errorWidget: (context, url, error) =>
                    _PlaceholderContent(image: image),
              )
            else
              _PlaceholderContent(image: image),
            Positioned(
              bottom: 24,
              left: 4,
              child: image.isComplete
                  ? ImageReviewStatus(image: image, showActions: false)
                  : Chip(label: Text(image.analysisLabel)),
            ),
            // Status icon (top-right)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                _statusIcon(image.processingStatus),
                semanticLabel: image.analysisLabel,
                size: 16,
                color: statusColor,
              ),
            ),
            // Crystal count badge (bottom-right)
            if (image.crystalCount > 0)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${image.crystalCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            // Label (bottom-left)
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'B${image.bagNumber}/${image.imageNumber}',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
            // Image actions (top-left).
            if (onInvalidate != null || onRelocate != null)
              Positioned(
                top: 2,
                left: 2,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  icon: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.more_vert,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                  onSelected: (value) {
                    if (value == 'relocate') {
                      _showImageRelocationDialog(
                        context,
                        image: image,
                        destinations: relocationDestinations,
                        onRelocate: onRelocate!,
                      );
                    } else if (value == 'invalidate') {
                      onInvalidate!();
                    }
                  },
                  itemBuilder: (context) => [
                    if (onRelocate != null)
                      const PopupMenuItem(
                        value: 'relocate',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.drive_file_move_outline, size: 16),
                            SizedBox(width: 8),
                            Text('Relocate'),
                          ],
                        ),
                      ),
                    if (onInvalidate != null)
                      const PopupMenuItem(
                        value: 'invalidate',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.block, size: 16, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Discard Image'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Discarded section showing invalidated images grouped by sublot.
class _DiscardedSection extends StatelessWidget {
  const _DiscardedSection({
    required this.images,
    this.lotCode,
    this.onRevalidate,
    required this.relocationDestinations,
    this.onRelocate,
  });

  final List<ImageModel> images;
  final String? lotCode;
  final ValueChanged<ImageModel>? onRevalidate;
  final List<CampaignBagDestination> relocationDestinations;
  final Future<void> Function(ImageModel, CampaignBagDestination)? onRelocate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Group invalidated images by sublot letter
    final grouped = <String, List<ImageModel>>{};
    for (final img in images) {
      grouped.putIfAbsent(img.sublotLetter, () => []).add(img);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Icon(Icons.block, size: 18, color: theme.colorScheme.outline),
              const SizedBox(width: 8),
              Text(
                'Discarded',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${images.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Sublot groups within discarded section
        ...sortedKeys.map((letter) {
          final sublotImages = grouped[letter]!;
          sublotImages.sort((a, b) {
            final cmp = a.bagNumber.compareTo(b.bagNumber);
            return cmp != 0 ? cmp : a.imageNumber.compareTo(b.imageNumber);
          });
          return _DiscardedSublotGroup(
            letter: letter,
            lotCode: lotCode,
            images: sublotImages,
            onRevalidate: onRevalidate,
            relocationDestinations: relocationDestinations,
            onRelocate: onRelocate,
          );
        }),
      ],
    );
  }
}

/// A sublot group within the discarded section — minimal thumbnails.
class _DiscardedSublotGroup extends StatelessWidget {
  const _DiscardedSublotGroup({
    required this.letter,
    this.lotCode,
    required this.images,
    this.onRevalidate,
    required this.relocationDestinations,
    this.onRelocate,
  });

  final String letter;
  final String? lotCode;
  final List<ImageModel> images;
  final ValueChanged<ImageModel>? onRevalidate;
  final List<CampaignBagDestination> relocationDestinations;
  final Future<void> Function(ImageModel, CampaignBagDestination)? onRelocate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Text(
            lotCode != null ? 'Sublot $lotCode$letter' : 'Sublot $letter',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 800
                ? 8
                : constraints.maxWidth > 500
                ? 6
                : 4;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: images.length,
              itemBuilder: (context, index) {
                return _DiscardedThumbnail(
                  image: images[index],
                  onRevalidate: onRevalidate != null
                      ? () => onRevalidate!(images[index])
                      : null,
                  relocationDestinations: relocationDestinations,
                  onRelocate: onRelocate,
                );
              },
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Minimal thumbnail for discarded images — no crystal count, no status icon.
class _DiscardedThumbnail extends StatelessWidget {
  const _DiscardedThumbnail({
    required this.image,
    this.onRevalidate,
    required this.relocationDestinations,
    this.onRelocate,
  });

  final ImageModel image;
  final VoidCallback? onRevalidate;
  final List<CampaignBagDestination> relocationDestinations;
  final Future<void> Function(ImageModel, CampaignBagDestination)? onRelocate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Muted thumbnail
          Opacity(
            opacity: 0.5,
            child: image.hasThumbnail || image.hasCroppedImage
                ? CachedNetworkImage(
                    imageUrl: image.thumbnailUrl ?? image.croppedImageUrl!,
                    fit: BoxFit.contain,
                    placeholder: (context, url) =>
                        _PlaceholderContent(image: image),
                    errorWidget: (context, url, error) =>
                        _PlaceholderContent(image: image),
                  )
                : _PlaceholderContent(image: image),
          ),
          // Filename label (bottom)
          Positioned(
            bottom: 2,
            left: 2,
            right: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'B${image.bagNumber}/${image.imageNumber}',
                style: const TextStyle(color: Colors.white, fontSize: 9),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          // Discarded image actions.
          if (onRevalidate != null || onRelocate != null)
            Positioned(
              top: 2,
              right: 2,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 16,
                icon: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.more_vert,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
                onSelected: (value) {
                  if (value == 'relocate') {
                    _showImageRelocationDialog(
                      context,
                      image: image,
                      destinations: relocationDestinations,
                      onRelocate: onRelocate!,
                    );
                  } else if (value == 'revalidate') {
                    onRevalidate!();
                  }
                },
                itemBuilder: (context) => [
                  if (onRelocate != null)
                    const PopupMenuItem(
                      value: 'relocate',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.drive_file_move_outline, size: 16),
                          SizedBox(width: 8),
                          Text('Relocate'),
                        ],
                      ),
                    ),
                  if (onRevalidate != null)
                    const PopupMenuItem(
                      value: 'revalidate',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.undo, size: 16),
                          SizedBox(width: 8),
                          Text('Restore Image'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaceholderContent extends StatelessWidget {
  const _PlaceholderContent({required this.image});

  final ImageModel image;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.science_outlined,
            size: 24,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 2),
          Text(
            'B${image.bagNumber}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
