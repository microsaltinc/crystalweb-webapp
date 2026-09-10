import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/formulas/models/formula.dart';
import 'package:crystalapp/features/formulas/providers/formula_provider.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio mockDio;
  late ApiClient apiClient;

  final sampleFormulaJson = {
    'id': 'abc-123',
    'code': 'MS.CN.IO.GM.60-MX',
    'description': 'Microsalt Mined Salt Iodized GMO 60 - Mexico',
    'salt_pct': 60,
    'process': null,
    'salt_origin': 'MS',
    'carrier_origin': 'CN',
    'iodine': 'IO',
    'gmo_status': 'GM',
    'additive': null,
    'region': 'MX',
    'certificate_of_origin': null,
    'comment': null,
    'active': true,
    'created_at': '2026-04-01T00:00:00Z',
  };

  setUp(() {
    mockDio = MockDio();
    apiClient = ApiClient.withDio(mockDio);
  });

  group('createFormula', () {
    test('calls POST /api/v1/formulas and returns created formula', () async {
      final inputData = {
        'code': 'MS.CN.IO.GM.60-MX',
        'description': 'Microsalt Mined Salt Iodized GMO 60 - Mexico',
        'salt_pct': 60,
        'salt_origin': 'MS',
        'carrier_origin': 'CN',
        'iodine': 'IO',
        'gmo_status': 'GM',
        'active': true,
      };

      when(() => mockDio.post('/api/v1/formulas', data: inputData)).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/v1/formulas'),
          statusCode: 201,
          data: sampleFormulaJson,
        ),
      );

      final result = await createFormula(apiClient, inputData);

      expect(result, isA<Formula>());
      expect(result.id, 'abc-123');
      expect(result.code, 'MS.CN.IO.GM.60-MX');
      verify(() => mockDio.post('/api/v1/formulas', data: inputData)).called(1);
    });
  });

  group('updateFormula', () {
    test(
      'calls PUT /api/v1/formulas/{id} and returns updated formula',
      () async {
        final inputData = {
          'code': 'MS.CN.IO.GM.60-MX',
          'description': 'Updated desc',
          'salt_pct': 60,
          'active': true,
        };

        when(
          () => mockDio.put('/api/v1/formulas/abc-123', data: inputData),
        ).thenAnswer(
          (_) async => Response(
            requestOptions: RequestOptions(path: '/api/v1/formulas/abc-123'),
            statusCode: 200,
            data: {...sampleFormulaJson, 'description': 'Updated desc'},
          ),
        );

        final result = await updateFormula(apiClient, 'abc-123', inputData);

        expect(result, isA<Formula>());
        expect(result.description, 'Updated desc');
        verify(
          () => mockDio.put('/api/v1/formulas/abc-123', data: inputData),
        ).called(1);
      },
    );
  });

  group('deleteFormula', () {
    test('calls DELETE /api/v1/formulas/{id}', () async {
      when(() => mockDio.delete('/api/v1/formulas/abc-123')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/v1/formulas/abc-123'),
          statusCode: 204,
        ),
      );

      await deleteFormula(apiClient, 'abc-123');

      verify(() => mockDio.delete('/api/v1/formulas/abc-123')).called(1);
    });
  });

  group('formulaListProvider', () {
    test('fetches list from GET /api/v1/formulas', () async {
      when(
        () => mockDio.get(
          '/api/v1/formulas',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/v1/formulas'),
          statusCode: 200,
          data: [sampleFormulaJson],
        ),
      );

      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(apiClient)],
      );
      addTearDown(container.dispose);

      final formulas = await container.read(formulaListProvider.future);
      expect(formulas, hasLength(1));
      expect(formulas.first.code, 'MS.CN.IO.GM.60-MX');
    });
  });

  group('formulaDetailProvider', () {
    test('fetches single formula from GET /api/v1/formulas/{id}', () async {
      when(() => mockDio.get('/api/v1/formulas/abc-123')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/v1/formulas/abc-123'),
          statusCode: 200,
          data: sampleFormulaJson,
        ),
      );

      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(apiClient)],
      );
      addTearDown(container.dispose);

      final formula = await container.read(
        formulaDetailProvider('abc-123').future,
      );
      expect(formula.id, 'abc-123');
      expect(formula.saltPct, 60);
    });
  });
}
