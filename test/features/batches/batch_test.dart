import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/batches/models/batch.dart';

void main() {
  group('Batch model', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': '550e8400-e29b-41d4-a716-446655440000',
        'lot_code': 'L26096A-3',
        'formula_code': 'MS.CN.IO.GM.60-MX',
        'dryer_code': 'L',
        'campaign_num': 3,
        'sublot_count': 5,
        'image_count': 20,
        'processed_count': 10,
        'status': 'processing',
        'created_at': '2026-04-06T10:30:00Z',
        'project_id': 'project-1',
        'project_name': 'Dryer Optimization',
      };
      final batch = Batch.fromJson(json);
      expect(batch.lotCode, 'L26096A-3');
      expect(batch.formulaCode, 'MS.CN.IO.GM.60-MX');
      expect(batch.dryerCode, 'L');
      expect(batch.campaignNum, 3);
      expect(batch.sublotCount, 5);
      expect(batch.imageCount, 20);
      expect(batch.processedCount, 10);
      expect(batch.status, 'processing');
      expect(batch.projectId, 'project-1');
      expect(batch.projectName, 'Dryer Optimization');
    });

    test('fromJson handles null/missing optional fields', () {
      final json = {
        'id': '123',
        'lot_code': 'LOT-001',
        'created_at': '2026-04-09T01:27:38Z',
      };
      final batch = Batch.fromJson(json);
      expect(batch.formulaCode, '');
      expect(batch.dryerCode, '');
      expect(batch.sublotCount, 0);
      expect(batch.imageCount, 0);
      expect(batch.processedCount, 0);
      expect(batch.status, 'pending');
      expect(batch.projectId, isNull);
      expect(batch.projectName, isNull);
      expect(batch.displayName, 'LOT-001 ');
    });

    test('fromJson parses owner projection and display labels', () {
      final batch = Batch.fromJson({
        'id': '123',
        'lot_code': 'LOT-001',
        'created_at': '2026-04-09T01:27:38Z',
        'owner_operator_id': 'op-1',
        'owner_operator_name': 'Maria',
        'owner_operator_active': true,
        'owner_email': 'maria@microsaltinc.com',
        'owner_session_email': 'lab@microsaltinc.com',
        'owner_requires_operator_name': true,
        'ownership_version': 4,
      });

      expect(batch.ownerOperatorId, 'op-1');
      expect(batch.ownerOperatorName, 'Maria');
      expect(batch.ownerOperatorActive, isTrue);
      expect(batch.ownerSessionEmail, 'lab@microsaltinc.com');
      expect(batch.ownerEmail, 'maria@microsaltinc.com');
      expect(batch.ownershipVersion, 4);
      expect(batch.ownerRequiresOperatorName, isTrue);
      expect(batch.ownerDisplayLabel, 'Maria — maria');
    });

    test('owner display handles unassigned and inactive states', () {
      final unassigned = Batch.fromJson({
        'id': '123',
        'lot_code': 'LOT-001',
        'created_at': '2026-04-09T01:27:38Z',
      });
      expect(unassigned.ownerDisplayLabel, 'Unassigned');

      final inactive = Batch.fromJson({
        'id': '124',
        'lot_code': 'LOT-002',
        'created_at': '2026-04-09T01:27:38Z',
        'owner_operator_id': 'op-2',
        'owner_operator_name': 'Jane',
        'owner_operator_active': false,
        'owner_email': 'jane@microsaltinc.com',
        'owner_session_email': 'jane@microsaltinc.com',
      });
      expect(
        inactive.ownerDisplayWithStatus,
        'Jane — jane (inactive)',
      );
    });

    test('toJson roundtrip', () {
      final batch = Batch(
        id: '123',
        lotCode: 'L26096A-3',
        formulaCode: 'MS.CN.IO.GM.60-MX',
        dryerCode: 'L',
        campaignNum: 3,
        sublotCount: 5,
        imageCount: 20,
        processedCount: 10,
        status: 'processing',
        createdAt: DateTime.parse('2026-04-06T10:30:00Z'),
        projectId: 'project-1',
        projectName: 'Dryer Optimization',
      );
      final json = batch.toJson();
      final restored = Batch.fromJson(json);
      expect(restored.lotCode, batch.lotCode);
      expect(restored.sublotCount, batch.sublotCount);
      expect(restored.imageCount, batch.imageCount);
      expect(restored.status, batch.status);
      expect(restored.projectId, batch.projectId);
      expect(restored.projectName, batch.projectName);
    });

    test('displayName combines lot code and formula', () {
      final batch = Batch(
        id: '1',
        lotCode: 'L26096A-3',
        formulaCode: 'MS.CN.IO.GM.60-MX',
        dryerCode: 'L',
        campaignNum: 3,
        sublotCount: 5,
        imageCount: 20,
        status: 'pending',
        createdAt: DateTime.now(),
      );
      expect(batch.displayName, 'L26096A-3 MS.CN.IO.GM.60-MX');
    });

    test('processingProgress calculates correctly', () {
      final batch = Batch(
        id: '1',
        lotCode: 'L26096A-3',
        formulaCode: 'MS.CN.IO.GM.60-MX',
        dryerCode: 'L',
        campaignNum: 3,
        sublotCount: 5,
        imageCount: 20,
        processedCount: 10,
        status: 'processing',
        createdAt: DateTime.now(),
      );
      expect(batch.processingProgress, 0.5);
    });

    test('processingProgress zero when no images', () {
      final batch = Batch(
        id: '1',
        lotCode: 'L26096A-3',
        formulaCode: '',
        dryerCode: '',
        campaignNum: 1,
        sublotCount: 0,
        imageCount: 0,
        status: 'pending',
        createdAt: DateTime.now(),
      );
      expect(batch.processingProgress, 0.0);
    });
  });

  group('workflow projection', () {
    test('parses Done identity and round-trips workflow fields', () {
      final batch = Batch.fromJson({
        'id': 'wf-1',
        'lot_code': 'LOT-WF',
        'created_at': '2026-08-12T00:00:00Z',
        'workflow_status_id': 'status-done',
        'workflow_status_key': 'done',
        'workflow_status_label': 'Shipped',
        'workflow_status_color': 'green',
        'workflow_status_display_order': 2,
        'workflow_status_is_default': false,
        'workflow_status_is_done': true,
      });
      expect(batch.workflowStatusId, 'status-done');
      expect(batch.workflowStatusIsDone, isTrue);
      expect(batch.workflowStatusLabel, 'Shipped');
      expect(batch.workflowStatusColor, 'green');
      final restored = Batch.fromJson(batch.toJson());
      expect(restored.workflowStatusKey, 'done');
      expect(restored.workflowStatusIsDone, isTrue);
    });

    test('missing workflow projection uses safe display fallbacks', () {
      final batch = Batch.fromJson({
        'id': 'wf-2',
        'lot_code': 'LOT-OLD',
        'created_at': '2026-08-12T00:00:00Z',
      });
      expect(batch.workflowStatusId, isNull);
      expect(batch.workflowStatusLabel, 'Unknown');
      expect(batch.workflowStatusColor, 'gray');
      expect(batch.workflowStatusIsDone, isFalse);
    });
  });

  group('campaign locking projection', () {
    test('parses state and conflict count with legacy defaults', () {
      final locked = Batch.fromJson({
        'id': 'b',
        'lot_code': 'L',
        'created_at': '2026-08-12T00:00:00Z',
        'edit_state': 'locked',
        'edit_state_version': 3,
        'content_revision': 9,
        'unresolved_registration_conflict_count': 2,
      });
      expect(locked.isLocked, isTrue);
      expect(locked.unresolvedRegistrationConflictCount, 2);
      final legacy = Batch.fromJson({
        'id': 'b',
        'lot_code': 'L',
        'created_at': '2026-08-12T00:00:00Z',
        'edit_state_version': 'bad',
      });
      expect(legacy.editState, 'editable');
      expect(legacy.editStateVersion, 1);
    });
  });
}
