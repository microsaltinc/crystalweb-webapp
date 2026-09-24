import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/crystal.dart';
import '../models/image_model.dart';
import 'interactive_crystal_overlay.dart';

/// Image viewer with pan/zoom and interactive crystal overlay support.
class ImageViewer extends StatefulWidget {
  const ImageViewer({
    super.key,
    required this.image,
    required this.crystals,
    required this.selectedCrystalId,
    required this.showDiscarded,
    this.showOverlay = true,
    this.showNumbers = true,
    this.selectedAnnotationScale = 1,
    this.onTapCrystal,
    this.onQuadChanged,
    this.effectiveQuads,
    this.effectiveDiscarded,
    this.onDoubleTap,
    this.onDownload,
    this.onReanalyze,
    this.delRegionActive = false,
    this.delRegionPoints = const [],
    this.onDelRegionTap,
    this.editable = true,
  });

  final ImageModel image;
  final List<Crystal> crystals;
  final String? selectedCrystalId;
  final bool showDiscarded;

  /// Whether the crystal annotation overlay is visible.
  final bool showOverlay;

  /// Whether crystal number labels are shown on the overlay.
  final bool showNumbers;
  final int selectedAnnotationScale;
  final ValueChanged<String?>? onTapCrystal;

  /// Called when a crystal quad is changed via drag interaction.
  final void Function(Crystal crystal, List<Point> newQuad)? onQuadChanged;

  /// Effective quads with pending changes applied, keyed by crystal ID.
  final Map<String, List<Point>>? effectiveQuads;

  /// Effective discarded state with pending changes applied, keyed by crystal ID.
  final Map<String, bool>? effectiveDiscarded;

  /// Called when the user double-taps on the image to add a new annotation.
  /// Passes the position in image coordinates (not screen coordinates).
  final void Function(double x, double y)? onDoubleTap;

  /// Called when the user taps the download button.
  final VoidCallback? onDownload;

  /// Called when the user taps the re-analyze button.
  final VoidCallback? onReanalyze;

  /// Whether del-region drawing mode is active.
  final bool delRegionActive;

  /// Current lasso polygon points (image coordinates).
  final List<Point> delRegionPoints;

  /// Called when user clicks during del-region mode.
  final void Function(double x, double y)? onDelRegionTap;
  final bool editable;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  bool _annotationDragActive = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!widget.image.hasCroppedImage) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Image not yet processed',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.image.displayLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Status: ${widget.image.processingStatus}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    final visibleCrystals = widget.showDiscarded
        ? widget.crystals
        : widget.crystals.where((c) => !c.discarded).toList();

    final imageSize = Size(
      widget.image.widthPx.toDouble(),
      (widget.image.cropBottom ?? widget.image.heightPx).toDouble(),
    );

    // The InteractiveViewer + image stack
    final viewer = InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      panEnabled: !_annotationDragActive,
      scaleEnabled: !_annotationDragActive,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Decode at display resolution so the image codec (libjpeg)
          // handles downscaling with its built-in Lanczos filter — this
          // matches macOS Preview quality. Without this, Flutter's GPU
          // downscales 5120px→~1000px using bilinear sampling which
          // produces visible grain/noise on SEM images.
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final cacheWidth = (constraints.maxWidth * dpr).round().clamp(
            1,
            widget.image.widthPx,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: widget.image.croppedImageUrl!,
                fit: BoxFit.contain,
                memCacheWidth: cacheWidth,
                placeholder: (context, url) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (context, url, error) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Failed to load image',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.showOverlay)
                Positioned.fill(
                  child: InteractiveCrystalOverlay(
                    crystals: visibleCrystals,
                    selectedCrystalId: widget.selectedCrystalId,
                    imageSize: imageSize,
                    effectiveQuads: widget.effectiveQuads ?? {},
                    effectiveDiscarded: widget.effectiveDiscarded,
                    showNumbers: widget.showNumbers,
                    showDiscarded: widget.showDiscarded,
                    selectedAnnotationScale: widget.selectedAnnotationScale,
                    onTapCrystal: widget.onTapCrystal,
                    onQuadChanged: widget.editable
                        ? widget.onQuadChanged
                        : null,
                    onDragActiveChanged: (active) {
                      setState(() {
                        _annotationDragActive = active;
                      });
                    },
                    onDoubleTap: widget.editable ? widget.onDoubleTap : null,
                    delRegionActive: widget.editable && widget.delRegionActive,
                    delRegionPoints: widget.delRegionPoints,
                    onDelRegionTap: widget.editable
                        ? widget.onDelRegionTap
                        : null,
                  ),
                ),
            ],
          );
        },
      ),
    );

    // Wrap with action buttons overlay
    final hasActions = widget.onDownload != null || widget.onReanalyze != null;
    if (!hasActions) return viewer;

    return Stack(
      children: [
        viewer,
        Positioned(
          left: 8,
          bottom: 8,
          child: _ActionBar(
            onDownload: widget.onDownload,
            onReanalyze: widget.editable ? widget.onReanalyze : null,
          ),
        ),
      ],
    );
  }
}

/// Small floating action bar on the image viewer.
class _ActionBar extends StatelessWidget {
  const _ActionBar({this.onDownload, this.onReanalyze});

  final VoidCallback? onDownload;
  final VoidCallback? onReanalyze;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onDownload != null)
            IconButton(
              icon: const Icon(Icons.download, size: 18, color: Colors.white70),
              tooltip: 'Download cropped image',
              onPressed: onDownload,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          if (onReanalyze != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
              tooltip: 'Re-analyze (re-run crystal detection)',
              onPressed: onReanalyze,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
        ],
      ),
    );
  }
}
