import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/user_facing_error.dart';
import '../../microscope_upload/widgets/microscope_upload_dialog.dart';
import '../models/campaign_structure.dart';
import '../providers/campaign_structure_provider.dart';

int? _parseBagNumber(String value) {
  final normalized = value.trim();
  final match = RegExp(
    r'^(?:bag\s*)?([0-9]+)$',
    caseSensitive: false,
  ).firstMatch(normalized);
  return match == null ? null : int.tryParse(match.group(1)!);
}

Future<void> showCampaignStructureHelp(
  BuildContext context,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: const Text('Campaign structure'),
    content: const SingleChildScrollView(
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Campaign → Sublot → Bag → SEM Images → Crystals',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              'A Campaign contains one or more Sublots. Each Sublot contains one or more Bags, and each Bag groups its SEM Images and measured Crystals.',
            ),
            SizedBox(height: 12),
            Text(
              'Qualification is recorded at Bag and Campaign levels. Rejected Bags stay visible and auditable but are excluded from accepted totals and current reports. Sublots do not have a separate qualification status.',
            ),
            SizedBox(height: 12),
            Text(
              'Renaming a Sublot or moving or renumbering a Bag changes its current logical location. Source identity never changes, and original files are never renamed or deleted.',
            ),
            SizedBox(height: 12),
            Text(
              'Qualification-relevant structure changes return a finalized Campaign to Pending Review. Cosmetic labels and notes do not.',
            ),
            SizedBox(height: 12),
            Text(
              'Only empty, history-free Sublots and Bags can be permanently deleted. Everything else is archived and can be restored when its identifier is available.',
            ),
            SizedBox(height: 16),
            Text(
              'Documentation: Campaign Qualification and Bag/Sublot Management',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'microsalt.in/tech/projects/crystal_analysis/features/campaign-qualification',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Close'),
      ),
    ],
  ),
);

class CampaignStructureSection extends ConsumerWidget {
  const CampaignStructureSection({
    super.key,
    required this.batchId,
    required this.readOnly,
    this.supportsMicroscopeUpload,
  });
  final String batchId;
  final bool readOnly;
  final bool? supportsMicroscopeUpload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(campaignStructureProvider(batchId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: state.when(
          loading: () => const LinearProgressIndicator(
            semanticsLabel: 'Loading campaign structure',
          ),
          error: (error, _) =>
              Text(userFacingError(error, action: 'load structure')),
          data: (structure) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Physical Structure',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (!readOnly && !structure.isLocked)
                    IconButton(
                      tooltip: 'Add Sublot',
                      onPressed: () => _addSublot(context, ref, structure),
                      icon: const Icon(Icons.add),
                    ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Lot Code: ${structure.lotCode} (source: ${structure.sourceLotCode})',
                    ),
                  ),
                  if (!readOnly && !structure.isLocked)
                    IconButton(
                      tooltip: 'Edit Lot Code',
                      onPressed: () => _editLot(context, ref, structure),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                ],
              ),
              if (structure.isLocked || readOnly)
                const Text('Locked — structure is read-only.'),
              if (structure.activeSublots.isEmpty)
                const Text('No active Sublots.'),
              for (final sublot in structure.activeSublots)
                ExpansionTile(
                  key: ValueKey('structure-sublot-${sublot.id}'),
                  title: Text(
                    'Sublot ${sublot.identifier}${sublot.label == null ? '' : ' — ${sublot.label}'}',
                  ),
                  subtitle: sublot.sourceIdentifier == sublot.identifier
                      ? null
                      : Text('Source Sublot ${sublot.sourceIdentifier}'),
                  trailing: readOnly || structure.isLocked
                      ? null
                      : Wrap(
                          children: [
                            IconButton(
                              tooltip: 'Edit Sublot',
                              onPressed: () =>
                                  _editSublot(context, ref, structure, sublot),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Add Bag',
                              onPressed: () =>
                                  _addBag(context, ref, structure, sublot),
                              icon: const Icon(Icons.add_box_outlined),
                            ),
                            IconButton(
                              tooltip: sublot.capabilities.canDelete
                                  ? 'Delete Sublot'
                                  : 'Archive Sublot',
                              onPressed: () => _removeSublot(
                                context,
                                ref,
                                structure,
                                sublot,
                              ),
                              icon: Icon(
                                sublot.capabilities.canDelete
                                    ? Icons.delete_outline
                                    : Icons.archive_outlined,
                              ),
                            ),
                          ],
                        ),
                  children: [
                    if (sublot.bags.isEmpty)
                      const ListTile(title: Text('Empty Sublot')),
                    for (final bag in sublot.bags)
                      ListTile(
                        title: Text(
                          'Bag ${bag.number}${bag.isExcluded ? ' — Excluded' : ''}',
                        ),
                        subtitle: Text(
                          'Source Bag ${bag.sourceNumber} · ${bag.imageCount} image(s)',
                        ),
                        trailing: readOnly || structure.isLocked
                            ? null
                            : Wrap(
                                children: [
                                  if (supportsMicroscopeUpload ?? true)
                                    IconButton(
                                      tooltip: 'Add microscope files',
                                      icon: const Icon(
                                        Icons.add_photo_alternate_outlined,
                                      ),
                                      onPressed: () => showMicroscopeUploadDialog(
                                        context,
                                        batchId: structure.batchId,
                                        bagId: bag.id,
                                        bagNumber: bag.number,
                                        destinationLabel:
                                            '${structure.mode == 'rnd' ? 'R&D' : 'Production'} ${structure.lotCode} › Sublot ${sublot.identifier} › Bag ${bag.number}',
                                        editStateVersion:
                                            structure.editStateVersion,
                                        contentRevision:
                                            structure.contentRevision,
                                      ),
                                    ),
                                  IconButton(
                                    tooltip: 'Edit or move Bag',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () =>
                                        _editBag(context, ref, structure, bag),
                                  ),
                                  IconButton(
                                    tooltip: bag.capabilities.canDelete
                                        ? 'Delete Bag'
                                        : 'Archive Bag',
                                    icon: Icon(
                                      bag.capabilities.canDelete
                                          ? Icons.delete_outline
                                          : Icons.archive_outlined,
                                    ),
                                    onPressed: () => _removeBag(
                                      context,
                                      ref,
                                      structure,
                                      bag,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                  ],
                ),
              if (structure.archivedSublots.isNotEmpty ||
                  structure.archivedBags.isNotEmpty) ...[
                const Divider(),
                Text(
                  'Archived Structure',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final sublot in structure.archivedSublots)
                  ListTile(
                    title: Text('Sublot ${sublot.identifier} (Archived)'),
                    trailing: readOnly || structure.isLocked
                        ? null
                        : TextButton(
                            onPressed: () =>
                                _restoreSublot(context, ref, structure, sublot),
                            child: const Text('Restore'),
                          ),
                  ),
                for (final bag in structure.archivedBags)
                  ListTile(
                    title: Text('Bag ${bag.number} (Archived)'),
                    trailing: readOnly || structure.isLocked
                        ? null
                        : TextButton(
                            onPressed: () =>
                                _restoreBag(context, ref, structure, bag),
                            child: const Text('Restore'),
                          ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editValue(
    BuildContext context, {
    required String title,
    required String label,
    String initialValue = '',
    TextInputType? keyboardType,
    required Future<Object> Function(String value) submit,
  }) => showDialog<void>(
    context: context,
    builder: (dialogContext) => _EditValueDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      keyboardType: keyboardType,
      submit: submit,
    ),
  );

  Future<void> _editLot(
    BuildContext context,
    WidgetRef ref,
    CampaignStructure state,
  ) => _editValue(
    context,
    title: 'Edit Lot Code',
    label: 'Lot Code',
    initialValue: state.lotCode,
    submit: (value) => ref
        .read(campaignStructureActionsProvider)
        .updateLot(
          batchId,
          value,
          editStateVersion: state.editStateVersion,
          contentRevision: state.contentRevision,
        ),
  );

  Future<void> _addSublot(
    BuildContext context,
    WidgetRef ref,
    CampaignStructure state,
  ) => _editValue(
    context,
    title: 'Add Sublot',
    label: 'Identifier A–Z',
    submit: (value) => ref
        .read(campaignStructureActionsProvider)
        .addSublot(
          batchId,
          value,
          editStateVersion: state.editStateVersion,
          contentRevision: state.contentRevision,
        ),
  );

  Future<void> _editSublot(
    BuildContext context,
    WidgetRef ref,
    CampaignStructure state,
    CampaignSublot sublot,
  ) => _editValue(
    context,
    title: 'Edit Sublot',
    label: 'Identifier A–Z',
    initialValue: sublot.identifier,
    submit: (value) => ref
        .read(campaignStructureActionsProvider)
        .updateSublot(
          batchId,
          sublot.id,
          {'identifier': value},
          editStateVersion: state.editStateVersion,
          contentRevision: state.contentRevision,
        ),
  );

  Future<void> _addBag(
    BuildContext context,
    WidgetRef ref,
    CampaignStructure state,
    CampaignSublot sublot,
  ) => _editValue(
    context,
    title: 'Add Bag',
    label: 'Positive Bag number',
    keyboardType: TextInputType.number,
    submit: (value) {
      final number = _parseBagNumber(value);
      if (number == null || number <= 0) {
        throw const FormatException('Enter a positive Bag number.');
      }
      return ref
          .read(campaignStructureActionsProvider)
          .addBag(
            batchId,
            sublot.id,
            number,
            editStateVersion: state.editStateVersion,
            contentRevision: state.contentRevision,
          );
    },
  );

  Future<void> _editBag(
    BuildContext context,
    WidgetRef ref,
    CampaignStructure state,
    CampaignBag bag,
  ) => showDialog<void>(
    context: context,
    builder: (dialogContext) => _EditBagDialog(
      batchId: batchId,
      structure: state,
      bag: bag,
      actions: ref.read(campaignStructureActionsProvider),
    ),
  );

  Future<void> _removeBag(
    BuildContext context,
    WidgetRef ref,
    CampaignStructure state,
    CampaignBag bag,
  ) => _run(
    context,
    () => bag.capabilities.canDelete
        ? ref
              .read(campaignStructureActionsProvider)
              .deleteBag(
                batchId,
                bag.id,
                editStateVersion: state.editStateVersion,
                contentRevision: state.contentRevision,
              )
        : ref
              .read(campaignStructureActionsProvider)
              .archiveBag(
                batchId,
                bag.id,
                editStateVersion: state.editStateVersion,
                contentRevision: state.contentRevision,
              ),
  );
  Future<void> _removeSublot(
    BuildContext context,
    WidgetRef ref,
    CampaignStructure state,
    CampaignSublot sublot,
  ) => _run(
    context,
    () => sublot.capabilities.canDelete
        ? ref
              .read(campaignStructureActionsProvider)
              .deleteSublot(
                batchId,
                sublot.id,
                editStateVersion: state.editStateVersion,
                contentRevision: state.contentRevision,
              )
        : ref
              .read(campaignStructureActionsProvider)
              .archiveSublot(
                batchId,
                sublot.id,
                editStateVersion: state.editStateVersion,
                contentRevision: state.contentRevision,
              ),
  );
  Future<void> _restoreBag(
    BuildContext context,
    WidgetRef ref,
    CampaignStructure state,
    CampaignBag bag,
  ) => _run(
    context,
    () => ref
        .read(campaignStructureActionsProvider)
        .restoreBag(
          batchId,
          bag.id,
          editStateVersion: state.editStateVersion,
          contentRevision: state.contentRevision,
        ),
  );
  Future<void> _restoreSublot(
    BuildContext context,
    WidgetRef ref,
    CampaignStructure state,
    CampaignSublot sublot,
  ) => _run(
    context,
    () => ref
        .read(campaignStructureActionsProvider)
        .restoreSublot(
          batchId,
          sublot.id,
          editStateVersion: state.editStateVersion,
          contentRevision: state.contentRevision,
        ),
  );
  Future<void> _run(
    BuildContext context,
    Future<Object> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(error, action: 'change campaign structure'),
            ),
          ),
        );
      }
    }
  }
}

class _EditValueDialog extends StatefulWidget {
  const _EditValueDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    this.keyboardType,
    required this.submit,
  });

  final String title;
  final String label;
  final String initialValue;
  final TextInputType? keyboardType;
  final Future<Object> Function(String value) submit;

  @override
  State<_EditValueDialog> createState() => _EditValueDialogState();
}

class _EditValueDialogState extends State<_EditValueDialog> {
  late final TextEditingController _controller;
  bool _busy = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _submitError = '${widget.label} is required.');
      return;
    }
    setState(() {
      _busy = true;
      _submitError = null;
    });
    try {
      await widget.submit(value);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _submitError = error is FormatException
              ? error.message.toString()
              : userFacingError(error, action: 'save campaign structure');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          enabled: !_busy,
          keyboardType: widget.keyboardType,
          decoration: InputDecoration(labelText: widget.label),
        ),
        if (_submitError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _submitError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
    ],
  );
}

class _EditBagDialog extends StatefulWidget {
  const _EditBagDialog({
    required this.batchId,
    required this.structure,
    required this.bag,
    required this.actions,
  });

  final String batchId;
  final CampaignStructure structure;
  final CampaignBag bag;
  final CampaignStructureActions actions;

  @override
  State<_EditBagDialog> createState() => _EditBagDialogState();
}

class _EditBagDialogState extends State<_EditBagDialog> {
  late final TextEditingController _numberController;
  late String _destinationId;
  bool _busy = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _numberController = TextEditingController(
      text: widget.bag.number.toString(),
    );
    _destinationId = widget.bag.sublotId;
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final number = _parseBagNumber(_numberController.text);
    if (number == null || number <= 0) {
      setState(() => _submitError = 'Enter a positive Bag number.');
      return;
    }
    setState(() {
      _busy = true;
      _submitError = null;
    });
    try {
      await widget.actions.updateBag(
        widget.batchId,
        widget.bag.id,
        {'number': number, 'sublot_id': _destinationId},
        editStateVersion: widget.structure.editStateVersion,
        contentRevision: widget.structure.contentRevision,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _submitError = userFacingError(error, action: 'edit or move Bag');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit or move Bag'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _numberController,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Bag number'),
        ),
        DropdownButtonFormField<String>(
          initialValue: _destinationId,
          decoration: const InputDecoration(labelText: 'Current Sublot'),
          items: [
            for (final sublot in widget.structure.activeSublots)
              DropdownMenuItem(
                value: sublot.id,
                child: Text('Sublot ${sublot.identifier}'),
              ),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() => _destinationId = value!),
        ),
        Text('Source Bag ${widget.bag.sourceNumber} remains unchanged.'),
        if (_submitError != null)
          Text(
            _submitError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
    ],
  );
}

/// Reuses the version-checked structure dialogs in the contextual workspace.
class CampaignStructureControls extends ConsumerWidget {
  const CampaignStructureControls({
    super.key,
    required this.structure,
    this.sublot,
    this.bag,
    this.readOnly = false,
  });
  final CampaignStructure structure;
  final CampaignSublot? sublot;
  final CampaignBag? bag;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (readOnly || structure.isLocked) return const SizedBox.shrink();
    final actions = CampaignStructureSection(
      batchId: structure.batchId,
      readOnly: false,
    );
    final target = bag != null
        ? 'Bag ${bag!.number}'
        : sublot != null
        ? 'Sublot ${sublot!.identifier}'
        : 'Campaign';
    Future<void> remove() async {
      final delete =
          bag?.capabilities.canDelete ?? sublot!.capabilities.canDelete;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${delete ? 'Delete' : 'Archive'} $target?'),
          content: Text(
            delete
                ? 'This empty item has no history and will be permanently deleted.'
                : 'This item will leave the active workspace. Its files and history are retained, and it can be restored.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(delete ? 'Delete' : 'Archive'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      if (bag != null) {
        await actions._removeBag(context, ref, structure, bag!);
      } else {
        await actions._removeSublot(context, ref, structure, sublot!);
      }
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        if (bag == null)
          TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: Text(sublot == null ? 'Add sublot' : 'Add bag'),
            onPressed: () => sublot == null
                ? actions._addSublot(context, ref, structure)
                : actions._addBag(context, ref, structure, sublot!),
          ),
        PopupMenuButton<String>(
          tooltip: '$target actions',
          onSelected: (value) async {
            switch (value) {
              case 'edit':
                if (bag != null) {
                  await actions._editBag(context, ref, structure, bag!);
                } else if (sublot != null) {
                  await actions._editSublot(context, ref, structure, sublot!);
                } else {
                  await actions._editLot(context, ref, structure);
                }
              case 'remove':
                await remove();
              case 'source':
                await showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('$target details'),
                    content: SelectableText(
                      bag != null
                          ? 'Current bag: ${bag!.number}\nSource bag: ${bag!.sourceNumber}\n${bag!.notes ?? ''}'
                          : 'Current sublot: ${sublot!.identifier}\nSource sublot: ${sublot!.sourceIdentifier}\n${sublot!.notes ?? ''}',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'edit',
              child: Text(
                bag != null
                    ? 'Edit or move bag'
                    : sublot != null
                    ? 'Rename sublot'
                    : 'Edit lot code',
              ),
            ),
            if (bag != null || sublot != null)
              const PopupMenuItem(
                value: 'source',
                child: Text('Source details'),
              ),
            if (bag != null || sublot != null)
              PopupMenuItem(
                value: 'remove',
                enabled: bag != null
                    ? bag!.capabilities.canDelete ||
                          bag!.capabilities.canArchive
                    : sublot!.capabilities.canDelete ||
                          sublot!.capabilities.canArchive,
                child: Text(
                  (bag?.capabilities.canDelete ??
                          sublot!.capabilities.canDelete)
                      ? 'Delete empty item'
                      : 'Archive',
                ),
              ),
          ],
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Actions'),
                SizedBox(width: 4),
                Icon(Icons.more_horiz, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class CampaignArchivePanel extends ConsumerWidget {
  const CampaignArchivePanel({
    super.key,
    required this.structure,
    required this.readOnly,
  });
  final CampaignStructure structure;
  final bool readOnly;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = CampaignStructureSection(
      batchId: structure.batchId,
      readOnly: readOnly,
    );
    final editable = !readOnly && !structure.isLocked;
    return ExpansionTile(
      title: Text(
        'Archived items (${structure.archivedSublots.length + structure.archivedBags.length})',
      ),
      subtitle: const Text('Archived items retain their files and history.'),
      children: [
        for (final sublot in structure.archivedSublots)
          ListTile(
            title: Text('Sublot ${sublot.identifier}'),
            trailing: TextButton(
              onPressed: editable && sublot.capabilities.canRestore
                  ? () =>
                        actions._restoreSublot(context, ref, structure, sublot)
                  : null,
              child: const Text('Restore'),
            ),
          ),
        for (final bag in structure.archivedBags)
          ListTile(
            title: Text('Bag ${bag.number}'),
            trailing: TextButton(
              onPressed: editable && bag.capabilities.canRestore
                  ? () => actions._restoreBag(context, ref, structure, bag)
                  : null,
              child: const Text('Restore'),
            ),
          ),
      ],
    );
  }
}
