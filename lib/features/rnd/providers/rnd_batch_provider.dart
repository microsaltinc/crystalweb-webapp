import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../batches/models/batch.dart';
import '../../batches/providers/campaign_ownership_filter_provider.dart';
import '../../batches/providers/campaign_workflow_filter_provider.dart';

final rndBatchListProvider = FutureProvider.autoDispose<List<Batch>>((
  ref,
) async {
  final client = ref.watch(apiClientProvider);
  final ownershipFilter = ref.watch(campaignOwnershipFilterProvider);
  final queryParameters = <String, dynamic>{'mode': 'rnd'};
  final workflowStatusId = ref.watch(campaignWorkflowFilterProvider);
  if (workflowStatusId != null) {
    queryParameters['workflow_status_id'] = workflowStatusId;
  }
  if (ownershipFilter.kind != OwnershipFilterKind.all) {
    queryParameters['owner'] = ownershipFilter.queryValue;
  }
  final response = await client.dio.get(
    '/api/v1/batches',
    queryParameters: queryParameters,
  );
  final data = response.data as List;
  return data.map((j) => Batch.fromJson(j as Map<String, dynamic>)).toList();
});
