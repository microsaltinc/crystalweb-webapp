import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BatchDateFilterChip extends StatelessWidget {
  const BatchDateFilterChip({
    required this.label,
    required this.date,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    super.key,
  });

  final String label;
  final DateTime? date;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final displayLabel = date != null
        ? '$label: ${DateFormat('MMM d').format(date!)}'
        : label;

    return InputChip(
      label: Text(displayLabel, style: const TextStyle(fontSize: 13)),
      selected: date != null,
      showCheckmark: false,
      deleteIcon: date != null ? const Icon(Icons.close, size: 16) : null,
      onDeleted: date != null ? () => onChanged(null) : null,
      onPressed: () async {
        final earliest = firstDate ?? DateTime(2024);
        final latest = lastDate ?? DateTime.now();
        var initial = date ?? DateTime.now().subtract(const Duration(days: 7));
        if (initial.isBefore(earliest)) initial = earliest;
        if (initial.isAfter(latest)) initial = latest;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: earliest,
          lastDate: latest,
        );
        if (picked != null) {
          onChanged(picked);
        }
      },
    );
  }
}

class BatchDropdownFilterChip extends StatelessWidget {
  const BatchDropdownFilterChip({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final displayLabel = value ?? label;

    return InputChip(
      label: Text(
        displayLabel,
        style: const TextStyle(fontSize: 13),
        overflow: TextOverflow.ellipsis,
      ),
      selected: value != null,
      showCheckmark: false,
      deleteIcon: value != null ? const Icon(Icons.close, size: 16) : null,
      onDeleted: value != null ? () => onChanged(null) : null,
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Select $label',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (_, index) => ListTile(
                      title: Text(options[index]),
                      selected: options[index] == value,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        onChanged(options[index]);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
