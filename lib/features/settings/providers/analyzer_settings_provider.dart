import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// Fetches current analyzer settings from the API.
final analyzerSettingsProvider =
    FutureProvider.autoDispose<double>((ref) async {
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/api/v1/settings/analyzer');
  final data = response.data as Map<String, dynamic>;
  return (data['min_crystal_area_um2'] as num).toDouble();
});

/// Updates the minimum crystal area threshold.
Future<double> updateMinCrystalArea(ApiClient client, double value) async {
  final response = await client.dio.patch(
    '/api/v1/settings/analyzer',
    data: {'min_crystal_area_um2': value},
  );
  final data = response.data as Map<String, dynamic>;
  return (data['min_crystal_area_um2'] as num).toDouble();
}
