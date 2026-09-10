import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../models/formula_option.dart';
import '../providers/formula_options_provider.dart';

/// A dropdown that fetches options from the API and allows adding new ones
/// via a "+" button that opens a management dialog.
class EditableDropdown extends ConsumerWidget {
  const EditableDropdown({
    super.key,
    required this.category,
    required this.value,
    required this.onChanged,
    required this.labelText,
    this.isNumeric = false,
    this.nullable = false,
  });

  final String category;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String labelText;
  final bool isNumeric;
  final bool nullable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optionsAsync = ref.watch(formulaOptionsProvider(category));

    return optionsAsync.when(
      data: (options) => _buildRow(context, ref, options),
      loading: () => Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: value,
              decoration: InputDecoration(labelText: labelText),
              items: const [],
              onChanged: null,
            ),
          ),
          const SizedBox(width: 8),
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ),
      error: (e, _) => _buildRow(context, ref, []),
    );
  }

  Widget _buildRow(
    BuildContext context,
    WidgetRef ref,
    List<FormulaOption> options,
  ) {
    // Ensure current value is in the list (might be a custom value not yet loaded)
    final hasValue = value == null || options.any((o) => o.code == value);
    final items = <DropdownMenuItem<String>>[
      // Allow clearing the selection (for optional fields like Region)
      if (nullable) const DropdownMenuItem(value: null, child: Text('None')),
      ...options.map(
        (o) => DropdownMenuItem(
          value: o.code,
          child: Text('${o.label} (${o.code})'),
        ),
      ),
    ];

    // If value not in options, add it temporarily
    if (!hasValue && value != null) {
      items.add(DropdownMenuItem(value: value, child: Text(value!)));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: value,
            decoration: InputDecoration(labelText: labelText),
            items: items,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, size: 22),
          tooltip: 'Add new $labelText',
          onPressed: () => _showAddDialog(context, ref, options),
        ),
      ],
    );
  }

  void _showAddDialog(
    BuildContext context,
    WidgetRef ref,
    List<FormulaOption> options,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => _AddOptionDialog(
        category: category,
        labelText: labelText,
        existingOptions: options,
        isNumeric: isNumeric,
        onAdded: (code) {
          onChanged(code);
        },
      ),
    );
  }
}

class _AddOptionDialog extends ConsumerStatefulWidget {
  const _AddOptionDialog({
    required this.category,
    required this.labelText,
    required this.existingOptions,
    required this.isNumeric,
    required this.onAdded,
  });

  final String category;
  final String labelText;
  final List<FormulaOption> existingOptions;
  final bool isNumeric;
  final ValueChanged<String> onAdded;

  @override
  ConsumerState<_AddOptionDialog> createState() => _AddOptionDialogState();
}

class _AddOptionDialogState extends ConsumerState<_AddOptionDialog> {
  final _codeController = TextEditingController();
  final _labelController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _codeController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _handleAdd() async {
    final code = _codeController.text.trim().toUpperCase();
    final label = widget.isNumeric ? '$code%' : _labelController.text.trim();

    if (code.isEmpty) {
      setState(
        () => _error = widget.isNumeric ? 'Enter a number' : 'Code is required',
      );
      return;
    }
    if (!widget.isNumeric && label.isEmpty) {
      setState(() => _error = 'Label is required');
      return;
    }
    if (widget.isNumeric) {
      final num = int.tryParse(code);
      if (num == null || num < 1 || num > 99) {
        setState(() => _error = 'Enter a valid percentage (1-99)');
        return;
      }
    }
    if (widget.existingOptions.any((o) => o.code == code)) {
      setState(() => _error = 'Code "$code" already exists');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final client = ref.read(apiClientProvider);
      await addFormulaOption(
        client,
        ref,
        category: widget.category,
        code: code,
        label: label,
      );
      if (mounted) {
        Navigator.of(context).pop();
        widget.onAdded(code);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userFacingError(e, action: 'add option');
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text('Manage ${widget.labelText}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Existing options
            Text('Current options:', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: widget.existingOptions
                  .map(
                    (o) => Chip(
                      label: Text(
                        widget.isNumeric ? o.label : '${o.label} (${o.code})',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  )
                  .toList(),
            ),
            const Divider(height: 24),
            // Add new
            Text('Add new:', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            if (widget.isNumeric)
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'Percentage',
                  hintText: 'e.g. 80',
                  suffixText: '%',
                ),
                keyboardType: TextInputType.number,
              )
            else ...[
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        hintText: 'e.g. RS',
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _labelController,
                      decoration: const InputDecoration(
                        labelText: 'Label',
                        hintText: 'e.g. Rock Salt',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        _saving
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : ElevatedButton(onPressed: _handleAdd, child: const Text('Add')),
      ],
    );
  }
}
