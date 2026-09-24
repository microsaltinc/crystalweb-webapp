import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'selected_annotation_size_storage_stub.dart'
    if (dart.library.js_interop) 'selected_annotation_size_storage_web.dart';

/// A display preference for this browser, independent of annotation geometry.
final selectedAnnotationSizeProvider =
    StateNotifierProvider<SelectedAnnotationSizeNotifier, int>((ref) {
      return SelectedAnnotationSizeNotifier();
    });

class SelectedAnnotationSizeNotifier extends StateNotifier<int> {
  SelectedAnnotationSizeNotifier({
    String? Function() read = readSelectedAnnotationSize,
    void Function(int) write = writeSelectedAnnotationSize,
  }) : _write = write,
       super(_load(read));

  final void Function(int) _write;

  static int _load(String? Function() read) {
    try {
      final value = int.tryParse(read() ?? '');
      if (value != null && value >= 1 && value <= 5) return value;
    } catch (_) {
      // Browsers can deny access to local storage. Keep the editor usable.
    }
    return 1;
  }

  /// Applies immediately; returns false if persistence is unavailable.
  bool setSize(int value) {
    RangeError.checkValueInInterval(value, 1, 5, 'value');
    state = value;
    try {
      _write(value);
      return true;
    } catch (_) {
      return false;
    }
  }
}
