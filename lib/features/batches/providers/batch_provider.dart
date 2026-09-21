import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../models/batch.dart';
import 'campaign_ownership_filter_provider.dart';
import 'campaign_workflow_filter_provider.dart';

final batchListProvider = FutureProvider.autoDispose<List<Batch>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final queryParams = <String, dynamic>{'mode': 'production'};
  final workflowStatusId = ref.watch(campaignWorkflowFilterProvider);
  if (workflowStatusId != null) {
    queryParams['workflow_status_id'] = workflowStatusId;
  }
  final ownershipFilter = ref.watch(campaignOwnershipFilterProvider);
  if (ownershipFilter.kind != OwnershipFilterKind.all) {
    queryParams['owner'] = ownershipFilter.queryValue;
  }
  final response = await client.dio.get(
    '/api/v1/batches',
    queryParameters: queryParams,
  );
  final data = response.data as List;
  return data.map((j) => Batch.fromJson(j as Map<String, dynamic>)).toList();
});

final batchDetailProvider = FutureProvider.autoDispose.family<Batch, String>((
  ref,
  batchId,
) async {
  // Keep cached so navigating away (e.g., to Reports) and back doesn't
  // trigger a full-screen spinner while re-fetching.
  ref.keepAlive();
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/api/v1/batches/$batchId');
  return Batch.fromJson(response.data as Map<String, dynamic>);
});

/// Dryer model (minimal — just what we need for batch creation).
class Dryer {
  Dryer({required this.id, required this.code, required this.name});

  factory Dryer.fromJson(Map<String, dynamic> json) => Dryer(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
  );

  final String id;
  final String code;
  final String name;
}

/// Fetches all active dryers.
final dryerListProvider = FutureProvider.autoDispose<List<Dryer>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/api/v1/dryers');
  final data = response.data as List;
  return data.map((j) => Dryer.fromJson(j as Map<String, dynamic>)).toList();
});

/// Creates a batch via POST /api/v1/batches.
Future<Batch> createBatch(
  ApiClient client, {
  required String formulaId,
  required String dryerId,
  required String lotCode,
  required int campaignNum,
  required int julianDate,
  required int year,
  required List<String> sublotLetters,
  String mode = 'production',
  bool createPlaceholderImages = true,
  String? creationRequestId,
}) async {
  final response = await client.dio.post(
    '/api/v1/batches',
    data: {
      'formula_id': formulaId,
      'dryer_id': dryerId,
      'lot_code': lotCode,
      'campaign_num': campaignNum,
      'julian_date': julianDate,
      'year': year,
      'sublot_letters': sublotLetters,
      'mode': mode,
      'create_placeholder_images': createPlaceholderImages,
      'creation_request_id': ?creationRequestId,
    },
  );
  return Batch.fromJson(response.data as Map<String, dynamic>);
}

/// Create an upload-ready record without production metadata.
Future<Batch> createCustomBatch(
  ApiClient client, {
  required String formulaId,
  required String name,
  required String creationRequestId,
  String mode = 'production',
}) async {
  final response = await client.dio.post(
    '/api/v1/batches',
    data: {
      'naming_mode': 'custom',
      'custom_name': name,
      'formula_id': formulaId,
      'mode': mode,
      'creation_request_id': creationRequestId,
      'create_placeholder_images': false,
      'sublot_letters': ['A'],
    },
  );
  return Batch.fromJson(response.data as Map<String, dynamic>);
}
