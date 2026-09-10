import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../batches/providers/campaign_locking_provider.dart';
import '../models/report.dart';
import '../providers/report_provider.dart';
import '../screens/pdf_viewer_screen.dart';
import '../services/report_download_service.dart';

/// A widget that displays the report section on the batch detail screen.
///
/// Shows per-sublot reports:
/// - Batch not complete: informational message
/// - No reports: "Generate Reports" button (generates all sublots)
/// - Reports exist: per-sublot rows with status and download buttons
class ReportSection extends ConsumerStatefulWidget {
  const ReportSection({
    super.key,
    required this.batchId,
    required this.batchStatus,
    required this.lotCode,
    this.editable = true,
    this.expectedEditStateVersion,
  });

  final String batchId;
  final String batchStatus;
  final String lotCode;
  final bool editable;
  final int? expectedEditStateVersion;

  @override
  ConsumerState<ReportSection> createState() => _ReportSectionState();
}

class _ReportSectionState extends ConsumerState<ReportSection> {
  bool _isGenerating = false;
  bool _isGeneratingBags = false;
  final _downloadService = const ReportDownloadService();

  Future<void> _generateReports() async {
    setState(() => _isGenerating = true);
    try {
      final client = ref.read(apiClientProvider);
      final response = await client.dio.post(
        '/api/v1/reports/batch/${widget.batchId}',
        options: widget.expectedEditStateVersion == null
            ? null
            : Options(
                headers: {
                  'If-Match': campaignEditETag(
                    widget.expectedEditStateVersion!,
                  ),
                },
              ),
      );

      final data = response.data as List;
      final reports = data
          .map((j) => Report.fromJson(j as Map<String, dynamic>))
          .toList();

      for (final report in reports) {
        if (report.isPending) {
          unawaited(_pollReport(report.id));
        }
      }

      ref.invalidate(reportsForBatchProvider(widget.batchId));
    } catch (e) {
      if (mounted) {
        _showError(userFacingError(e, action: 'start report generation'));
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _generateBagReports() async {
    setState(() => _isGeneratingBags = true);
    try {
      final client = ref.read(apiClientProvider);
      final response = await client.dio.post(
        '/api/v1/reports/batch/${widget.batchId}/bags',
        options: widget.expectedEditStateVersion == null
            ? null
            : Options(
                headers: {
                  'If-Match': campaignEditETag(
                    widget.expectedEditStateVersion!,
                  ),
                },
              ),
      );

      final data = response.data as List;
      final reports = data
          .map((j) => Report.fromJson(j as Map<String, dynamic>))
          .toList();

      for (final report in reports) {
        if (report.isPending) {
          unawaited(_pollReport(report.id));
        }
      }

      ref.invalidate(reportsForBatchProvider(widget.batchId));
    } catch (e) {
      if (mounted) {
        _showError(userFacingError(e, action: 'start bag report generation'));
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingBags = false);
      }
    }
  }

  /// Polls a single report until complete. Handles all outcomes silently
  /// except genuine failures, which surface a user-friendly message.
  Future<void> _pollReport(String reportId) async {
    try {
      await ref
          .read(reportPollingProvider.notifier)
          .pollUntilComplete(reportId);
      if (mounted) {
        ref.invalidate(reportsForBatchProvider(widget.batchId));
      }
    } on ReportSupersededException {
      // Report was replaced by a newer generation — just refresh the list.
      if (mounted) {
        ref.invalidate(reportsForBatchProvider(widget.batchId));
      }
    } on ReportPollingTimeoutException {
      // Still generating — not a hard error, just refresh and let the user retry.
      if (mounted) {
        ref.invalidate(reportsForBatchProvider(widget.batchId));
        _showError(
          'Report is taking longer than expected. '
          'It will appear automatically when ready.',
        );
      }
    } catch (e) {
      if (mounted) {
        ref.invalidate(reportsForBatchProvider(widget.batchId));
        _showError(userFriendlyError(e));
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _downloadFile(String url, String defaultName) async {
    try {
      final path = await _downloadService.downloadFile(
        url: url,
        defaultFileName: defaultName,
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $path'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Download failed. Please try again.');
      }
    }
  }

  void _viewPdf(String url, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(url: url, title: title),
      ),
    );
  }

  Color _statusColor(ReportStatus status) {
    switch (status) {
      case ReportStatus.complete:
        return AppColors.statusComplete;
      case ReportStatus.pending:
      case ReportStatus.generating:
        return AppColors.statusProcessing;
      case ReportStatus.failed:
      case ReportStatus.error:
      case ReportStatus.blocked:
        return AppColors.statusFailed;
    }
  }

  String _statusLabel(ReportStatus status) {
    switch (status) {
      case ReportStatus.complete:
        return 'Complete';
      case ReportStatus.pending:
        return 'Pending';
      case ReportStatus.generating:
        return 'Generating';
      case ReportStatus.failed:
      case ReportStatus.error:
        return 'Failed';
      case ReportStatus.blocked:
        return 'Blocked';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBatchComplete = widget.batchStatus == 'complete';

    final reportsAsync = ref.watch(reportsForBatchProvider(widget.batchId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reports', style: theme.textTheme.titleMedium),
        if (!isBatchComplete)
          Text(
            'Reports are available after all images are processed',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (!widget.editable)
          Text(
            'Read-only — existing report history remains available.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 8),
        reportsAsync.when(
          data: (reports) {
            int newestFirst(Report left, Report right) {
              if (left.isCurrent != right.isCurrent) {
                return left.isCurrent ? -1 : 1;
              }
              return right.createdAt.compareTo(left.createdAt);
            }

            final sublotReports =
                reports.where((r) => r.reportType == 'sublot').toList()
                  ..sort(newestFirst);
            final bagReports =
                reports.where((r) => r.reportType == 'bag').toList()
                  ..sort(newestFirst);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Campaign Report section
                if (isBatchComplete)
                  _buildCampaignGenerateButton(sublotReports),
                if (isBatchComplete) const SizedBox(height: 8),
                if (sublotReports.isEmpty)
                  Text(
                    'No campaign report generated yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  ...sublotReports.map(_buildSublotReportRow),

                // Bag Reports section
                const Divider(height: 24),
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text('Bag Reports', style: theme.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 8),
                if (isBatchComplete) _buildBagGenerateButton(bagReports),
                if (isBatchComplete) const SizedBox(height: 8),
                if (bagReports.isEmpty)
                  Text(
                    'No bag reports generated yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  ..._buildBagReportsGroupedBySublot(bagReports, theme),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(),
          ),
          error: (err, stack) => Text(
            userFacingError(err, action: 'load report status'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }

  Widget _buildCampaignGenerateButton(List<Report> sublotReports) {
    final hasReports = sublotReports.isNotEmpty;
    final hasPending = sublotReports.any((r) => r.isPending);
    final label = hasReports
        ? 'Regenerate Campaign Report'
        : 'Generate Campaign Report';
    final icon = hasReports ? Icons.refresh : Icons.picture_as_pdf;

    if (_isGenerating || hasPending) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Generating campaign report...'),
        ],
      );
    }

    return ElevatedButton.icon(
      onPressed: widget.editable && widget.batchStatus == 'complete'
          ? _generateReports
          : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Widget _buildBagGenerateButton(List<Report> bagReports) {
    final hasBagReports = bagReports.isNotEmpty;
    final hasPending = bagReports.any((r) => r.isPending);
    final label = hasBagReports
        ? 'Regenerate Bag Reports'
        : 'Generate Bag Reports';
    final icon = hasBagReports ? Icons.refresh : Icons.inventory_2;

    if (_isGeneratingBags || hasPending) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Generating bag reports...'),
        ],
      );
    }

    return OutlinedButton.icon(
      onPressed: widget.editable && widget.batchStatus == 'complete'
          ? _generateBagReports
          : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  List<Widget> _buildBagReportsGroupedBySublot(
    List<Report> bagReports,
    ThemeData theme,
  ) {
    final grouped = <String, List<Report>>{};
    for (final report in bagReports) {
      final key = report.sublotLetter ?? 'Legacy';
      grouped.putIfAbsent(key, () => []).add(report);
    }

    final sortedKeys = grouped.keys.toList()..sort();
    final widgets = <Widget>[];

    for (final sublotKey in sortedKeys) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            sublotKey == 'Legacy' ? 'Legacy' : 'Sublot $sublotKey',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
      for (final report in grouped[sublotKey]!) {
        widgets.add(_buildSublotReportRow(report));
      }
    }

    return widgets;
  }

  Widget _buildSublotReportRow(Report report) {
    final theme = Theme.of(context);
    final sublotName = report.reportType == 'bag'
        ? (report.bagLabel ?? 'Bag${report.bagNumber ?? 0}')
        : (report.sublotName ??
              '${widget.lotCode}${report.sublotLetter ?? ''}');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Sublot name
          SizedBox(
            width: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sublotName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (report.dispositionLabel != null)
                  Text(
                    report.isExcludedScope
                        ? '${report.dispositionLabel} · Excluded Bag'
                        : report.dispositionLabel!,
                    style: theme.textTheme.labelSmall,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Status chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _statusColor(report.status).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _statusLabel(report.status),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _statusColor(report.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  report.currencyLabel,
                  key: Key('report-currency-${report.id}'),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Generated date
          Text(
            DateFormat('MMM d, yyyy HH:mm').format(report.createdAt.toLocal()),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          // Action buttons or spinner
          if (report.isDownloadable) ...[
            if (report.pdfUrl != null)
              TextButton.icon(
                onPressed: () => _viewPdf(report.pdfUrl!, '$sublotName Report'),
                icon: const Icon(Icons.visibility, size: 18),
                label: const Text('View'),
              ),
            if (report.pdfUrl != null)
              IconButton(
                icon: const Icon(Icons.download, size: 20),
                tooltip: 'Download PDF',
                onPressed: () =>
                    _downloadFile(report.pdfUrl!, '${sublotName}_report.pdf'),
              ),
            if (report.csvUrl != null)
              IconButton(
                icon: const Icon(Icons.table_chart, size: 20),
                tooltip: 'Download CSV',
                onPressed: () =>
                    _downloadFile(report.csvUrl!, '${sublotName}_report.csv'),
              ),
          ],
          if (report.isPending)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (report.hasError)
            TextButton(
              onPressed: widget.editable ? _generateReports : null,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
