import 'dart:math' as math;

enum CrystalSource { auto, operator }

class Point {
  const Point(this.x, this.y);

  factory Point.fromJson(List<dynamic> json) =>
      Point((json[0] as num).toDouble(), (json[1] as num).toDouble());

  final double x;
  final double y;

  List<double> toJson() => [x, y];
}

/// Computes the area of a quad (polygon) in pixels using the Shoelace formula.
double quadAreaPx(List<Point> quad) {
  if (quad.length < 3) return 0.0;
  double sum = 0.0;
  for (int i = 0; i < quad.length; i++) {
    final j = (i + 1) % quad.length;
    sum += quad[i].x * quad[j].y;
    sum -= quad[j].x * quad[i].y;
  }
  return sum.abs() / 2.0;
}

/// Computes area in µm² from a quad and the image calibration.
double quadAreaUm2(List<Point> quad, double umPerPixel) {
  return quadAreaPx(quad) * umPerPixel * umPerPixel;
}

/// Computes the equivalent diameter in µm from an area in µm².
/// Uses: diameter = sqrt(4 * area / π)
double equivalentDiameterFromArea(double areaUm2) {
  if (areaUm2 <= 0) return 0.0;
  return math.sqrt(4.0 * areaUm2 / math.pi);
}

class Crystal {
  Crystal({
    required this.id,
    required this.imageId,
    required this.quad,
    required this.confidence,
    required this.areaUm2,
    required this.equivalentDiameterUm,
    required this.partialVisible,
    required this.discarded,
    required this.source,
    this.diameterUm,
    this.shellAdjacent,
    this.areaPx,
  });

  factory Crystal.fromJson(Map<String, dynamic> json) {
    return Crystal(
      id: json['id'] as String,
      imageId: json['image_id'] as String,
      quad: (json['quad'] as List)
          .map((p) => Point.fromJson(p as List))
          .toList(),
      confidence: (json['confidence'] as num).toDouble(),
      areaUm2: (json['area_um2'] as num).toDouble(),
      equivalentDiameterUm: (json['equivalent_diameter_um'] as num).toDouble(),
      partialVisible: json['partial_visible'] as bool,
      discarded: json['discarded'] as bool,
      source: json['source'] == 'operator'
          ? CrystalSource.operator
          : CrystalSource.auto,
      diameterUm: json['diameter_um'] != null
          ? (json['diameter_um'] as num).toDouble()
          : null,
      shellAdjacent: json['shell_adjacent'] as bool?,
      areaPx: json['area_px'] != null
          ? (json['area_px'] as num).toDouble()
          : null,
    );
  }

  final String id;
  final String imageId;
  final List<Point> quad;
  final double confidence;
  final double areaUm2;
  final double equivalentDiameterUm;
  final bool partialVisible;
  final bool discarded;
  final CrystalSource source;
  final double? diameterUm;
  final bool? shellAdjacent;
  final double? areaPx;

  /// Returns the best available diameter: physical diameter if available,
  /// otherwise the equivalent diameter from area.
  double get bestDiameterUm => diameterUm ?? equivalentDiameterUm;

  bool isLarge({double thresholdUm = 1.0}) =>
      equivalentDiameterUm >= thresholdUm;

  Map<String, dynamic> toJson() => {
        'id': id,
        'image_id': imageId,
        'quad': quad.map((p) => p.toJson()).toList(),
        'confidence': confidence,
        'area_um2': areaUm2,
        'equivalent_diameter_um': equivalentDiameterUm,
        'partial_visible': partialVisible,
        'discarded': discarded,
        'source': source == CrystalSource.operator ? 'operator' : 'auto',
        'diameter_um': diameterUm,
        'shell_adjacent': shellAdjacent,
        'area_px': areaPx,
      };
}
