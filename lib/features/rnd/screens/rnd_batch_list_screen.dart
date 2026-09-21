import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/user_facing_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../batches/models/batch.dart';
import '../../batches/providers/campaign_ownership_filter_provider.dart';
import '../../batches/providers/campaign_workflow_filter_provider.dart';
import '../../batches/widgets/batch_list_filter_chips.dart';
import '../../batches/widgets/campaign_edit_state_chip.dart';
import '../../batches/widgets/campaign_create_dialog.dart';
import '../../batches/widgets/campaign_owner_chip.dart';
import '../../batches/widgets/campaign_workflow_status_chip.dart';
import '../../batches/widgets/campaign_workflow_filter_bar.dart';
import '../../batches/widgets/ownership_filter_bar.dart';
import '../../projects/models/project.dart';
import '../../projects/providers/project_provider.dart';
import '../../projects/widgets/project_assign_dialog.dart';
import '../providers/rnd_batch_provider.dart';
import '../rnd_batch_filters.dart';

class RndBatchListScreen extends ConsumerStatefulWidget {
  const RndBatchListScreen({super.key});

  @override
  ConsumerState<RndBatchListScreen> createState() => _RndBatchListScreenState();
}

class _RndBatchListScreenState extends ConsumerState<RndBatchListScreen> {
  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  static const _allProjects = '__all_projects__';
  static const _noProject = '__no_project__';
  String _filter = _allProjects;
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _selectedFormula;

  bool get _hasLocalFilters =>
      _fromDate != null ||
      _toDate != null ||
      _selectedFormula != null ||
      _filter != _allProjects;

  void _clearFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _selectedFormula = null;
      _filter = _allProjects;
    });
    ref.read(campaignOwnershipFilterProvider.notifier).state =
        const OwnershipFilter.all();
    ref.read(campaignWorkflowFilterProvider.notifier).state = null;
  }

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

  @override
  Widget build(BuildContext context) {
    final batchesAsync = ref.watch(rndBatchListProvider);
    final ownershipFilter = ref.watch(campaignOwnershipFilterProvider);
    final projectsAsync = ref.watch(projectListProvider);
    final theme = Theme.of(context);
    final workflowFiltered = ref.watch(campaignWorkflowFilterProvider) != null;
    final hasActiveFilters =
        _hasLocalFilters ||
        ownershipFilter.kind != OwnershipFilterKind.all ||
        workflowFiltered;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.biotech, color: theme.colorScheme.tertiary),
            const SizedBox(width: 8),
            const Flexible(
              child: Text('R&D Experiments', overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 12),
            IconButton.filled(
              key: const Key('create-rnd-header'),
              tooltip: 'New R&D experiment',
              icon: const Icon(Icons.add),
              onPressed: () async {
                final batchId = await showCampaignCreateDialog(
                  context,
                  mode: 'rnd',
                );
                if (batchId != null && context.mounted) {
                  context.go('/rnd/$batchId');
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
            onPressed: () {
              ref.invalidate(rndBatchListProvider);
              ref.invalidate(projectListProvider);
            },
          ),
        ],
      ),
      body: batchesAsync.when(
        data: (batches) => projectsAsync.when(
          data: (projects) => _buildContent(
            theme,
            batches,
            projects,
            workflowFiltered: workflowFiltered,
            hasActiveFilters: hasActiveFilters,
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text(userFacingError(error, action: 'load Projects')),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text(userFacingError(err, action: 'load R&D batches')),
        ),
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    List<Batch> batches,
    List<Project> projects, {
    required bool workflowFiltered,
    required bool hasActiveFilters,
  }) {
    if (batches.isEmpty) {
      if (workflowFiltered) {
        return const Center(
          child: Text('No experiments match the workflow status filter'),
        );
      }
      if (hasActiveFilters) {
        return const Center(child: Text('No experiments match filters'));
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.biotech_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No R&D experiments yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Create a direct-upload destination to begin'),
          ],
        ),
      );
    }

    final sortedProjects = [...projects]
      ..sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
    final formulas =
        batches
            .map((batch) => batch.formulaCode)
            .where((formula) => formula.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final filtered = filterRndBatches(
      batches,
      fromDate: _fromDate,
      toDate: _toDate,
      formulaCode: _selectedFormula,
      projectId: _filter == _allProjects || _filter == _noProject
          ? null
          : _filter,
      noProject: _filter == _noProject,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  Icons.filter_list,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
                const OwnershipFilterBar(),
                const CampaignWorkflowFilterBar(),
                BatchDateFilterChip(
                  label: 'From',
                  date: _fromDate,
                  lastDate: _toDate ?? DateTime.now(),
                  onChanged: (date) => setState(() => _fromDate = date),
                ),
                BatchDateFilterChip(
                  label: 'To',
                  date: _toDate,
                  firstDate: _fromDate,
                  lastDate: DateTime.now(),
                  onChanged: (date) => setState(() => _toDate = date),
                ),
                BatchDropdownFilterChip(
                  label: 'Formula',
                  value: _selectedFormula,
                  options: formulas,
                  onChanged: (formula) =>
                      setState(() => _selectedFormula = formula),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('project-filter'),
                  initialValue: _filter,
                  decoration: const InputDecoration(
                    labelText: 'Filter by Project',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: _allProjects,
                      child: Text('All Projects'),
                    ),
                    for (final project in sortedProjects)
                      DropdownMenuItem(
                        value: project.id,
                        child: Text(project.name),
                      ),
                    const DropdownMenuItem(
                      value: _noProject,
                      child: Text('No Project'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _filter = value ?? _allProjects),
                ),
              ),
              if (_filter != _allProjects) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _filter = _allProjects),
                  child: const Text('Clear filter'),
                ),
              ],
            ],
          ),
        ),
        if (hasActiveFilters)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${filtered.length} of ${batches.length} experiments',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No experiments match filters'))
              : _filter == _allProjects
              ? _buildGroupedList(filtered)
              : ListView(children: filtered.map(_buildTile).toList()),
        ),
      ],
    );
  }

  Widget _buildGroupedList(List<Batch> batches) {
    final groups = <String?, List<Batch>>{};
    for (final batch in batches) {
      groups.putIfAbsent(batch.projectId, () => []).add(batch);
    }
    final namedIds = groups.keys.whereType<String>().toList()
      ..sort((left, right) {
        final leftName = groups[left]!.first.projectName ?? '';
        final rightName = groups[right]!.first.projectName ?? '';
        return leftName.toLowerCase().compareTo(rightName.toLowerCase());
      });
    final sections = <Widget>[];
    for (final id in namedIds) {
      final group = groups[id]!;
      sections.add(
        _groupHeader(
          '${group.first.projectName ?? 'Project'} (${group.length})',
        ),
      );
      sections.addAll(group.map(_buildTile));
    }
    final unassigned = groups[null] ?? const <Batch>[];
    if (unassigned.isNotEmpty) {
      sections.add(_groupHeader('No Project (${unassigned.length})'));
      sections.addAll(unassigned.map(_buildTile));
    }
    return ListView(children: sections);
  }

  Widget _groupHeader(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(label, style: Theme.of(context).textTheme.titleSmall),
  );

  Widget _buildTile(Batch batch) => _RndBatchTile(
    batch: batch,
    dateFormat: _dateFormat,
    statusColor: _statusColor(batch.status),
    onTap: () => context.go('/rnd/${batch.id}'),
    onProjectTap: () => showDialog<void>(
      context: context,
      builder: (_) => ProjectAssignDialog(
        batchId: batch.id,
        currentProjectId: batch.projectId,
        editable: !batch.isLocked,
        expectedEditStateVersion: batch.editStateVersion,
      ),
    ),
  );
}

class _RndBatchTile extends StatelessWidget {
  const _RndBatchTile({
    required this.batch,
    required this.dateFormat,
    required this.statusColor,
    required this.onTap,
    required this.onProjectTap,
  });

  final Batch batch;
  final DateFormat dateFormat;
  final Color statusColor;
  final VoidCallback onTap;
  final VoidCallback onProjectTap;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: Icon(Icons.biotech, color: Theme.of(context).colorScheme.tertiary),
    title: Text(
      '${dateFormat.format(batch.createdAt.toLocal())} | ${batch.identityLabel}  ${batch.formulaCode}',
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      '${batch.sublotCount} sublots | ${batch.imageCount} imgs | ${batch.crystalCount} crystals',
    ),
    trailing: Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        CampaignEditStateChip(batch: batch),
        CampaignConflictWarning(batch: batch),
        CampaignWorkflowStatusChip(
          label: batch.workflowStatusLabel,
          colorToken: batch.workflowStatusColor,
        ),
        CampaignOwnerChip(batch: batch, compact: true),
        Semantics(
          button: true,
          label: 'Assign Project for ${batch.identityLabel}',
          child: ActionChip(
            tooltip: 'Assign Project for ${batch.identityLabel}',
            avatar: const Icon(Icons.folder_outlined, size: 16),
            label: Text(batch.projectName ?? 'No Project'),
            onPressed: onProjectTap,
          ),
        ),
        Chip(
          label: Text(
            batch.status,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          backgroundColor: statusColor,
        ),
      ],
    ),
    onTap: onTap,
  );
}
