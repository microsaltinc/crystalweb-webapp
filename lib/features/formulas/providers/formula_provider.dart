import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/role_scope_provider.dart';
import '../models/formula.dart';

final formulaListProvider =
    FutureProvider.autoDispose<List<Formula>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final scope = ref.watch(roleScopeProvider);
  final queryParams = <String, dynamic>{};
  final isTestingFilter = scope.isTestingFilter;
  if (isTestingFilter != null) {
    queryParams['is_testing'] = isTestingFilter.toString();
  }
  final response = await client.dio.get(
    '/api/v1/formulas',
    queryParameters: queryParams,
  );
  final data = response.data as List;
  return data
      .map((j) => Formula.fromJson(j as Map<String, dynamic>))
      .toList();
});

final formulaDetailProvider =
    FutureProvider.autoDispose.family<Formula, String>((ref, id) async {
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/api/v1/formulas/$id');
  return Formula.fromJson(response.data as Map<String, dynamic>);
});

/// Creates a new formula via POST. Returns the created formula.
Future<Formula> createFormula(
    ApiClient client, Map<String, dynamic> data) async {
  final response = await client.dio.post('/api/v1/formulas', data: data);
  return Formula.fromJson(response.data as Map<String, dynamic>);
}

/// Updates an existing formula via PUT. Returns the updated formula.
Future<Formula> updateFormula(
    ApiClient client, String id, Map<String, dynamic> data) async {
  final response =
      await client.dio.put('/api/v1/formulas/$id', data: data);
  return Formula.fromJson(response.data as Map<String, dynamic>);
}

/// Deletes a formula by ID.
Future<void> deleteFormula(ApiClient client, String id) async {
  await client.dio.delete('/api/v1/formulas/$id');
}
