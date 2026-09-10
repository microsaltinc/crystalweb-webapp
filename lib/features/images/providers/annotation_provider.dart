import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_error.dart';
import '../../batches/providers/campaign_locking_provider.dart';
import '../../../core/api/user_facing_error.dart';
import '../models/crystal.dart';
import 'image_provider.dart';

/// Represents a single annotation change to be submitted.
class AnnotationChange {
  AnnotationChange({
    required this.crystalId,
    this.discarded,
    this.quad,
    this.partialVisible,
  });

  final String crystalId;
  final bool? discarded;
  final List<Point>? quad;
  final bool? partialVisible;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'crystal_id': crystalId};
    if (discarded != null) map['discarded'] = discarded;
    if (quad != null) map['quad'] = quad!.map((p) => p.toJson()).toList();
    if (partialVisible != null) map['partial_visible'] = partialVisible;
    // Any operator edit promotes source to operator and confidence to 100%
    map['source'] = 'operator';
    map['confidence'] = 1.0;
    return map;
  }
}

/// Tracks the editing state for annotations on an image.
class AnnotationState {
  const AnnotationState({
    this.selectedCrystalId,
    this.showDiscarded = false,
    this.showOverlay = true,
    this.showNumbers = false,
    this.changes = const {},
    this.isSubmitting = false,
    this.submitError,
    this.readOnlyDueToConflict = false,
    this.delRegionActive = false,
    this.delRegionPoints = const [],
  });

  final String? selectedCrystalId;
  final bool showDiscarded;

  /// Whether crystal annotation overlay is visible on the image.
  final bool showOverlay;

  /// Whether crystal number labels are shown on the overlay.
  final bool showNumbers;
  final Map<String, AnnotationChange> changes;
  final bool isSubmitting;
  final String? submitError;

  /// Set after a late server lock/state conflict. Local edits are intentionally
  /// retained, but every further mutation and automatic retry is disabled.
  final bool readOnlyDueToConflict;

  /// Whether the "Del Region" tool is active (drawing a lasso).
  final bool delRegionActive;

  /// Polygon vertices for the del-region lasso, in image coordinates.
  final List<Point> delRegionPoints;

  AnnotationState copyWith({
    String? selectedCrystalId,
    bool clearSelection = false,
    bool? showDiscarded,
    bool? showOverlay,
    bool? showNumbers,
    Map<String, AnnotationChange>? changes,
    bool? isSubmitting,
    String? submitError,
    bool clearError = false,
    bool? readOnlyDueToConflict,
    bool? delRegionActive,
    List<Point>? delRegionPoints,
  }) {
    return AnnotationState(
      selectedCrystalId: clearSelection
          ? null
          : (selectedCrystalId ?? this.selectedCrystalId),
      showDiscarded: showDiscarded ?? this.showDiscarded,
      showOverlay: showOverlay ?? this.showOverlay,
      showNumbers: showNumbers ?? this.showNumbers,
      changes: changes ?? this.changes,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitError: clearError ? null : (submitError ?? this.submitError),
      readOnlyDueToConflict:
          readOnlyDueToConflict ?? this.readOnlyDueToConflict,
      delRegionActive: delRegionActive ?? this.delRegionActive,
      delRegionPoints: delRegionPoints ?? this.delRegionPoints,
    );
  }

  bool get hasChanges => changes.isNotEmpty;
  bool get canMutate => !readOnlyDueToConflict && !isSubmitting;
}

/// Notifier that manages annotation editing for a single image.
class AnnotationNotifier extends StateNotifier<AnnotationState> {
  AnnotationNotifier(this._ref, this._imageId) : super(const AnnotationState());

  final Ref _ref;
  final String _imageId;
  String? _observedBatchId;
  int? _observedEditStateVersion;
  bool? _observedEditable;

  /// Synchronizes server authority loaded by the image/deep-link screen. This
  /// is deliberately kept outside [AnnotationState], so refreshing authority
  /// cannot overwrite pending geometry, selection, or undo information.
  void setCampaignAuthority({
    required String batchId,
    required int editStateVersion,
    required bool editable,
  }) {
    _observedBatchId = batchId;
    _observedEditStateVersion = editStateVersion;
    _observedEditable = editable;
  }

  void selectCrystal(String? crystalId) {
    state = state.copyWith(
      selectedCrystalId: crystalId,
      clearSelection: crystalId == null,
    );
  }

  void toggleShowDiscarded() {
    state = state.copyWith(showDiscarded: !state.showDiscarded);
  }

  void toggleOverlay() {
    state = state.copyWith(showOverlay: !state.showOverlay);
  }

  void toggleNumbers() {
    state = state.copyWith(showNumbers: !state.showNumbers);
  }

  void toggleDiscard(Crystal crystal) {
    if (!state.canMutate) return;
    // Check if there's already a pending change for this crystal
    final existingChange = state.changes[crystal.id];
    final currentEffective = existingChange?.discarded ?? crystal.discarded;
    final newDiscarded = !currentEffective;

    // If toggling back to original state, remove the change
    if (newDiscarded == crystal.discarded) {
      final changes = Map<String, AnnotationChange>.from(state.changes);
      changes.remove(crystal.id);
      state = state.copyWith(changes: changes);
    } else {
      final changes = Map<String, AnnotationChange>.from(state.changes);
      changes[crystal.id] = AnnotationChange(
        crystalId: crystal.id,
        discarded: newDiscarded,
      );
      state = state.copyWith(changes: changes);
    }
  }

  void markPartial(Crystal crystal, bool partial) {
    if (!state.canMutate) return;
    final changes = Map<String, AnnotationChange>.from(state.changes);
    final existing = changes[crystal.id];
    changes[crystal.id] = AnnotationChange(
      crystalId: crystal.id,
      discarded: existing?.discarded,
      quad: existing?.quad,
      partialVisible: partial,
    );
    state = state.copyWith(changes: changes);
  }

  void updateQuad(Crystal crystal, List<Point> newQuad) {
    if (!state.canMutate) return;
    final changes = Map<String, AnnotationChange>.from(state.changes);
    final existing = changes[crystal.id];
    changes[crystal.id] = AnnotationChange(
      crystalId: crystal.id,
      discarded: existing?.discarded,
      quad: newQuad,
      partialVisible: existing?.partialVisible,
    );
    state = state.copyWith(changes: changes);
  }

  /// Returns the effective quad for a crystal, considering pending changes.
  List<Point> effectiveQuad(Crystal crystal) {
    final change = state.changes[crystal.id];
    return change?.quad ?? crystal.quad;
  }

  /// Translates all 4 points of a crystal's quad by (dx, dy) in image pixels.
  void nudgeQuad(Crystal crystal, double dx, double dy) {
    if (!state.canMutate) return;
    final currentQuad = effectiveQuad(crystal);
    final newQuad = currentQuad.map((p) => Point(p.x + dx, p.y + dy)).toList();
    updateQuad(crystal, newQuad);
  }

  /// Moves a single vertex of a crystal's quad by (dx, dy) in image pixels.
  /// cornerIndex: 0=top-left, 1=top-right, 2=bottom-left, 3=bottom-right.
  void nudgeCorner(Crystal crystal, int cornerIndex, double dx, double dy) {
    if (!state.canMutate) return;
    final currentQuad = effectiveQuad(crystal);
    if (currentQuad.length != 4 || cornerIndex < 0 || cornerIndex > 3) return;
    final newQuad = List<Point>.from(currentQuad);
    newQuad[cornerIndex] = Point(
      currentQuad[cornerIndex].x + dx,
      currentQuad[cornerIndex].y + dy,
    );
    updateQuad(crystal, newQuad);
  }

  /// Rotates a crystal's quad by [degrees] around its centroid.
  void rotateQuad(Crystal crystal, double degrees) {
    if (!state.canMutate) return;
    final currentQuad = effectiveQuad(crystal);
    if (currentQuad.length != 4) return;

    // Compute centroid
    final cx = currentQuad.map((p) => p.x).reduce((a, b) => a + b) / 4;
    final cy = currentQuad.map((p) => p.y).reduce((a, b) => a + b) / 4;

    final radians = degrees * math.pi / 180;
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);

    final newQuad = currentQuad.map((p) {
      final dx = p.x - cx;
      final dy = p.y - cy;
      return Point(cx + dx * cosA - dy * sinA, cy + dx * sinA + dy * cosA);
    }).toList();

    updateQuad(crystal, newQuad);
  }

  /// Scales a crystal's quad by [factor] around its centroid.
  /// factor=1.05 means 5% larger, 0.95 means 5% smaller.
  void scaleQuad(Crystal crystal, double factor) {
    if (!state.canMutate) return;
    final currentQuad = effectiveQuad(crystal);
    if (currentQuad.length != 4) return;

    final cx = currentQuad.map((p) => p.x).reduce((a, b) => a + b) / 4;
    final cy = currentQuad.map((p) => p.y).reduce((a, b) => a + b) / 4;

    final newQuad = currentQuad.map((p) {
      return Point(cx + (p.x - cx) * factor, cy + (p.y - cy) * factor);
    }).toList();

    updateQuad(crystal, newQuad);
  }

  /// Removes any pending change for the given crystal.
  void undoChange(String crystalId) {
    if (!state.canMutate) return;
    final changes = Map<String, AnnotationChange>.from(state.changes);
    changes.remove(crystalId);
    state = state.copyWith(changes: changes);
  }

  // --- Del Region tool ---

  /// Toggle the del-region drawing mode on/off.
  void toggleDelRegion() {
    if (!state.canMutate) return;
    if (state.delRegionActive) {
      // Cancel — clear points and deactivate
      state = state.copyWith(
        delRegionActive: false,
        delRegionPoints: const [],
        clearSelection: true,
      );
    } else {
      state = state.copyWith(
        delRegionActive: true,
        delRegionPoints: const [],
        clearSelection: true,
      );
    }
  }

  /// Add a vertex to the del-region polygon (image coordinates).
  void addDelRegionPoint(double x, double y) {
    if (!state.canMutate) return;
    if (!state.delRegionActive) return;
    final pts = List<Point>.from(state.delRegionPoints)..add(Point(x, y));
    state = state.copyWith(delRegionPoints: pts);
  }

  /// Close the region and return crystal IDs whose centroids fall inside.
  List<Crystal> finishDelRegion(List<Crystal> crystals) {
    if (!state.canMutate) return [];
    final polygon = state.delRegionPoints;
    if (polygon.length < 3) {
      // Not enough points — cancel
      state = state.copyWith(delRegionActive: false, delRegionPoints: const []);
      return [];
    }

    // Find crystals whose centroid is inside the polygon
    final inside = <Crystal>[];
    for (final crystal in crystals) {
      final quad = effectiveQuad(crystal);
      if (quad.isEmpty) continue;
      // Compute centroid of the crystal quad
      final cx = quad.map((p) => p.x).reduce((a, b) => a + b) / quad.length;
      final cy = quad.map((p) => p.y).reduce((a, b) => a + b) / quad.length;
      if (_pointInPolygon(cx, cy, polygon)) {
        inside.add(crystal);
      }
    }
    return inside;
  }

  /// Discard all the given crystals (mark as discarded in pending changes).
  void discardMultiple(List<Crystal> crystals) {
    if (!state.canMutate) return;
    final changes = Map<String, AnnotationChange>.from(state.changes);
    for (final c in crystals) {
      changes[c.id] = AnnotationChange(crystalId: c.id, discarded: true);
    }
    state = state.copyWith(
      changes: changes,
      delRegionActive: false,
      delRegionPoints: const [],
    );
  }

  /// Cancel del-region mode without applying.
  void cancelDelRegion() {
    if (!state.canMutate) return;
    state = state.copyWith(delRegionActive: false, delRegionPoints: const []);
  }

  /// Ray-casting point-in-polygon test.
  static bool _pointInPolygon(double px, double py, List<Point> polygon) {
    var inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].x, yi = polygon[i].y;
      final xj = polygon[j].x, yj = polygon[j].y;
      final intersect =
          ((yi > py) != (yj > py)) &&
          (px < (xj - xi) * (py - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// Add a new crystal annotation at a given position (image coords).
  /// Creates a small default quad (40x40 px) centered at the point.
  void addCrystalAt(double x, double y) {
    if (!state.canMutate) return;
    // We'll use the submit endpoint's additions list for new crystals.
    // For now, track additions separately in state as a special change.
    // The Crystal model requires an ID — we generate a temporary one.
    final tempId = 'new-${DateTime.now().millisecondsSinceEpoch}';
    const halfSize = 60.0;
    final quad = [
      Point(x - halfSize, y - halfSize),
      Point(x + halfSize, y - halfSize),
      Point(x + halfSize, y + halfSize),
      Point(x - halfSize, y + halfSize),
    ];
    final changes = Map<String, AnnotationChange>.from(state.changes);
    changes[tempId] = AnnotationChange(crystalId: tempId, quad: quad);
    state = state.copyWith(changes: changes);
  }

  Future<bool> submit() async {
    if (!state.hasChanges) return true;
    if (!state.canMutate) return false;

    if (_observedEditable == false) {
      state = state.copyWith(
        readOnlyDueToConflict: true,
        submitError:
            'This campaign was locked elsewhere. Your unsaved edits are still available locally.',
      );
      if (_observedBatchId != null) {
        refreshImageStateFromProvider(_ref, _imageId, _observedBatchId!);
      }
      return false;
    }

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final client = _ref.read(apiClientProvider);
      final updates = <Map<String, dynamic>>[];
      final additions = <Map<String, dynamic>>[];
      for (final change in state.changes.values) {
        if (change.crystalId.startsWith('new-')) {
          if (change.quad != null) {
            additions.add({
              'quad': change.quad!.map((p) => p.toJson()).toList(),
            });
          }
        } else {
          updates.add(change.toJson());
        }
      }

      await client.dio.post(
        '/api/v1/images/$_imageId/annotations/submit',
        data: {
          'updates': updates,
          'deletions': <String>[],
          'additions': additions,
        },
        options: _observedEditStateVersion == null
            ? null
            : Options(
                headers: {
                  'If-Match': campaignEditETag(_observedEditStateVersion!),
                },
              ),
      );
      state = state.copyWith(isSubmitting: false, changes: const {});
      if (_observedBatchId != null) {
        refreshImageStateFromProvider(_ref, _imageId, _observedBatchId!);
      }
      _ref.invalidate(crystalsForImageProvider(_imageId));
      return true;
    } catch (error) {
      final structured = ApiError.tryParse(error);
      final isLateConflict =
          structured?.code == 'campaign_locked' ||
          structured?.code == 'campaign_state_conflict';
      state = state.copyWith(
        isSubmitting: false,
        readOnlyDueToConflict: isLateConflict ? true : null,
        submitError: isLateConflict
            ? 'This campaign was locked or changed elsewhere. Your unsaved edits are still available locally.'
            : userFacingError(error, action: 'submit annotations'),
      );
      // Refresh authority and all report/readiness surfaces, but deliberately
      // never clear, retry, or resubmit local annotation state.
      if (_observedBatchId != null) {
        refreshImageStateFromProvider(_ref, _imageId, _observedBatchId!);
      }
      return false;
    }
  }
}

/// Family provider for annotation state, keyed by imageId.
final annotationProvider = StateNotifierProvider.autoDispose
    .family<AnnotationNotifier, AnnotationState, String>(
      (ref, imageId) => AnnotationNotifier(ref, imageId),
    );
