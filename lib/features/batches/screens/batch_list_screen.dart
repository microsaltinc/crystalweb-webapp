import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/user_facing_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../purchase_orders/widgets/po_assign_dialog.dart';
import '../models/batch.dart';
import '../providers/batch_provider.dart';
import '../providers/campaign_ownership_filter_provider.dart';
import '../providers/campaign_workflow_filter_provider.dart';
import '../widgets/batch_list_filter_chips.dart';
import '../widgets/campaign_edit_state_chip.dart';
import '../widgets/campaign_create_dialog.dart';
import '../widgets/campaign_owner_chip.dart';
import '../widgets/campaign_workflow_status_chip.dart';
import '../widgets/campaign_workflow_filter_bar.dart';
import '../widgets/ownership_filter_bar.dart';

class BatchListScreen extends ConsumerStatefulWidget {
  const BatchListScreen({super.key});

  @override
  ConsumerState<BatchListScreen> createState() => _BatchListScreenState();
}

class _BatchListScreenState extends ConsumerState<BatchListScreen> {
  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  DateTime? _fromDate;
  DateTime? _toDate;
  String? _selectedFormula;
  String? _selectedLotCode;
  String? _selectedPO;

  Color _statusColor(String status) {
    switch (status) {
      case 'processing':
        return AppColors.statusProcessing;
      case 'complete':
        return AppColors.statusComplete;
      case 'failed':
        return AppColors.statusFailed;
      default:
        return AppColors.statusPending;
    }
  }

  List<Batch> _applyFilters(List<Batch> batches) {
    var filtered = batches;
    if (_fromDate != null) {
      filtered = filtered
          .where((b) => !b.createdAt.isBefore(_fromDate!))
          .toList();
    }
    if (_toDate != null) {
      final endOfDay = DateTime(
        _toDate!.year,
        _toDate!.month,
        _toDate!.day,
        23,
        59,
        59,
      );
      filtered = filtered.where((b) => !b.createdAt.isAfter(endOfDay)).toList();
    }
    if (_selectedFormula != null) {
      filtered = filtered
          .where((b) => b.formulaCode == _selectedFormula)
          .toList();
    }
    if (_selectedLotCode != null) {
      filtered = filtered.where((b) => b.lotCode == _selectedLotCode).toList();
    }
    if (_selectedPO != null) {
      filtered = filtered
          .where((b) => b.purchaseOrderCode == _selectedPO)
          .toList();
    }
    return filtered;
  }

  void _clearFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _selectedFormula = null;
      _selectedLotCode = null;
      _selectedPO = null;
    });
    ref.read(campaignOwnershipFilterProvider.notifier).state =
        const OwnershipFilter.all();
    ref.read(campaignWorkflowFilterProvider.notifier).state = null;
  }

  bool get _hasLocalFilters =>
      _fromDate != null ||
      _toDate != null ||
      _selectedFormula != null ||
      _selectedLotCode != null ||
      _selectedPO != null;

  Widget _buildCampaignList(List<Batch> filtered, ThemeData theme) {
    if (_selectedPO != null) {
      return ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (context, index) =>
            _buildBatchTile(filtered[index], theme),
      );
    }

    final grouped = <String, List<Batch>>{};
    for (final batch in filtered) {
      final key = batch.purchaseOrderCode ?? 'Unassigned';
      grouped.putIfAbsent(key, () => []).add(batch);
    }
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == 'Unassigned') return 1;
        if (b == 'Unassigned') return -1;
        return a.compareTo(b);
      });

    final items = <Widget>[];
    for (final key in sortedKeys) {
      items.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Text(
            key == 'Unassigned' ? 'No PO' : 'PO: $key',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      for (final batch in grouped[key]!) {
        items.add(_buildBatchTile(batch, theme));
      }
    }

    return ListView(children: items);
  }

  Widget _buildBatchTile(Batch batch, ThemeData theme) {
    final poLabel = batch.purchaseOrderCode ?? '—';
    return ListTile(
      dense: true,
      title: Text(
        '${_dateFormat.format(batch.createdAt.toLocal())} | ${batch.identityLabel}  ${batch.formulaCode}',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${batch.sublotCount} sublots | ${batch.imageCount} imgs | ${batch.crystalCount} crystals (auto: ${batch.autoCrystalCount} / op: ${batch.operatorCrystalCount}) | ${batch.dryerCode.isEmpty ? 'Dryer: Not provided' : 'Dryer ${batch.dryerCode}'} | PO: $poLabel',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CampaignEditStateChip(batch: batch),
          const SizedBox(width: 4),
          CampaignConflictWarning(batch: batch),
          if (batch.unresolvedRegistrationConflictCount > 0)
            const SizedBox(width: 4),
          CampaignWorkflowStatusChip(
            label: batch.workflowStatusLabel,
            colorToken: batch.workflowStatusColor,
          ),
          const SizedBox(width: 4),
          CampaignOwnerChip(batch: batch, compact: true),
          const SizedBox(width: 4),
          InkWell(
            onTap: batch.isLocked
                ? null
                : () => showDialog(
                    context: context,
                    builder: (_) => PoAssignDialog(
                      batchId: batch.id,
                      currentPoId: batch.purchaseOrderId,
                      editable: !batch.isLocked,
                      expectedEditStateVersion: batch.editStateVersion,
                    ),
                  ),
            child: Chip(
              avatar: const Icon(Icons.receipt_long, size: 14),
              label: Text(poLabel, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          Chip(
            label: Text(
              batch.status,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            backgroundColor: _statusColor(batch.status),
          ),
        ],
      ),
      onTap: () => context.go('/batches/${batch.id}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final batchesAsync = ref.watch(batchListProvider);
    final ownershipFilter = ref.watch(campaignOwnershipFilterProvider);
    final workflowFiltered = ref.watch(campaignWorkflowFilterProvider) != null;
    final hasActiveFilters =
        _hasLocalFilters ||
        ownershipFilter.kind != OwnershipFilterKind.all ||
        workflowFiltered;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Flexible(
              child: Text('Campaigns', overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 12),
            IconButton.filled(
              key: const Key('create-batches-header'),
              tooltip: 'New Campaign',
              icon: const Icon(Icons.add),
              onPressed: () async {
                final batchId = await showCampaignCreateDialog(
                  context,
                  mode: 'production',
                );
                if (batchId != null && context.mounted) {
                  context.go('/batches/$batchId');
                }
              },
            ),
          ],
        ),
        actions: [
          if (hasActiveFilters)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              tooltip: 'Clear filters',
              onPressed: _clearFilters,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(batchListProvider),
          ),
        ],
      ),
      body: batchesAsync.when(
        data: (batches) {
          if (batches.isEmpty) {
            if (workflowFiltered) {
              return const Center(
                child: Text('No campaigns match the workflow status filter'),
              );
            }
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.science_outlined,
                    size: 64,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text('No campaigns yet', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Create a direct-upload destination to begin',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            );
          }

          final formulas =
              batches
                  .map((b) => b.formulaCode)
                  .where((f) => f.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();

          final lotCodes =
              batches
                  .map((b) => b.lotCode)
                  .where((code) => code.isNotEmpty)
                  .where((l) => l.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();

          final poCodes =
              batches
                  .map((b) => b.purchaseOrderCode)
                  .where((p) => p != null && p.isNotEmpty)
                  .cast<String>()
                  .toSet()
                  .toList()
                ..sort();

          final filtered = _applyFilters(batches);

          return Column(
            children: [
              _FilterBar(
                fromDate: _fromDate,
                toDate: _toDate,
                selectedFormula: _selectedFormula,
                selectedLotCode: _selectedLotCode,
                selectedPO: _selectedPO,
                formulas: formulas,
                lotCodes: lotCodes,
                poCodes: poCodes,
                onFromDateChanged: (d) => setState(() => _fromDate = d),
                onToDateChanged: (d) => setState(() => _toDate = d),
                onFormulaChanged: (f) => setState(() => _selectedFormula = f),
                onLotCodeChanged: (l) => setState(() => _selectedLotCode = l),
                onPOChanged: (p) => setState(() => _selectedPO = p),
              ),
              if (hasActiveFilters)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${filtered.length} of ${batches.length} campaigns',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          workflowFiltered
                              ? 'No campaigns match the workflow status filter'
                              : 'No campaigns match filters',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      )
                    : _buildCampaignList(filtered, theme),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) =>
            Center(child: Text(userFacingError(err, action: 'load batches'))),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.fromDate,
    required this.toDate,
    required this.selectedFormula,
    required this.selectedLotCode,
    required this.selectedPO,
    required this.formulas,
    required this.lotCodes,
    required this.poCodes,
    required this.onFromDateChanged,
    required this.onToDateChanged,
    required this.onFormulaChanged,
    required this.onLotCodeChanged,
    required this.onPOChanged,
  });

  final DateTime? fromDate;
  final DateTime? toDate;
  final String? selectedFormula;
  final String? selectedLotCode;
  final String? selectedPO;
  final List<String> formulas;
  final List<String> lotCodes;
  final List<String> poCodes;
  final ValueChanged<DateTime?> onFromDateChanged;
  final ValueChanged<DateTime?> onToDateChanged;
  final ValueChanged<String?> onFormulaChanged;
  final ValueChanged<String?> onLotCodeChanged;
  final ValueChanged<String?> onPOChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.filter_list, size: 18, color: theme.colorScheme.outline),
          const OwnershipFilterBar(),
          const CampaignWorkflowFilterBar(),
          BatchDateFilterChip(
            label: 'From',
            date: fromDate,
            lastDate: toDate ?? DateTime.now(),
            onChanged: onFromDateChanged,
          ),
          BatchDateFilterChip(
            label: 'To',
            date: toDate,
            firstDate: fromDate,
            lastDate: DateTime.now(),
            onChanged: onToDateChanged,
          ),
          BatchDropdownFilterChip(
            label: 'Formula',
            value: selectedFormula,
            options: formulas,
            onChanged: onFormulaChanged,
          ),
          BatchDropdownFilterChip(
            label: 'Lot Code',
            value: selectedLotCode,
            options: lotCodes,
            onChanged: onLotCodeChanged,
          ),
          BatchDropdownFilterChip(
            label: 'PO',
            value: selectedPO,
            options: poCodes,
            onChanged: onPOChanged,
          ),
        ],
      ),
    );
  }
}
