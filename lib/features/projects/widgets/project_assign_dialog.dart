import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../batches/providers/batch_provider.dart';
import '../../rnd/providers/rnd_batch_provider.dart';
import '../models/project.dart';
import '../providers/project_provider.dart';

class ProjectAssignDialog extends ConsumerStatefulWidget {
  const ProjectAssignDialog({
    super.key,
    required this.batchId,
    required this.currentProjectId,
    this.editable = true,
    this.expectedEditStateVersion,
  });

  final String batchId;
  final String? currentProjectId;
  final bool editable;
  final int? expectedEditStateVersion;

  @override
  ConsumerState<ProjectAssignDialog> createState() =>
      _ProjectAssignDialogState();
}

class _ProjectAssignDialogState extends ConsumerState<ProjectAssignDialog> {
  final _nameController = TextEditingController();
  bool _saving = false;
  String? _error;
  Project? _createdProject;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _invalidateAfterAssignment() {
    ref.invalidate(rndBatchListProvider);
    ref.invalidate(batchListProvider);
    ref.invalidate(batchDetailProvider(widget.batchId));
  }

  Future<void> _assign(String? projectId) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await assignProject(
        ref.read(apiClientProvider),
        batchId: widget.batchId,
        projectId: projectId,
        expectedEditStateVersion: widget.expectedEditStateVersion,
      );
      _invalidateAfterAssignment();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = projectErrorMessage(error);
        });
      }
    }
  }

  Future<void> _createAndAssign() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Project name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final project = await createProject(ref.read(apiClientProvider), name);
      _createdProject = project;
      ref.invalidate(projectListProvider);
      await assignProject(
        ref.read(apiClientProvider),
        batchId: widget.batchId,
        projectId: project.id,
        expectedEditStateVersion: widget.expectedEditStateVersion,
      );
      _invalidateAfterAssignment();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = projectErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectListProvider);
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Assign Project'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            projectsAsync.when(
              data: (projects) => _buildProjectList(projects),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Text(
                'Unable to load Projects: ${projectErrorMessage(error)}',
              ),
            ),
            const Divider(height: 24),
            Text('Create new Project:', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    enabled: widget.editable && !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Project name',
                      isDense: true,
                    ),
                    onSubmitted: _saving ? null : (_) => _createAndAssign(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Create and assign Project',
                  icon: const Icon(Icons.add_circle),
                  onPressed: _saving || !widget.editable
                      ? null
                      : _createAndAssign,
                ),
              ],
            ),
            if (!widget.editable) ...[
              const SizedBox(height: 8),
              const Text(
                'Read-only — unlock the campaign to assign a Project.',
              ),
            ],
            if (_createdProject != null && _error != null) ...[
              const SizedBox(height: 8),
              Text(
                '${_createdProject!.name} was created. Select it above to retry assignment.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildProjectList(List<Project> projects) {
    final available = [...projects];
    if (_createdProject != null &&
        !available.any((project) => project.id == _createdProject!.id)) {
      available.add(_createdProject!);
    }
    available.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            dense: true,
            selected: widget.currentProjectId == null,
            leading: widget.currentProjectId == null
                ? const Icon(Icons.check_circle, size: 18)
                : const Icon(Icons.folder_off_outlined, size: 18),
            title: const Text('No Project'),
            onTap:
                _saving || !widget.editable || widget.currentProjectId == null
                ? null
                : () => _assign(null),
          ),
          if (available.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No Projects yet. Create one below.'),
            ),
          for (final project in available)
            ListTile(
              dense: true,
              selected: project.id == widget.currentProjectId,
              leading: project.id == widget.currentProjectId
                  ? const Icon(Icons.check_circle, size: 18)
                  : const Icon(Icons.folder_outlined, size: 18),
              title: Text(project.name),
              onTap:
                  _saving ||
                      !widget.editable ||
                      project.id == widget.currentProjectId
                  ? null
                  : () => _assign(project.id),
            ),
        ],
      ),
    );
  }
}
