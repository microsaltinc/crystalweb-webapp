import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../batches/providers/campaign_locking_provider.dart';
import '../models/purchase_order.dart';

final purchaseOrderListProvider =
    FutureProvider.autoDispose<List<PurchaseOrder>>((ref) async {
      final client = ref.watch(apiClientProvider);
      final response = await client.dio.get('/api/v1/purchase-orders');
      final data = response.data as List;
      return data
          .map((j) => PurchaseOrder.fromJson(j as Map<String, dynamic>))
          .toList();
    });

Future<PurchaseOrder> createPurchaseOrder(ApiClient client, String code) async {
  final response = await client.dio.post(
    '/api/v1/purchase-orders',
    data: {'code': code},
  );
  return PurchaseOrder.fromJson(response.data as Map<String, dynamic>);
}

Future<void> assignPurchaseOrder(
  ApiClient client, {
  required String batchId,
  required String? poId,
  int? expectedEditStateVersion,
}) async {
  await client.dio.patch(
    '/api/v1/purchase-orders/$batchId/assign',
    queryParameters: {'po_id': poId},
    options: expectedEditStateVersion == null
        ? null
        : Options(
            headers: {'If-Match': campaignEditETag(expectedEditStateVersion)},
          ),
  );
}
