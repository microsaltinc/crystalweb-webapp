import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/formulas/models/formula.dart';

void main() {
  group('Formula model', () {
    test('fromJson parses correctly', () {
      final json = {
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
      final formula = Formula.fromJson(json);
      expect(formula.id, 'abc-123');
      expect(formula.code, 'MS.CN.IO.GM.60-MX');
      expect(formula.description,
          'Microsalt Mined Salt Iodized GMO 60 - Mexico');
      expect(formula.saltPct, 60);
      expect(formula.process, isNull);
      expect(formula.saltOrigin, 'MS');
      expect(formula.carrierOrigin, 'CN');
      expect(formula.iodine, 'IO');
      expect(formula.gmoStatus, 'GM');
      expect(formula.additive, isNull);
      expect(formula.region, 'MX');
      expect(formula.active, true);
    });

    test('fromJson parses granulated formula', () {
      final json = {
        'id': 'def-456',
        'code': 'GR.MS.CN.IO.IP.75',
        'description':
            'Microsalt Granulated Mined Salt Iodized non-GMO 75',
        'salt_pct': 75,
        'process': 'GR',
        'salt_origin': 'MS',
        'carrier_origin': 'CN',
        'iodine': 'IO',
        'gmo_status': 'IP',
        'additive': 'MG',
        'region': null,
        'certificate_of_origin': 'Some cert',
        'comment': 'Test comment',
        'active': true,
        'created_at': '2026-04-01T00:00:00Z',
      };
      final formula = Formula.fromJson(json);
      expect(formula.process, 'GR');
      expect(formula.additive, 'MG');
      expect(formula.certificateOfOrigin, 'Some cert');
      expect(formula.comment, 'Test comment');
    });

    test('toJson roundtrip', () {
      final formula = Formula(
        id: '1',
        code: 'SS.TAS.NI.IP.25',
        description: 'Microsalt Sea Salt Non-Iodized non-GMO 25',
        saltPct: 25,
        saltOrigin: 'SS',
        carrierOrigin: 'TAS',
        iodine: 'NI',
        gmoStatus: 'IP',
        active: true,
        createdAt: DateTime.parse('2026-04-01T00:00:00Z'),
      );
      final json = formula.toJson();
      final restored = Formula.fromJson(json);
      expect(restored.code, formula.code);
      expect(restored.saltPct, formula.saltPct);
      expect(restored.saltOrigin, formula.saltOrigin);
    });

    test('toJson serializes all fields correctly', () {
      final formula = Formula(
        id: 'xyz',
        code: 'GR.MS.CN.IO.IP.75.MG-CA',
        description: 'Full formula',
        saltPct: 75,
        process: 'GR',
        saltOrigin: 'MS',
        carrierOrigin: 'CN',
        iodine: 'IO',
        gmoStatus: 'IP',
        additive: 'MG',
        region: 'CA',
        certificateOfOrigin: 'Cert-123',
        comment: 'Test note',
        active: false,
        createdAt: DateTime.parse('2026-04-10T12:00:00Z'),
      );
      final json = formula.toJson();

      expect(json['id'], 'xyz');
      expect(json['code'], 'GR.MS.CN.IO.IP.75.MG-CA');
      expect(json['description'], 'Full formula');
      expect(json['salt_pct'], 75);
      expect(json['process'], 'GR');
      expect(json['salt_origin'], 'MS');
      expect(json['carrier_origin'], 'CN');
      expect(json['iodine'], 'IO');
      expect(json['gmo_status'], 'IP');
      expect(json['additive'], 'MG');
      expect(json['region'], 'CA');
      expect(json['certificate_of_origin'], 'Cert-123');
      expect(json['comment'], 'Test note');
      expect(json['active'], false);
      expect(json['created_at'], contains('2026-04-10'));
    });
  });

  group('FormulaCodeBuilder', () {
    test('builds standard formula code', () {
      final code = FormulaCodeBuilder.buildCode(
        saltOrigin: 'MS',
        carrierOrigin: 'CN',
        iodine: 'IO',
        gmoStatus: 'GM',
        saltPct: 60,
        region: 'MX',
      );
      expect(code, 'MS.CN.IO.GM.60-MX');
    });

    test('builds granulated formula code', () {
      final code = FormulaCodeBuilder.buildCode(
        process: 'GR',
        saltOrigin: 'MS',
        carrierOrigin: 'CN',
        iodine: 'IO',
        gmoStatus: 'IP',
        saltPct: 75,
      );
      expect(code, 'GR.MS.CN.IO.IP.75');
    });

    test('builds code with explicit additive', () {
      final code = FormulaCodeBuilder.buildCode(
        saltOrigin: 'SS',
        carrierOrigin: 'TA',
        iodine: 'NI',
        gmoStatus: 'GM',
        saltPct: 50,
        additive: 'MG',
      );
      expect(code, 'SS.TA.NI.GM.50.MG');
    });

    test('builds code with additive and region', () {
      final code = FormulaCodeBuilder.buildCode(
        saltOrigin: 'MS',
        carrierOrigin: 'CN',
        iodine: 'IO',
        gmoStatus: 'IP',
        saltPct: 25,
        additive: 'MG',
        region: 'CA',
      );
      expect(code, 'MS.CN.IO.IP.25.MG-CA');
    });

    test('builds minimal code without optional segments', () {
      final code = FormulaCodeBuilder.buildCode(
        saltOrigin: 'SS',
        carrierOrigin: 'TAS',
        iodine: 'NI',
        gmoStatus: 'IP',
        saltPct: 25,
      );
      expect(code, 'SS.TAS.NI.IP.25');
    });

    test('builds description for standard formula', () {
      final desc = FormulaCodeBuilder.buildDescription(
        saltOrigin: 'MS',
        carrierOrigin: 'CN',
        iodine: 'IO',
        gmoStatus: 'GM',
        saltPct: 60,
        region: 'MX',
      );
      expect(desc, 'Microsalt Mined Salt Iodized GMO 60 - Mexico');
    });

    test('builds description for granulated formula', () {
      final desc = FormulaCodeBuilder.buildDescription(
        process: 'GR',
        saltOrigin: 'SS',
        carrierOrigin: 'TAS',
        iodine: 'NI',
        gmoStatus: 'IP',
        saltPct: 75,
        additive: 'MG',
      );
      expect(desc,
          'Microsalt Granulated Sea Salt Non-Iodized non-GMO 75 Magnesium Stearate');
    });

    test('builds description with region', () {
      final desc = FormulaCodeBuilder.buildDescription(
        saltOrigin: 'SS',
        carrierOrigin: 'CN',
        iodine: 'IO',
        gmoStatus: 'IP',
        saltPct: 50,
        region: 'CA',
      );
      expect(desc, 'Microsalt Sea Salt Iodized non-GMO 50 - Canada');
    });
  });
}
