import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/batches/models/batch.dart';
import 'package:crystalapp/features/batches/providers/batch_provider.dart';
import 'package:crystalapp/features/batches/widgets/campaign_create_dialog.dart';
import 'package:crystalapp/features/formulas/models/formula.dart';
import 'package:crystalapp/features/formulas/providers/formula_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter extends Interceptor {
  final requests = <Map<String, dynamic>>[];
  bool fail = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final body = Map<String, dynamic>.from(options.data as Map);
    requests.add(body);
    if (fail) {
      handler.reject(
        DioException.badResponse(
          statusCode: 503,
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 503,
            data: {'detail': 'Please retry'},
          ),
        ),
      );
      return;
    }
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 201,
        data: {
          'id': 'new-custom',
          'naming_mode': 'custom',
          'custom_name': body['custom_name'],
          'lot_code': null,
          'campaign_num': null,
          'dryer_code': null,
          'formula_code': 'TEST',
          'created_at': '2026-09-20T00:00:00Z',
          'sublot_count': 1,
          'image_count': 0,
          'status': 'pending',
        },
      ),
    );
  }
}

Formula formula(bool rnd) => Formula.fromJson({
  'id': rnd ? 'rnd-formula' : 'prod-formula',
  'code': rnd ? 'TEST' : 'PROD',
  'description': 'Test',
  'salt_pct': 50,
  'salt_origin': 'MS',
  'carrier_origin': 'CN',
  'iodine': 'NI',
  'gmo_status': 'GM',
  'active': true,
  'is_testing': rnd,
  'created_at': '2026-09-20T00:00:00Z',
});

Future<void> _openDialog(
  WidgetTester tester,
  _Adapter adapter,
  String mode,
) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'))
    ..interceptors.add(adapter);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
        formulaListProvider.overrideWith(
          (ref) async => [formula(false), formula(true)],
        ),
        // Custom creation must succeed even when no dryers are available.
        dryerListProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCampaignCreateDialog(context, mode: mode),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Custom name'));
  await tester.pumpAndSettle();
}

void main() {
  for (final mode in ['production', 'rnd']) {
    testWidgets('$mode custom creation uses only name and eligible formula', (
      tester,
    ) async {
      final adapter = _Adapter();
      await _openDialog(tester, adapter, mode);
      expect(find.text('Dryer'), findsNothing);
      expect(find.text('Production date'), findsNothing);
      expect(find.text('Campaign number'), findsNothing);
      expect(find.text('Product of day'), findsNothing);
      await tester.tap(find.byKey(const Key('create-direct-upload-campaign')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);
      expect(adapter.requests, isEmpty);
      await tester.enterText(
        find.byKey(const Key('campaign-custom-name')),
        '  Séptembre trial  ',
      );
      await tester.tap(find.byKey(const Key('campaign-formula')));
      await tester.pumpAndSettle();
      final code = mode == 'rnd' ? 'TEST' : 'PROD';
      expect(find.text(mode == 'rnd' ? 'PROD' : 'TEST'), findsNothing);
      await tester.tap(find.text(code).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-direct-upload-campaign')));
      await tester.pumpAndSettle();
      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(request['custom_name'], 'Séptembre trial');
      expect(request['mode'], mode);
      expect(request['naming_mode'], 'custom');
      expect(request['creation_request_id'], isNotEmpty);
      expect(request['sublot_letters'], ['A']);
      expect(request['create_placeholder_images'], isFalse);
      for (final key in [
        'dryer_id',
        'lot_code',
        'year',
        'julian_date',
        'campaign_num',
      ]) {
        expect(request.containsKey(key), isFalse);
      }
      expect(find.byType(CampaignCreateDialog), findsNothing);
    });
  }

  testWidgets('retry retains input and creation reference', (tester) async {
    final adapter = _Adapter()..fail = true;
    await _openDialog(tester, adapter, 'production');
    await tester.enterText(
      find.byKey(const Key('campaign-custom-name')),
      'Trial',
    );
    await tester.tap(find.byKey(const Key('campaign-formula')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PROD').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-direct-upload-campaign')));
    await tester.pumpAndSettle();
    expect(find.text('Trial'), findsOneWidget);
    adapter.fail = false;
    await tester.tap(find.byKey(const Key('create-direct-upload-campaign')));
    await tester.pumpAndSettle();
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests[0], adapter.requests[1]);
  });

  test(
    'custom model preserves missing production data and display identity',
    () {
      final batch = Batch.fromJson({
        'id': 'custom-id',
        'naming_mode': 'custom',
        'custom_name': 'Drying trial',
        'lot_code': null,
        'campaign_num': null,
        'dryer_code': null,
        'formula_code': 'TEST',
        'created_at': '2026-09-20T00:00:00Z',
      });
      expect(batch.displayName, 'Drying trial');
      expect(batch.referenceCode, 'custom-custom-id');
      expect(batch.campaignNum, isNull);
      expect(batch.toJson()['lot_code'], isNull);
    },
  );
}
