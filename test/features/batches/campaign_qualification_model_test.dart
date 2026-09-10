import 'package:crystalapp/features/batches/models/campaign_qualification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strict statuses and fixed reason catalog', () {
    expect(
      CampaignQualificationStatus.fromJson('accepted_with_exclusions').label,
      'Accepted with Exclusions',
    );
    expect(BagQualificationStatus.fromJson('rejected').label, 'Rejected');
    expect(QualificationReason.values, hasLength(7));
    expect(
      () => BagQualificationStatus.fromJson('unsafe'),
      throwsFormatException,
    );
  });

  test(
    'parses current included/excluded population and composite versions',
    () {
      final model = CampaignQualification.fromJson({
        'batch_id': 'batch',
        'mode': 'production',
        'edit_state': 'editable',
        'edit_state_version': 4,
        'content_revision': 19,
        'campaign': {'status': 'accepted_with_exclusions'},
        'included_bags': [
          {
            'id': 'b1',
            'sublot_id': 's1',
            'sublot_identifier': 'A',
            'number': 1,
            'status': 'accepted',
            'image_count': 2,
            'operator_reviewed': true,
          },
        ],
        'excluded_bags': [
          {
            'id': 'b2',
            'sublot_id': 's1',
            'sublot_identifier': 'A',
            'number': 2,
            'status': 'rejected',
            'reason_code': 'other',
            'notes': 'evidence',
            'image_count': 1,
          },
        ],
        'pending_bag_ids': <String>[],
        'can_finalize_as': ['accepted_with_exclusions', 'rejected'],
        'finalization_blockers': <Object>[],
      });
      expect(model.contentRevision, 19);
      expect(model.includedBags.single.id, 'b1');
      expect(model.includedBags.single.operatorReviewed, isTrue);
      expect(model.excludedBags.single.operatorReviewed, isFalse);
      expect(model.excludedBags.single.reason?.label, 'Other');
    },
  );
}
