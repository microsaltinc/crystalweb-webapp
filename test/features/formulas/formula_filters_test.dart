import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/formulas/formula_filters.dart';
import 'package:crystalapp/features/formulas/models/formula.dart';

Formula formula(
  String id, {
  String? process,
  String saltOrigin = 'MS',
  String carrierOrigin = 'CN',
  String iodine = 'IO',
  String gmoStatus = 'GM',
  int saltPct = 60,
  String? additive,
  String? region,
  List<String> extraIngredients = const [],
}) => Formula(
  id: id,
  code: id,
  description: id,
  saltPct: saltPct,
  process: process,
  saltOrigin: saltOrigin,
  carrierOrigin: carrierOrigin,
  iodine: iodine,
  gmoStatus: gmoStatus,
  additive: additive,
  region: region,
  extraIngredients: extraIngredients,
  active: true,
  createdAt: DateTime.utc(2026),
);

void main() {
  final formulas = [
    formula('plain'),
    formula(
      'granulated',
      process: 'GR',
      saltOrigin: 'SS',
      carrierOrigin: 'TAS',
      iodine: 'NI',
      gmoStatus: 'IP',
      saltPct: 75,
      additive: 'MG',
      region: 'CA',
      extraIngredients: const ['VIT', 'KC'],
    ),
  ];

  test(
    'formula field filters combine every scalar field with AND semantics',
    () {
      var filters = const FormulaFieldFilters();
      for (final selection in <(FormulaFilterField, String)>[
        (FormulaFilterField.process, 'GR'),
        (FormulaFilterField.saltOrigin, 'SS'),
        (FormulaFilterField.carrierOrigin, 'TAS'),
        (FormulaFilterField.iodine, 'NI'),
        (FormulaFilterField.gmoStatus, 'IP'),
        (FormulaFilterField.saltPct, '75'),
        (FormulaFilterField.additive, 'MG'),
        (FormulaFilterField.region, 'CA'),
      ]) {
        filters = filters.withValue(selection.$1, selection.$2);
      }

      expect(filterFormulasByFields(formulas, filters).map((f) => f.id), [
        'granulated',
      ]);
      expect(
        filterFormulasByFields(
          formulas,
          filters.withValue(FormulaFilterField.iodine, 'IO'),
        ),
        isEmpty,
      );
    },
  );

  test('nullable and empty-list fields support an explicit None selection', () {
    for (final field in [
      FormulaFilterField.process,
      FormulaFilterField.additive,
      FormulaFilterField.region,
      FormulaFilterField.extraIngredient,
    ]) {
      final filtered = filterFormulasByFields(
        formulas,
        const FormulaFieldFilters().withValue(field, formulaAbsentFilterValue),
      );
      expect(filtered.map((f) => f.id), ['plain'], reason: field.name);
    }
  });

  test('extra ingredient matches by containment', () {
    final filtered = filterFormulasByFields(
      formulas,
      const FormulaFieldFilters().withValue(
        FormulaFilterField.extraIngredient,
        'VIT',
      ),
    );

    expect(filtered.map((f) => f.id), ['granulated']);
  });

  test('options are unique, sorted, and include meaningful absence', () {
    final options = FormulaFilterOptions.fromFormulas([
      ...formulas,
      formula('duplicate', saltOrigin: 'SS', extraIngredients: const ['KC']),
    ]);

    expect(options.forField(FormulaFilterField.saltOrigin), ['MS', 'SS']);
    expect(options.forField(FormulaFilterField.saltPct), ['60', '75']);
    expect(options.forField(FormulaFilterField.process), [
      formulaAbsentFilterValue,
      'GR',
    ]);
    expect(options.forField(FormulaFilterField.extraIngredient), [
      formulaAbsentFilterValue,
      'KC',
      'VIT',
    ]);
  });

  test('pure filtering handles one thousand formulas synchronously', () {
    final many = List.generate(
      1000,
      (index) => formula('$index', saltOrigin: index.isEven ? 'MS' : 'SS'),
    );

    final result = filterFormulasByFields(
      many,
      const FormulaFieldFilters().withValue(
        FormulaFilterField.saltOrigin,
        'SS',
      ),
    );

    expect(result, hasLength(500));
  });
}
