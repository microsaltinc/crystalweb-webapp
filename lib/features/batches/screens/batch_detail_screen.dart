import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../../images/models/image_model.dart';
import '../../images/providers/image_provider.dart';
import '../../images/widgets/image_grid.dart';
import '../../microscope_upload/widgets/microscope_upload_dialog.dart';
import '../../projects/widgets/project_assign_dialog.dart';
import '../../purchase_orders/widgets/po_assign_dialog.dart';
import '../../reports/widgets/report_section.dart';
import '../models/batch.dart';
import '../models/campaign_structure.dart';
import '../models/campaign_qualification.dart';
import '../providers/batch_provider.dart';
import '../providers/campaign_qualification_provider.dart';
import '../providers/campaign_structure_provider.dart';
import '../widgets/campaign_comments_section.dart';
import '../widgets/campaign_locking_section.dart';
import '../widgets/campaign_qualification_section.dart';
import '../widgets/campaign_structure_section.dart';
import '../widgets/campaign_registration_conflicts_section.dart';
import '../widgets/campaign_ownership_section.dart';
import '../widgets/campaign_workflow_section.dart';
import '../services/batch_download_service.dart';
import '../widgets/download_format_dialog.dart';

class BatchDetailScreen extends ConsumerStatefulWidget {
  const BatchDetailScreen({
    super.key,
    required this.batchId,
    this.routeRoot = '/batches',
  });
  final String batchId;
  final String routeRoot;
  @override
  ConsumerState<BatchDetailScreen> createState() => _BatchDetailScreenState();
}

class _BatchDetailScreenState extends ConsumerState<BatchDetailScreen> {
  Timer? _poll;
  bool _refreshing = false;
  bool _refreshFailed = false;
  String _scope = 'auto';
  int _tab = 0;
  String _filter = 'all';
  double _thumbnailWidth = 220;
  String get batchId => widget.batchId;
  bool get _experiment => widget.routeRoot == '/rnd';
  String get _entity => _experiment ? 'Experiment' : 'Campaign';

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.hidden) {
        return;
      }
      final images = ref.read(imagesForBatchProvider(batchId)).valueOrNull;
      if (images != null &&
          images.any((i) => !i.isInvalidated && i.isAnalysisActive)) {
        unawaited(_refresh());
      }
    });
  }

  @override
  void didUpdateWidget(covariant BatchDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.batchId != batchId) {
      _scope = 'auto';
      _tab = 0;
      _filter = 'all';
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    final id = batchId;
    setState(() => _refreshing = true);
    try {
      await Future.wait<Object?>([
        ref.refresh(batchDetailProvider(id).future),
        ref.refresh(imagesForBatchProvider(id).future),
        ref.refresh(campaignStructureProvider(id).future),
        ref.refresh(campaignQualificationProvider(id).future),
      ]);
      if (mounted) setState(() => _refreshFailed = false);
    } catch (_) {
      if (mounted) setState(() => _refreshFailed = true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _openImage(ImageModel image) =>
      context.go('${widget.routeRoot}/$batchId/images/${image.id}');

  Future<void> _discardImage(ImageModel image, {required bool restore}) async {
    try {
      if (restore) {
        await revalidateImage(ref, image.id);
      } else {
        await invalidateImage(ref, image.id);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(
                error,
                action: restore ? 'restore image' : 'discard image',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _panel(String title, Widget child) => showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _upload(
    CampaignStructure structure,
    CampaignBagDestination destination,
  ) async {
    await showMicroscopeUploadDialog(
      context,
      batchId: batchId,
      bagId: destination.bag.id,
      bagNumber: destination.bag.number,
      destinationLabel: destination.label,
      editStateVersion: structure.editStateVersion,
      contentRevision: structure.contentRevision,
    );
    if (mounted) await _refresh();
  }

  Future<void> _details() => _panel(
    '$_entity details',
    Consumer(
      builder: (context, ref, _) {
        final batch = ref.watch(batchDetailProvider(batchId)).valueOrNull;
        final structureState = ref.watch(campaignStructureProvider(batchId));
        final structure = structureState.hasError
            ? null
            : structureState.valueOrNull;
        if (batch == null) return const CircularProgressIndicator();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              'Lot: ${batch.lotCode}\nFormula: ${batch.formulaCode}\nDryer: ${batch.dryerCode}\n$_entity number: ${batch.campaignNum}\nCreated: ${batch.createdAt.toLocal()}\nID: ${batch.id}',
            ),
            const SizedBox(height: 12),
            _CampaignInfoButton(batch: batch),
            if (structure != null) ...[
              const Divider(),
              SelectableText('Original lot: ${structure.sourceLotCode}'),
              CampaignStructureControls(
                structure: structure,
                readOnly: batch.isLocked,
              ),
              CampaignArchivePanel(
                structure: structure,
                readOnly: batch.isLocked,
              ),
            ],
          ],
        );
      },
    ),
  );

  Future<void> _completion() => _panel(
    '$_entity completion',
    Consumer(
      builder: (context, ref, _) {
        final batch = ref.watch(batchDetailProvider(batchId)).valueOrNull;
        if (batch == null) return const CircularProgressIndicator();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Analysis, human review, bag decisions, and locking are separate steps. Review the outstanding requirements before finishing.',
            ),
            CampaignQualificationSection(
              batchId: batchId,
              readOnly: batch.isLocked,
              showBags: false,
              experiment: _experiment,
            ),
            CampaignLockingSection(batch: batch),
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final batchState = ref.watch(batchDetailProvider(batchId));
    final imageState = ref.watch(imagesForBatchProvider(batchId));
    final structureState = ref.watch(campaignStructureProvider(batchId));
    final qualificationState = ref.watch(
      campaignQualificationProvider(batchId),
    );
    final batch = batchState.valueOrNull;
    final structure = structureState.valueOrNull;
    final qualification = qualificationState.hasError
        ? null
        : qualificationState.valueOrNull;
    final structureReadOnly =
        batchState.hasError ||
        structureState.hasError ||
        batch?.isLocked == true;
    final images = imageState.valueOrNull;
    final destinations =
        structure?.activeBagDestinations ?? <CampaignBagDestination>[];
    final effectiveScope = _scope == 'auto'
        ? (destinations.length == 1
              ? 'bag:${destinations.first.bag.id}'
              : 'all')
        : _scope;
    final selectedBag = destinations
        .where((d) => 'bag:${d.bag.id}' == effectiveScope)
        .firstOrNull;
    final selectedSublot = structure?.activeSublots
        .where(
          (s) =>
              'sublot:${s.id}' == effectiveScope ||
              s.id == selectedBag?.bag.sublotId,
        )
        .firstOrNull;
    final visible = (images ?? <ImageModel>[])
        .where(
          (i) => selectedBag != null
              ? i.bagId == selectedBag.bag.id
              : selectedSublot != null
              ? i.sublotId == selectedSublot.id
              : true,
        )
        .toList();
    final title =
        selectedBag?.label ??
        (selectedSublot != null
            ? 'Sublot ${selectedSublot.identifier}'
            : 'All bags');
    final activeImages = visible.where((i) => !i.isInvalidated).toList();
    final nextImage = activeImages
        .where((i) => i.isComplete && !i.reviewComplete)
        .firstOrNull;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_experiment ? 'R&D experiment' : 'Campaign'),
        actions: [
          IconButton(
            tooltip: 'How sublots and bags work',
            onPressed: () => showCampaignStructureHelp(context),
            icon: const Icon(Icons.help_outline),
          ),
          if (batch != null && batch.processedCount > 0)
            IconButton(
              tooltip: 'Download images',
              onPressed: () => _downloadImages(context, ref, batch),
              icon: const Icon(Icons.download_outlined),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshing ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: batch == null
          ? Center(
              child: batchState.hasError
                  ? Text(
                      userFacingError(
                        batchState.error!,
                        action: 'load campaign',
                      ),
                    )
                  : const CircularProgressIndicator(),
            )
          : Column(
              children: [
                if (_refreshing) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: SingleChildScrollView(
                    key: PageStorageKey('workspace-$batchId'),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  batch.lotCode,
                                  style: theme.textTheme.headlineSmall,
                                ),
                                Text(
                                  '${batch.formulaCode} · Dryer ${batch.dryerCode} · $_entity ${batch.campaignNum}',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                            OutlinedButton.icon(
                              onPressed: _completion,
                              icon: Icon(
                                batch.isLocked
                                    ? Icons.lock_outline
                                    : Icons.fact_check_outlined,
                              ),
                              label: Text(
                                batch.isLocked
                                    ? 'Locked · view details'
                                    : 'Completion & lock',
                              ),
                            ),
                            TextButton(
                              onPressed: _details,
                              child: const Text('Details'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ActionChip(
                              avatar: const Icon(
                                Icons.person_outline,
                                size: 18,
                              ),
                              label: Text(
                                'Owner: ${batch.ownerDisplayWithStatus}',
                              ),
                              onPressed: () => _panel(
                                'Ownership',
                                Consumer(
                                  builder: (_, ref, _) =>
                                      CampaignOwnershipSection(
                                        batch:
                                            ref
                                                .watch(
                                                  batchDetailProvider(batchId),
                                                )
                                                .valueOrNull ??
                                            batch,
                                      ),
                                ),
                              ),
                            ),
                            CampaignWorkflowSection(batch: batch),
                            ActionChip(
                              avatar: Icon(
                                _experiment
                                    ? Icons.folder_outlined
                                    : Icons.receipt_long_outlined,
                                size: 18,
                              ),
                              label: Text(
                                _experiment
                                    ? 'Project: ${batch.projectName ?? 'Unassigned'}'
                                    : 'PO: ${batch.purchaseOrderCode ?? 'Unassigned'}',
                              ),
                              onPressed: batch.isLocked
                                  ? null
                                  : () => showDialog<void>(
                                      context: context,
                                      builder: (_) => _experiment
                                          ? ProjectAssignDialog(
                                              batchId: batchId,
                                              currentProjectId: batch.projectId,
                                              expectedEditStateVersion:
                                                  batch.editStateVersion,
                                            )
                                          : PoAssignDialog(
                                              batchId: batchId,
                                              currentPoId:
                                                  batch.purchaseOrderId,
                                              expectedEditStateVersion:
                                                  batch.editStateVersion,
                                            ),
                                    ),
                            ),
                            Text(
                              batch.isLocked
                                  ? 'Editing: locked'
                                  : 'Editing: editable',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (images != null)
                          _AnalysisSummary(
                            images: images
                                .where((i) => !i.isInvalidated)
                                .toList(),
                          ),
                        if (_refreshFailed)
                          const Text(
                            'Could not refresh progress. Showing the last loaded data; use Refresh to try again.',
                          ),
                        if (batch.unresolvedRegistrationConflictCount > 0)
                          CampaignRegistrationConflictsSection(batch: batch),
                        const SizedBox(height: 12),
                        _NextAction(
                          message: batch.isLocked
                              ? 'This $_entity is locked. Images, reports, and discussion remain available.'
                              : imageState.hasError
                              ? 'Image status is unavailable. Refresh before deciding what to review.'
                              : images == null
                              ? 'Loading image status…'
                              : nextImage != null
                              ? 'Next: review the analyzed images in $title.'
                              : activeImages.any((i) => i.isFailed)
                              ? 'Some images need attention. Open a failed image to inspect it and retry analysis.'
                              : activeImages.any((i) => i.isAnalysisActive)
                              ? 'Analysis is running. You can keep working while the queue progresses.'
                              : activeImages.isEmpty
                              ? 'Start by uploading matching microscope TIFF and TXT files to a bag.'
                              : 'Image reviews are complete in this scope. Check bag decisions and campaign completion.',
                          label: !batch.isLocked && nextImage != null
                              ? 'Review next image'
                              : null,
                          onPressed: nextImage == null
                              ? null
                              : () => _openImage(nextImage),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final (index, label) in [
                              (0, 'Images & review'),
                              (1, 'Reports'),
                              (2, 'Discussion'),
                            ])
                              ChoiceChip(
                                label: Text(label),
                                selected: _tab == index,
                                onSelected: (_) => setState(() => _tab = index),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_tab == 1)
                          ReportSection(
                            batchId: batchId,
                            batchStatus: batch.status,
                            lotCode: batch.lotCode,
                            editable: !batch.isLocked,
                            expectedEditStateVersion: batch.editStateVersion,
                          ),
                        if (_tab == 2)
                          CampaignCommentsSection(batchId: batchId),
                        if (_tab == 0)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final navigator = _ScopeNavigator(
                                structure: structure,
                                scope: effectiveScope,
                                readOnly: structureReadOnly,
                                onSelect: (scope) => setState(() {
                                  _scope = scope;
                                  _filter = 'all';
                                }),
                              );
                              final content = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (structureState.hasError)
                                    _LoadError(
                                      message:
                                          'Could not load sublots and bags. Structural and upload actions are unavailable.',
                                      onRetry: _refresh,
                                    ),
                                  if (imageState.hasError)
                                    _LoadError(
                                      message: 'Could not load images.',
                                      onRetry: _refresh,
                                    ),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        title,
                                        style: theme.textTheme.titleLarge,
                                      ),
                                      if (structure != null &&
                                          selectedBag != null &&
                                          !structureReadOnly &&
                                          !structure.isLocked)
                                        FilledButton.icon(
                                          key: const Key('workspace-upload'),
                                          onPressed: () =>
                                              _upload(structure, selectedBag),
                                          icon: const Icon(
                                            Icons.add_photo_alternate_outlined,
                                          ),
                                          label: const Text('Upload images'),
                                        ),
                                      if (structure != null)
                                        CampaignStructureControls(
                                          structure: structure,
                                          sublot: selectedSublot,
                                          bag: selectedBag?.bag,
                                          readOnly: structureReadOnly,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (qualificationState.hasError)
                                    _LoadError(
                                      message:
                                          'Bag decisions could not be loaded. Decision actions are unavailable until refreshed.',
                                      onRetry: _refresh,
                                    ),
                                  if (selectedBag != null &&
                                      qualification != null)
                                    for (final bag
                                        in qualification.allBags.where(
                                          (b) => b.id == selectedBag.bag.id,
                                        ))
                                      CampaignBagDecision(
                                        qualification: qualification,
                                        bag: bag,
                                        readOnly: batch.isLocked,
                                      ),
                                  if (selectedBag == null &&
                                      structure != null) ...[
                                    _BagOverview(
                                      destinations: destinations
                                          .where(
                                            (d) =>
                                                selectedSublot == null ||
                                                d.bag.sublotId ==
                                                    selectedSublot.id,
                                          )
                                          .toList(),
                                      images: images,
                                      qualification: qualification,
                                      onSelect: (id) =>
                                          setState(() => _scope = 'bag:$id'),
                                    ),
                                    if (selectedSublot != null &&
                                        qualification != null)
                                      SublotAcceptEligible(
                                        qualification: qualification,
                                        sublotId: selectedSublot.id,
                                        readOnly: batch.isLocked,
                                      ),
                                  ],
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      DropdownButton<String>(
                                        value: _filter,
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'all',
                                            child: Text('All images'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'review',
                                            child: Text('Needs review'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'progress',
                                            child: Text('Queued / analyzing'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'failed',
                                            child: Text('Needs attention'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'discarded',
                                            child: Text('Discarded images'),
                                          ),
                                        ],
                                        onChanged: (value) =>
                                            setState(() => _filter = value!),
                                      ),
                                      Text(
                                        '${activeImages.length} images · ${activeImages.where((i) => i.reviewComplete).length} reviewed',
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('Thumbnail size'),
                                          IconButton(
                                            tooltip: 'Smaller thumbnails',
                                            onPressed: _thumbnailWidth > 160
                                                ? () => setState(
                                                    () => _thumbnailWidth -= 60,
                                                  )
                                                : null,
                                            icon: const Icon(Icons.remove),
                                          ),
                                          IconButton(
                                            tooltip: 'Larger thumbnails',
                                            onPressed: _thumbnailWidth < 400
                                                ? () => setState(
                                                    () => _thumbnailWidth += 60,
                                                  )
                                                : null,
                                            icon: const Icon(Icons.add),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  if (images == null && !imageState.hasError)
                                    const LinearProgressIndicator()
                                  else if (visible.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 32,
                                      ),
                                      child: Text(
                                        'No images in this scope yet. Select a bag and choose Upload images.',
                                      ),
                                    )
                                  else
                                    ImageGrid(
                                      images: activeImages
                                          .where(
                                            (i) => switch (_filter) {
                                              'review' =>
                                                i.isComplete &&
                                                    !i.reviewComplete,
                                              'progress' => i.isAnalysisActive,
                                              'failed' => i.isFailed,
                                              'discarded' => false,
                                              _ => true,
                                            },
                                          )
                                          .toList(),
                                      invalidatedImages:
                                          _filter == 'all' ||
                                              _filter == 'discarded'
                                          ? visible
                                                .where((i) => i.isInvalidated)
                                                .toList()
                                          : [],
                                      lotCode: batch.lotCode,
                                      thumbnailWidth: _thumbnailWidth,
                                      onImageTap: _openImage,
                                      relocationDestinations: destinations,
                                      onRelocate:
                                          structureReadOnly ||
                                              structure == null ||
                                              structure.isLocked
                                          ? null
                                          : (image, destination) async {
                                              try {
                                                await ref
                                                    .read(
                                                      imageRelocationActionsProvider,
                                                    )
                                                    .relocate(
                                                      image.id,
                                                      batchId: batchId,
                                                      destinationBagId:
                                                          destination.bag.id,
                                                      expectedEditStateVersion:
                                                          structure
                                                              .editStateVersion,
                                                      expectedContentRevision:
                                                          structure
                                                              .contentRevision,
                                                    );
                                              } catch (error) {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        userFacingError(
                                                          error,
                                                          action:
                                                              'relocate image',
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                      onInvalidate: batch.isLocked
                                          ? null
                                          : (image) => _discardImage(
                                              image,
                                              restore: false,
                                            ),
                                      onRevalidate: batch.isLocked
                                          ? null
                                          : (image) => _discardImage(
                                              image,
                                              restore: true,
                                            ),
                                    ),
                                ],
                              );
                              if (constraints.maxWidth < 1050) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Card(
                                      child: ExpansionTile(
                                        key: const Key(
                                          'workspace-scope-picker',
                                        ),
                                        title: Text('Sublots & bags · $title'),
                                        children: [navigator],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    content,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(width: 230, child: navigator),
                                  const SizedBox(width: 24),
                                  Expanded(child: content),
                                ],
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _downloadImages(
    BuildContext context,
    WidgetRef ref,
    Batch batch,
  ) async {
    final format = await DownloadFormatDialog.show(context);
    if (format == null || !context.mounted) return;

    final client = ref.read(apiClientProvider);
    final service = BatchDownloadService(dio: client.dio);

    // Show a progress snackbar
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Downloading images...'),
          ],
        ),
        duration: Duration(minutes: 5),
      ),
    );

    try {
      final path = await service.downloadBatchImages(
        batchId: batch.id,
        format: format,
        lotCode: batch.lotCode,
        campaignNum: batch.campaignNum,
      );

      messenger.hideCurrentSnackBar();
      if (path != null && context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Images saved to: $path')),
        );
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(userFacingError(e, action: 'download images')),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _downloadImages(context, ref, batch),
            ),
          ),
        );
      }
    }
  }
}

class _AnalysisSummary extends StatelessWidget {
  const _AnalysisSummary({required this.images});
  final List<ImageModel> images;
  @override
  Widget build(BuildContext context) {
    final ready = images.where((i) => i.isComplete).length;
    final analyzing = images.where((i) => i.isProcessing).length;
    final queued = images.where((i) => i.isPending).length;
    final failed = images.where((i) => i.isFailed).length;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        Text('Analysis: $ready/${images.length} ready'),
        if (analyzing > 0) Text('$analyzing analyzing'),
        if (queued > 0) Text('$queued queued'),
        if (failed > 0)
          Text(
            '$failed failed',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Text(
          'Human review: ${images.where((i) => i.reviewComplete).length}/${images.length} complete',
        ),
      ],
    );
  }
}

class _NextAction extends StatelessWidget {
  const _NextAction({required this.message, this.label, this.onPressed});
  final String message;
  final String? label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: .3),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(message),
        if (label != null)
          FilledButton(onPressed: onPressed, child: Text(label!)),
      ],
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      TextButton(onPressed: onRetry, child: const Text('Retry')),
    ],
  );
}

class _ScopeNavigator extends StatelessWidget {
  const _ScopeNavigator({
    required this.structure,
    required this.scope,
    required this.readOnly,
    required this.onSelect,
  });
  final CampaignStructure? structure;
  final String scope;
  final bool readOnly;
  final ValueChanged<String> onSelect;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 520),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Sublots & bags',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ListTile(
            dense: true,
            title: const Text('All bags'),
            selected: scope == 'all',
            onTap: () => onSelect('all'),
          ),
          if (structure == null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Structure unavailable'),
            ),
          for (final sublot
              in structure?.activeSublots ?? <CampaignSublot>[]) ...[
            ListTile(
              dense: true,
              leading: const Icon(Icons.folder_outlined, size: 18),
              title: Text('Sublot ${sublot.identifier}'),
              selected: scope == 'sublot:${sublot.id}',
              onTap: () => onSelect('sublot:${sublot.id}'),
            ),
            for (final bag in sublot.bags.where(
              (b) => !b.effectivelyArchived && !b.archived,
            ))
              ListTile(
                key: ValueKey('workspace-bag-${bag.id}'),
                dense: true,
                contentPadding: const EdgeInsets.only(left: 38, right: 8),
                title: Text('Bag ${bag.number}'),
                subtitle: Text(
                  '${bag.imageCount} images${bag.isExcluded ? ' · Excluded' : ''}',
                ),
                selected: scope == 'bag:${bag.id}',
                onTap: () => onSelect('bag:${bag.id}'),
              ),
          ],
          if (structure != null)
            CampaignStructureControls(
              structure: structure!,
              readOnly: readOnly,
            ),
        ],
      ),
    ),
  );
}

class _BagOverview extends StatelessWidget {
  const _BagOverview({
    required this.destinations,
    required this.images,
    required this.qualification,
    required this.onSelect,
  });
  final List<CampaignBagDestination> destinations;
  final List<ImageModel>? images;
  final CampaignQualification? qualification;
  final ValueChanged<String> onSelect;
  @override
  Widget build(BuildContext context) {
    if (destinations.isEmpty) {
      return const Text(
        'No active bags. Add a sublot or select a sublot to add a bag.',
      );
    }
    return Card(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SingleChildScrollView(
          child: Column(
            children: [
              for (final destination in destinations)
                Builder(
                  builder: (context) {
                    final bagImages = images
                        ?.where(
                          (i) =>
                              i.bagId == destination.bag.id && !i.isInvalidated,
                        )
                        .toList();
                    final decision = qualification?.allBags
                        .where((b) => b.id == destination.bag.id)
                        .firstOrNull;
                    return ListTile(
                      title: Text(destination.label),
                      subtitle: Text(
                        '${bagImages?.length ?? destination.bag.imageCount} images · ${bagImages == null ? 'Analysis unavailable' : '${bagImages.where((i) => i.isComplete).length} ready · ${bagImages.where((i) => i.reviewComplete).length} reviewed'} · ${decision?.status.label ?? 'Decision unavailable'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => onSelect(destination.bag.id),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [+More] button that shows campaign details with copy functionality.
class _CampaignInfoButton extends StatelessWidget {
  const _CampaignInfoButton({required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _showInfoPanel(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 2),
            Text(
              'Copy details',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showInfoPanel(BuildContext context) {
    final fields = <String, String>{
      'Campaign ID': batch.id,
      'Lot Code': batch.lotCode,
      'Formula': batch.formulaCode,
      'Dryer': batch.dryerCode,
      'Campaign #': batch.campaignNum.toString(),
      'Sublots': batch.sublotCount.toString(),
      'Images': '${batch.processedCount} / ${batch.imageCount}',
      'Status': batch.status,
      'Owner': batch.ownerDisplayWithStatus,
      'Created': _formatDateTime(batch.createdAt.toLocal()),
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Campaign Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: fields.entries
              .map((e) => _CampaignInfoRow(label: e.key, value: e.value))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final text = fields.entries
                  .map((e) => '${e.key}: ${e.value}')
                  .join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text('All fields copied'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: const Text('Copy All'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _CampaignInfoRow extends StatelessWidget {
  const _CampaignInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: 'Copy $label',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label copied'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
