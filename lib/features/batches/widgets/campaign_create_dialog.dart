import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../models/lot_code.dart';
import '../models/batch.dart';
import '../../formulas/models/formula.dart';
import '../../formulas/providers/formula_provider.dart';
import '../../rnd/providers/rnd_batch_provider.dart';
import '../providers/batch_provider.dart';

Future<String?> showCampaignCreateDialog(
  BuildContext context, {
  required String mode,
}) => showDialog<String>(
  context: context,
  builder: (_) => CampaignCreateDialog(mode: mode),
);

/// Creates the server-owned Campaign/Sublot/Bag destination used by direct
/// browser uploads. It intentionally creates no placeholder Image because the
/// first exact TIFF/TXT upload owns image number 1.
class CampaignCreateDialog extends ConsumerStatefulWidget {
  const CampaignCreateDialog({super.key, required this.mode});

  final String mode;

  @override
  ConsumerState<CampaignCreateDialog> createState() =>
      _CampaignCreateDialogState();
}

class _CampaignCreateDialogState extends ConsumerState<CampaignCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _creationRequestId = const Uuid().v4();
  final _nameController = TextEditingController();
  bool _customNameMode = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  DateTime _date = DateTime.now();
  String _productOfDay = 'A';
  int _campaignNumber = 1;
  String? _formulaId;
  String? _dryerId;
  bool _submitting = false;
  String? _error;

  bool get _rnd => widget.mode == 'rnd';

  @override
  Widget build(BuildContext context) {
    final formulas = ref.watch(formulaListProvider);
    final dryers = _customNameMode
        ? const AsyncData<List<Dryer>>([])
        : ref.watch(dryerListProvider);
    return AlertDialog(
      title: Text(_rnd ? 'New R&D experiment' : 'New Campaign'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Standard')),
                    ButtonSegment(value: true, label: Text('Custom name')),
                  ],
                  selected: {_customNameMode},
                  onSelectionChanged: _submitting
                      ? null
                      : (value) => setState(() {
                          _customNameMode = value.single;
                          _error = null;
                          _formKey.currentState?.reset();
                        }),
                ),
                const SizedBox(height: 16),
                if (_customNameMode) ...[
                  TextFormField(
                    key: const Key('campaign-custom-name'),
                    controller: _nameController,
                    enabled: !_submitting,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: _rnd ? 'Experiment name' : 'Campaign name',
                      hintText: 'e.g. September drying trial',
                    ),
                    validator: (value) {
                      final name = (value ?? '').trim();
                      if (name.isEmpty) return 'Enter a name';
                      if (name.runes.length > 100) {
                        return 'Use 100 characters or fewer';
                      }
                      if (RegExp(
                        r'[\x00-\x1f\x7f-\x9f\u2028\u2029]',
                      ).hasMatch(name)) {
                        return 'Use a single line without control characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Start with Sublot A and Bag 1. You can add more later. '
                  'Upload matching microscope TIFF and TXT files after creating your campaign or experiment.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                formulas.when(
                  data: (items) => _formulaField(items),
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) =>
                      Text(userFacingError(error, action: 'load formulas')),
                ),
                const SizedBox(height: 12),
                if (!_customNameMode) ...[
                  dryers.when(
                    data: (items) => DropdownButtonFormField<String>(
                      key: const Key('campaign-dryer'),
                      initialValue: _dryerId,
                      decoration: const InputDecoration(labelText: 'Dryer'),
                      items: [
                        for (final dryer in items)
                          DropdownMenuItem(
                            value: dryer.id,
                            child: Text('${dryer.code} — ${dryer.name}'),
                          ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _dryerId = value),
                      validator: (value) =>
                          value == null ? 'Select a dryer' : null,
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (error, _) =>
                        Text(userFacingError(error, action: 'load dryers')),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Production date'),
                    subtitle: Text(_dateLabel(_date)),
                    trailing: TextButton(
                      onPressed: _submitting ? null : _pickDate,
                      child: const Text('Change'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: const Key('campaign-product-of-day'),
                          initialValue: _productOfDay,
                          decoration: const InputDecoration(
                            labelText: 'Product of day',
                          ),
                          items: [
                            for (var code = 65; code <= 90; code++)
                              DropdownMenuItem(
                                value: String.fromCharCode(code),
                                child: Text(String.fromCharCode(code)),
                              ),
                          ],
                          onChanged: _submitting
                              ? null
                              : (value) => setState(
                                  () => _productOfDay = value ?? 'A',
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: const Key('campaign-number'),
                          initialValue: _campaignNumber,
                          decoration: const InputDecoration(
                            labelText: 'Campaign number',
                          ),
                          items: [
                            for (var value = 1; value <= 10; value++)
                              DropdownMenuItem(
                                value: value,
                                child: Text('$value'),
                              ),
                          ],
                          onChanged: _submitting
                              ? null
                              : (value) => setState(
                                  () => _campaignNumber = value ?? 1,
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _DestinationPreview(
                    date: _date,
                    productOfDay: _productOfDay,
                    campaignNumber: _campaignNumber,
                    dryerId: _dryerId,
                    dryers: dryers.value ?? const [],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('create-direct-upload-campaign'),
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text(
            _submitting
                ? 'Creating…'
                : (_rnd ? 'Create experiment' : 'Create campaign'),
          ),
        ),
      ],
    );
  }

  Widget _formulaField(List<Formula> formulas) {
    final eligible =
        formulas
            .where((formula) => formula.active && formula.isTesting == _rnd)
            .toList()
          ..sort((left, right) => left.code.compareTo(right.code));
    return DropdownButtonFormField<String>(
      key: const Key('campaign-formula'),
      initialValue: eligible.any((item) => item.id == _formulaId)
          ? _formulaId
          : null,
      decoration: InputDecoration(
        labelText: _rnd ? 'Testing formula' : 'Formula',
        helperText: eligible.isEmpty
            ? 'No active ${_rnd ? 'testing' : 'production'} formulas are available.'
            : null,
      ),
      items: [
        for (final formula in eligible)
          DropdownMenuItem(value: formula.id, child: Text(formula.code)),
      ],
      onChanged: _submitting
          ? null
          : (value) => setState(() => _formulaId = value),
      validator: (value) => value == null ? 'Select a formula' : null,
    );
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2099, 12, 31),
    );
    if (selected != null && mounted) setState(() => _date = selected);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_formulaId == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      late Batch created;
      if (_customNameMode) {
        created = await createCustomBatch(
          ref.read(apiClientProvider),
          formulaId: _formulaId!,
          name: _nameController.text.trim(),
          mode: widget.mode,
          creationRequestId: _creationRequestId,
        );
      } else {
        final dryers = await ref.read(dryerListProvider.future);
        final dryer = dryers.where((item) => item.id == _dryerId).firstOrNull;
        if (dryer == null) throw StateError('Select an available dryer');
        final lot = LotCode(
          dryerCode: dryer.code,
          year: _date.year % 100,
          julianDay: LotCode.julianDayFromDate(_date),
          productOfDay: _productOfDay,
          campaignNum: _campaignNumber,
        );
        created = await createBatch(
          ref.read(apiClientProvider),
          formulaId: _formulaId!,
          dryerId: dryer.id,
          lotCode: lot.campaignCode,
          campaignNum: _campaignNumber,
          julianDate: LotCode.julianDayFromDate(_date),
          year: _date.year,
          sublotLetters: const ['A'],
          mode: widget.mode,
          createPlaceholderImages: false,
          creationRequestId: _creationRequestId,
        );
      }
      ref.invalidate(batchListProvider);
      ref.invalidate(rndBatchListProvider);
      if (mounted) Navigator.of(context).pop(created.id);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = userFacingError(
            error,
            action: _rnd ? 'create experiment' : 'create campaign',
          );
        });
      }
    }
  }
}

class _DestinationPreview extends StatelessWidget {
  const _DestinationPreview({
    required this.date,
    required this.productOfDay,
    required this.campaignNumber,
    required this.dryerId,
    required this.dryers,
  });

  final DateTime date;
  final String productOfDay;
  final int campaignNumber;
  final String? dryerId;
  final List<Dryer> dryers;

  @override
  Widget build(BuildContext context) {
    final dryer = dryers.where((item) => item.id == dryerId).firstOrNull;
    final lot = dryer == null
        ? null
        : LotCode(
            dryerCode: dryer.code,
            year: date.year % 100,
            julianDay: LotCode.julianDayFromDate(date),
            productOfDay: productOfDay,
            campaignNum: campaignNumber,
          );
    return Card(
      child: ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: const Text('Starting structure'),
        subtitle: Text(
          lot == null
              ? 'Select a dryer to preview the Campaign.'
              : '${lot.campaignCode} › Sublot A › Bag 1',
        ),
      ),
    );
  }
}

String _dateLabel(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
