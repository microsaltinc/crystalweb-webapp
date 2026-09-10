import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../../batches/providers/campaign_locking_provider.dart';
import '../models/project.dart';

final projectListProvider = FutureProvider.autoDispose<List<Project>>((
  ref,
) async {
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/api/v1/projects');
  final data = response.data as List;
  return data
      .map((item) => Project.fromJson(item as Map<String, dynamic>))
      .toList();
});

Future<Project> createProject(ApiClient client, String name) async {
  final response = await client.dio.post(
    '/api/v1/projects',
    data: {'name': name.trim()},
  );
  return Project.fromJson(response.data as Map<String, dynamic>);
}

Future<void> assignProject(
  ApiClient client, {
  required String batchId,
  required String? projectId,
  int? expectedEditStateVersion,
}) async {
  await client.dio.patch(
    '/api/v1/projects/$batchId/assign',
    data: {'project_id': projectId},
    options: expectedEditStateVersion == null
        ? null
        : Options(
            headers: {'If-Match': campaignEditETag(expectedEditStateVersion)},
          ),
  );
}

String projectErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    final detail = data is Map ? data['detail'] : null;
    if (detail is String) {
      final normalized = detail.trim();
      final lower = normalized.toLowerCase();
      const unsafe = [
        'exception:',
        'traceback',
        'sqlalchemy',
        'asyncpg',
        '<html',
      ];
      if (normalized.isNotEmpty &&
          normalized.length <= 500 &&
          !unsafe.any(lower.contains)) {
        return normalized;
      }
    }
  }
  return userFacingError(error, action: 'assign Project');
}
