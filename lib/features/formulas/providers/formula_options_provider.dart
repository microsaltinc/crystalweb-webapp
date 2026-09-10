import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../models/formula_option.dart';
import '../models/formula.dart';

/// Provider that fetches formula options for a given category from the API.
/// Falls back to hardcoded defaults if API fails.
final formulaOptionsProvider = FutureProvider.autoDispose
    .family<List<FormulaOption>, String>((ref, category) async {
  final client = ref.watch(apiClientProvider);
  try {
    final response = await client.dio.get(
      '/api/v1/formulas/options',
      queryParameters: {'category': category},
    );
    final data = response.data as List;
    final options = data
        .map((j) => FormulaOption.fromJson(j as Map<String, dynamic>))
        .toList();
    if (options.isNotEmpty) return options;
  } catch (_) {
    // Fall back to hardcoded defaults
  }
  return _fallbackOptions(category);
});

/// Creates a new formula option via the API and invalidates the cache.
Future<FormulaOption> addFormulaOption(
  ApiClient client,
  WidgetRef ref, {
  required String category,
  required String code,
  required String label,
}) async {
  final response = await client.dio.post(
    '/api/v1/formulas/options',
    data: {'category': category, 'code': code, 'label': label},
  );
  ref.invalidate(formulaOptionsProvider(category));
  return FormulaOption.fromJson(response.data as Map<String, dynamic>);
}

/// Fallback options from hardcoded FormulaCodeBuilder maps.
List<FormulaOption> _fallbackOptions(String category) {
  switch (category) {
    case 'salt_origin':
      return FormulaCodeBuilder.saltOriginLabels.entries
          .map((e) => FormulaOption(
                id: '', category: category, code: e.key,
                label: e.value, active: true, sortOrder: 0,
              ))
          .toList();
    case 'carrier_origin':
      return FormulaCodeBuilder.carrierOriginLabels.entries
          .map((e) => FormulaOption(
                id: '', category: category, code: e.key,
                label: e.value, active: true, sortOrder: 0,
              ))
          .toList();
    case 'region':
      return FormulaCodeBuilder.regionLabels.entries
          .map((e) => FormulaOption(
                id: '', category: category, code: e.key,
                label: e.value, active: true, sortOrder: 0,
              ))
          .toList();
    case 'salt_pct':
      return FormulaCodeBuilder.validSaltPcts
          .map((p) => FormulaOption(
                id: '', category: category, code: p.toString(),
                label: '$p%', active: true, sortOrder: p,
              ))
          .toList();
    case 'iodine':
      return FormulaCodeBuilder.iodineLabels.entries
          .map((e) => FormulaOption(
                id: '', category: category, code: e.key,
                label: e.value, active: true, sortOrder: 0,
              ))
          .toList();
    case 'gmo_status':
      return FormulaCodeBuilder.gmoStatusLabels.entries
          .map((e) => FormulaOption(
                id: '', category: category, code: e.key,
                label: e.value, active: true, sortOrder: 0,
              ))
          .toList();
    case 'extra_ingredient':
      return [
        FormulaOption(id: '', category: category, code: 'VIT', label: 'Vitamin D', active: true, sortOrder: 0),
        FormulaOption(id: '', category: category, code: 'KC', label: 'Potassium Chloride', active: true, sortOrder: 1),
        FormulaOption(id: '', category: category, code: 'CA', label: 'Calcium Carbonate', active: true, sortOrder: 2),
        FormulaOption(id: '', category: category, code: 'FE', label: 'Iron', active: true, sortOrder: 3),
      ];
    default:
      return [];
  }
}
