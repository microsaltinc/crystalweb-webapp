import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/selected_annotation_size_provider.dart';

class SelectedAnnotationSizeSetting extends ConsumerWidget {
  const SelectedAnnotationSizeSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(selectedAnnotationSizeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int>(
          key: ValueKey(size),
          initialValue: size,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Selected annotation size',
            border: OutlineInputBorder(),
          ),
          items: [
            for (var value = 1; value <= 5; value++)
              DropdownMenuItem(
                value: value,
                child: Text(value == 1 ? '1× (default)' : '$value×'),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            final saved = ref
                .read(selectedAnnotationSizeProvider.notifier)
                .setSize(value);
            if (!saved) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Size updated for this session. Your browser could not save it.',
                  ),
                ),
              );
            }
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Adjusts the selected outline and corner dots. '
          'Saved in this browser; applies to all microscope images.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
