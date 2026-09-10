import 'dart:ui';

/// Computes the actual rendered rect of an image displayed with BoxFit.contain
/// within a widget of [widgetSize].
///
/// Returns a Rect representing where the image actually appears (with offset
/// for letterboxing) and uniform scale factor.
class FittedImageRect {
  FittedImageRect({
    required Size imageSize,
    required Size widgetSize,
  }) {
    final imageAspect = imageSize.width / imageSize.height;
    final widgetAspect = widgetSize.width / widgetSize.height;

    if (imageAspect > widgetAspect) {
      // Image is wider — fits width, letterbox top/bottom
      final renderedWidth = widgetSize.width;
      final renderedHeight = widgetSize.width / imageAspect;
      offsetX = 0;
      offsetY = (widgetSize.height - renderedHeight) / 2;
      scale = renderedWidth / imageSize.width;
    } else {
      // Image is taller — fits height, letterbox left/right
      final renderedHeight = widgetSize.height;
      final renderedWidth = widgetSize.height * imageAspect;
      offsetX = (widgetSize.width - renderedWidth) / 2;
      offsetY = (widgetSize.height - renderedHeight) / 2;
      scale = renderedHeight / imageSize.height;
    }
  }

  /// Offset from widget top-left to where the image starts.
  late final double offsetX;
  late final double offsetY;

  /// Uniform scale: image pixels * scale = widget pixels (within the fitted rect).
  late final double scale;

  /// Convert image coordinates to widget coordinates.
  Offset imageToWidget(double imgX, double imgY) {
    return Offset(imgX * scale + offsetX, imgY * scale + offsetY);
  }

  /// Convert widget coordinates to image coordinates.
  /// Returns null if the point is outside the rendered image area.
  Offset widgetToImage(Offset widgetPos) {
    return Offset(
      (widgetPos.dx - offsetX) / scale,
      (widgetPos.dy - offsetY) / scale,
    );
  }
}
