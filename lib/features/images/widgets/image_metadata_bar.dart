import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/image_model.dart';
import 'image_review_status.dart';

/// Compact bar showing image metadata (magnification, voltage, etc.).
class ImageMetadataBar extends StatelessWidget {
  const ImageMetadataBar({super.key, required this.image, this.editable});

  final ImageModel image;
  final bool? editable;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipStyle = theme.textTheme.bodySmall;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          ImageReviewStatus(image: image, editable: editable),
          _MetadataChip(
            icon: Icons.circle,
            iconColor: _statusColor(image.processingStatus),
            label: image.processingStatus,
            style: chipStyle,
          ),
          if (image.magnification != null)
            _MetadataChip(
              icon: Icons.zoom_in,
              label: '${image.magnification!}x',
              style: chipStyle,
            ),
          if (image.voltageKv != null)
            _MetadataChip(
              icon: Icons.bolt,
              label: '${image.voltageKv!.toStringAsFixed(1)} kV',
              style: chipStyle,
            ),
          if (image.workingDistanceMm != null)
            _MetadataChip(
              icon: Icons.straighten,
              label: '${image.workingDistanceMm!.toStringAsFixed(1)} mm WD',
              style: chipStyle,
            ),
          _MetadataChip(
            icon: Icons.aspect_ratio,
            label: '${image.widthPx} x ${image.heightPx}',
            style: chipStyle,
          ),
          _MetadataChip(
            icon: Icons.grain,
            label: '${image.crystalCount} crystals',
            style: chipStyle,
          ),
          if (image.nmPerPixel != null)
            _MetadataChip(
              icon: Icons.straighten,
              label: '${image.nmPerPixel!.toStringAsFixed(1)} nm/px',
              style: chipStyle,
            ),
          if (image.detector != null)
            _MetadataChip(
              icon: Icons.sensors,
              label: image.detector!,
              style: chipStyle,
            ),
          if (image.instrument != null)
            _MetadataChip(
              icon: Icons.precision_manufacturing,
              label: image.instrument!,
              style: chipStyle,
            ),
          if (image.scanDatetime != null)
            _MetadataChip(
              icon: Icons.schedule,
              label: image.scanDatetime!,
              style: chipStyle,
            ),
        ],
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({
    required this.icon,
    this.iconColor,
    required this.label,
    this.style,
  });

  final IconData icon;
  final Color? iconColor;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: iconColor ?? Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 4),
        Text(label, style: style),
      ],
    );
  }
}
