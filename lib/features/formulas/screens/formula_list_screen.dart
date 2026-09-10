import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../../../core/providers/role_scope_provider.dart';
import '../formula_filters.dart';
import '../models/formula.dart';
import '../providers/formula_provider.dart';

enum _FormulaModeFilter { all, production, experiment }

class FormulaListScreen extends ConsumerStatefulWidget {
  const FormulaListScreen({super.key});

  @override
  ConsumerState<FormulaListScreen> createState() => _FormulaListScreenState();
}

class _FormulaListScreenState extends ConsumerState<FormulaListScreen> {
  _FormulaModeFilter _selectedMode = _FormulaModeFilter.all;
  FormulaFieldFilters _fieldFilters = const FormulaFieldFilters();

  List<_FormulaModeFilter> _availableModes(RoleScope scope) {
    if (scope.canSeeAll || (scope.canSeeRnd && scope.canSeeProduction)) {
      return _FormulaModeFilter.values;
    }
    if (scope.canSeeRnd) return const [_FormulaModeFilter.experiment];
    if (scope.canSeeProduction) return const [_FormulaModeFilter.production];

    // The provider remains authoritative. This fallback keeps an already-scoped
    // collection usable while authentication state is still settling.
    return const [_FormulaModeFilter.all];
  }

  _FormulaModeFilter _effectiveMode(List<_FormulaModeFilter> availableModes) {
    if (availableModes.contains(_selectedMode)) return _selectedMode;
    return availableModes.first;
  }

  List<Formula> _filterFormulas(
    List<Formula> formulas,
    _FormulaModeFilter mode,
  ) {
    final modeFiltered = switch (mode) {
      _FormulaModeFilter.all => formulas,
      _FormulaModeFilter.production =>
        formulas.where((formula) => !formula.isTesting).toList(),
      _FormulaModeFilter.experiment =>
        formulas.where((formula) => formula.isTesting).toList(),
    };
    return filterFormulasByFields(modeFiltered, _fieldFilters);
  }

  void _clearFilters(List<_FormulaModeFilter> availableModes) {
    setState(() {
      _fieldFilters = const FormulaFieldFilters();
      _selectedMode = availableModes.contains(_FormulaModeFilter.all)
          ? _FormulaModeFilter.all
          : availableModes.first;
    });
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Formula formula,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Formula'),
        content: Text('Delete "${formula.code}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final client = ref.read(apiClientProvider);
        await deleteFormula(client, formula.id);
        ref.invalidate(formulaListProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(userFacingError(e, action: 'delete formula')),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formulasAsync = ref.watch(formulaListProvider);
    final roleScope = ref.watch(roleScopeProvider);
    final availableModes = _availableModes(roleScope);
    final effectiveMode = _effectiveMode(availableModes);
    final modeCanClear =
        availableModes.contains(_FormulaModeFilter.all) &&
        effectiveMode != _FormulaModeFilter.all;
    final hasClearableFilters = modeCanClear || _fieldFilters.isActive;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Formulas'),
        actions: [
          if (hasClearableFilters)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              tooltip: 'Clear formula filters',
              onPressed: () => _clearFilters(availableModes),
            ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/formulas/new'),
          ),
        ],
      ),
      body: formulasAsync.when(
        data: (formulas) {
          if (formulas.isEmpty) {
            return const Center(child: Text('No formulas yet'));
          }

          final filteredFormulas = _filterFormulas(formulas, effectiveMode);
          final options = FormulaFilterOptions.fromFormulas(formulas);
          final hasEffectiveFilters =
              effectiveMode != _FormulaModeFilter.all || _fieldFilters.isActive;

          return Column(
            children: [
              _FormulaFilterBar(
                availableModes: availableModes,
                selectedMode: effectiveMode,
                onModeSelected: (mode) => setState(() => _selectedMode = mode),
                filters: _fieldFilters,
                options: options,
                onFieldSelected: (field, value) => setState(
                  () => _fieldFilters = _fieldFilters.withValue(field, value),
                ),
              ),
              if (hasEffectiveFilters)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${filteredFormulas.length} of ${formulas.length} formulas',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: filteredFormulas.isEmpty
                    ? const Center(
                        child: Text('No formulas match these filters'),
                      )
                    : ListView.builder(
                        itemCount: filteredFormulas.length,
                        itemBuilder: (context, index) {
                          final formula = filteredFormulas[index];
                          return ListTile(
                            title: Text(formula.code),
                            subtitle: Text(formula.description),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Chip(label: Text('${formula.saltPct}%')),
                                const SizedBox(width: 8),
                                Icon(
                                  formula.active
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  color: formula.active
                                      ? Colors.green
                                      : Colors.grey,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _confirmDelete(context, ref, formula),
                                ),
                              ],
                            ),
                            onTap: () =>
                                context.push('/formulas/${formula.id}/edit'),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) =>
            Center(child: Text(userFacingError(err, action: 'load formulas'))),
      ),
    );
  }
}

class _FormulaFilterBar extends StatelessWidget {
  const _FormulaFilterBar({
    required this.availableModes,
    required this.selectedMode,
    required this.onModeSelected,
    required this.filters,
    required this.options,
    required this.onFieldSelected,
  });

  final List<_FormulaModeFilter> availableModes;
  final _FormulaModeFilter selectedMode;
  final ValueChanged<_FormulaModeFilter> onModeSelected;
  final FormulaFieldFilters filters;
  final FormulaFilterOptions options;
  final void Function(FormulaFilterField field, String? value) onFieldSelected;

  String _modeLabel(_FormulaModeFilter mode) => switch (mode) {
    _FormulaModeFilter.all => 'All',
    _FormulaModeFilter.production => 'Production',
    _FormulaModeFilter.experiment => 'Experiment',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.45).clamp(
      120.0,
      320.0,
    );

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.filter_list, size: 18, color: theme.colorScheme.outline),
            for (final mode in availableModes)
              ChoiceChip(
                key: Key('formula-filter-${mode.name}'),
                label: Text(_modeLabel(mode)),
                selected: selectedMode == mode,
                showCheckmark: false,
                onSelected: (_) => onModeSelected(mode),
              ),
            for (final field in FormulaFilterField.values)
              _FormulaFieldFilterChip(
                field: field,
                value: filters.valueFor(field),
                options: options.forField(field),
                onChanged: (value) => onFieldSelected(field, value),
              ),
          ],
        ),
      ),
    );
  }
}

class _FormulaFieldFilterChip extends StatelessWidget {
  const _FormulaFieldFilterChip({
    required this.field,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final FormulaFilterField field;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  String get _fieldLabel => switch (field) {
    FormulaFilterField.process => 'Process',
    FormulaFilterField.saltOrigin => 'Salt Origin',
    FormulaFilterField.carrierOrigin => 'Carrier Origin',
    FormulaFilterField.iodine => 'Iodine',
    FormulaFilterField.gmoStatus => 'GMO Status',
    FormulaFilterField.saltPct => 'Salt Content',
    FormulaFilterField.additive => 'Additive',
    FormulaFilterField.region => 'Region',
    FormulaFilterField.extraIngredient => 'Extra Ingredient',
  };

  String _displayValue(String option) {
    if (option == formulaAbsentFilterValue) return 'None';
    if (field == FormulaFilterField.saltPct) return '$option%';
    return option;
  }

  Future<void> _chooseValue(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Select $_fieldLabel',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final option in options)
              ListTile(
                key: Key('formula-filter-option-${field.name}-$option'),
                title: Text(_displayValue(option)),
                trailing: option == value ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(option),
              ),
          ],
        ),
      ),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final selectedLabel = value == null ? null : _displayValue(value!);
    return Tooltip(
      message: 'Filter by $_fieldLabel',
      child: InputChip(
        key: Key('formula-field-filter-${field.name}'),
        label: Text(
          selectedLabel == null ? _fieldLabel : '$_fieldLabel: $selectedLabel',
          overflow: TextOverflow.ellipsis,
        ),
        selected: value != null,
        showCheckmark: false,
        deleteIcon: value == null ? null : const Icon(Icons.close, size: 16),
        onDeleted: value == null ? null : () => onChanged(null),
        onPressed: options.isEmpty ? null : () => _chooseValue(context),
      ),
    );
  }
}
