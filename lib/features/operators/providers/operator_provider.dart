import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../models/operator.dart';

final operatorListProvider =
    FutureProvider.autoDispose<List<Operator>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final token = ref.watch(authStateProvider).token;
  final response = await client.dio.get(
    '/api/v1/operators',
    options: Options(
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ),
  );
  final data = response.data as List;
  return data
      .map((j) => Operator.fromJson(j as Map<String, dynamic>))
      .toList();
});

final operatorDetailProvider =
    FutureProvider.autoDispose.family<Operator, String>((ref, id) async {
  final client = ref.watch(apiClientProvider);
  final token = ref.watch(authStateProvider).token;
  final response = await client.dio.get(
    '/api/v1/operators/$id',
    options: Options(
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ),
  );
  return Operator.fromJson(response.data as Map<String, dynamic>);
});

/// Fetches all available roles in the system.
final availableRolesProvider =
    FutureProvider.autoDispose<List<OperatorRole>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final token = ref.watch(authStateProvider).token;
  final response = await client.dio.get(
    '/api/v1/operators/roles/all',
    options: Options(
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ),
  );
  final data = response.data as List;
  return data
      .map((j) => OperatorRole.fromJson(j as Map<String, dynamic>))
      .toList();
});

/// Assigns roles to an operator. Returns the updated operator.
Future<Operator> assignOperatorRoles(
  ApiClient client, {
  required String operatorId,
  required List<String> roleIds,
  String? token,
}) async {
  final response = await client.dio.put(
    '/api/v1/operators/$operatorId/roles',
    data: {'role_ids': roleIds},
    options: Options(
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ),
  );
  return Operator.fromJson(response.data as Map<String, dynamic>);
}
