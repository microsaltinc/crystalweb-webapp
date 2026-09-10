import 'package:flutter/material.dart';

/// Compact bar showing keyboard shortcut hints, displayed in the metadata area.
class KeyboardShortcutsBar extends StatelessWidget {
  const KeyboardShortcutsBar({
    super.key,
    this.delRegionActive = false,
    this.onToggleDelRegion,
    this.onFinishDelRegion,
    this.onSubmit,
    this.editable = true,
  });

  /// Whether the del-region tool is currently active.
  final bool delRegionActive;

  /// Toggle del-region mode on/off.
  final VoidCallback? onToggleDelRegion;

  /// Finish drawing and confirm deletion.
  final VoidCallback? onFinishDelRegion;

  /// Submit changes.
  final VoidCallback? onSubmit;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
      fontSize: 10,
    );
    final keyStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      fontFamily: 'monospace',
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Wrap(
        spacing: 10,
        runSpacing: 2,
        alignment: WrapAlignment.center,
        children: [
          if (!editable)
            const Chip(
              avatar: Icon(Icons.lock, size: 14),
              label: Text('Read-only'),
              visualDensity: VisualDensity.compact,
            ),
          if (editable)
            _shortcut(style, keyStyle, '\u2190\u2191\u2192\u2193', 'Move'),
          if (editable)
            _shortcut(
              style,
              keyStyle,
              '1-4+\u2190\u2191\u2192\u2193',
              'Vertex',
            ),
          if (editable) _shortcut(style, keyStyle, '+/-', 'Size'),
          if (editable) _shortcut(style, keyStyle, '[ ]', 'Rotate'),
          if (editable) _shortcut(style, keyStyle, 'Del', 'Discard'),
          if (editable) _shortcut(style, keyStyle, 'Dbl-click', 'Add'),
          _shortcut(style, keyStyle, 'Esc', 'Deselect'),
          if (editable) _shortcut(style, keyStyle, '\u2318Z', 'Undo'),
          if (editable) _shortcut(style, keyStyle, '\u2318S', 'Submit'),
          if (editable) _delRegionButton(theme),
        ],
      ),
    );
  }

  Widget _delRegionButton(ThemeData theme) {
    if (delRegionActive) {
      // Show "F Finish" and "Esc Cancel" when drawing
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toolButton(
            theme,
            icon: Icons.check_circle_outline,
            label: 'F Finalize',
            color: Colors.red,
            onTap: onFinishDelRegion,
          ),
          const SizedBox(width: 4),
          _toolButton(
            theme,
            icon: Icons.cancel_outlined,
            label: 'Esc Cancel',
            color: theme.colorScheme.outline,
            onTap: onToggleDelRegion,
          ),
        ],
      );
    }
    return _toolButton(
      theme,
      icon: Icons.select_all,
      label: 'R Del Region',
      color: theme.colorScheme.error,
      onTap: onToggleDelRegion,
    );
  }

  Widget _toolButton(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(4),
          color: color.withValues(alpha: 0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shortcut(
    TextStyle? labelStyle,
    TextStyle? keyStyle,
    String key,
    String label,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: Colors.grey.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Text(key, style: keyStyle),
        ),
        const SizedBox(width: 2),
        Text(label, style: labelStyle),
      ],
    );
  }
}
