import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/crystal.dart';
import '../providers/annotation_provider.dart';

/// Panel showing crystal detections for an image.
/// Used as a side panel on desktop or bottom sheet on mobile.
class CrystalListPanel extends StatelessWidget {
  const CrystalListPanel({
    super.key,
    required this.crystals,
    required this.annotationState,
    required this.onSelect,
    required this.onToggleDiscard,
    required this.onMarkPartial,
    required this.onToggleShowDiscarded,
    required this.onToggleOverlay,
    required this.onToggleNumbers,
    required this.onSubmit,
    this.onNudge,
    this.onScale,
    this.onUndo,
    this.editingDisabled = false,
    this.editingDisabledReason,
    this.effectiveQuads,
    this.umPerPixel,
  });

  final List<Crystal> crystals;
  final AnnotationState annotationState;
  final ValueChanged<String?> onSelect;
  final ValueChanged<Crystal> onToggleDiscard;
  final void Function(Crystal crystal, bool partial) onMarkPartial;
  final VoidCallback onToggleShowDiscarded;
  final VoidCallback onToggleOverlay;
  final VoidCallback onToggleNumbers;
  final VoidCallback onSubmit;
  final void Function(double dx, double dy)? onNudge;
  final void Function(double factor)? onScale;
  final void Function(String crystalId)? onUndo;
  final bool editingDisabled;
  final String? editingDisabledReason;

  /// Effective quads for crystals with pending modifications.
  final Map<String, List<Point>>? effectiveQuads;

  /// Image calibration: micrometers per pixel.
  final double? umPerPixel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleCrystals = annotationState.showDiscarded
        ? crystals
        : crystals.where((c) => !_isEffectivelyDiscarded(c)).toList();

    final selectedCrystal = annotationState.selectedCrystalId != null
        ? crystals
              .where((c) => c.id == annotationState.selectedCrystalId)
              .firstOrNull
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header — row 1: crystal count
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Icon(Icons.grain, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Crystals (${crystals.length})',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // Header — row 2: toggle icons
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Tooltip(
                message: annotationState.showOverlay
                    ? 'Hide annotations'
                    : 'Show annotations',
                child: IconButton(
                  icon: Icon(
                    annotationState.showOverlay
                        ? Icons.visibility
                        : Icons.visibility_off,
                    size: 20,
                  ),
                  onPressed: onToggleOverlay,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: annotationState.showNumbers
                    ? 'Hide crystal numbers'
                    : 'Show crystal numbers',
                child: IconButton(
                  icon: Icon(
                    annotationState.showNumbers
                        ? Icons.format_list_numbered
                        : Icons.format_list_numbered_rtl,
                    size: 20,
                    color: annotationState.showNumbers
                        ? null
                        : theme.colorScheme.outline,
                  ),
                  onPressed: onToggleNumbers,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ),
              const Spacer(),
              Tooltip(
                message: annotationState.showDiscarded
                    ? 'Hide discarded'
                    : 'Show discarded',
                child: IconButton(
                  icon: Icon(
                    annotationState.showDiscarded
                        ? Icons.delete_outline
                        : Icons.delete_forever_outlined,
                    size: 20,
                  ),
                  onPressed: onToggleShowDiscarded,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Control buttons (shown when a crystal is selected)
        if (selectedCrystal != null) ...[
          _ControlButtonsRow(
            crystal: selectedCrystal,
            isDiscarded: _isEffectivelyDiscarded(selectedCrystal),
            hasChange: annotationState.changes.containsKey(selectedCrystal.id),
            onNudge: editingDisabled ? null : onNudge,
            onScale: editingDisabled ? null : onScale,
            onToggleDiscard: editingDisabled
                ? null
                : () => onToggleDiscard(selectedCrystal),
            onUndo: !editingDisabled && onUndo != null
                ? () => onUndo!(selectedCrystal.id)
                : null,
          ),
          const Divider(height: 1),
        ],
        // Crystal list
        Expanded(
          child: visibleCrystals.isEmpty
              ? Center(
                  child: Text(
                    'No crystals detected',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: visibleCrystals.length,
                  itemBuilder: (context, index) {
                    final crystal = visibleCrystals[index];
                    final isSelected =
                        crystal.id == annotationState.selectedCrystalId;
                    final isDiscarded = _isEffectivelyDiscarded(crystal);
                    final hasChange = annotationState.changes.containsKey(
                      crystal.id,
                    );

                    // Compute effective measurements from quad when:
                    // - crystal has pending changes (modified quad), OR
                    // - server values are zero (not yet computed)
                    double effectiveArea = crystal.areaUm2;
                    double effectiveDiameter = crystal.bestDiameterUm;
                    if (effectiveQuads != null &&
                        umPerPixel != null &&
                        umPerPixel! > 0) {
                      final quad = effectiveQuads![crystal.id];
                      if (quad != null &&
                          (hasChange ||
                              effectiveArea <= 0 ||
                              effectiveDiameter <= 0)) {
                        effectiveArea = quadAreaUm2(quad, umPerPixel!);
                        effectiveDiameter = equivalentDiameterFromArea(
                          effectiveArea,
                        );
                      }
                    }

                    return _CrystalTile(
                      crystal: crystal,
                      index: index + 1,
                      isSelected: isSelected,
                      isDiscarded: isDiscarded,
                      hasChange: hasChange,
                      effectiveAreaUm2: effectiveArea,
                      effectiveDiameterUm: effectiveDiameter,
                      onTap: () => onSelect(isSelected ? null : crystal.id),
                      onToggleDiscard: editingDisabled
                          ? null
                          : () => onToggleDiscard(crystal),
                      onMarkPartial: editingDisabled
                          ? null
                          : (partial) => onMarkPartial(crystal, partial),
                    );
                  },
                ),
        ),
        // Editing disabled banner
        if (editingDisabled && editingDisabledReason != null) ...[
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.all(12.0),
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    editingDisabledReason!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        // Submit bar
        if (annotationState.hasChanges && !editingDisabled) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: FilledButton.icon(
              onPressed: annotationState.isSubmitting ? null : onSubmit,
              icon: annotationState.isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text('Submit ${annotationState.changes.length} change(s)'),
            ),
          ),
        ],
        if (annotationState.submitError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Text(
              annotationState.submitError!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ),
      ],
    );
  }

  bool _isEffectivelyDiscarded(Crystal crystal) {
    final change = annotationState.changes[crystal.id];
    if (change?.discarded != null) return change!.discarded!;
    return crystal.discarded;
  }
}

/// Control buttons for nudging, scaling, discarding, and undoing changes
/// on the selected crystal.
class _ControlButtonsRow extends StatelessWidget {
  const _ControlButtonsRow({
    required this.crystal,
    required this.isDiscarded,
    required this.hasChange,
    this.onNudge,
    this.onScale,
    this.onToggleDiscard,
    this.onUndo,
  });

  final Crystal crystal;
  final bool isDiscarded;
  final bool hasChange;
  final void Function(double dx, double dy)? onNudge;
  final void Function(double factor)? onScale;
  final VoidCallback? onToggleDiscard;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 2,
        children: [
          _compactButton(
            icon: Icons.arrow_upward,
            tooltip: 'Nudge up',
            onPressed: onNudge != null ? () => onNudge!(0, -5) : null,
          ),
          _compactButton(
            icon: Icons.arrow_downward,
            tooltip: 'Nudge down',
            onPressed: onNudge != null ? () => onNudge!(0, 5) : null,
          ),
          _compactButton(
            icon: Icons.arrow_back,
            tooltip: 'Nudge left',
            onPressed: onNudge != null ? () => onNudge!(-5, 0) : null,
          ),
          _compactButton(
            icon: Icons.arrow_forward,
            tooltip: 'Nudge right',
            onPressed: onNudge != null ? () => onNudge!(5, 0) : null,
          ),
          const SizedBox(width: 4),
          _compactButton(
            icon: Icons.add_circle_outline,
            tooltip: 'Grow 5%  +',
            onPressed: onScale != null ? () => onScale!(1.05) : null,
          ),
          _compactButton(
            icon: Icons.remove_circle_outline,
            tooltip: 'Shrink 5%  \u2212',
            onPressed: onScale != null ? () => onScale!(0.95) : null,
          ),
          const SizedBox(width: 4),
          _compactButton(
            icon: Icons.delete_outline,
            tooltip: isDiscarded ? 'Undiscard' : 'Discard',
            onPressed: onToggleDiscard,
            color: isDiscarded ? AppColors.success : AppColors.error,
          ),
          if (hasChange)
            _compactButton(
              icon: Icons.undo,
              tooltip: 'Undo changes',
              onPressed: onUndo,
            ),
        ],
      ),
    );
  }

  Widget _compactButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18, color: color),
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }
}

class _CrystalTile extends StatelessWidget {
  const _CrystalTile({
    required this.crystal,
    required this.index,
    required this.isSelected,
    required this.isDiscarded,
    required this.hasChange,
    required this.effectiveAreaUm2,
    required this.effectiveDiameterUm,
    required this.onTap,
    required this.onToggleDiscard,
    required this.onMarkPartial,
  });

  final Crystal crystal;
  final int index;
  final bool isSelected;
  final bool isDiscarded;
  final bool hasChange;
  final double effectiveAreaUm2;
  final double effectiveDiameterUm;
  final VoidCallback onTap;
  final VoidCallback? onToggleDiscard;
  final ValueChanged<bool>? onMarkPartial;

  Color get _labelColor {
    if (isDiscarded) return AppColors.crystalDiscarded;
    if (crystal.source == CrystalSource.operator) return AppColors.crystalHuman;
    return AppColors.crystalModel;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      selected: isSelected,
      selectedTileColor: AppColors.crystalSelected.withValues(alpha: 0.12),
      onTap: onTap,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: _labelColor,
        child: Text(
          '$index',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        '\u2300 ${effectiveDiameterUm.toStringAsFixed(1)} \u00B5m   ${effectiveAreaUm2.toStringAsFixed(1)} \u00B5m\u00B2',
        style: theme.textTheme.bodyMedium?.copyWith(
          decoration: isDiscarded ? TextDecoration.lineThrough : null,
          color: isDiscarded ? theme.colorScheme.outline : null,
        ),
      ),
      subtitle: Row(
        children: [
          Text(
            hasChange
                ? '100%'
                : '${(crystal.confidence * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          _SourceBadge(
            source: hasChange ? CrystalSource.operator : crystal.source,
          ),
          if (hasChange) ...[
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 12, color: theme.colorScheme.primary),
          ],
        ],
      ),
      trailing: isSelected
          ? _CrystalActions(
              crystal: crystal,
              isDiscarded: isDiscarded,
              onToggleDiscard: onToggleDiscard,
              onMarkPartial: onMarkPartial,
            )
          : null,
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final CrystalSource source;

  @override
  Widget build(BuildContext context) {
    final isOperator = source == CrystalSource.operator;
    final color = isOperator ? AppColors.crystalHuman : AppColors.crystalModel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isOperator ? 'operator' : 'auto',
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}

class _CrystalActions extends StatelessWidget {
  const _CrystalActions({
    required this.crystal,
    required this.isDiscarded,
    required this.onToggleDiscard,
    required this.onMarkPartial,
  });

  final Crystal crystal;
  final bool isDiscarded;
  final VoidCallback? onToggleDiscard;
  final ValueChanged<bool>? onMarkPartial;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: isDiscarded ? 'Accept' : 'Reject',
          child: IconButton(
            icon: Icon(
              isDiscarded ? Icons.check_circle_outline : Icons.cancel_outlined,
              size: 20,
              color: isDiscarded ? AppColors.success : AppColors.error,
            ),
            onPressed: onToggleDiscard,
            visualDensity: VisualDensity.compact,
          ),
        ),
        Tooltip(
          message: crystal.partialVisible ? 'Unmark partial' : 'Mark partial',
          child: IconButton(
            icon: Icon(
              Icons.crop_free,
              size: 20,
              color: crystal.partialVisible
                  ? AppColors.warning
                  : Theme.of(context).colorScheme.outline,
            ),
            onPressed: onMarkPartial == null
                ? null
                : () => onMarkPartial!(!crystal.partialVisible),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}
