import 'package:crystalapp/features/batches/models/campaign_structure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retains stable current/source identity and ordering', () {
    final model = CampaignStructure.fromJson({
      'batch_id': 'batch',
      'lot_code': 'NEW',
      'source_lot_code': 'OLD',
      'mode': 'rnd',
      'edit_state': 'editable',
      'edit_state_version': 2,
      'content_revision': 8,
      'active_sublots': [
        {
          'id': 's1',
          'identifier': 'B',
          'source_identifier': 'A',
          'archived': false,
          'can_delete': false,
          'can_archive': true,
          'can_restore': false,
          'bags': [
            {
              'id': 'b1',
              'sublot_id': 's1',
              'number': 2,
              'source_sublot_id': 's1',
              'source_number': 1,
              'qualification_status': 'rejected',
              'image_count': 3,
              'archived': false,
              'effectively_archived': false,
              'can_delete': false,
              'can_archive': true,
              'can_restore': false,
            },
          ],
        },
      ],
      'excluded_bags': <Object>[],
      'archived_sublots': <Object>[],
      'archived_bags': <Object>[],
    });
    expect(model.sourceLotCode, 'OLD');
    expect(model.activeSublots.single.sourceIdentifier, 'A');
    expect(model.activeSublots.single.bags.single.sourceNumber, 1);
    expect(model.activeSublots.single.bags.single.isExcluded, isTrue);
  });
}
