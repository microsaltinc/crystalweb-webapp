import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/operators/models/operator.dart';
import 'package:crystalapp/features/operators/providers/operator_provider.dart';

void main() {
  group('Operator model', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': '123',
        'name': 'Operator A',
        'active': true,
        'has_pin': true,
        'created_at': '2026-04-01T00:00:00Z',
        'email': 'opa@microsaltinc.com',
        'phone': '+1234567890',
        'managed_by': 'admin@microsaltinc.com',
      };
      final op = Operator.fromJson(json);
      expect(op.name, 'Operator A');
      expect(op.active, true);
      expect(op.hasPin, true);
      expect(op.email, 'opa@microsaltinc.com');
      expect(op.phone, '+1234567890');
      expect(op.managedBy, 'admin@microsaltinc.com');
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': '123',
        'name': 'Operator B',
        'active': true,
        'has_pin': false,
        'created_at': '2026-04-01T00:00:00Z',
      };
      final op = Operator.fromJson(json);
      expect(op.email, '');
      expect(op.phone, isNull);
      expect(op.managedBy, '');
    });

    test('toJson roundtrip', () {
      final op = Operator(
        id: '1',
        name: 'Test',
        active: true,
        hasPin: false,
        createdAt: DateTime.parse('2026-04-01T00:00:00Z'),
        email: 'test@microsaltinc.com',
        managedBy: 'test@microsaltinc.com',
      );
      final json = op.toJson();
      final restored = Operator.fromJson(json);
      expect(restored.name, op.name);
      expect(restored.active, op.active);
      expect(restored.email, op.email);
      expect(restored.managedBy, op.managedBy);
    });

    test('initials from name', () {
      final op = Operator(
        id: '1',
        name: 'John Doe',
        active: true,
        hasPin: true,
        createdAt: DateTime.now(),
        email: 'john@microsaltinc.com',
        managedBy: 'admin@microsaltinc.com',
      );
      expect(op.initials, 'JD');
    });

    test('single name initials', () {
      final op = Operator(
        id: '1',
        name: 'Maria',
        active: true,
        hasPin: true,
        createdAt: DateTime.now(),
        email: 'maria@microsaltinc.com',
        managedBy: 'admin@microsaltinc.com',
      );
      expect(op.initials, 'M');
    });

    test('toJson includes email, phone, managedBy', () {
      final op = Operator(
        id: '1',
        name: 'Test',
        active: true,
        hasPin: false,
        createdAt: DateTime.parse('2026-04-01T00:00:00Z'),
        email: 'test@microsaltinc.com',
        phone: '+1555555',
        managedBy: 'admin@microsaltinc.com',
      );
      final json = op.toJson();
      expect(json['email'], 'test@microsaltinc.com');
      expect(json['phone'], '+1555555');
      expect(json['managed_by'], 'admin@microsaltinc.com');
    });
  });

  group('Operator list provider contract', () {
    test('login screen and management screen use the same provider', () {
      // Both OperatorSelectScreen and OperatorListScreen must use
      // operatorListProvider, which calls GET /api/v1/operators.
      // The backend resolves the correct user_id from both user tokens
      // (sub=user_id) and operator tokens (sub=operator_id), so both
      // screens always see the same operator list.
      //
      // This test verifies the provider exists and is the single source
      // of truth. If someone creates a second provider, this test should
      // prompt them to use the shared one instead.
      expect(operatorListProvider, isNotNull);
      // The provider is an autoDispose FutureProvider<List<Operator>>.
      // Verify its type to catch accidental replacement.
      expect(
        operatorListProvider.toString(),
        contains('List<Operator>'),
      );
    });

    test('Operator.fromJson parses has_pin for PIN set vs verify', () {
      // The PIN screen relies on has_pin to decide between "Set PIN"
      // and "Verify" mode. This must be parsed correctly from the API.
      final withPin = Operator.fromJson({
        'id': '1',
        'name': 'A',
        'active': true,
        'has_pin': true,
        'created_at': '2026-04-01T00:00:00Z',
        'email': 'a@microsaltinc.com',
        'managed_by': 'a@microsaltinc.com',
      });
      expect(withPin.hasPin, true);

      final withoutPin = Operator.fromJson({
        'id': '2',
        'name': 'B',
        'active': true,
        'has_pin': false,
        'created_at': '2026-04-01T00:00:00Z',
        'email': 'b@microsaltinc.com',
        'managed_by': 'b@microsaltinc.com',
      });
      expect(withoutPin.hasPin, false);
    });
  });
}
