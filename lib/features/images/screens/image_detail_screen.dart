import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../../batches/models/batch.dart';
import '../../batches/providers/batch_provider.dart';
import '../../batches/providers/campaign_locking_provider.dart';
import '../models/crystal.dart';
import '../models/image_model.dart';
import '../providers/annotation_provider.dart';
import '../providers/image_provider.dart';
import '../widgets/crystal_list_panel.dart';
import '../widgets/image_metadata_bar.dart';
import '../widgets/image_viewer.dart';
import '../widgets/keyboard_shortcuts_bar.dart';

/// Full image detail screen with crystal overlay and annotation editing.
class ImageDetailScreen extends ConsumerWidget {
  const ImageDetailScreen({
    super.key,
    required this.batchId,
    required this.imageId,
  });

  final String batchId;
  final String imageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageAsync = ref.watch(imageDetailProvider(imageId));
    final crystalsAsync = ref.watch(crystalsForImageProvider(imageId));
    final annotationState = ref.watch(annotationProvider(imageId));
    final annotationNotifier = ref.read(annotationProvider(imageId).notifier);

    final batchAsync = ref.watch(batchDetailProvider(batchId));

    return Scaffold(
      appBar: AppBar(
        title:
            imageAsync.whenOrNull(
              data: (image) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(image.displayLabel),
                  const SizedBox(width: 8),
                  _MoreInfoButton(image: image, batch: batchAsync.valueOrNull),
                ],
              ),
            ) ??
            const Text('Image Detail'),
      ),
      body: imageAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) =>
            Center(child: Text(userFacingError(err, action: 'load image'))),
        data: (image) {
          final actualParent = batchAsync.valueOrNull;
          final authorityLoaded = actualParent != null;
          final editable =
              authorityLoaded &&
              !actualParent.isLocked &&
              !image.campaignIsLocked &&
              !annotationState.readOnlyDueToConflict;
          if (actualParent != null) {
            annotationNotifier.setCampaignAuthority(
              batchId: actualParent.id,
              editStateVersion: actualParent.editStateVersion,
              editable: editable,
            );
          }
          final serverCrystals = crystalsAsync.valueOrNull ?? [];

          // Build effective quads and discarded maps
          final effectiveQuads = <String, List<Point>>{};
          final effectiveDiscarded = <String, bool>{};
          for (final crystal in serverCrystals) {
            effectiveQuads[crystal.id] = annotationNotifier.effectiveQuad(
              crystal,
            );
            final change = annotationState.changes[crystal.id];
            effectiveDiscarded[crystal.id] =
                change?.discarded ?? crystal.discarded;
          }

          // Create temporary Crystal objects for pending additions (new-xxx)
          // so they render in the overlay
          final allCrystals = List<Crystal>.from(serverCrystals);
          final umPx = image.umPerPixel ?? 0.0;
          for (final change in annotationState.changes.values) {
            if (change.crystalId.startsWith('new-') && change.quad != null) {
              effectiveQuads[change.crystalId] = change.quad!;
              effectiveDiscarded[change.crystalId] = false;
              final area = umPx > 0 ? quadAreaUm2(change.quad!, umPx) : 0.0;
              final diameter = equivalentDiameterFromArea(area);
              allCrystals.add(
                Crystal(
                  id: change.crystalId,
                  imageId: imageId,
                  quad: change.quad!,
                  confidence: 1.0,
                  areaUm2: area,
                  equivalentDiameterUm: diameter,
                  partialVisible: false,
                  discarded: false,
                  source: CrystalSource.operator,
                ),
              );
            }
          }

          return _KeyboardHandler(
            crystals: allCrystals,
            annotationState: annotationState,
            annotationNotifier: annotationNotifier,
            editable: editable,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;

                if (isWide) {
                  return _WideLayout(
                    image: image,
                    editable: editable,
                    editStateVersion:
                        actualParent?.editStateVersion ??
                        image.campaignEditStateVersion,
                    crystals: allCrystals,
                    annotationState: annotationState,
                    annotationNotifier: annotationNotifier,
                    effectiveQuads: effectiveQuads,
                    effectiveDiscarded: effectiveDiscarded,
                  );
                } else {
                  return _NarrowLayout(
                    image: image,
                    editable: editable,
                    editStateVersion:
                        actualParent?.editStateVersion ??
                        image.campaignEditStateVersion,
                    crystals: allCrystals,
                    annotationState: annotationState,
                    annotationNotifier: annotationNotifier,
                    effectiveQuads: effectiveQuads,
                    effectiveDiscarded: effectiveDiscarded,
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }
}

/// Handles keyboard shortcuts for annotation editing.
/// Uses FocusScope to maintain keyboard focus even after mouse clicks.
class _KeyboardHandler extends StatefulWidget {
  const _KeyboardHandler({
    required this.crystals,
    required this.annotationState,
    required this.annotationNotifier,
    required this.editable,
    required this.child,
  });

  final List<Crystal> crystals;
  final AnnotationState annotationState;
  final AnnotationNotifier annotationNotifier;
  final bool editable;
  final Widget child;

  @override
  State<_KeyboardHandler> createState() => _KeyboardHandlerState();
}

class _KeyboardHandlerState extends State<_KeyboardHandler> {
  final FocusNode _focusNode = FocusNode();

  /// Active corner for vertex nudge: 0=TL, 1=TR, 2=BL, 3=BR, null=none.
  int? _activeCorner;

  @override
  void didUpdateWidget(covariant _KeyboardHandler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.annotationState.selectedCrystalId !=
        oldWidget.annotationState.selectedCrystalId) {
      _activeCorner = null;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Crystal? get _selectedCrystal {
    if (widget.annotationState.selectedCrystalId == null) return null;
    return widget.crystals
        .where((c) => c.id == widget.annotationState.selectedCrystalId)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    // Ensure focus is maintained whenever a crystal is selected/deselected
    // so keyboard shortcuts (Delete, arrows, etc.) work immediately.
    if (widget.annotationState.selectedCrystalId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      });
    }

    return GestureDetector(
      // Re-grab focus when user clicks anywhere in the screen
      onTap: () => _focusNode.requestFocus(),
      behavior: HitTestBehavior.translucent,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (_, event) => _handleKeyEvent(event),
        child: widget.child,
      ),
    );
  }

  Future<void> _finishDelRegion() async {
    final notifier = widget.annotationNotifier;
    final inside = notifier.finishDelRegion(widget.crystals);
    if (inside.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No annotations found in the selected region.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      notifier.cancelDelRegion();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete annotations in region?'),
        content: Text(
          'This will discard ${inside.length} annotation(s) inside the '
          'selected area. You can undo before submitting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm deletion'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      notifier.discardMultiple(inside);
    } else {
      notifier.cancelDelRegion();
    }
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (!widget.editable ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final c = _selectedCrystal;
    final notifier = widget.annotationNotifier;
    final isCtrlOrCmd =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    var handled = false;

    if (c != null) {
      // Keys 1-4 select a vertex for individual nudging.
      if (key == LogicalKeyboardKey.digit1) {
        setState(() => _activeCorner = 0);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit2) {
        setState(() => _activeCorner = 1);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit3) {
        setState(() => _activeCorner = 2);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit4) {
        setState(() => _activeCorner = 3);
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowUp) {
        if (_activeCorner != null) {
          notifier.nudgeCorner(c, _activeCorner!, 0, -4.0);
        } else {
          notifier.nudgeQuad(c, 0, -5);
        }
        handled = true;
      } else if (key == LogicalKeyboardKey.arrowDown) {
        if (_activeCorner != null) {
          notifier.nudgeCorner(c, _activeCorner!, 0, 4.0);
        } else {
          notifier.nudgeQuad(c, 0, 5);
        }
        handled = true;
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        if (_activeCorner != null) {
          notifier.nudgeCorner(c, _activeCorner!, -4.0, 0);
        } else {
          notifier.nudgeQuad(c, -5, 0);
        }
        handled = true;
      } else if (key == LogicalKeyboardKey.arrowRight) {
        if (_activeCorner != null) {
          notifier.nudgeCorner(c, _activeCorner!, 4.0, 0);
        } else {
          notifier.nudgeQuad(c, 5, 0);
        }
        handled = true;
      } else if (key == LogicalKeyboardKey.delete ||
          key == LogicalKeyboardKey.backspace) {
        notifier.toggleDiscard(c);
        handled = true;
      } else if (key == LogicalKeyboardKey.equal ||
          key == LogicalKeyboardKey.numpadAdd) {
        notifier.scaleQuad(c, 1.05);
        handled = true;
      } else if (key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.numpadSubtract) {
        notifier.scaleQuad(c, 0.95);
        handled = true;
      } else if (key == LogicalKeyboardKey.keyZ && isCtrlOrCmd) {
        notifier.undoChange(c.id);
        handled = true;
      }
    }

    if (key == LogicalKeyboardKey.keyS && isCtrlOrCmd) {
      notifier.submit();
      handled = true;
    } else if (key == LogicalKeyboardKey.keyR && !isCtrlOrCmd) {
      notifier.toggleDelRegion();
      handled = true;
    } else if (key == LogicalKeyboardKey.keyF &&
        !isCtrlOrCmd &&
        widget.annotationState.delRegionActive) {
      _finishDelRegion();
      handled = true;
    } else if (key == LogicalKeyboardKey.escape) {
      if (widget.annotationState.delRegionActive) {
        notifier.cancelDelRegion();
      } else {
        setState(() => _activeCorner = null);
        notifier.selectCrystal(null);
      }
      handled = true;
    }
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }
}

/// Desktop / wide layout: image viewer on left, crystal panel on right.
class _WideLayout extends ConsumerWidget {
  const _WideLayout({
    required this.image,
    required this.editable,
    required this.editStateVersion,
    required this.crystals,
    required this.annotationState,
    required this.annotationNotifier,
    required this.effectiveQuads,
    required this.effectiveDiscarded,
  });

  final ImageModel image;
  final bool editable;
  final int editStateVersion;
  final List<Crystal> crystals;
  final AnnotationState annotationState;
  final AnnotationNotifier annotationNotifier;
  final Map<String, List<Point>> effectiveQuads;
  final Map<String, bool> effectiveDiscarded;

  Future<void> _finishDelRegion(BuildContext context) async {
    final inside = annotationNotifier.finishDelRegion(crystals);
    if (inside.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No annotations found in the selected region.'),
          duration: Duration(seconds: 2),
        ),
      );
      annotationNotifier.cancelDelRegion();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete annotations in region?'),
        content: Text(
          'This will discard ${inside.length} annotation(s) inside the '
          'selected area. You can undo before submitting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm deletion'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      annotationNotifier.discardMultiple(inside);
    } else {
      annotationNotifier.cancelDelRegion();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ImageMetadataBar(image: image, editable: editable),
            ),
            KeyboardShortcutsBar(
              editable: editable,
              delRegionActive: annotationState.delRegionActive,
              onToggleDelRegion: annotationNotifier.toggleDelRegion,
              onFinishDelRegion: () => _finishDelRegion(context),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: _ImageViewerWithActions(
                  image: image,
                  editable: editable,
                  editStateVersion: editStateVersion,
                  crystals: crystals,
                  annotationState: annotationState,
                  annotationNotifier: annotationNotifier,
                  effectiveQuads: effectiveQuads,
                  effectiveDiscarded: effectiveDiscarded,
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(width: 320, child: _buildPanel()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPanel() {
    final selectedCrystal = annotationState.selectedCrystalId != null
        ? crystals
              .where((c) => c.id == annotationState.selectedCrystalId)
              .firstOrNull
        : null;

    final notComplete = !image.isComplete;
    final editingDisabled = notComplete || !editable;

    return CrystalListPanel(
      crystals: crystals,
      annotationState: annotationState,
      effectiveQuads: effectiveQuads,
      umPerPixel: image.umPerPixel,
      onSelect: annotationNotifier.selectCrystal,
      onToggleDiscard: annotationNotifier.toggleDiscard,
      onMarkPartial: annotationNotifier.markPartial,
      onToggleShowDiscarded: annotationNotifier.toggleShowDiscarded,
      onToggleOverlay: annotationNotifier.toggleOverlay,
      onToggleNumbers: annotationNotifier.toggleNumbers,
      onSubmit: () => annotationNotifier.submit(),
      onNudge: selectedCrystal != null
          ? (dx, dy) => annotationNotifier.nudgeQuad(selectedCrystal, dx, dy)
          : null,
      onScale: selectedCrystal != null
          ? (factor) => annotationNotifier.scaleQuad(selectedCrystal, factor)
          : null,
      onUndo: (crystalId) => annotationNotifier.undoChange(crystalId),
      editingDisabled: editingDisabled,
      editingDisabledReason: !editable
          ? 'Read-only — campaign is Locked or state is loading'
          : notComplete
          ? 'Editing disabled — image is ${image.processingStatus}'
          : null,
    );
  }
}

/// Mobile / narrow layout: image viewer on top, crystal list below.
class _NarrowLayout extends ConsumerWidget {
  const _NarrowLayout({
    required this.image,
    required this.editable,
    required this.editStateVersion,
    required this.crystals,
    required this.annotationState,
    required this.annotationNotifier,
    required this.effectiveQuads,
    required this.effectiveDiscarded,
  });

  final ImageModel image;
  final bool editable;
  final int editStateVersion;
  final List<Crystal> crystals;
  final AnnotationState annotationState;
  final AnnotationNotifier annotationNotifier;
  final Map<String, List<Point>> effectiveQuads;
  final Map<String, bool> effectiveDiscarded;

  Future<void> _finishDelRegion(BuildContext context) async {
    final inside = annotationNotifier.finishDelRegion(crystals);
    if (inside.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No annotations found in the selected region.'),
          duration: Duration(seconds: 2),
        ),
      );
      annotationNotifier.cancelDelRegion();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete annotations in region?'),
        content: Text(
          'This will discard ${inside.length} annotation(s) inside the '
          'selected area. You can undo before submitting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm deletion'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      annotationNotifier.discardMultiple(inside);
    } else {
      annotationNotifier.cancelDelRegion();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCrystal = annotationState.selectedCrystalId != null
        ? crystals
              .where((c) => c.id == annotationState.selectedCrystalId)
              .firstOrNull
        : null;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ImageMetadataBar(image: image, editable: editable),
            ),
            KeyboardShortcutsBar(
              editable: editable,
              delRegionActive: annotationState.delRegionActive,
              onToggleDelRegion: annotationNotifier.toggleDelRegion,
              onFinishDelRegion: () => _finishDelRegion(context),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          flex: 3,
          child: _ImageViewerWithActions(
            image: image,
            editable: editable,
            editStateVersion: editStateVersion,
            crystals: crystals,
            annotationState: annotationState,
            annotationNotifier: annotationNotifier,
            effectiveQuads: effectiveQuads,
            effectiveDiscarded: effectiveDiscarded,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          flex: 2,
          child: Builder(
            builder: (_) {
              final notComplete = !image.isComplete;
              final editingDisabled = notComplete || !editable;
              return CrystalListPanel(
                crystals: crystals,
                annotationState: annotationState,
                effectiveQuads: effectiveQuads,
                umPerPixel: image.umPerPixel,
                onSelect: annotationNotifier.selectCrystal,
                onToggleDiscard: annotationNotifier.toggleDiscard,
                onMarkPartial: annotationNotifier.markPartial,
                onToggleShowDiscarded: annotationNotifier.toggleShowDiscarded,
                onToggleOverlay: annotationNotifier.toggleOverlay,
                onToggleNumbers: annotationNotifier.toggleNumbers,
                onSubmit: () => annotationNotifier.submit(),
                onNudge: selectedCrystal != null
                    ? (dx, dy) =>
                          annotationNotifier.nudgeQuad(selectedCrystal, dx, dy)
                    : null,
                onScale: selectedCrystal != null
                    ? (factor) =>
                          annotationNotifier.scaleQuad(selectedCrystal, factor)
                    : null,
                onUndo: (crystalId) => annotationNotifier.undoChange(crystalId),
                editingDisabled: editingDisabled,
                editingDisabledReason: !editable
                    ? 'Read-only — campaign is Locked or state is loading'
                    : notComplete
                    ? 'Editing disabled — image is ${image.processingStatus}'
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Wraps ImageViewer with download + re-analyze action buttons.
/// Handles the API call and confirmation dialog for re-analysis.
class _ImageViewerWithActions extends ConsumerStatefulWidget {
  const _ImageViewerWithActions({
    required this.image,
    required this.editable,
    required this.editStateVersion,
    required this.crystals,
    required this.annotationState,
    required this.annotationNotifier,
    required this.effectiveQuads,
    required this.effectiveDiscarded,
  });

  final ImageModel image;
  final bool editable;
  final int editStateVersion;
  final List<Crystal> crystals;
  final AnnotationState annotationState;
  final AnnotationNotifier annotationNotifier;
  final Map<String, List<Point>> effectiveQuads;
  final Map<String, bool> effectiveDiscarded;

  @override
  ConsumerState<_ImageViewerWithActions> createState() =>
      _ImageViewerWithActionsState();
}

class _ImageViewerWithActionsState
    extends ConsumerState<_ImageViewerWithActions> {
  Future<void> _downloadCroppedImage() async {
    final url = widget.image.croppedImageUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _reanalyze() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-analyze image?'),
        content: const Text(
          'This will re-run crystal detection on this image. '
          'Existing crystals and any pending edits will be replaced '
          'with new results.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Re-analyze'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final client = ref.read(apiClientProvider);
      await client.dio.post(
        '/api/v1/images/${widget.image.id}/process',
        options: Options(
          headers: {'If-Match': campaignEditETag(widget.editStateVersion)},
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Re-analysis queued. Refresh to see new results.'),
        ),
      );
      refreshImageState(ref, widget.image.id, widget.image.batchId);
      ref.invalidate(crystalsForImageProvider(widget.image.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e, action: 'start re-analysis')),
        ),
      );
    }
  }

  void _handleDelRegionTap(double x, double y) {
    widget.annotationNotifier.addDelRegionPoint(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final delActive = widget.annotationState.delRegionActive;
    final delPoints = widget.annotationState.delRegionPoints;

    return ImageViewer(
      editable: widget.editable,
      image: widget.image,
      crystals: widget.crystals,
      selectedCrystalId: widget.annotationState.selectedCrystalId,
      showDiscarded: widget.annotationState.showDiscarded,
      showOverlay: widget.annotationState.showOverlay,
      showNumbers: widget.annotationState.showNumbers,
      onTapCrystal: widget.annotationNotifier.selectCrystal,
      onQuadChanged: widget.annotationNotifier.updateQuad,
      effectiveQuads: widget.effectiveQuads,
      effectiveDiscarded: widget.effectiveDiscarded,
      onDoubleTap: (x, y) => widget.annotationNotifier.addCrystalAt(x, y),
      onDownload: widget.image.hasCroppedImage ? _downloadCroppedImage : null,
      onReanalyze: widget.editable ? _reanalyze : null,
      delRegionActive: delActive,
      delRegionPoints: delPoints,
      onDelRegionTap: delActive ? _handleDelRegionTap : null,
    );
  }
}

/// [+] button that expands to show image/batch/sublot/campaign details.
class _MoreInfoButton extends StatelessWidget {
  const _MoreInfoButton({required this.image, this.batch});

  final ImageModel image;
  final Batch? batch;

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
    final sublotName = batch != null
        ? '${batch!.identityLabel} · Sublot ${image.sublotLetter}'
        : image.sublotLetter;
    final campaignName = batch != null
        ? (batch!.isCustom
              ? batch!.identityLabel
              : 'Campaign ${batch!.campaignNum}')
        : '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Image Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _InfoRow(label: 'Image ID', value: image.id),
            _InfoRow(label: 'Image Name', value: image.displayLabel),
            _InfoRow(
              label: 'Sublot',
              value: sublotName,
              secondaryValue: batch?.id,
              secondaryLabel: 'Batch ID',
            ),
            if (batch != null) ...[
              _InfoRow(
                label: batch!.isCustom ? 'Name' : 'Lot Code',
                value: batch!.identityLabel,
              ),
              _InfoRow(label: 'Campaign', value: campaignName),
            ],
            _InfoRow(
              label: 'Uploaded',
              value: _formatDateTime(image.createdAt),
            ),
            if (image.scanDatetime != null)
              _InfoRow(label: 'Scanned', value: image.scanDatetime!),
            _InfoRow(
              label: 'Analyzed',
              value: image.analyzedAt != null
                  ? _formatDateTime(image.analyzedAt!)
                  : 'Not yet',
            ),
            _InfoRow(
              label: 'Triggered',
              value: image.analysisTriggeredBy ?? '-',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final fields = <String, String>{
                'Image ID': image.id,
                'Image Name': image.displayLabel,
                'Sublot': sublotName,
              };
              if (batch != null) {
                fields['Batch ID'] = batch!.id;
                fields[batch!.isCustom ? 'Name' : 'Lot Code'] =
                    batch!.identityLabel;
                fields['Campaign'] = campaignName;
              }
              fields['Uploaded'] = _formatDateTime(image.createdAt);
              if (image.scanDatetime != null) {
                fields['Scanned'] = image.scanDatetime!;
              }
              fields['Analyzed'] = image.analyzedAt != null
                  ? _formatDateTime(image.analyzedAt!)
                  : 'Not yet';
              fields['Triggered'] = image.analysisTriggeredBy ?? '-';
              final text = fields.entries
                  .map((e) => '${e.key}: ${e.value}')
                  .join(', ');
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

/// A single info row with label, value, and copy button.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.secondaryValue,
    this.secondaryLabel,
  });

  final String label;
  final String value;
  final String? secondaryValue;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRow(context, theme, label, value),
          if (secondaryValue != null && secondaryLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _buildRow(
                context,
                theme,
                secondaryLabel!,
                secondaryValue!,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    ThemeData theme,
    String lbl,
    String val,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            lbl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        Expanded(
          child: Text(
            val,
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 16),
          tooltip: 'Copy $lbl',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: val));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$lbl copied'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        ),
      ],
    );
  }
}
