import 'models/formula.dart';

const formulaAbsentFilterValue = '__formula_filter_absent__';

enum FormulaFilterField {
  process,
  saltOrigin,
  carrierOrigin,
  iodine,
  gmoStatus,
  saltPct,
  additive,
  region,
  extraIngredient,
}

class FormulaFieldFilters {
  const FormulaFieldFilters({
    this.process,
    this.saltOrigin,
    this.carrierOrigin,
    this.iodine,
    this.gmoStatus,
    this.saltPct,
    this.additive,
    this.region,
    this.extraIngredient,
  });

  final String? process;
  final String? saltOrigin;
  final String? carrierOrigin;
  final String? iodine;
  final String? gmoStatus;
  final String? saltPct;
  final String? additive;
  final String? region;
  final String? extraIngredient;

  bool get isActive =>
      FormulaFilterField.values.any((field) => valueFor(field) != null);

  String? valueFor(FormulaFilterField field) => switch (field) {
    FormulaFilterField.process => process,
    FormulaFilterField.saltOrigin => saltOrigin,
    FormulaFilterField.carrierOrigin => carrierOrigin,
    FormulaFilterField.iodine => iodine,
    FormulaFilterField.gmoStatus => gmoStatus,
    FormulaFilterField.saltPct => saltPct,
    FormulaFilterField.additive => additive,
    FormulaFilterField.region => region,
    FormulaFilterField.extraIngredient => extraIngredient,
  };

  FormulaFieldFilters withValue(FormulaFilterField field, String? value) =>
      FormulaFieldFilters(
        process: field == FormulaFilterField.process ? value : process,
        saltOrigin: field == FormulaFilterField.saltOrigin ? value : saltOrigin,
        carrierOrigin: field == FormulaFilterField.carrierOrigin
            ? value
            : carrierOrigin,
        iodine: field == FormulaFilterField.iodine ? value : iodine,
        gmoStatus: field == FormulaFilterField.gmoStatus ? value : gmoStatus,
        saltPct: field == FormulaFilterField.saltPct ? value : saltPct,
        additive: field == FormulaFilterField.additive ? value : additive,
        region: field == FormulaFilterField.region ? value : region,
        extraIngredient: field == FormulaFilterField.extraIngredient
            ? value
            : extraIngredient,
      );

  bool matches(Formula formula) {
    if (!_matchesNullable(formula.process, process) ||
        !_matchesScalar(formula.saltOrigin, saltOrigin) ||
        !_matchesScalar(formula.carrierOrigin, carrierOrigin) ||
        !_matchesScalar(formula.iodine, iodine) ||
        !_matchesScalar(formula.gmoStatus, gmoStatus) ||
        !_matchesScalar(formula.saltPct.toString(), saltPct) ||
        !_matchesNullable(formula.additive, additive) ||
        !_matchesNullable(formula.region, region)) {
      return false;
    }
    if (extraIngredient == null) return true;
    if (extraIngredient == formulaAbsentFilterValue) {
      return formula.extraIngredients.isEmpty;
    }
    return formula.extraIngredients.contains(extraIngredient);
  }

  bool _matchesScalar(String actual, String? selected) =>
      selected == null || actual == selected;

  bool _matchesNullable(String? actual, String? selected) {
    if (selected == null) return true;
    if (selected == formulaAbsentFilterValue) {
      return actual == null || actual.isEmpty;
    }
    return actual == selected;
  }
}

List<Formula> filterFormulasByFields(
  Iterable<Formula> formulas,
  FormulaFieldFilters filters,
) => formulas.where(filters.matches).toList(growable: false);

class FormulaFilterOptions {
  FormulaFilterOptions._(this._values);

  factory FormulaFilterOptions.fromFormulas(Iterable<Formula> formulas) {
    final source = formulas.toList(growable: false);
    return FormulaFilterOptions._({
      FormulaFilterField.process: _nullableOptions(
        source.map((formula) => formula.process),
      ),
      FormulaFilterField.saltOrigin: _options(
        source.map((formula) => formula.saltOrigin),
      ),
      FormulaFilterField.carrierOrigin: _options(
        source.map((formula) => formula.carrierOrigin),
      ),
      FormulaFilterField.iodine: _options(
        source.map((formula) => formula.iodine),
      ),
      FormulaFilterField.gmoStatus: _options(
        source.map((formula) => formula.gmoStatus),
      ),
      FormulaFilterField.saltPct: _numericOptions(
        source.map((formula) => formula.saltPct),
      ),
      FormulaFilterField.additive: _nullableOptions(
        source.map((formula) => formula.additive),
      ),
      FormulaFilterField.region: _nullableOptions(
        source.map((formula) => formula.region),
      ),
      FormulaFilterField.extraIngredient: _extraIngredientOptions(source),
    });
  }

  final Map<FormulaFilterField, List<String>> _values;

  List<String> forField(FormulaFilterField field) => _values[field] ?? const [];

  static List<String> _options(Iterable<String> values) {
    final result = values.where((value) => value.isNotEmpty).toSet().toList()
      ..sort(
        (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
      );
    return List.unmodifiable(result);
  }

  static List<String> _nullableOptions(Iterable<String?> values) {
    final source = values.toList(growable: false);
    final result = _options(source.whereType<String>());
    return List.unmodifiable([
      if (source.any((value) => value == null || value.isEmpty))
        formulaAbsentFilterValue,
      ...result,
    ]);
  }

  static List<String> _numericOptions(Iterable<int> values) {
    final result = values.toSet().toList()..sort();
    return List.unmodifiable(result.map((value) => value.toString()));
  }

  static List<String> _extraIngredientOptions(List<Formula> formulas) =>
      List.unmodifiable([
        if (formulas.any((formula) => formula.extraIngredients.isEmpty))
          formulaAbsentFilterValue,
        ..._options(formulas.expand((formula) => formula.extraIngredients)),
      ]);
}
