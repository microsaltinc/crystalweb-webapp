import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/images/models/crystal.dart';
import 'package:crystalapp/features/images/providers/annotation_provider.dart';

class _MockDio extends Mock implements Dio {}

Crystal _crystal() => Crystal(
  id: 'crystal-1',
  imageId: 'image-1',
  quad: const [Point(0, 0), Point(10, 0), Point(10, 10), Point(0, 10)],
  confidence: 0.9,
  areaUm2: 10,
  equivalentDiameterUm: 2,
  partialVisible: false,
  discarded: false,
  source: CrystalSource.auto,
);

void main() {
  test(
    'late campaign_locked retains every local edit and disables mutation',
    () async {
      final dio = _MockDio();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
        ],
      );
      addTearDown(container.dispose);
      final provider = annotationProvider('image-1');
      final notifier = container.read(provider.notifier);
      final crystal = _crystal();
      notifier.setCampaignAuthority(
        batchId: 'batch-1',
        editStateVersion: 9,
        editable: true,
      );
      notifier.selectCrystal(crystal.id);
      notifier.toggleDiscard(crystal);
      notifier.addCrystalAt(30, 30);
      notifier.toggleDelRegion();
      notifier.addDelRegionPoint(1, 2);
      final before = container.read(provider);

      when(
        () => dio.post(
          '/api/v1/images/image-1/annotations/submit',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/annotations/submit'),
          response: Response(
            requestOptions: RequestOptions(path: '/annotations/submit'),
            statusCode: 409,
            data: {
              'detail': {
                'code': 'campaign_locked',
                'message': 'The campaign was locked elsewhere.',
              },
            },
          ),
        ),
      );

      expect(await notifier.submit(), isFalse);
      final conflicted = container.read(provider);
      expect(conflicted.readOnlyDueToConflict, isTrue);
      expect(conflicted.selectedCrystalId, before.selectedCrystalId);
      expect(conflicted.changes.keys, unorderedEquals(before.changes.keys));
      expect(conflicted.delRegionActive, before.delRegionActive);
      expect(conflicted.delRegionPoints, before.delRegionPoints);
      expect(conflicted.submitError, contains('unsaved edits'));

      notifier.toggleDiscard(crystal);
      notifier.undoChange(crystal.id);
      notifier.addCrystalAt(99, 99);
      expect(
        container.read(provider).changes.keys,
        unorderedEquals(before.changes.keys),
      );
      verify(
        () => dio.post(
          '/api/v1/images/image-1/annotations/submit',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).called(1);
      expect(await notifier.submit(), isFalse);
      verifyNever(
        () => dio.post(
          '/api/v1/images/image-1/annotations/submit',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      );
    },
  );
}
