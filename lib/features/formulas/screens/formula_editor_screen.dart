import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../../../core/providers/role_scope_provider.dart';
import '../models/formula.dart';
import '../providers/formula_options_provider.dart';
import '../providers/formula_provider.dart' as providers;
import '../widgets/editable_dropdown.dart';

class FormulaEditorScreen extends ConsumerStatefulWidget {
  const FormulaEditorScreen({super.key, this.formulaId});

  final String? formulaId;

  @override
  ConsumerState<FormulaEditorScreen> createState() =>
      _FormulaEditorScreenState();
}

class _FormulaEditorScreenState extends ConsumerState<FormulaEditorScreen> {
  // Segment selections with defaults
  bool _isGranulated = false;
  String _saltOrigin = 'MS';
  String _carrierOrigin = 'CN';
  String _iodine = 'IO';
  String _gmoStatus = 'GM';
  int _saltPct = 60;
  bool _hasAdditive = false;
  Set<String> _selectedExtraIngredients = {};
  String? _region;

  final _descriptionController = TextEditingController();
  final _certificateController = TextEditingController();
  final _commentController = TextEditingController();

  bool _descriptionManuallyEdited = false;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  bool _active = true;
  bool _isTesting = false;
  bool _wasAlreadyTesting = false;

  bool get isEditing => widget.formulaId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _isLoading = true;
      _loadFormula();
    } else {
      _updateDescription();
    }
  }

  Future<void> _loadFormula() async {
    try {
      final formula = await ref.read(
        providers.formulaDetailProvider(widget.formulaId!).future,
      );
      if (mounted) {
        setState(() {
          _isGranulated = formula.process == 'GR';
          _saltOrigin = formula.saltOrigin;
          _carrierOrigin = formula.carrierOrigin;
          _iodine = formula.iodine;
          _gmoStatus = formula.gmoStatus;
          _saltPct = formula.saltPct;
          _hasAdditive = formula.additive == 'MG';
          _selectedExtraIngredients = formula.extraIngredients.toSet();
          _region = formula.region;
          _active = formula.active;
          _isTesting = formula.isTesting;
          _wasAlreadyTesting = formula.isTesting;
          _descriptionController.text = formula.description;
          _certificateController.text = formula.certificateOfOrigin ?? '';
          _commentController.text = formula.comment ?? '';
          _descriptionManuallyEdited = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userFacingError(e, action: 'load formula');
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _certificateController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  String? get _process => _isGranulated ? 'GR' : null;
  String? get _additive => _hasAdditive ? 'MG' : null;

  String get _codePreview => FormulaCodeBuilder.buildCode(
    process: _process,
    saltOrigin: _saltOrigin,
    carrierOrigin: _carrierOrigin,
    iodine: _iodine,
    gmoStatus: _gmoStatus,
    saltPct: _saltPct,
    additive: _additive,
    extraIngredients: _selectedExtraIngredients.toList(),
    region: _region,
  );

  void _updateDescription() {
    if (!_descriptionManuallyEdited) {
      // Build labels map from currently loaded options
      Map<String, String> extraLabels = {};
      final optionsValue = ref.read(formulaOptionsProvider('extra_ingredient'));
      optionsValue.whenData((options) {
        for (final opt in options) {
          extraLabels[opt.code] = opt.label;
        }
      });
      _descriptionController.text = FormulaCodeBuilder.buildDescription(
        process: _process,
        saltOrigin: _saltOrigin,
        carrierOrigin: _carrierOrigin,
        iodine: _iodine,
        gmoStatus: _gmoStatus,
        saltPct: _saltPct,
        additive: _additive,
        extraIngredients: _selectedExtraIngredients.toList(),
        extraIngredientLabels: extraLabels,
        region: _region,
      );
    }
  }

  void _onSegmentChanged() {
    setState(() {});
    _updateDescription();
  }

  Future<void> _handleSave() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    final data = <String, dynamic>{
      'code': _codePreview,
      'description': _descriptionController.text.trim(),
      'salt_pct': _saltPct,
      'process': _process,
      'salt_origin': _saltOrigin,
      'carrier_origin': _carrierOrigin,
      'iodine': _iodine,
      'gmo_status': _gmoStatus,
      'additive': _additive,
      'extra_ingredients': _selectedExtraIngredients.toList()..sort(),
      'region': _region,
      'certificate_of_origin': _certificateController.text.trim().isNotEmpty
          ? _certificateController.text.trim()
          : null,
      'comment': _commentController.text.trim().isNotEmpty
          ? _commentController.text.trim()
          : null,
      'active': _active,
      'is_testing': _isTesting,
    };

    try {
      final client = ref.read(apiClientProvider);
      if (isEditing) {
        await providers.updateFormula(client, widget.formulaId!, data);
      } else {
        await providers.createFormula(client, data);
      }

      ref.invalidate(providers.formulaListProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = userFacingError(e, action: 'save formula'));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildExtraIngredientsSection() {
    final optionsAsync = ref.watch(formulaOptionsProvider('extra_ingredient'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Extra Ingredients',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              tooltip: 'Add new ingredient',
              onPressed: _showAddExtraIngredientDialog,
            ),
          ],
        ),
        const SizedBox(height: 8),
        optionsAsync.when(
          data: (options) => Wrap(
            spacing: 8,
            runSpacing: 4,
            children: options
                .map(
                  (opt) => FilterChip(
                    label: Text(opt.label),
                    selected: _selectedExtraIngredients.contains(opt.code),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedExtraIngredients.add(opt.code);
                        } else {
                          _selectedExtraIngredients.remove(opt.code);
                        }
                      });
                      _onSegmentChanged();
                    },
                  ),
                )
                .toList(),
          ),
          loading: () => const SizedBox(
            height: 32,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, _) => const Text('Failed to load ingredients'),
        ),
      ],
    );
  }

  Future<void> _showAddExtraIngredientDialog() async {
    final codeController = TextEditingController();
    final labelController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Extra Ingredient'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              decoration: const InputDecoration(labelText: 'Code (e.g., VIT)'),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: labelController,
              decoration: const InputDecoration(
                labelText: 'Label (e.g., Vitamin D)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result == true &&
        codeController.text.isNotEmpty &&
        labelController.text.isNotEmpty) {
      final client = ref.read(apiClientProvider);
      try {
        await addFormulaOption(
          client,
          ref,
          category: 'extra_ingredient',
          code: codeController.text.trim().toUpperCase(),
          label: labelController.text.trim(),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(userFacingError(e, action: 'add ingredient')),
            ),
          );
        }
      }
    }
  }

  Widget _buildTestingFormulaToggle() {
    final theme = Theme.of(context);
    final scope = ref.watch(roleScopeProvider);
    final isLockedByRole = !scope.canSeeAll && !scope.isAdmin;
    final effectiveValue = isLockedByRole ? scope.canSeeRnd : _isTesting;

    if (isLockedByRole && effectiveValue != _isTesting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _isTesting = effectiveValue);
        }
      });
    }

    return SwitchListTile(
      key: const Key('testing-formula-toggle'),
      title: Row(
        children: [
          const Text('Testing Formula'),
          if (effectiveValue) ...[
            const SizedBox(width: 8),
            Chip(
              label: const Text('R&D'),
              visualDensity: VisualDensity.compact,
              backgroundColor: theme.colorScheme.tertiaryContainer,
              labelStyle: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        isLockedByRole
            ? 'Set by your operator role'
            : _wasAlreadyTesting
            ? 'Testing designation cannot be reverted'
            : 'Mark as testing formula for R&D experiments',
      ),
      value: effectiveValue,
      onChanged: (_wasAlreadyTesting || isLockedByRole)
          ? null
          : (val) => setState(() => _isTesting = val),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Formula' : 'New Formula')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Primary classification — establish operating mode first.
                  _buildTestingFormulaToggle(),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Live code preview
                  Card(
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Formula Code',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _codePreview,
                            key: const Key('formula-code-preview'),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Process toggle
                  SwitchListTile(
                    title: const Text('Granulated'),
                    subtitle: const Text('Compaction process (GR)'),
                    value: _isGranulated,
                    onChanged: (val) {
                      _isGranulated = val;
                      // Auto-check MG additive for granulated
                      if (val) _hasAdditive = true;
                      _onSegmentChanged();
                    },
                  ),
                  const Divider(),

                  // Salt Origin
                  EditableDropdown(
                    category: 'salt_origin',
                    value: _saltOrigin,
                    labelText: 'Salt Origin',
                    onChanged: (val) {
                      if (val != null) {
                        _saltOrigin = val;
                        _onSegmentChanged();
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Carrier Origin
                  EditableDropdown(
                    category: 'carrier_origin',
                    value: _carrierOrigin,
                    labelText: 'Carrier Origin',
                    onChanged: (val) {
                      if (val != null) {
                        _carrierOrigin = val;
                        _onSegmentChanged();
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Iodine toggle
                  SwitchListTile(
                    title: const Text('Iodized'),
                    subtitle: Text(
                      _iodine == 'IO' ? 'Iodized (IO)' : 'Non-Iodized (NI)',
                    ),
                    value: _iodine == 'IO',
                    onChanged: (val) {
                      _iodine = val ? 'IO' : 'NI';
                      _onSegmentChanged();
                    },
                  ),

                  // GMO Status toggle
                  SwitchListTile(
                    title: const Text('GMO Status'),
                    subtitle: Text(
                      _gmoStatus == 'GM' ? 'GMO (GM)' : 'non-GMO IP (IP)',
                    ),
                    value: _gmoStatus == 'GM',
                    onChanged: (val) {
                      _gmoStatus = val ? 'GM' : 'IP';
                      _onSegmentChanged();
                    },
                  ),
                  const Divider(),

                  // Salt Content
                  EditableDropdown(
                    category: 'salt_pct',
                    value: _saltPct.toString(),
                    labelText: 'Salt Content',
                    isNumeric: true,
                    onChanged: (val) {
                      if (val != null) {
                        _saltPct = int.tryParse(val) ?? _saltPct;
                        _onSegmentChanged();
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Additive checkbox
                  CheckboxListTile(
                    title: const Text('Magnesium Stearate (MG)'),
                    subtitle: const Text('0.5% additive'),
                    value: _hasAdditive,
                    onChanged: _isGranulated
                        ? null // Locked on when granulated
                        : (val) {
                            _hasAdditive = val ?? false;
                            _onSegmentChanged();
                          },
                  ),

                  const SizedBox(height: 16),
                  // Extra Ingredients multi-select
                  _buildExtraIngredientsSection(),
                  const SizedBox(height: 16),

                  // Region
                  EditableDropdown(
                    category: 'region',
                    value: _region,
                    labelText: 'Region',
                    nullable: true,
                    onChanged: (val) {
                      _region = val;
                      _onSegmentChanged();
                    },
                  ),
                  const SizedBox(height: 24),
                  const Divider(),

                  // Description (auto-generated but editable)
                  TextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      helperText:
                          'Auto-generated from selections. Edit to customize.',
                    ),
                    onChanged: (_) => _descriptionManuallyEdited = true,
                  ),
                  const SizedBox(height: 16),

                  // Certificate of Origin
                  TextField(
                    controller: _certificateController,
                    decoration: const InputDecoration(
                      labelText: 'Certificate of Origin',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Comment
                  TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(labelText: 'Comment'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),

                  // Active toggle (edit mode only)
                  if (isEditing)
                    SwitchListTile(
                      title: const Text('Active'),
                      value: _active,
                      onChanged: (val) => setState(() => _active = val),
                    ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: _isSaving
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: _handleSave,
                            child: const Text('Save Formula'),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
