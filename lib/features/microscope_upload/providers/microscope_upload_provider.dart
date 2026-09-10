import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_error.dart';
import '../../../core/api/user_facing_error.dart';
import '../../batches/providers/campaign_qualification_provider.dart';
import '../../batches/providers/campaign_structure_provider.dart';
import '../models/microscope_file_set.dart';
import '../models/microscope_upload_feedback.dart';
import '../services/microscope_file_grouping.dart';
import '../services/microscope_file_source.dart';

const _uuid = Uuid();
const _multipartProtocol = 'multipart-v1';
const _multipartMaxAttempts = 4;
const _multipartPartSizeBytes = 8 * 1024 * 1024;
const _multipartTargetBudget = 1000;
const _uploadSetBatchLimit = 100;

const crystalWebChecksumHeader = 'X-CrystalWeb-Checksum-SHA256';

Map<String, String> webSafeTransferHeaders(Map<String, String> headers) => {
  for (final entry in headers.entries)
    if (entry.key.toLowerCase() != Headers.contentLengthHeader)
      entry.key: entry.value,
};

String? _responseHeaderValue(Headers headers, String name) {
  final normalized = name.toLowerCase();
  for (final entry in headers.map.entries) {
    if (entry.key.toLowerCase() == normalized && entry.value.isNotEmpty) {
      return entry.value.first.trim();
    }
  }
  return null;
}

ApiError _browserMultipartRequired() => const ApiError(
  code: 'microscope_upload_browser_multipart_required',
  message:
      'This server cannot provide bounded multipart upload targets required by the browser.',
  statusCode: 426,
  details: {
    'source': 'session',
    'severity': 'warning',
    'retryable': false,
    'recommended_action': 'Update the server, then reopen this upload.',
  },
);

final microscopeFileSourceProvider = Provider<MicroscopeFileSource>(
  (ref) => createMicroscopeFileSource(),
);

final microscopeTransferDioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(minutes: 10),
      receiveTimeout: const Duration(minutes: 2),
    ),
  ),
);

enum MicroscopeUploadFilter { all, ready, incomplete, failed, uploaded }

class MicroscopeUploadArgs {
  const MicroscopeUploadArgs({
    required this.batchId,
    required this.bagId,
    required this.editStateVersion,
    required this.contentRevision,
  });

  final String batchId;
  final String bagId;
  final int editStateVersion;
  final int contentRevision;

  @override
  bool operator ==(Object other) =>
      other is MicroscopeUploadArgs &&
      other.batchId == batchId &&
      other.bagId == bagId &&
      other.editStateVersion == editStateVersion &&
      other.contentRevision == contentRevision;

  @override
  int get hashCode =>
      Object.hash(batchId, bagId, editStateVersion, contentRevision);
}

class MicroscopeUploadState {
  const MicroscopeUploadState({
    this.sets = const [],
    this.filter = MicroscopeUploadFilter.all,
    this.selecting = false,
    this.uploading = false,
    this.sessionId,
    this.error,
    this.issue,
    this.notice,
    this.expiresAt,
    this.queuedCount = 0,
    this.recoverySessionId,
    this.recoveryIdentities = const [],
  });

  final List<MicroscopeFileSet> sets;
  final MicroscopeUploadFilter filter;
  final bool selecting;
  final bool uploading;
  final String? sessionId;
  final String? error;
  final MicroscopeUploadIssue? issue;
  final String? notice;
  final DateTime? expiresAt;
  final int queuedCount;
  final String? recoverySessionId;
  final List<String> recoveryIdentities;

  int get readyCount => sets
      .where(
        (set) =>
            set.canUpload &&
            set.uploadError == null &&
            set.activity.phase == MicroscopeUploadPhase.idle,
      )
      .length;
  int get resumeCount => sets
      .where(
        (set) =>
            set.canUpload &&
            (set.uploadError != null ||
                set.activity.phase == MicroscopeUploadPhase.paused),
      )
      .length;
  int get actionableCount => sets.where((set) => set.canUpload).length;
  int get incompleteCount => sets
      .where((set) => set.selectionStatus != MicroscopeSetSelectionStatus.ready)
      .length;
  int get failedCount => sets.where((set) => set.uploadError != null).length;
  int get uploadedCount => sets.where((set) => set.uploaded).length;
  bool get hasRetainedWork =>
      sessionId != null ||
      recoverySessionId != null ||
      sets.any(
        (set) =>
            !set.uploaded &&
            (set.serverSetId != null ||
                set.uploadProgress > 0 ||
                set.activity.savedParts > 0),
      );

  List<MicroscopeFileSet> get visibleSets => switch (filter) {
    MicroscopeUploadFilter.all => sets,
    MicroscopeUploadFilter.ready =>
      sets
          .where(
            (set) =>
                set.canUpload &&
                set.uploadError == null &&
                set.activity.phase == MicroscopeUploadPhase.idle,
          )
          .toList(),
    MicroscopeUploadFilter.incomplete =>
      sets
          .where(
            (set) => set.selectionStatus != MicroscopeSetSelectionStatus.ready,
          )
          .toList(),
    MicroscopeUploadFilter.failed =>
      sets.where((set) => set.uploadError != null).toList(),
    MicroscopeUploadFilter.uploaded =>
      sets.where((set) => set.uploaded).toList(),
  };

  MicroscopeUploadState copyWith({
    List<MicroscopeFileSet>? sets,
    MicroscopeUploadFilter? filter,
    bool? selecting,
    bool? uploading,
    String? sessionId,
    String? error,
    MicroscopeUploadIssue? issue,
    String? notice,
    DateTime? expiresAt,
    int? queuedCount,
    String? recoverySessionId,
    List<String>? recoveryIdentities,
    bool clearError = false,
    bool clearIssue = false,
    bool clearSession = false,
    bool clearNotice = false,
    bool clearExpiresAt = false,
    bool clearRecovery = false,
  }) => MicroscopeUploadState(
    sets: sets ?? this.sets,
    filter: filter ?? this.filter,
    selecting: selecting ?? this.selecting,
    uploading: uploading ?? this.uploading,
    sessionId: clearSession ? null : sessionId ?? this.sessionId,
    error: clearError ? null : error ?? this.error,
    issue: clearIssue ? null : issue ?? this.issue,
    notice: clearNotice ? null : notice ?? this.notice,
    expiresAt: clearExpiresAt ? null : expiresAt ?? this.expiresAt,
    queuedCount: queuedCount ?? this.queuedCount,
    recoverySessionId: clearRecovery
        ? null
        : recoverySessionId ?? this.recoverySessionId,
    recoveryIdentities: clearRecovery
        ? const []
        : recoveryIdentities ?? this.recoveryIdentities,
  );
}

final microscopeUploadProvider = StateNotifierProvider.autoDispose
    .family<
      MicroscopeUploadNotifier,
      MicroscopeUploadState,
      MicroscopeUploadArgs
    >((ref, args) => MicroscopeUploadNotifier(ref, args));

class MicroscopeUploadNotifier extends StateNotifier<MicroscopeUploadState> {
  MicroscopeUploadNotifier(this._ref, this._args)
    : _editStateVersion = _args.editStateVersion,
      _contentRevision = _args.contentRevision,
      super(const MicroscopeUploadState()) {
    _fileSource = _ref.read(microscopeFileSourceProvider);
  }

  final Ref _ref;
  late final MicroscopeFileSource _fileSource;
  final MicroscopeUploadArgs _args;
  int _editStateVersion;
  int _contentRevision;
  Map<String, _ServerSet> _serverSets = const {};
  String? _createIdempotencyKey;
  final Map<String, String> _finalizeIdempotencyKeys = {};
  final Set<CancelToken> _activeTransfers = {};
  bool _pauseRequested = false;

  @override
  void dispose() {
    _requestPause();
    _fileSource.releaseFiles(state.sets.expand((set) => set.allFiles));
    super.dispose();
  }

  void setFilter(MicroscopeUploadFilter filter) {
    state = state.copyWith(filter: filter);
  }

  Future<void> pickFiles({bool allowMultiple = true}) async {
    state = state.copyWith(selecting: true, clearError: true);
    try {
      final files = await _fileSource.pickFiles(allowMultiple: allowMultiple);
      addFiles(files);
    } catch (error) {
      state = state.copyWith(
        error: userFacingError(error, action: 'select microscope files'),
      );
    } finally {
      state = state.copyWith(selecting: false);
    }
  }

  void addFiles(Iterable<MicroscopeLocalFile> files) {
    final selected = files.toList(growable: false);
    final unsupportedFiles = selected
        .where((file) => microscopeFileRoleForName(file.name) == null)
        .toList(growable: false);
    final unsupported = unsupportedFiles.map((file) => file.name).toList();
    _fileSource.releaseFiles(unsupportedFiles);
    final retained = state.sets.where((set) => set.uploaded).toList();
    final editable = state.sets.where((set) => !set.uploaded).toList();
    final regrouped = groupMicroscopeFiles([
      for (final set in editable) ...set.allFiles,
      ...selected,
    ], existing: editable);
    state = state.copyWith(
      sets: [...retained, ...regrouped],
      error: unsupported.isEmpty
          ? null
          : 'Unsupported files were ignored: ${unsupported.join(', ')}',
      clearError: unsupported.isEmpty,
    );
  }

  void removeSet(String clientSetId) {
    final removed = state.sets
        .where((set) => set.clientSetId == clientSetId && !set.uploaded)
        .expand((set) => set.allFiles)
        .toList(growable: false);
    _fileSource.releaseFiles(removed);
    state = state.copyWith(
      sets: state.sets
          .where((set) => set.clientSetId != clientSetId || set.uploaded)
          .toList(),
      clearError: true,
    );
  }

  void removeFile(String clientSetId, String path) {
    final removed = state.sets
        .expand((set) => set.allFiles)
        .where((file) => file.path == path)
        .toList(growable: false);
    _fileSource.releaseFiles(removed);
    final retained = state.sets.where((set) => set.uploaded).toList();
    final editable = state.sets.where((set) => !set.uploaded).toList();
    final remainingFiles = <MicroscopeLocalFile>[
      for (final set in editable)
        for (final file in set.allFiles)
          if (!(set.clientSetId == clientSetId && file.path == path)) file,
    ];
    state = state.copyWith(
      sets: [
        ...retained,
        ...groupMicroscopeFiles(remainingFiles, existing: editable),
      ],
      clearError: true,
    );
  }

  Future<void> replaceFile(String clientSetId, MicroscopeFileRole role) async {
    final picked = await _fileSource.pickFiles(allowMultiple: false);
    if (picked.isEmpty) return;
    if (microscopeFileRoleForName(picked.single.name) != role) {
      _fileSource.releaseFiles(picked);
      state = state.copyWith(
        error: 'Choose a ${microscopeRoleLabel(role)} file for this slot.',
      );
      return;
    }
    final target = state.sets.firstWhere(
      (set) => set.clientSetId == clientSetId,
    );
    final current = target.files[role];
    if (current != null) removeFile(clientSetId, current.path);
    addFiles(picked);
  }

  Future<void> uploadReady() async {
    if (state.uploading || state.actionableCount == 0) return;
    _pauseRequested = false;
    state = state.copyWith(
      uploading: true,
      clearError: true,
      clearIssue: true,
      clearNotice: true,
      clearRecovery: true,
    );
    try {
      if (state.sessionId != null) await _reconcileSession();
      final ready = state.sets.where((set) => set.canUpload).toList();
      final eligible = state.sessionId == null
          ? ready
          : ready
                .where((set) => _serverSets.containsKey(set.clientSetId))
                .toList();
      var candidates = _nextUploadBatch(eligible);
      if (candidates.isEmpty && state.sessionId != null && ready.isNotEmpty) {
        // A completed local session may remain visible as terminal evidence. New
        // selections start a separate bounded session without cancelling or
        // mutating the completed one.
        _serverSets = const {};
        _createIdempotencyKey = null;
        _finalizeIdempotencyKeys.clear();
        state = state.copyWith(clearSession: true, clearExpiresAt: true);
        candidates = _nextUploadBatch(ready);
      }
      if (candidates.isEmpty) {
        const issue = MicroscopeUploadIssue(
          title: 'This image set is too large for one secure upload session',
          message:
              'The selected TIFF and TXT require more than 1,000 secure upload parts.',
          recommendedAction:
              'Contact support before retrying; CrystalApp has not reserved or uploaded these files.',
          source: MicroscopeUploadIssueSource.file,
          severity: MicroscopeUploadMessageSeverity.warning,
          retryable: false,
          code: 'microscope_upload_target_budget_exceeded',
        );
        state = state.copyWith(
          error: '${issue.message} ${issue.recommendedAction}',
          issue: issue,
        );
        return;
      }
      final selectedIds = candidates.map((set) => set.clientSetId).toSet();
      final queuedCount = ready.length - candidates.length;
      for (final set in ready.where(
        (set) => !selectedIds.contains(set.clientSetId),
      )) {
        _setActivity(
          set.clientSetId,
          set.activity.copyWith(phase: MicroscopeUploadPhase.waiting),
          clearUploadError: true,
        );
      }
      state = state.copyWith(
        queuedCount: queuedCount,
        notice: queuedCount > 0
            ? '$queuedCount image ${queuedCount == 1 ? 'set is' : 'sets are'} queued for the next safe upload batch.'
            : null,
        clearNotice: queuedCount == 0,
      );
      final candidateIds = candidates.map((set) => set.clientSetId).toSet();
      await _hashReadyFiles(candidates);
      if (_pauseRequested) return;
      candidates = state.sets
          .where(
            (set) => candidateIds.contains(set.clientSetId) && set.canUpload,
          )
          .toList();
      var createdSession = false;
      if (state.sessionId == null) {
        await _createSession(candidates);
        createdSession = true;
        final recovering = candidates
            .where(
              (set) => _serverSets[set.clientSetId]?.status == 'finalizing',
            )
            .toList();
        if (recovering.isNotEmpty && !_pauseRequested) {
          await _finalize(recovering);
        }
      } else {
        final recovering = candidates
            .where(
              (set) => _serverSets[set.clientSetId]?.status == 'finalizing',
            )
            .toList();
        if (recovering.isNotEmpty) {
          if (!_pauseRequested) await _finalize(recovering);
          return;
        }
      }
      candidates = candidates
          .map(
            (candidate) => state.sets.firstWhere(
              (set) => set.clientSetId == candidate.clientSetId,
            ),
          )
          .where((set) => set.canUpload)
          .toList();
      final transferred = await _transferCandidates(
        candidates,
        firstWaveFresh: createdSession,
      );
      if (transferred.isNotEmpty && !_pauseRequested) {
        await _finalize(transferred);
      }
    } catch (error) {
      if (!_pauseRequested && !_captureRecoveryConflict(error)) {
        final issue = microscopeUploadIssue(
          error,
          operation: 'continue the microscope upload',
          sessionId: state.sessionId,
        );
        if (_isAuthorityIssue(issue)) {
          _pauseForAuthorityIssue(error, issue);
        } else {
          state = state.copyWith(
            error: '${issue.message} ${issue.recommendedAction}',
            issue: issue,
          );
        }
      }
    } finally {
      if (mounted) state = state.copyWith(uploading: false);
    }
  }

  void _requestPause() {
    _pauseRequested = true;
    for (final token in _activeTransfers.toList()) {
      if (!token.isCancelled) token.cancel('Upload paused');
    }
  }

  Future<void> pause() async {
    if (!state.uploading) return;
    _requestPause();
    while (mounted && state.uploading) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (!mounted) return;
    for (final set in state.sets.where((item) => !item.uploaded)) {
      if (set.activity.phase != MicroscopeUploadPhase.idle) {
        _setActivity(
          set.clientSetId,
          set.activity.copyWith(phase: MicroscopeUploadPhase.paused),
        );
      }
    }
    state = state.copyWith(
      notice:
          'Upload paused. Completed parts remain safely stored. Choose Resume to continue, or close and reselect the exact files later.',
    );
  }

  Future<void> discardPreviousAndRetry() async {
    final recoverySessionId = state.recoverySessionId;
    if (recoverySessionId == null || state.uploading) return;
    state = state.copyWith(uploading: true, clearError: true);
    try {
      await _ref
          .read(apiClientProvider)
          .dio
          .post('/api/v1/microscope-upload-sessions/$recoverySessionId/cancel');
      _serverSets = const {};
      _createIdempotencyKey = null;
      _finalizeIdempotencyKeys.clear();
      state = state.copyWith(
        uploading: false,
        clearSession: true,
        clearError: true,
        clearRecovery: true,
        notice:
            'Previous unfinished upload discarded. Retrying selected files…',
      );
      await uploadReady();
    } catch (error) {
      state = state.copyWith(
        uploading: false,
        error: userFacingError(error, action: 'discard the previous upload'),
      );
    }
  }

  Future<bool> cancel() async {
    final sessionId = state.sessionId;
    if (sessionId == null) return true;
    try {
      await _ref
          .read(apiClientProvider)
          .dio
          .post('/api/v1/microscope-upload-sessions/$sessionId/cancel');
      _serverSets = const {};
      _createIdempotencyKey = null;
      _finalizeIdempotencyKeys.clear();
      state = state.copyWith(clearSession: true, clearError: true);
      return true;
    } catch (error) {
      state = state.copyWith(
        error: userFacingError(error, action: 'cancel this upload session'),
      );
      return false;
    }
  }

  List<MicroscopeFileSet> _nextUploadBatch(List<MicroscopeFileSet> ready) {
    final selected = <MicroscopeFileSet>[];
    var targets = 0;
    for (final set in ready) {
      final setTargets = set.files.values.fold<int>(
        0,
        (total, file) =>
            total +
            ((file.sizeBytes + _multipartPartSizeBytes - 1) ~/
                _multipartPartSizeBytes),
      );
      if (selected.length >= _uploadSetBatchLimit ||
          targets + setTargets > _multipartTargetBudget) {
        break;
      }
      selected.add(set);
      targets += setTargets;
    }
    return selected;
  }

  Future<void> _hashReadyFiles(List<MicroscopeFileSet> candidates) async {
    final source = _fileSource;
    await _forEachConcurrent(candidates, 4, (set) async {
      final hashed = <MicroscopeFileRole, MicroscopeLocalFile>{};
      for (final entry in set.files.entries) {
        if (_pauseRequested) return;
        _setActivity(
          set.clientSetId,
          MicroscopeUploadActivity(
            phase: MicroscopeUploadPhase.preparing,
            role: entry.key,
            totalBytes: entry.value.sizeBytes,
          ),
        );
        var file = entry.value.sha256 == null
            ? await source.hashFile(entry.value)
            : entry.value;
        if (file.multipartChecksums == null) {
          file = await _withMultipartChecksums(source, file);
        }
        hashed[entry.key] = file;
      }
      if (hashed.length == set.files.length) {
        final current = state.sets.firstWhere(
          (item) => item.clientSetId == set.clientSetId,
        );
        _replaceSet(
          current.copyWith(
            files: Map.unmodifiable(hashed),
            activity: const MicroscopeUploadActivity(
              phase: MicroscopeUploadPhase.reserving,
            ),
          ),
        );
      }
    });
  }

  Future<MicroscopeLocalFile> _withMultipartChecksums(
    MicroscopeFileSource source,
    MicroscopeLocalFile file,
  ) async {
    final checksums = <String>[];
    for (
      var start = 0;
      start < file.sizeBytes;
      start += _multipartPartSizeBytes
    ) {
      final end = min(file.sizeBytes, start + _multipartPartSizeBytes);
      final builder = BytesBuilder(copy: false);
      await for (final chunk in source.openRead(file, start: start, end: end)) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.length != end - start) {
        throw StateError('Could not hash the requested multipart byte range.');
      }
      checksums.add(base64Encode(sha256.convert(bytes).bytes));
    }
    return file.copyWith(multipartChecksums: List.unmodifiable(checksums));
  }

  Future<void> _createSession(List<MicroscopeFileSet> candidates) async {
    final dio = _ref.read(apiClientProvider).dio;
    final path = '/api/v1/bags/${_args.bagId}/microscope-upload-sessions';
    final options = Options(
      headers: {
        'If-Match': campaignCompositeETag(_editStateVersion, _contentRevision),
        'Idempotency-Key': _createIdempotencyKey ??= _uuid.v4(),
      },
    );
    Response<dynamic> response;
    try {
      response = await dio.post(
        path,
        data: {
          'upload_protocol': _multipartProtocol,
          'sets': [for (final set in candidates) _manifestJson(set)],
        },
        options: options,
      );
    } on DioException catch (error) {
      if (_isUnsupportedMultipartResponse(error)) {
        throw _browserMultipartRequired();
      }
      rethrow;
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    _readServerSets(data);
    final resumed = data['resumed'] == true || data['recovered'] == true;
    final resumeKind = data['resume_kind'] as String?;
    state = state.copyWith(
      sessionId: data['session_id'] as String,
      expiresAt: DateTime.tryParse(data['expires_at']?.toString() ?? ''),
      notice: resumed
          ? resumeKind == 'handoff'
                ? 'Continuing the exact unfinished upload from another operator. Verified parts will be reused; finalized Images are unchanged.'
                : 'The server found this exact unfinished upload. Verified parts will be reused; finalized Images are unchanged.'
          : null,
      clearNotice: !resumed,
    );
  }

  Future<void> _reconcileSession() async {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    final response = await _ref
        .read(apiClientProvider)
        .dio
        .get('/api/v1/microscope-upload-sessions/$sessionId');
    final data = Map<String, dynamic>.from(response.data as Map);
    _editStateVersion = (data['edit_state_version'] as num).toInt();
    _contentRevision = (data['content_revision'] as num).toInt();
    state = state.copyWith(
      expiresAt: DateTime.tryParse(data['expires_at']?.toString() ?? ''),
    );
    final updated = <String, _ServerSet>{..._serverSets};
    for (final raw in data['sets'] as List? ?? const []) {
      var serverSet = _ServerSet.fromJson(
        Map<String, dynamic>.from(raw as Map),
      );
      final local = state.sets
          .where(
            (set) =>
                set.clientSetId == serverSet.clientSetId ||
                set.serverSetId == serverSet.setId ||
                (serverSet.normalizedMatchKey != null &&
                    set.normalizedMatchKey == serverSet.normalizedMatchKey),
          )
          .firstOrNull;
      if (local != null) {
        serverSet = serverSet.copyWith(clientSetId: local.clientSetId);
      }
      final existing = updated[serverSet.clientSetId];
      if (serverSet.targets.isEmpty && existing != null) {
        serverSet = serverSet.copyWith(targets: existing.targets);
      }
      updated[serverSet.clientSetId] = serverSet;
      if (local == null) continue;
      final item = Map<String, dynamic>.from(raw);
      if (serverSet.status == 'finalized' && item['image_id'] != null) {
        _replaceSet(
          local.copyWith(
            uploaded: true,
            uploadProgress: 1,
            imageId: item['image_id'] as String,
            activity: const MicroscopeUploadActivity(
              phase: MicroscopeUploadPhase.queued,
            ),
            clearUploadError: true,
          ),
        );
      } else if (serverSet.status == 'failed') {
        final message =
            item['last_error_message'] as String? ??
            'The server could not finish this Image.';
        final issue = microscopeUploadIssue(
          ApiError(
            code: item['last_error_code'] as String?,
            message: message,
            statusCode: 409,
          ),
          operation: 'resume the image upload',
          logicalName: local.logicalBaseName,
          sessionId: sessionId,
        );
        _replaceSet(
          local.copyWith(
            uploadError: '${issue.message} ${issue.recommendedAction}',
            issue: issue,
            activity: const MicroscopeUploadActivity(
              phase: MicroscopeUploadPhase.paused,
            ),
          ),
        );
      } else if (serverSet.status == 'finalizing') {
        _replaceSet(
          local.copyWith(
            activity: const MicroscopeUploadActivity(
              phase: MicroscopeUploadPhase.registering,
            ),
            clearUploadError: true,
          ),
        );
      }
    }
    _serverSets = updated;
    final sessionStatus = data['status'] as String?;
    if (sessionStatus == 'cancelled' || sessionStatus == 'expired') {
      _serverSets = const {};
      _createIdempotencyKey = null;
      _finalizeIdempotencyKeys.clear();
      state = state.copyWith(clearSession: true);
    }
  }

  Future<void> _refreshTargets(List<MicroscopeFileSet> candidates) async {
    final sessionId = state.sessionId!;
    final ids = [
      for (final set in candidates)
        if (_serverSets[set.clientSetId] != null)
          _serverSets[set.clientSetId]!.setId,
    ];
    if (ids.isEmpty) return;
    final dio = _ref.read(apiClientProvider).dio;
    final path = '/api/v1/microscope-upload-sessions/$sessionId/targets';
    final options = Options(
      headers: {
        'If-Match': campaignCompositeETag(_editStateVersion, _contentRevision),
      },
    );
    final requestData = {
      'upload_protocol': _multipartProtocol,
      'sets': [
        for (final id in ids)
          {
            'set_id': id,
            'roles': const ['tiff', 'txt'],
          },
      ],
    };
    try {
      final response = await dio.post(
        path,
        data: requestData,
        options: options,
      );
      _readServerSets(Map<String, dynamic>.from(response.data as Map));
    } on DioException catch (error) {
      if (_isUnsupportedMultipartResponse(error)) {
        throw _browserMultipartRequired();
      }
      rethrow;
    }
  }

  Map<String, dynamic> _manifestJson(MicroscopeFileSet set) => {
    'client_set_id': set.clientSetId,
    'logical_base_name': set.logicalBaseName,
    'files': {
      for (final entry in set.files.entries)
        microscopeRoleKey(entry.key): {
          'original_name': entry.value.name,
          'size_bytes': entry.value.sizeBytes,
          'sha256': entry.value.sha256,
          'multipart_parts': [
            for (final (index, checksum)
                in (entry.value.multipartChecksums ?? const <String>[]).indexed)
              {'part_number': index + 1, 'checksum_sha256': checksum},
          ],
        },
    },
  };

  void _readServerSets(Map<String, dynamic> data) {
    final updated = <String, _ServerSet>{..._serverSets};
    for (final raw in data['sets'] as List? ?? const []) {
      var serverSet = _ServerSet.fromJson(
        Map<String, dynamic>.from(raw as Map),
      );
      final local = state.sets
          .where(
            (set) =>
                set.clientSetId == serverSet.clientSetId ||
                set.serverSetId == serverSet.setId ||
                (serverSet.normalizedMatchKey != null &&
                    set.normalizedMatchKey == serverSet.normalizedMatchKey),
          )
          .firstOrNull;
      if (local == null) continue;
      serverSet = serverSet.copyWith(clientSetId: local.clientSetId);
      updated[local.clientSetId] = serverSet;
      final savedParts = serverSet.savedParts(local);
      _replaceSet(
        local.copyWith(
          serverSetId: serverSet.setId,
          activity: MicroscopeUploadActivity(
            phase: MicroscopeUploadPhase.recovering,
            savedParts: savedParts,
          ),
        ),
      );
    }
    _serverSets = updated;
  }

  bool _isAuthorityIssue(MicroscopeUploadIssue issue) =>
      issue.source == MicroscopeUploadIssueSource.concurrency ||
      issue.source == MicroscopeUploadIssueSource.destination ||
      issue.source == MicroscopeUploadIssueSource.session;

  void _pauseForAuthorityIssue(Object error, MicroscopeUploadIssue issue) {
    for (final set in state.sets.where(
      (item) => !item.uploaded && item.serverSetId != null,
    )) {
      _setActivity(
        set.clientSetId,
        set.activity.copyWith(phase: MicroscopeUploadPhase.paused),
        uploadError: '${issue.message} ${issue.recommendedAction}',
        issue: issue,
      );
    }
    state = state.copyWith(
      error: '${issue.message} ${issue.recommendedAction}',
      issue: issue,
    );
    if (issue.code == 'microscope_upload_stale') {
      _detachStaleSession(error);
    }
    _requestPause();
  }

  void _detachStaleSession(Object error) {
    final apiError = ApiError.tryParse(error);
    final currentEditStateVersion =
        apiError?.details['edit_state_version'] as int?;
    final currentContentRevision =
        apiError?.details['content_revision'] as int?;
    if (currentEditStateVersion != null) {
      _editStateVersion = currentEditStateVersion;
    }
    if (currentContentRevision != null) {
      _contentRevision = currentContentRevision;
    }
    // Do not cancel the stale server session: a new create request with the
    // exact manifest safely rebinds it and preserves every verified part.
    _serverSets = const {};
    _createIdempotencyKey = null;
    _finalizeIdempotencyKeys.clear();
    state = state.copyWith(clearSession: true);
  }

  bool _captureRecoveryConflict(Object error) {
    if (error is! DioException || error.response?.statusCode != 409) {
      return false;
    }
    final responseData = error.response?.data;
    if (responseData is! Map) return false;
    final detail = responseData['detail'];
    if (detail is! Map ||
        detail['code'] != 'microscope_upload_recovery_required' ||
        detail['can_discard'] != true ||
        detail['recovery_session_id'] is! String) {
      return false;
    }
    final identities = (detail['identities'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    final issue = microscopeUploadIssue(
      error,
      operation: 'start this upload',
      sessionId: detail['recovery_session_id'] as String,
    );
    state = state.copyWith(
      error: '${issue.message} ${issue.recommendedAction}',
      issue: issue,
      recoverySessionId: detail['recovery_session_id'] as String,
      recoveryIdentities: identities,
    );
    return true;
  }

  Future<List<MicroscopeFileSet>> _transferCandidates(
    List<MicroscopeFileSet> candidates, {
    bool firstWaveFresh = false,
  }) async {
    final completed = <MicroscopeFileSet>[];
    for (var offset = 0; offset < candidates.length; offset += 4) {
      if (_pauseRequested) break;
      final wave = candidates.sublist(
        offset,
        min(offset + 4, candidates.length),
      );
      for (final set in wave) {
        _setActivity(
          set.clientSetId,
          MicroscopeUploadActivity(
            phase: MicroscopeUploadPhase.recovering,
            savedParts: _serverSets[set.clientSetId]?.savedParts(set) ?? 0,
          ),
          clearUploadError: true,
        );
      }
      // Secure targets expire quickly. Refresh only the active transfer wave so
      // slow connections and large selections never start with stale URLs. The
      // first wave can use targets returned by a just-created session.
      if (!firstWaveFresh || offset > 0) await _refreshTargets(wave);
      if (_pauseRequested) break;
      await _forEachConcurrent(wave, 4, (set) async {
        if (_pauseRequested) return;
        final serverSet = _serverSets[set.clientSetId];
        if (serverSet == null) return;
        var refreshedRejectedTarget = false;
        while (!_pauseRequested) {
          Object? transferError;
          try {
            completed.add(await _transferSet(set));
            return;
          } catch (error) {
            transferError = error;
          }
          if (_pauseRequested) {
            _setActivity(
              set.clientSetId,
              state.sets
                  .firstWhere((item) => item.clientSetId == set.clientSetId)
                  .activity
                  .copyWith(phase: MicroscopeUploadPhase.paused),
            );
            return;
          }
          var issue = microscopeUploadIssue(
            transferError,
            operation: 'upload ${set.logicalBaseName}',
            logicalName: set.logicalBaseName,
            sessionId: state.sessionId,
          );
          if (issue.code == 'microscope_upload_target_rejected' &&
              !refreshedRejectedTarget) {
            refreshedRejectedTarget = true;
            _setActivity(
              set.clientSetId,
              state.sets
                  .firstWhere((item) => item.clientSetId == set.clientSetId)
                  .activity
                  .copyWith(
                    phase: MicroscopeUploadPhase.retrying,
                    retryNumber: 1,
                    maxRetries: 1,
                  ),
              clearUploadError: true,
            );
            try {
              await _refreshTargets([set]);
              continue;
            } catch (refreshError) {
              transferError = refreshError;
              issue = microscopeUploadIssue(
                refreshError,
                operation: 'refresh the secure upload target',
                logicalName: set.logicalBaseName,
                sessionId: state.sessionId,
              );
            }
          }
          _setActivity(
            set.clientSetId,
            state.sets
                .firstWhere((item) => item.clientSetId == set.clientSetId)
                .activity
                .copyWith(phase: MicroscopeUploadPhase.paused),
            uploadError: '${issue.message} ${issue.recommendedAction}',
            issue: issue,
          );
          if (_isAuthorityIssue(issue)) {
            _pauseForAuthorityIssue(transferError, issue);
            throw transferError;
          }
          return;
        }
      });
    }
    return completed;
  }

  Future<MicroscopeFileSet> _transferSet(MicroscopeFileSet set) async {
    final serverSet = _serverSets[set.clientSetId];
    if (serverSet == null) throw StateError('Missing server upload set.');
    final progress = _SetUploadProgress(
      totals: {
        for (final entry in set.files.entries)
          entry.key:
              serverSet.targets[entry.key]?.totalSize(entry.value) ??
              entry.value.sizeBytes,
      },
      onChanged: (uploadedBytes, totalBytes, value) {
        final current = state.sets
            .where((item) => item.clientSetId == set.clientSetId)
            .firstOrNull;
        if (current != null) {
          _replaceSet(
            current.copyWith(
              uploadProgress: value,
              activity: current.activity.copyWith(
                completedBytes: uploadedBytes,
                totalBytes: totalBytes,
              ),
            ),
          );
        }
      },
    );
    for (final entry in set.files.entries) {
      final target = serverSet.targets[entry.key];
      if (target == null) throw StateError('Missing upload target.');
      progress.update(entry.key, target.completedSize(entry.value));
    }
    for (final entry in set.files.entries) {
      if (_pauseRequested) throw StateError('Upload paused.');
      final target = serverSet.targets[entry.key];
      if (target == null) throw StateError('Missing upload target.');
      _setActivity(
        set.clientSetId,
        MicroscopeUploadActivity(
          phase: MicroscopeUploadPhase.uploading,
          role: entry.key,
          completedBytes: progress.uploadedBytes,
          totalBytes: progress.totalBytes,
          savedParts: serverSet.savedParts(set),
        ),
        clearUploadError: true,
      );
      await _uploadFile(
        serverSet,
        set.clientSetId,
        entry.key,
        entry.value,
        target,
        progress,
      );
    }
    return state.sets.firstWhere((item) => item.clientSetId == set.clientSetId);
  }

  Future<void> _uploadFile(
    _ServerSet serverSet,
    String clientSetId,
    MicroscopeFileRole role,
    MicroscopeLocalFile file,
    _UploadTarget target,
    _SetUploadProgress progress,
  ) async {
    if (!target.isMultipart) throw _browserMultipartRequired();
    await _uploadMultipartFile(
      serverSet,
      clientSetId,
      role,
      file,
      target,
      progress,
    );
  }

  Future<void> _uploadMultipartFile(
    _ServerSet serverSet,
    String clientSetId,
    MicroscopeFileRole role,
    MicroscopeLocalFile file,
    _UploadTarget target,
    _SetUploadProgress progress,
  ) async {
    if (target.completed) {
      progress.update(role, target.totalSize(file));
      return;
    }
    final partSize = target.partSizeBytes;
    if (partSize == null || partSize <= 0 || target.parts.isEmpty) {
      throw StateError('Invalid multipart upload target.');
    }
    final parts = [...target.parts]
      ..sort((left, right) => left.partNumber.compareTo(right.partNumber));
    if (parts.fold<int>(0, (total, part) => total + part.sizeBytes) !=
            file.sizeBytes ||
        parts.indexed.any((entry) => entry.$2.partNumber != entry.$1 + 1)) {
      throw StateError('Multipart upload target does not match the file.');
    }
    final completedParts = <int, _MultipartPart>{
      for (final part in parts)
        if (part.isUploaded) part.partNumber: part,
    };
    var completedBytes = completedParts.values.fold<int>(
      0,
      (total, part) => total + part.sizeBytes,
    );
    progress.update(role, completedBytes);

    for (final part in parts) {
      final start = (part.partNumber - 1) * partSize;
      final end = start + part.sizeBytes;
      if (part.sizeBytes <= 0 || start < 0 || end > file.sizeBytes) {
        throw StateError('Invalid multipart byte range.');
      }
      final expectedChecksum = file.multipartChecksums![part.partNumber - 1];
      if (part.isUploaded) {
        if (part.checksumSha256 != expectedChecksum) {
          throw StateError(
            'A recovered multipart part does not match the selected file.',
          );
        }
        continue;
      }
      final url = part.url;
      if (url == null) throw StateError('Missing multipart upload URL.');
      _setActivity(
        clientSetId,
        MicroscopeUploadActivity(
          phase: MicroscopeUploadPhase.uploading,
          role: role,
          completedBytes: progress.uploadedBytes,
          totalBytes: progress.totalBytes,
          currentPart: part.partNumber,
          totalParts: parts.length,
          savedParts: completedParts.length,
        ),
        clearUploadError: true,
      );
      final bytes = await _readPartBytes(file, part, start, end);
      final checksum = base64Encode(sha256.convert(bytes).bytes);
      if (checksum != expectedChecksum) {
        throw StateError('The selected file changed after it was verified.');
      }
      final uploaded = await _uploadPartWithRetry(
        clientSetId: clientSetId,
        role: role,
        totalParts: parts.length,
        savedParts: completedParts.length,
        part: part,
        url: url,
        bytes: bytes,
        checksum: checksum,
        completedBytes: completedBytes,
        progress: progress,
      );
      completedParts[part.partNumber] = uploaded;
      completedBytes += part.sizeBytes;
      progress.update(role, completedBytes);
    }

    await _completeMultipart(serverSet, clientSetId, role, [
      for (final part in parts) completedParts[part.partNumber]!,
    ]);
  }

  Future<Uint8List> _readPartBytes(
    MicroscopeLocalFile file,
    _MultipartPart part,
    int start,
    int end,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in _fileSource.openRead(
      file,
      start: start,
      end: end,
    )) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.length != part.sizeBytes) {
      throw StateError('Could not read the requested multipart byte range.');
    }
    return bytes;
  }

  Future<_MultipartPart> _uploadPartWithRetry({
    required String clientSetId,
    required MicroscopeFileRole role,
    required int totalParts,
    required int savedParts,
    required _MultipartPart part,
    required String url,
    required Uint8List bytes,
    required String checksum,
    required int completedBytes,
    required _SetUploadProgress progress,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _multipartMaxAttempts; attempt++) {
      if (_pauseRequested) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: url),
          reason: 'Upload paused by user',
        );
      }
      final cancelToken = CancelToken();
      _activeTransfers.add(cancelToken);
      try {
        final response = await _ref
            .read(microscopeTransferDioProvider)
            .putUri(
              Uri.parse(url),
              data: bytes,
              cancelToken: cancelToken,
              options: Options(headers: webSafeTransferHeaders(part.headers)),
              onSendProgress: (sent, total) {
                progress.update(
                  role,
                  completedBytes + min(sent, part.sizeBytes),
                );
              },
            );
        final etag = _responseHeaderValue(response.headers, 'etag');
        final observedChecksum = _responseHeaderValue(
          response.headers,
          crystalWebChecksumHeader,
        );
        if (etag == null || etag.isEmpty || observedChecksum != checksum) {
          throw StateError('Storage did not return multipart verification.');
        }
        return part.copyWith(etag: etag, checksumSha256: checksum);
      } catch (error) {
        lastError = error;
        progress.update(role, completedBytes);
        if (_pauseRequested ||
            attempt == _multipartMaxAttempts ||
            !_isTransientTransfer(error)) {
          rethrow;
        }
        _setActivity(
          clientSetId,
          MicroscopeUploadActivity(
            phase: MicroscopeUploadPhase.retrying,
            role: role,
            completedBytes: progress.uploadedBytes,
            totalBytes: progress.totalBytes,
            currentPart: part.partNumber,
            totalParts: totalParts,
            savedParts: savedParts,
            retryNumber: attempt,
            maxRetries: _multipartMaxAttempts - 1,
          ),
        );
        await Future<void>.delayed(
          Duration(
            milliseconds: 250 * (1 << (attempt - 1)) + Random().nextInt(101),
          ),
        );
      } finally {
        _activeTransfers.remove(cancelToken);
      }
    }
    throw lastError!;
  }

  Future<void> _completeMultipart(
    _ServerSet serverSet,
    String clientSetId,
    MicroscopeFileRole role,
    List<_MultipartPart> parts,
  ) async {
    final sessionId = state.sessionId!;
    _setActivity(
      clientSetId,
      MicroscopeUploadActivity(
        phase: MicroscopeUploadPhase.verifying,
        role: role,
        completedBytes: parts.fold<int>(
          0,
          (total, part) => total + part.sizeBytes,
        ),
        totalBytes: parts.fold<int>(0, (total, part) => total + part.sizeBytes),
        savedParts: parts.length,
        totalParts: parts.length,
      ),
    );
    await _ref
        .read(apiClientProvider)
        .dio
        .post(
          '/api/v1/microscope-upload-sessions/$sessionId/sets/'
          '${serverSet.setId}/multipart/${microscopeRoleKey(role)}/complete',
          data: {
            'parts': [
              for (final part in parts)
                {
                  'part_number': part.partNumber,
                  'etag': part.etag,
                  'checksum_sha256': part.checksumSha256,
                },
            ],
          },
          options: Options(
            headers: {
              'If-Match': campaignCompositeETag(
                _editStateVersion,
                _contentRevision,
              ),
            },
          ),
        );
  }

  Future<void> _finalize(List<MicroscopeFileSet> transferred) async {
    final sessionId = state.sessionId!;
    final setIds = [
      for (final set in transferred) _serverSets[set.clientSetId]!.setId,
    ];
    final signature = (setIds.toList()..sort()).join(',');
    final idempotencyKey = _finalizeIdempotencyKeys.putIfAbsent(
      signature,
      _uuid.v4,
    );
    for (final set in transferred) {
      _setActivity(
        set.clientSetId,
        const MicroscopeUploadActivity(
          phase: MicroscopeUploadPhase.registering,
        ),
        clearUploadError: true,
      );
    }
    final response = await _ref
        .read(apiClientProvider)
        .dio
        .post(
          '/api/v1/microscope-upload-sessions/$sessionId/finalize',
          data: {'set_ids': setIds},
          options: Options(
            headers: {
              'If-Match': campaignCompositeETag(
                _editStateVersion,
                _contentRevision,
              ),
              'Idempotency-Key': idempotencyKey,
            },
          ),
        );
    final data = Map<String, dynamic>.from(response.data as Map);
    _editStateVersion = (data['edit_state_version'] as num).toInt();
    _contentRevision = (data['content_revision'] as num).toInt();
    final byServerId = {
      for (final entry in _serverSets.entries) entry.value.setId: entry.key,
    };
    for (final key in ['finalized', 'already_finalized']) {
      for (final raw in data[key] as List? ?? const []) {
        final item = Map<String, dynamic>.from(raw as Map);
        final clientId = byServerId[item['set_id']];
        if (clientId == null) continue;
        final local = state.sets.firstWhere(
          (set) => set.clientSetId == clientId,
        );
        _replaceSet(
          local.copyWith(
            uploaded: true,
            uploadProgress: 1,
            imageId: item['image_id'] as String?,
            activity: const MicroscopeUploadActivity(
              phase: MicroscopeUploadPhase.queued,
            ),
            clearUploadError: true,
          ),
        );
      }
    }
    for (final raw in data['failed'] as List? ?? const []) {
      final item = Map<String, dynamic>.from(raw as Map);
      final clientId = byServerId[item['set_id']];
      if (clientId == null) continue;
      final local = state.sets.firstWhere((set) => set.clientSetId == clientId);
      final message =
          item['message'] as String? ??
          'The server could not register this Image.';
      final issue = microscopeUploadIssue(
        ApiError(
          code: item['code'] as String?,
          message: message,
          statusCode: 409,
          details: item,
        ),
        operation: 'register the image',
        logicalName: local.logicalBaseName,
        sessionId: sessionId,
      );
      _replaceSet(
        local.copyWith(
          uploadError: '${issue.message} ${issue.recommendedAction}',
          issue: issue,
          activity: const MicroscopeUploadActivity(
            phase: MicroscopeUploadPhase.paused,
          ),
        ),
      );
    }
    if (state.queuedCount > 0 && data['status'] == 'completed') {
      _serverSets = const {};
      _createIdempotencyKey = null;
      _finalizeIdempotencyKeys.clear();
      state = state.copyWith(clearSession: true, clearExpiresAt: true);
    }
    refreshCampaignDetail(_ref, _args.batchId);
    _ref.invalidate(campaignStructureProvider(_args.batchId));
  }

  void _setActivity(
    String clientSetId,
    MicroscopeUploadActivity activity, {
    String? uploadError,
    MicroscopeUploadIssue? issue,
    bool clearUploadError = false,
  }) {
    if (!mounted) return;
    final current = state.sets
        .where((set) => set.clientSetId == clientSetId)
        .firstOrNull;
    if (current == null) return;
    _replaceSet(
      current.copyWith(
        activity: activity,
        uploadError: uploadError,
        issue: issue,
        clearUploadError: clearUploadError,
      ),
    );
  }

  void _replaceSet(MicroscopeFileSet replacement) {
    state = state.copyWith(
      sets: [
        for (final set in state.sets)
          if (set.clientSetId == replacement.clientSetId) replacement else set,
      ],
    );
  }
}

class _ServerSet {
  const _ServerSet({
    required this.setId,
    required this.clientSetId,
    required this.status,
    required this.targets,
    this.normalizedMatchKey,
  });

  factory _ServerSet.fromJson(Map<String, dynamic> json) => _ServerSet(
    setId: json['set_id'] as String,
    clientSetId: json['client_set_id'] as String,
    status: json['status'] as String? ?? 'pending',
    normalizedMatchKey: json['normalized_match_key'] as String?,
    targets: _targetsFromJson(
      Map<String, dynamic>.from(json['targets'] as Map? ?? const {}),
    ),
  );

  _ServerSet copyWith({
    String? clientSetId,
    String? status,
    Map<MicroscopeFileRole, _UploadTarget>? targets,
  }) => _ServerSet(
    setId: setId,
    clientSetId: clientSetId ?? this.clientSetId,
    status: status ?? this.status,
    targets: targets ?? this.targets,
    normalizedMatchKey: normalizedMatchKey,
  );

  final String setId;
  final String clientSetId;
  final String status;
  final String? normalizedMatchKey;
  final Map<MicroscopeFileRole, _UploadTarget> targets;

  int savedParts(MicroscopeFileSet local) {
    var count = 0;
    for (final entry in targets.entries) {
      final target = entry.value;
      if (target.completed) {
        count += local.files[entry.key]?.multipartChecksums?.length ?? 1;
      } else {
        count += target.parts.where((part) => part.isUploaded).length;
      }
    }
    return count;
  }
}

Map<MicroscopeFileRole, _UploadTarget> _targetsFromJson(
  Map<String, dynamic> json,
) {
  final targets = <MicroscopeFileRole, _UploadTarget>{};
  for (final entry in json.entries) {
    final role = _roleFromKey(entry.key);
    if (role != null) {
      targets[role] = _UploadTarget.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }
  }
  return targets;
}

class _UploadTarget {
  const _UploadTarget({
    required this.url,
    required this.headers,
    required this.protocol,
    required this.completed,
    required this.parts,
    this.partSizeBytes,
  });

  factory _UploadTarget.fromJson(Map<String, dynamic> json) => _UploadTarget(
    url: json['url'] as String?,
    headers: _stringHeaders(json['headers']),
    protocol: json['protocol'] as String?,
    partSizeBytes: (json['part_size_bytes'] as num?)?.toInt(),
    completed: json['completed'] == true,
    parts: [
      for (final raw in json['parts'] as List? ?? const [])
        _MultipartPart.fromJson(Map<String, dynamic>.from(raw as Map)),
    ],
  );

  final String? url;
  final Map<String, String> headers;
  final String? protocol;
  final int? partSizeBytes;
  final bool completed;
  final List<_MultipartPart> parts;

  bool get isMultipart => protocol == _multipartProtocol;

  int totalSize(MicroscopeLocalFile file) {
    if (!isMultipart || parts.isEmpty) return file.sizeBytes;
    return parts.fold(0, (total, part) => total + part.sizeBytes);
  }

  int completedSize(MicroscopeLocalFile file) {
    if (!isMultipart) return 0;
    if (completed) return totalSize(file);
    return parts
        .where((part) => part.isUploaded)
        .fold(0, (total, part) => total + part.sizeBytes);
  }
}

class _MultipartPart {
  const _MultipartPart({
    required this.partNumber,
    required this.sizeBytes,
    required this.headers,
    this.url,
    this.etag,
    this.checksumSha256,
  });

  factory _MultipartPart.fromJson(Map<String, dynamic> json) => _MultipartPart(
    partNumber: (json['part_number'] as num).toInt(),
    sizeBytes: (json['size_bytes'] as num).toInt(),
    url: json['url'] as String?,
    headers: _stringHeaders(json['headers']),
    etag: json['etag'] as String?,
    checksumSha256: json['checksum_sha256'] as String?,
  );

  final int partNumber;
  final int sizeBytes;
  final String? url;
  final Map<String, String> headers;
  final String? etag;
  final String? checksumSha256;

  bool get isUploaded => etag != null && etag!.isNotEmpty;

  _MultipartPart copyWith({String? etag, String? checksumSha256}) =>
      _MultipartPart(
        partNumber: partNumber,
        sizeBytes: sizeBytes,
        url: url,
        headers: headers,
        etag: etag ?? this.etag,
        checksumSha256: checksumSha256 ?? this.checksumSha256,
      );
}

Map<String, String> _stringHeaders(Object? raw) => Map<String, dynamic>.from(
  raw as Map? ?? const {},
).map((key, value) => MapEntry(key, value.toString()));

class _SetUploadProgress {
  _SetUploadProgress({required this.totals, required this.onChanged});

  final Map<MicroscopeFileRole, int> totals;
  final void Function(int uploadedBytes, int totalBytes, double progress)
  onChanged;
  final Map<MicroscopeFileRole, int> _uploaded = {};
  int _lastReportedBytes = -1;
  double _lastReportedProgress = -1;

  int get totalBytes => totals.values.fold<int>(0, (sum, value) => sum + value);
  int get uploadedBytes =>
      _uploaded.values.fold<int>(0, (sum, value) => sum + value);

  void update(MicroscopeFileRole role, int bytes) {
    final roleTotal = totals[role] ?? 0;
    _uploaded[role] = bytes.clamp(0, roleTotal);
    final total = totalBytes;
    final uploaded = uploadedBytes;
    final progress = total <= 0 ? 0.0 : min(1.0, uploaded / total);
    final movedBackward = uploaded < _lastReportedBytes;
    final reachedBoundary = uploaded == 0 || uploaded == total;
    if (!movedBackward &&
        !reachedBoundary &&
        _lastReportedProgress >= 0 &&
        progress - _lastReportedProgress < 0.01) {
      return;
    }
    _lastReportedBytes = uploaded;
    _lastReportedProgress = progress;
    onChanged(uploaded, total, progress);
  }
}

bool _isUnsupportedMultipartResponse(DioException error) {
  if (error.response?.statusCode != 422) return false;
  final data = error.response?.data;
  if (data is! Map || data['detail'] is! List) return false;
  return (data['detail'] as List).any((item) {
    if (item is! Map || item['type'] != 'extra_forbidden') return false;
    final location = item['loc'];
    if (location is! List || location.isEmpty) return false;
    return location.last == 'upload_protocol' ||
        location.last == 'multipart_parts';
  });
}

bool _isTransientTransfer(Object error) {
  if (error is! DioException) return false;
  final statusCode = error.response?.statusCode;
  if (statusCode != null) {
    return statusCode == 408 ||
        statusCode == 429 ||
        statusCode >= 500 && statusCode <= 599;
  }
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError ||
    DioExceptionType.unknown => true,
    _ => false,
  };
}

MicroscopeFileRole? _roleFromKey(String value) => switch (value) {
  'tiff' => MicroscopeFileRole.tiff,
  'txt' => MicroscopeFileRole.txt,
  _ => null,
};

Future<void> _forEachConcurrent<T>(
  List<T> values,
  int concurrency,
  Future<void> Function(T value) action,
) async {
  var next = 0;
  Future<void> worker() async {
    while (next < values.length) {
      final index = next++;
      await action(values[index]);
    }
  }

  await Future.wait([
    for (var index = 0; index < min(concurrency, values.length); index++)
      worker(),
  ]);
}
