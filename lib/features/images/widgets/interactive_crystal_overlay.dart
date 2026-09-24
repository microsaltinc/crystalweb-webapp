import 'package:flutter/material.dart';

import '../models/crystal.dart';
import 'crystal_overlay_painter.dart';
import 'fitted_image_rect.dart';

/// The type of drag interaction currently active.
enum DragMode { none, move }

/// Tracks a corner resize drag, including which corner index.
class CornerDrag {
  const CornerDrag(this.cornerIndex);
  final int cornerIndex;
}

/// Interactive overlay that renders crystal quads and handles gesture-based
/// editing (move, resize corners, rotate) for the selected crystal.
class InteractiveCrystalOverlay extends StatefulWidget {
  const InteractiveCrystalOverlay({
    super.key,
    required this.crystals,
    required this.selectedCrystalId,
    required this.imageSize,
    required this.effectiveQuads,
    this.effectiveDiscarded,
    this.showNumbers = true,
    this.showDiscarded = false,
    this.selectedAnnotationScale = 1,
    this.onTapCrystal,
    this.onQuadChanged,
    this.onDragActiveChanged,
    this.onDoubleTap,
    this.delRegionActive = false,
    this.delRegionPoints = const [],
    this.onDelRegionTap,
  });

  final List<Crystal> crystals;
  final String? selectedCrystalId;
  final Size imageSize;

  /// Effective quads (original + pending changes) for each crystal by ID.
  final Map<String, List<Point>> effectiveQuads;

  /// Effective discarded state (original + pending changes) for each crystal by ID.
  final Map<String, bool>? effectiveDiscarded;

  /// Whether to show number labels on crystals.
  final bool showNumbers;

  /// Whether to render discarded/below-threshold crystals (in red).
  final bool showDiscarded;
  final int selectedAnnotationScale;
  final ValueChanged<String?>? onTapCrystal;

  /// Called when the user drags to change a quad. Passes the crystal and new quad.
  final void Function(Crystal crystal, List<Point> newQuad)? onQuadChanged;

  /// Notifies parent when annotation drag starts/stops (to disable InteractiveViewer panning).
  final ValueChanged<bool>? onDragActiveChanged;

  /// Called on double-tap to add a new annotation. Passes image coordinates.
  final void Function(double x, double y)? onDoubleTap;

  /// Whether del-region mode is active.
  final bool delRegionActive;

  /// Current polygon points for del-region (image coordinates).
  final List<Point> delRegionPoints;

  /// Called when user taps during del-region mode, passing image coordinates.
  final void Function(double x, double y)? onDelRegionTap;

  @override
  State<InteractiveCrystalOverlay> createState() =>
      _InteractiveCrystalOverlayState();
}

class _InteractiveCrystalOverlayState extends State<InteractiveCrystalOverlay> {
  DragMode _dragMode = DragMode.none;
  CornerDrag? _cornerDrag;
  Offset? _dragStart;

  /// The quad at the start of the current drag, in image coordinates.
  List<Point>? _dragStartQuad;

  /// Position captured from onDoubleTapDown for use in onDoubleTap.
  Offset? _doubleTapPos;

  /// Position captured from onTapDown for use in onTap.
  Offset? _tapDownPos;

  // Keep corners easy to grab even when their visible dots are small.
  static const double _handleHitRadius = 6.0;

  Crystal? get _selectedCrystal {
    if (widget.selectedCrystalId == null) return null;
    try {
      return widget.crystals.firstWhere(
        (c) => c.id == widget.selectedCrystalId,
      );
    } catch (_) {
      return null;
    }
  }

  List<Point> _effectiveQuad(Crystal crystal) {
    return widget.effectiveQuads[crystal.id] ?? crystal.quad;
  }

  bool _isEffectivelyDiscarded(Crystal crystal) {
    return widget.effectiveDiscarded?[crystal.id] ?? crystal.discarded;
  }

  FittedImageRect _fit(BoxConstraints constraints) {
    return FittedImageRect(
      imageSize: widget.imageSize,
      widgetSize: Size(constraints.maxWidth, constraints.maxHeight),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) => _tapDownPos = details.localPosition,
          onTap: () {
            if (widget.delRegionActive) {
              _handleDelRegionTap(constraints);
            } else {
              _handleTap(constraints);
            }
          },
          onDoubleTapDown: widget.onDoubleTap == null
              ? null
              : (details) => _doubleTapPos = details.localPosition,
          onDoubleTap: widget.onDoubleTap == null
              ? null
              : () => _handleDoubleTap(constraints),
          onPanStart: widget.delRegionActive || widget.onQuadChanged == null
              ? null
              : (details) => _handlePanStart(details, constraints),
          onPanUpdate: widget.delRegionActive || widget.onQuadChanged == null
              ? null
              : (details) => _handlePanUpdate(details, constraints),
          onPanEnd: widget.delRegionActive || widget.onQuadChanged == null
              ? null
              : (_) => _handlePanEnd(),
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: CrystalOverlayPainter(
              crystals: widget.crystals,
              selectedId: widget.selectedCrystalId,
              imageSize: widget.imageSize,
              showHandles:
                  widget.selectedCrystalId != null &&
                  widget.onQuadChanged != null,
              showNumbers: widget.showNumbers,
              showDiscarded: widget.showDiscarded,
              selectedAnnotationScale: widget.selectedAnnotationScale,
              effectiveQuads: widget.effectiveQuads,
              effectiveDiscarded: widget.effectiveDiscarded,
              delRegionPoints: widget.delRegionPoints,
            ),
          ),
        );
      },
    );
  }

  void _handleDelRegionTap(BoxConstraints constraints) {
    if (_tapDownPos == null || widget.onDelRegionTap == null) return;
    final pos = _tapDownPos!;
    _tapDownPos = null;
    final fit = _fit(constraints);
    final imgCoord = fit.widgetToImage(pos);
    widget.onDelRegionTap!(imgCoord.dx, imgCoord.dy);
  }

  void _handleTap(BoxConstraints constraints) {
    if (_tapDownPos == null) return;
    final pos = _tapDownPos!;
    _tapDownPos = null;
    final fit = _fit(constraints);

    // Check if tap is on any crystal
    for (final crystal in widget.crystals) {
      if (_isEffectivelyDiscarded(crystal)) continue;
      final quad = _effectiveQuad(crystal);
      if (_isPointInQuad(pos, quad, fit)) {
        widget.onTapCrystal?.call(crystal.id);
        return;
      }
    }
    // Tapped outside — deselect
    widget.onTapCrystal?.call(null);
  }

  void _handleDoubleTap(BoxConstraints constraints) {
    if (_doubleTapPos == null || widget.onDoubleTap == null) return;
    final pos = _doubleTapPos!;
    final fit = _fit(constraints);
    final imgCoord = fit.widgetToImage(pos);
    widget.onDoubleTap!(imgCoord.dx, imgCoord.dy);
    _doubleTapPos = null;
  }

  void _handlePanStart(DragStartDetails details, BoxConstraints constraints) {
    final selected = _selectedCrystal;
    if (selected == null) return;

    final pos = details.localPosition;
    final fit = _fit(constraints);
    final quad = _effectiveQuad(selected);
    if (quad.length != 4) return;

    final scaledPoints = quad.map((p) => fit.imageToWidget(p.x, p.y)).toList();

    // Find the nearest corner within hit radius
    int? nearestCorner;
    double nearestDist = double.infinity;
    for (var i = 0; i < scaledPoints.length; i++) {
      final dist = (pos - scaledPoints[i]).distance;
      if (dist <= _handleHitRadius && dist < nearestDist) {
        nearestDist = dist;
        nearestCorner = i;
      }
    }
    if (nearestCorner != null) {
      setState(() {
        _dragMode = DragMode.none;
        _cornerDrag = CornerDrag(nearestCorner!);
        _dragStart = pos;
        _dragStartQuad = List.from(quad);
      });
      widget.onDragActiveChanged?.call(true);
      return;
    }

    // Check if inside the quad body -> move
    if (_isPointInQuad(pos, quad, fit)) {
      setState(() {
        _dragMode = DragMode.move;
        _dragStart = pos;
        _dragStartQuad = List.from(quad);
      });
      widget.onDragActiveChanged?.call(true);
      return;
    }
  }

  void _handlePanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final selected = _selectedCrystal;
    if (selected == null || _dragStartQuad == null || _dragStart == null) {
      return;
    }

    final pos = details.localPosition;
    final fit = _fit(constraints);
    final scale = fit.scale;

    if (_cornerDrag != null) {
      // Resize: move single corner
      final idx = _cornerDrag!.cornerIndex;
      final delta = pos - _dragStart!;
      final newQuad = List<Point>.from(_dragStartQuad!);
      newQuad[idx] = Point(
        _dragStartQuad![idx].x + delta.dx / scale,
        _dragStartQuad![idx].y + delta.dy / scale,
      );
      widget.onQuadChanged?.call(selected, newQuad);
    } else if (_dragMode == DragMode.move) {
      // Move: translate all points
      final delta = pos - _dragStart!;
      final newQuad = _dragStartQuad!
          .map((p) => Point(p.x + delta.dx / scale, p.y + delta.dy / scale))
          .toList();
      widget.onQuadChanged?.call(selected, newQuad);
    }
  }

  void _handlePanEnd() {
    if (_dragMode != DragMode.none || _cornerDrag != null) {
      widget.onDragActiveChanged?.call(false);
    }
    setState(() {
      _dragMode = DragMode.none;
      _cornerDrag = null;
      _dragStart = null;
      _dragStartQuad = null;
    });
  }

  /// Simple point-in-polygon test for a quad using ray casting.
  /// Uses FittedImageRect to properly convert image coords to widget coords.
  bool _isPointInQuad(Offset point, List<Point> quad, FittedImageRect fit) {
    if (quad.length != 4) return false;

    final scaledQuad = quad.map((p) => fit.imageToWidget(p.x, p.y)).toList();

    var inside = false;
    for (int i = 0, j = scaledQuad.length - 1; i < scaledQuad.length; j = i++) {
      final xi = scaledQuad[i].dx;
      final yi = scaledQuad[i].dy;
      final xj = scaledQuad[j].dx;
      final yj = scaledQuad[j].dy;

      final intersect =
          ((yi > point.dy) != (yj > point.dy)) &&
          (point.dx < (xj - xi) * (point.dy - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}
