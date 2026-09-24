import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/crystal.dart';
import 'fitted_image_rect.dart';

class CrystalOverlayPainter extends CustomPainter {
  CrystalOverlayPainter({
    required this.crystals,
    required this.selectedId,
    required this.imageSize,
    this.showHandles = false,
    this.showNumbers = true,
    this.showDiscarded = false,
    this.selectedAnnotationScale = 1,
    this.effectiveQuads,
    this.effectiveDiscarded,
    this.delRegionPoints = const [],
  });

  final List<Crystal> crystals;
  final String? selectedId;
  final Size imageSize;
  final bool showHandles;
  /// Whether to draw numbered labels at crystal centroids.
  final bool showNumbers;
  /// Whether to render discarded/below-threshold crystals (in red).
  final bool showDiscarded;
  /// Multiplier for the selected outline and visible corner handles only.
  final int selectedAnnotationScale;
  /// If provided, use these quads instead of crystal.quad (for pending edits).
  final Map<String, List<Point>>? effectiveQuads;
  /// If provided, overrides crystal.discarded for rendering.
  final Map<String, bool>? effectiveDiscarded;
  /// Lasso polygon points for del-region tool (image coordinates).
  final List<Point> delRegionPoints;

  @override
  void paint(Canvas canvas, Size size) {
    final fit = FittedImageRect(imageSize: imageSize, widgetSize: size);

    for (var i = 0; i < crystals.length; i++) {
      final crystal = crystals[i];
      final isDiscarded = effectiveDiscarded?[crystal.id] ?? crystal.discarded;
      if (isDiscarded && !showDiscarded) continue;

      final quad = effectiveQuads?[crystal.id] ?? crystal.quad;
      final color = _colorForCrystal(crystal);
      final isSelected = crystal.id == selectedId;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 1.5 * selectedAnnotationScale : 1.5;

      final path = Path();
      if (quad.length != 4) continue;

      final scaledPoints = quad
          .map((p) => fit.imageToWidget(p.x, p.y))
          .toList();

      path.moveTo(scaledPoints[0].dx, scaledPoints[0].dy);
      for (var j = 1; j < 4; j++) {
        path.lineTo(scaledPoints[j].dx, scaledPoints[j].dy);
      }
      path.close();
      canvas.drawPath(path, paint);

      // Fill with semi-transparent color
      final fillPaint = Paint()
        ..color = color.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);

      // Draw numbered label at centroid (if enabled)
      if (showNumbers) {
        _drawNumberLabel(canvas, scaledPoints, i + 1, color);
      }

      // Draw handles for selected crystal
      if (isSelected && showHandles) {
        _drawHandles(canvas, scaledPoints);
      }
    }

    // Draw del-region lasso polygon
    if (delRegionPoints.isNotEmpty) {
      _drawDelRegionLasso(canvas, fit);
    }
  }

  void _drawDelRegionLasso(Canvas canvas, FittedImageRect fit) {
    final pts = delRegionPoints
        .map((p) => fit.imageToWidget(p.x, p.y))
        .toList();

    // Draw filled polygon with semi-transparent red
    if (pts.length >= 3) {
      final fillPath = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (var i = 1; i < pts.length; i++) {
        fillPath.lineTo(pts[i].dx, pts[i].dy);
      }
      fillPath.close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..color = Colors.red.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill,
      );
    }

    // Draw stroke lines
    final strokePaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Dashed-style effect via individual segments
    for (var i = 0; i < pts.length - 1; i++) {
      canvas.drawLine(pts[i], pts[i + 1], strokePaint);
    }
    // Close line (dotted to show it will auto-close)
    if (pts.length >= 3) {
      final closePaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawLine(pts.last, pts.first, closePaint);
    }

    // Draw vertex dots
    final dotPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;
    for (final pt in pts) {
      canvas.drawCircle(pt, 4, dotPaint);
    }
  }

  void _drawNumberLabel(
    Canvas canvas,
    List<Offset> scaledPoints,
    int number,
    Color color,
  ) {
    // Compute centroid
    final cx = scaledPoints.map((p) => p.dx).reduce((a, b) => a + b) / 4;
    final cy = scaledPoints.map((p) => p.dy).reduce((a, b) => a + b) / 4;

    // Background circle
    const radius = 10.0;
    final bgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), radius, bgPaint);

    // White text
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$number',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(cx - textPainter.width / 2, cy - textPainter.height / 2),
    );
  }

  void _drawHandles(Canvas canvas, List<Offset> scaledPoints) {
    final handleRadius = 0.9 * selectedAnnotationScale;
    final handlePaint = Paint()
      ..color = AppColors.crystalSelected
      ..style = PaintingStyle.fill;
    final handleBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5 * selectedAnnotationScale;

    // Corner handles
    for (final point in scaledPoints) {
      canvas.drawCircle(point, handleRadius, handlePaint);
      canvas.drawCircle(point, handleRadius, handleBorderPaint);
    }
  }

  Color _colorForCrystal(Crystal crystal) {
    if (crystal.id == selectedId) return AppColors.crystalSelected;
    final isDiscarded = effectiveDiscarded?[crystal.id] ?? crystal.discarded;
    if (isDiscarded) return Colors.red;
    if (crystal.source == CrystalSource.operator) return AppColors.crystalHuman;
    return AppColors.crystalModel;
  }

  @override
  bool shouldRepaint(CrystalOverlayPainter oldDelegate) {
    return crystals != oldDelegate.crystals ||
        selectedId != oldDelegate.selectedId ||
        showHandles != oldDelegate.showHandles ||
        selectedAnnotationScale != oldDelegate.selectedAnnotationScale ||
        effectiveQuads != oldDelegate.effectiveQuads ||
        effectiveDiscarded != oldDelegate.effectiveDiscarded ||
        delRegionPoints != oldDelegate.delRegionPoints;
  }
}
