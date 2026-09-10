import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/microscope_upload/models/microscope_file_set.dart';
import 'package:crystalapp/features/microscope_upload/models/microscope_upload_feedback.dart';
import 'package:crystalapp/features/microscope_upload/providers/microscope_upload_provider.dart';
import 'package:crystalapp/features/microscope_upload/services/microscope_file_source_base.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

MicroscopeLocalFile file(String name) =>
    MicroscopeLocalFile(path: '/tmp/$name', name: name, sizeBytes: 10);

class _FakeSource implements MicroscopeFileSource {
  @override
  Future<List<MicroscopeLocalFile>> pickFiles({
    bool allowMultiple = true,
  }) async => [];

  @override
  Future<MicroscopeLocalFile> hashFile(MicroscopeLocalFile file) async =>
      file.copyWith(sha256: 'a' * 64);

  @override
  void releaseFiles(Iterable<MicroscopeLocalFile> files) {}

  @override
  Stream<List<int>> openRead(
    MicroscopeLocalFile file, {
    int? start,
    int? end,
  }) =>
      Stream.value(List<int>.filled((end ?? file.sizeBytes) - (start ?? 0), 1));
}

class _ApiAdapter implements HttpClientAdapter {
  _ApiAdapter({
    this.loseFirstCreate = false,
    this.loseFirstFinalize = false,
    this.rejectMultipart = false,
    this.rejectMultipartSafety = false,
    this.rejectRefreshSafety = false,
    this.rejectRefreshStale = false,
    this.rejectFinalizeStale = false,
  });

  final bool loseFirstCreate;
  final bool loseFirstFinalize;
  final bool rejectMultipart;
  final bool rejectMultipartSafety;
  final bool rejectRefreshSafety;
  bool rejectRefreshStale;
  bool rejectFinalizeStale;
  final requests = <RequestOptions>[];
  var createAttempts = 0;
  var finalizeAttempts = 0;
  var serverFinalized = false;
  String? clientSetId;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path.endsWith('/microscope-upload-sessions')) {
      if (rejectMultipartSafety &&
          (options.data as Map).containsKey('upload_protocol')) {
        return _json({
          'detail': {
            'code': 'microscope_upload_manifest_invalid',
            'message': 'Select fewer sets for bounded multipart targets.',
          },
        }, 422);
      }
      if (rejectMultipart &&
          (options.data as Map).containsKey('upload_protocol')) {
        return _json({
          'detail': [
            {
              'type': 'extra_forbidden',
              'loc': ['body', 'upload_protocol'],
              'msg': 'Extra inputs are not permitted',
            },
          ],
        }, 422);
      }
      createAttempts++;
      clientSetId = (options.data as Map)['sets'][0]['client_set_id'] as String;
      if (loseFirstCreate && createAttempts == 1) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'response lost',
        );
      }
      final files = (options.data as Map)['sets'][0]['files'] as Map;
      Map<String, Object?> target(String role) => {
        'protocol': 'multipart-v1',
        'part_size_bytes': 8 * 1024 * 1024,
        'completed': false,
        'parts': [
          {
            'part_number': 1,
            'size_bytes': files[role]['size_bytes'],
            'url': 'https://upload.invalid/$role/1',
            'headers': <String, String>{
              crystalWebChecksumHeader:
                  (((files[role] as Map)['multipart_parts'] as List).first
                          as Map)['checksum_sha256']
                      as String,
            },
          },
        ],
      };
      return _json({
        'session_id': 'session-1',
        'status': 'active',
        'sets': [
          {
            'set_id': 'set-1',
            'client_set_id': clientSetId,
            'targets': {'tiff': target('tiff'), 'txt': target('txt')},
          },
        ],
      }, 201);
    }
    if (options.method == 'GET' && options.path.endsWith('/session-1')) {
      return _json({
        'session_id': 'session-1',
        'batch_id': 'batch-1',
        'sublot_id': 'sublot-1',
        'bag_id': 'bag-1',
        'status': serverFinalized ? 'completed' : 'active',
        'expires_at': '2030-01-01T00:00:00Z',
        'edit_state_version': 2,
        'content_revision': serverFinalized ? 8 : 7,
        'counts': <String, int>{},
        'sets': [
          {
            'set_id': 'set-1',
            'client_set_id': clientSetId,
            'logical_base_name': 'Sample-001',
            'status': serverFinalized ? 'finalized' : 'pending',
            'reserved_image_number': 1,
            'image_id': serverFinalized ? 'image-1' : null,
          },
        ],
      });
    }
    if (options.path.endsWith('/targets') && rejectRefreshStale) {
      return _json({
        'detail': {
          'code': 'microscope_upload_stale',
          'message':
              'The Campaign changed before secure targets were refreshed.',
          'edit_state_version': 2,
          'content_revision': 9,
        },
      }, 409);
    }
    if (options.path.endsWith('/targets') && rejectRefreshSafety) {
      return _json({
        'detail': {
          'code': 'microscope_upload_manifest_invalid',
          'message': 'Multipart evidence is invalid.',
        },
      }, 422);
    }
    if (options.path.endsWith('/finalize')) {
      finalizeAttempts++;
      if (rejectFinalizeStale) {
        return _json({
          'detail': {
            'code': 'microscope_upload_stale',
            'message': 'The Campaign changed before Image registration.',
            'edit_state_version': 2,
            'content_revision': 9,
          },
        }, 409);
      }
      serverFinalized = true;
      if (loseFirstFinalize && finalizeAttempts == 1) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'response lost',
        );
      }
      return _json({
        'session_id': 'session-1',
        'status': 'completed',
        'edit_state_version': 2,
        'content_revision': 8,
        'finalized': [
          {'set_id': 'set-1', 'image_id': 'image-1', 'status': 'pending'},
        ],
        'already_finalized': <Map<String, Object?>>[],
        'failed': <Map<String, Object?>>[],
      });
    }
    return _json({});
  }

  ResponseBody _json(Map<String, Object?> body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  @override
  void close({bool force = false}) {}
}

class _TransferAdapter implements HttpClientAdapter {
  _TransferAdapter({this.forbidden = false, this.forbiddenFirst = false});

  final bool forbidden;
  final bool forbiddenFirst;
  final requests = <RequestOptions>[];
  var attempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    attempts++;
    final body = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        body.addAll(chunk);
      }
    }
    if (forbidden || (forbiddenFirst && attempts == 1)) {
      return ResponseBody.fromString(
        '<Error><Code>AccessForbidden</Code></Error>',
        403,
        headers: {
          Headers.contentTypeHeader: ['application/xml'],
        },
      );
    }
    return ResponseBody.fromString(
      '',
      200,
      headers: {
        'etag': ['"etag-$attempts"'],
        'x-crystalweb-checksum-sha256': [
          base64Encode(sha256.convert(body).bytes),
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RejectFirstTargetAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        body.addAll(chunk);
      }
    }
    return ResponseBody.fromString(
      requests.length == 1 ? '<Error><Code>ExpiredToken</Code></Error>' : '',
      requests.length == 1 ? 403 : 200,
      headers: {
        Headers.contentTypeHeader: [
          requests.length == 1 ? 'application/xml' : 'text/plain',
        ],
        if (requests.length > 1) 'etag': ['"refreshed-etag"'],
        if (requests.length > 1)
          'X-CrystalWeb-Checksum-SHA256': [
            base64Encode(sha256.convert(body).bytes),
          ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RecoveryApiAdapter implements HttpClientAdapter {
  _RecoveryApiAdapter({
    required this.changedFingerprint,
    this.finalizing = false,
  });

  final bool changedFingerprint;
  final bool finalizing;
  final requests = <RequestOptions>[];
  var createAttempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path.endsWith('/microscope-upload-sessions')) {
      createAttempts++;
      if (changedFingerprint && createAttempts == 1) {
        return _json({
          'detail': {
            'code': 'microscope_upload_recovery_required',
            'message':
                'An earlier unfinished upload is using these microscope names.',
            'recovery_session_id': 'previous-session',
            'identities': ['sample-001'],
            'can_discard': true,
          },
        }, 409);
      }
      final requestedSet = (options.data as Map)['sets'][0] as Map;
      final requestedId = requestedSet['client_set_id'] as String;
      final files = requestedSet['files'] as Map;
      Map<String, Object?> target(String role) => {
        'protocol': 'multipart-v1',
        'part_size_bytes': 8 * 1024 * 1024,
        'completed': false,
        'parts': [
          {
            'part_number': 1,
            'size_bytes': files[role]['size_bytes'],
            'url': 'https://upload.invalid/$role/1',
            'headers': <String, String>{
              crystalWebChecksumHeader:
                  (((files[role] as Map)['multipart_parts'] as List).first
                          as Map)['checksum_sha256']
                      as String,
            },
          },
        ],
      };
      return _json({
        'session_id': changedFingerprint
            ? 'replacement-session'
            : 'previous-session',
        'status': 'active',
        'resumed': !changedFingerprint,
        'sets': [
          {
            'set_id': 'recovered-set',
            'client_set_id': changedFingerprint ? requestedId : 'old-client-id',
            'logical_base_name': 'Sample-001',
            'normalized_match_key': 'sample-001',
            'status': finalizing ? 'finalizing' : 'pending',
            'targets': finalizing
                ? <String, Object?>{}
                : {'tiff': target('tiff'), 'txt': target('txt')},
          },
        ],
      }, changedFingerprint ? 201 : 200);
    }
    if (options.path.endsWith('/previous-session/cancel')) {
      return _json({
        'session_id': 'previous-session',
        'status': 'cancelled',
        'deleted_staging_objects': 0,
        'cleanup_failures': 0,
      });
    }
    if (options.path.endsWith('/finalize')) {
      return _json({
        'session_id': changedFingerprint
            ? 'replacement-session'
            : 'previous-session',
        'status': 'completed',
        'edit_state_version': 2,
        'content_revision': 8,
        'finalized': [
          {
            'set_id': 'recovered-set',
            'image_id': 'image-1',
            'status': 'pending',
          },
        ],
        'already_finalized': <Map<String, Object?>>[],
        'failed': <Map<String, Object?>>[],
      });
    }
    return _json({});
  }

  ResponseBody _json(Map<String, Object?> body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  @override
  void close({bool force = false}) {}
}

class _RangeRead {
  const _RangeRead(this.path, this.start, this.end);

  final String path;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is _RangeRead &&
      other.path == path &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(path, start, end);

  @override
  String toString() => '$path[$start:$end]';
}

class _RangeSource implements MicroscopeFileSource {
  final reads = <_RangeRead>[];

  @override
  Future<List<MicroscopeLocalFile>> pickFiles({
    bool allowMultiple = true,
  }) async => const [];

  @override
  Future<MicroscopeLocalFile> hashFile(MicroscopeLocalFile file) async {
    final bytes = List<int>.generate(file.sizeBytes, (index) => index);
    final checksums = <String>[];
    for (var start = 0; start < bytes.length; start += 4) {
      checksums.add(
        base64Encode(
          sha256
              .convert(bytes.sublist(start, min(start + 4, bytes.length)))
              .bytes,
        ),
      );
    }
    return file.copyWith(
      sha256: sha256.convert(bytes).toString(),
      multipartChecksums: checksums,
    );
  }

  @override
  void releaseFiles(Iterable<MicroscopeLocalFile> files) {}

  @override
  Stream<List<int>> openRead(MicroscopeLocalFile file, {int? start, int? end}) {
    final rangeStart = start ?? 0;
    final rangeEnd = end ?? file.sizeBytes;
    reads.add(_RangeRead(file.path, rangeStart, rangeEnd));
    return Stream.value(
      List<int>.generate(rangeEnd - rangeStart, (index) => rangeStart + index),
    );
  }
}

class _MultipartApiAdapter implements HttpClientAdapter {
  _MultipartApiAdapter({
    this.includeRecoveredPart = true,
    this.rejectCompleteAsStale = false,
    this.completeEntered,
    this.releaseComplete,
  });

  bool includeRecoveredPart;
  bool rejectCompleteAsStale;
  final Completer<void>? completeEntered;
  final Completer<void>? releaseComplete;
  bool recoverSinglePart = false;
  final requests = <RequestOptions>[];
  String? clientSetId;

  String _checksum(int start, int end) => base64Encode(
    sha256.convert(List<int>.generate(end - start, (i) => start + i)).bytes,
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path.endsWith('/microscope-upload-sessions')) {
      clientSetId = (options.data as Map)['sets'][0]['client_set_id'] as String;
      return _json({
        'session_id': 'multipart-session',
        'status': 'active',
        'sets': [
          {
            'set_id': 'multipart-set',
            'client_set_id': clientSetId,
            'targets': {
              'tiff': {
                'protocol': 'multipart-v1',
                'part_size_bytes': 4,
                'completed': false,
                'parts': [
                  if (includeRecoveredPart || recoverSinglePart)
                    {
                      'part_number': 1,
                      'size_bytes': 4,
                      'etag': '"recovered-etag"',
                      'checksum_sha256': _checksum(0, 4),
                    }
                  else
                    {
                      'part_number': 1,
                      'size_bytes': 4,
                      'url': 'https://upload.invalid/tiff/1',
                      'headers': {crystalWebChecksumHeader: _checksum(0, 4)},
                    },
                  if (includeRecoveredPart) ...[
                    {
                      'part_number': 2,
                      'size_bytes': 4,
                      'url': 'https://upload.invalid/tiff/2',
                      'headers': {
                        'Content-Length': '4',
                        crystalWebChecksumHeader: _checksum(4, 8),
                      },
                    },
                    {
                      'part_number': 3,
                      'size_bytes': 2,
                      'url': 'https://upload.invalid/tiff/3',
                      'headers': {
                        'content-length': '2',
                        crystalWebChecksumHeader: _checksum(8, 10),
                      },
                    },
                  ],
                ],
              },
              'txt': {
                'protocol': 'multipart-v1',
                'part_size_bytes': 3,
                'completed': true,
                'parts': [
                  {
                    'part_number': 1,
                    'size_bytes': 3,
                    'etag': '"txt-etag"',
                    'checksum_sha256': _checksum(0, 3),
                  },
                ],
              },
            },
          },
        ],
      }, 201);
    }
    if (options.method == 'GET' &&
        options.path.endsWith(
          '/microscope-upload-sessions/multipart-session',
        )) {
      return _json({
        'session_id': 'multipart-session',
        'status': 'active',
        'expires_at': '2026-08-21T00:00:00Z',
        'edit_state_version': 2,
        'content_revision': 7,
        'sets': [
          {
            'set_id': 'multipart-set',
            'client_set_id': clientSetId,
            'normalized_match_key': 'sample-001',
            'status': 'pending',
          },
        ],
      });
    }
    if (options.path.contains('/multipart/') &&
        options.path.endsWith('/complete')) {
      if (completeEntered != null && !completeEntered!.isCompleted) {
        completeEntered!.complete();
      }
      if (releaseComplete != null) await releaseComplete!.future;
      if (rejectCompleteAsStale) {
        return _json({
          'detail': {
            'code': 'microscope_upload_stale',
            'message': 'The Campaign changed while these files were uploading.',
            'source': 'concurrency',
            'severity': 'warning',
            'retryable': true,
            'recommended_action':
                'Refresh the Campaign to load the latest operator changes, then resume this upload.',
            'edit_state_version': 2,
            'content_revision': 9,
          },
        }, 412);
      }
      return _json({'status': 'completed'});
    }
    if (options.path.endsWith('/finalize')) {
      return _json({
        'session_id': 'multipart-session',
        'status': 'completed',
        'edit_state_version': 2,
        'content_revision': 8,
        'finalized': [
          {
            'set_id': 'multipart-set',
            'image_id': 'multipart-image',
            'status': 'pending',
          },
        ],
        'already_finalized': <Map<String, Object?>>[],
        'failed': <Map<String, Object?>>[],
      });
    }
    return _json({});
  }

  ResponseBody _json(Map<String, Object?> body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  @override
  void close({bool force = false}) {}
}

class _MultipartTransferAdapter implements HttpClientAdapter {
  _MultipartTransferAdapter({
    this.failuresBeforeSuccess = 0,
    this.failureStatus = 503,
  });

  final int failuresBeforeSuccess;
  final int failureStatus;
  final requests = <RequestOptions>[];
  final bodies = <List<int>>[];
  var attempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    attempts++;
    final body = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        body.addAll(chunk);
      }
    }
    bodies.add(body);
    if (attempts <= failuresBeforeSuccess) {
      return ResponseBody.fromString(
        'temporary transfer failure',
        failureStatus,
      );
    }
    return ResponseBody.fromString(
      '',
      200,
      headers: {
        'etag': ['"etag-$attempts"'],
        'x-cRyStAlWeB-cHeCkSuM-sHa256': [
          base64Encode(sha256.convert(body).bytes),
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _BatchingApiAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  var sessions = 0;
  final Map<String, String> clientIdsByServerId = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path.endsWith('/microscope-upload-sessions')) {
      sessions++;
      final declarations = (options.data as Map)['sets'] as List;
      final sets = <Map<String, Object?>>[];
      for (final (index, raw) in declarations.indexed) {
        final declaration = raw as Map;
        final serverId = 'set-$sessions-$index';
        final clientId = declaration['client_set_id'] as String;
        final files = declaration['files'] as Map;
        Map<String, Object?> target(String role) => {
          'protocol': 'multipart-v1',
          'part_size_bytes': 8 * 1024 * 1024,
          'completed': false,
          'parts': [
            {
              'part_number': 1,
              'size_bytes': files[role]['size_bytes'],
              'url': 'https://upload.invalid/$serverId/$role/1',
              'headers': <String, String>{
                crystalWebChecksumHeader:
                    (((files[role] as Map)['multipart_parts'] as List).first
                            as Map)['checksum_sha256']
                        as String,
              },
            },
          ],
        };
        clientIdsByServerId[serverId] = clientId;
        sets.add({
          'set_id': serverId,
          'client_set_id': clientId,
          'status': 'pending',
          'reserved_image_number': index + 1,
          'targets': {'tiff': target('tiff'), 'txt': target('txt')},
        });
      }
      return _json({
        'session_id': 'batch-session-$sessions',
        'status': 'active',
        'expires_at': '2030-01-01T00:00:00Z',
        'sets': sets,
      }, 201);
    }
    if (options.path.endsWith('/finalize')) {
      final ids = ((options.data as Map)['set_ids'] as List).cast<String>();
      return _json({
        'session_id': 'batch-session-$sessions',
        'status': 'completed',
        'edit_state_version': 2,
        'content_revision': 7 + sessions,
        'finalized': [
          for (final id in ids)
            {'set_id': id, 'image_id': 'image-$id', 'status': 'pending'},
        ],
        'already_finalized': <Map<String, Object?>>[],
        'failed': <Map<String, Object?>>[],
      });
    }
    return _json({});
  }

  ResponseBody _json(Map<String, Object?> body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  @override
  void close({bool force = false}) {}
}

class _PausingTransferAdapter implements HttpClientAdapter {
  final started = Completer<void>();
  var block = true;
  var attempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts++;
    if (!started.isCompleted) started.complete();
    if (block && cancelFuture != null) await cancelFuture;
    if (block) return ResponseBody.fromString('paused', 499);
    final body = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        body.addAll(chunk);
      }
    }
    return ResponseBody.fromString(
      '',
      200,
      headers: {
        'etag': ['"pause-etag-$attempts"'],
        crystalWebChecksumHeader: [base64Encode(sha256.convert(body).bytes)],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('sanitizes target headers for browser multipart requests', () {
    expect(
      webSafeTransferHeaders({
        'Content-Length': '4',
        crystalWebChecksumHeader: 'checksum',
        'X-Request-Id': 'request-1',
      }),
      {crystalWebChecksumHeader: 'checksum', 'X-Request-Id': 'request-1'},
    );
  });

  test('requires multipart-v1 and never downgrades to single PUT', () async {
    final apiAdapter = _ApiAdapter(rejectMultipart: true);
    final apiDio = Dio(BaseOptions(baseUrl: 'https://api.invalid'))
      ..httpClientAdapter = apiAdapter;
    final transferAdapter = _TransferAdapter();
    final transferDio = Dio()..httpClientAdapter = transferAdapter;
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient.withDio(apiDio)),
        microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
        microscopeTransferDioProvider.overrideWithValue(transferDio),
      ],
    );
    addTearDown(container.dispose);
    const args = MicroscopeUploadArgs(
      batchId: 'batch-1',
      bagId: 'bag-1',
      editStateVersion: 2,
      contentRevision: 7,
    );
    final subscription = container.listen(
      microscopeUploadProvider(args),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(microscopeUploadProvider(args).notifier);
    notifier.addFiles([file('Sample-001.tif'), file('Sample-001.txt')]);

    await notifier.uploadReady();

    final state = container.read(microscopeUploadProvider(args));
    expect(apiAdapter.requests, hasLength(1));
    final create = apiAdapter.requests.single;
    final body = create.data as Map;
    expect(body['upload_protocol'], 'multipart-v1');
    expect(body['sets'][0]['files']['tiff']['multipart_parts'], isNotEmpty);
    expect(create.headers['If-Match'], '"campaign-edit-2-content-7"');
    expect(create.headers['Idempotency-Key'], isNotEmpty);
    expect(state.issue?.code, 'microscope_upload_browser_multipart_required');
    expect(state.issue?.retryable, isFalse);
    expect(transferAdapter.requests, isEmpty);
  });

  test('does not downgrade a new-backend multipart create 422', () async {
    final apiAdapter = _ApiAdapter(rejectMultipartSafety: true);
    final transferAdapter = _TransferAdapter();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient.withDio(
            Dio(BaseOptions(baseUrl: 'https://api.invalid'))
              ..httpClientAdapter = apiAdapter,
          ),
        ),
        microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
        microscopeTransferDioProvider.overrideWithValue(
          Dio()..httpClientAdapter = transferAdapter,
        ),
      ],
    );
    addTearDown(container.dispose);
    const args = MicroscopeUploadArgs(
      batchId: 'batch-1',
      bagId: 'bag-1',
      editStateVersion: 2,
      contentRevision: 7,
    );
    final subscription = container.listen(
      microscopeUploadProvider(args),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(microscopeUploadProvider(args).notifier);
    notifier.addFiles([file('Sample-001.tif'), file('Sample-001.txt')]);

    await notifier.uploadReady();

    expect(
      apiAdapter.requests.where(
        (request) => request.path.endsWith('/microscope-upload-sessions'),
      ),
      hasLength(1),
    );
    expect(transferAdapter.requests, isEmpty);
    expect(
      container.read(microscopeUploadProvider(args)).error,
      contains('fewer'),
    );
  });

  test('does not downgrade a new-backend multipart refresh 422', () async {
    final apiAdapter = _ApiAdapter(rejectRefreshSafety: true);
    final transferAdapter = _TransferAdapter(forbiddenFirst: true);
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient.withDio(
            Dio(BaseOptions(baseUrl: 'https://api.invalid'))
              ..httpClientAdapter = apiAdapter,
          ),
        ),
        microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
        microscopeTransferDioProvider.overrideWithValue(
          Dio()..httpClientAdapter = transferAdapter,
        ),
      ],
    );
    addTearDown(container.dispose);
    const args = MicroscopeUploadArgs(
      batchId: 'batch-1',
      bagId: 'bag-1',
      editStateVersion: 2,
      contentRevision: 7,
    );
    final subscription = container.listen(
      microscopeUploadProvider(args),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(microscopeUploadProvider(args).notifier);
    notifier.addFiles([file('Sample-001.tif'), file('Sample-001.txt')]);
    await notifier.uploadReady();

    final refreshes = apiAdapter.requests
        .where((request) => request.path.endsWith('/targets'))
        .toList();
    expect(refreshes, hasLength(1));
    expect((refreshes.single.data as Map)['upload_protocol'], 'multipart-v1');
    expect(transferAdapter.attempts, 1);
    expect(
      container.read(microscopeUploadProvider(args)).sets.single.uploadError,
      contains('evidence'),
    );
  });

  test(
    'skips recovered parts and completes multipart with exact range checksums',
    () async {
      final apiAdapter = _MultipartApiAdapter();
      final transferAdapter = _MultipartTransferAdapter();
      final source = _RangeSource();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient.withDio(
              Dio(BaseOptions(baseUrl: 'https://api.invalid'))
                ..httpClientAdapter = apiAdapter,
            ),
          ),
          microscopeFileSourceProvider.overrideWithValue(source),
          microscopeTransferDioProvider.overrideWithValue(
            Dio()..httpClientAdapter = transferAdapter,
          ),
        ],
      );
      addTearDown(container.dispose);
      const args = MicroscopeUploadArgs(
        batchId: 'batch-1',
        bagId: 'bag-1',
        editStateVersion: 2,
        contentRevision: 7,
      );
      final subscription = container.listen(
        microscopeUploadProvider(args),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final notifier = container.read(microscopeUploadProvider(args).notifier);
      notifier.addFiles(const [
        MicroscopeLocalFile(
          path: '/tmp/Sample-001.tif',
          name: 'Sample-001.tif',
          sizeBytes: 10,
        ),
        MicroscopeLocalFile(
          path: '/tmp/Sample-001.txt',
          name: 'Sample-001.txt',
          sizeBytes: 3,
        ),
      ]);

      await notifier.uploadReady();

      expect(source.reads, [
        const _RangeRead('/tmp/Sample-001.tif', 4, 8),
        const _RangeRead('/tmp/Sample-001.tif', 8, 10),
      ]);
      expect(transferAdapter.bodies, [
        [4, 5, 6, 7],
        [8, 9],
      ]);
      expect(transferAdapter.requests, hasLength(2));
      expect(
        transferAdapter.requests[0].headers[crystalWebChecksumHeader],
        base64Encode(sha256.convert([4, 5, 6, 7]).bytes),
      );

      final create = apiAdapter.requests.first;
      expect((create.data as Map)['upload_protocol'], 'multipart-v1');
      final completes = apiAdapter.requests
          .where((request) => request.path.endsWith('/complete'))
          .toList();
      expect(completes, hasLength(1));
      expect(
        completes.single.path,
        '/api/v1/microscope-upload-sessions/multipart-session/sets/'
        'multipart-set/multipart/tiff/complete',
      );
      expect(
        completes.single.headers['If-Match'],
        '"campaign-edit-2-content-7"',
      );
      expect((completes.single.data as Map)['parts'], [
        {
          'part_number': 1,
          'etag': '"recovered-etag"',
          'checksum_sha256': base64Encode(sha256.convert([0, 1, 2, 3]).bytes),
        },
        {
          'part_number': 2,
          'etag': '"etag-1"',
          'checksum_sha256': base64Encode(sha256.convert([4, 5, 6, 7]).bytes),
        },
        {
          'part_number': 3,
          'etag': '"etag-2"',
          'checksum_sha256': base64Encode(sha256.convert([8, 9]).bytes),
        },
      ]);
      expect(
        apiAdapter.requests.where(
          (request) => request.path.endsWith('/finalize'),
        ),
        hasLength(1),
      );
      final state = container.read(microscopeUploadProvider(args));
      expect(state.sets.single.uploaded, isTrue);
      expect(state.sets.single.uploadProgress, 1);
      expect(state.sets.single.activity.phase, MicroscopeUploadPhase.queued);
      expect(
        state.sets.single.activity.detail,
        contains('queued for analysis'),
      );
    },
  );

  test(
    'retries a transient multipart part three times before fourth-attempt success',
    () async {
      final apiAdapter = _MultipartApiAdapter(includeRecoveredPart: false);
      final transferAdapter = _MultipartTransferAdapter(
        failuresBeforeSuccess: 3,
      );
      final source = _RangeSource();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient.withDio(
              Dio(BaseOptions(baseUrl: 'https://api.invalid'))
                ..httpClientAdapter = apiAdapter,
            ),
          ),
          microscopeFileSourceProvider.overrideWithValue(source),
          microscopeTransferDioProvider.overrideWithValue(
            Dio()..httpClientAdapter = transferAdapter,
          ),
        ],
      );
      addTearDown(container.dispose);
      const args = MicroscopeUploadArgs(
        batchId: 'batch-1',
        bagId: 'bag-1',
        editStateVersion: 2,
        contentRevision: 7,
      );
      final phases = <MicroscopeUploadPhase>[];
      final retryNumbers = <int>[];
      final subscription = container.listen(microscopeUploadProvider(args), (
        _,
        next,
      ) {
        if (next.sets.isNotEmpty) {
          phases.add(next.sets.single.activity.phase);
          final retry = next.sets.single.activity.retryNumber;
          if (retry != null) retryNumbers.add(retry);
        }
      }, fireImmediately: true);
      addTearDown(subscription.close);
      final notifier = container.read(microscopeUploadProvider(args).notifier);
      notifier.addFiles(const [
        MicroscopeLocalFile(
          path: '/tmp/Sample-001.tif',
          name: 'Sample-001.tif',
          sizeBytes: 4,
        ),
        MicroscopeLocalFile(
          path: '/tmp/Sample-001.txt',
          name: 'Sample-001.txt',
          sizeBytes: 3,
        ),
      ]);

      await notifier.uploadReady();

      expect(transferAdapter.attempts, 4);
      expect(transferAdapter.bodies, everyElement(equals([0, 1, 2, 3])));
      expect(source.reads, [const _RangeRead('/tmp/Sample-001.tif', 0, 4)]);
      expect(
        container.read(microscopeUploadProvider(args)).sets.single.uploaded,
        isTrue,
      );
      expect(phases, contains(MicroscopeUploadPhase.preparing));
      expect(phases, contains(MicroscopeUploadPhase.retrying));
      expect(phases, contains(MicroscopeUploadPhase.verifying));
      expect(phases, contains(MicroscopeUploadPhase.registering));
      expect(retryNumbers, containsAllInOrder([1, 2, 3]));
    },
  );

  test(
    'pause during storage verification does not start registration',
    () async {
      final completeEntered = Completer<void>();
      final releaseComplete = Completer<void>();
      final apiAdapter = _MultipartApiAdapter(
        includeRecoveredPart: false,
        completeEntered: completeEntered,
        releaseComplete: releaseComplete,
      );
      final transferAdapter = _MultipartTransferAdapter();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient.withDio(
              Dio(BaseOptions(baseUrl: 'https://api.invalid'))
                ..httpClientAdapter = apiAdapter,
            ),
          ),
          microscopeFileSourceProvider.overrideWithValue(_RangeSource()),
          microscopeTransferDioProvider.overrideWithValue(
            Dio()..httpClientAdapter = transferAdapter,
          ),
        ],
      );
      addTearDown(container.dispose);
      const args = MicroscopeUploadArgs(
        batchId: 'batch-1',
        bagId: 'bag-1',
        editStateVersion: 2,
        contentRevision: 7,
      );
      final subscription = container.listen(
        microscopeUploadProvider(args),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final notifier = container.read(microscopeUploadProvider(args).notifier);
      notifier.addFiles(const [
        MicroscopeLocalFile(
          path: '/tmp/Sample-001.tif',
          name: 'Sample-001.tif',
          sizeBytes: 4,
        ),
        MicroscopeLocalFile(
          path: '/tmp/Sample-001.txt',
          name: 'Sample-001.txt',
          sizeBytes: 3,
        ),
      ]);

      final upload = notifier.uploadReady();
      await completeEntered.future;
      final pausing = notifier.pause();
      releaseComplete.complete();
      await upload;
      await pausing;

      final state = container.read(microscopeUploadProvider(args));
      expect(state.sessionId, 'multipart-session');
      expect(state.sets.single.uploaded, isFalse);
      expect(state.sets.single.activity.phase, MicroscopeUploadPhase.paused);
      expect(
        apiAdapter.requests.where(
          (request) => request.path.endsWith('/finalize'),
        ),
        isEmpty,
      );
    },
  );

  test('large selections are split into visible safe server batches', () async {
    final apiAdapter = _BatchingApiAdapter();
    final transferAdapter = _TransferAdapter();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient.withDio(
            Dio(BaseOptions(baseUrl: 'https://api.invalid'))
              ..httpClientAdapter = apiAdapter,
          ),
        ),
        microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
        microscopeTransferDioProvider.overrideWithValue(
          Dio()..httpClientAdapter = transferAdapter,
        ),
      ],
    );
    addTearDown(container.dispose);
    const args = MicroscopeUploadArgs(
      batchId: 'batch-1',
      bagId: 'bag-1',
      editStateVersion: 2,
      contentRevision: 7,
    );
    final subscription = container.listen(
      microscopeUploadProvider(args),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(microscopeUploadProvider(args).notifier);
    notifier.addFiles([
      for (var number = 1; number <= 101; number++) ...[
        file('Sample-${number.toString().padLeft(3, '0')}.tif'),
        file('Sample-${number.toString().padLeft(3, '0')}.txt'),
      ],
    ]);

    await notifier.uploadReady();

    var state = container.read(microscopeUploadProvider(args));
    expect(state.uploadedCount, 100);
    expect(state.queuedCount, 1);
    expect(state.sessionId, isNull);
    final creates = apiAdapter.requests
        .where(
          (request) => request.path.endsWith('/microscope-upload-sessions'),
        )
        .toList();
    expect(((creates.single.data as Map)['sets'] as List), hasLength(100));

    await notifier.uploadReady();

    state = container.read(microscopeUploadProvider(args));
    expect(state.uploadedCount, 101);
    expect(apiAdapter.sessions, 2);
    expect(
      apiAdapter.requests.where(
        (request) => request.path.endsWith('/microscope-upload-sessions'),
      ),
      hasLength(2),
    );
  });

  test('pause keeps server session and resume continues safely', () async {
    final apiAdapter = _MultipartApiAdapter(includeRecoveredPart: false);
    final transferAdapter = _PausingTransferAdapter();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient.withDio(
            Dio(BaseOptions(baseUrl: 'https://api.invalid'))
              ..httpClientAdapter = apiAdapter,
          ),
        ),
        microscopeFileSourceProvider.overrideWithValue(_RangeSource()),
        microscopeTransferDioProvider.overrideWithValue(
          Dio()..httpClientAdapter = transferAdapter,
        ),
      ],
    );
    addTearDown(container.dispose);
    const args = MicroscopeUploadArgs(
      batchId: 'batch-1',
      bagId: 'bag-1',
      editStateVersion: 2,
      contentRevision: 7,
    );
    final subscription = container.listen(
      microscopeUploadProvider(args),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(microscopeUploadProvider(args).notifier);
    notifier.addFiles(const [
      MicroscopeLocalFile(
        path: '/tmp/Sample-001.tif',
        name: 'Sample-001.tif',
        sizeBytes: 4,
      ),
      MicroscopeLocalFile(
        path: '/tmp/Sample-001.txt',
        name: 'Sample-001.txt',
        sizeBytes: 3,
      ),
    ]);

    final upload = notifier.uploadReady();
    await transferAdapter.started.future;
    await notifier.pause();
    await upload;

    var state = container.read(microscopeUploadProvider(args));
    expect(state.uploading, isFalse);
    expect(state.sessionId, 'multipart-session');
    expect(state.sets.single.activity.phase, MicroscopeUploadPhase.paused);
    expect(
      apiAdapter.requests.where((request) => request.path.endsWith('/cancel')),
      isEmpty,
    );

    transferAdapter.block = false;
    await notifier.uploadReady();

    state = container.read(microscopeUploadProvider(args));
    expect(state.sets.single.uploaded, isTrue);
    expect(state.sets.single.activity.phase, MicroscopeUploadPhase.queued);
  });

  test('stale finalization pauses and rebinds before retry', () async {
    final apiAdapter = _ApiAdapter(rejectFinalizeStale: true);
    final transferAdapter = _TransferAdapter();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient.withDio(
            Dio(BaseOptions(baseUrl: 'https://api.invalid'))
              ..httpClientAdapter = apiAdapter,
          ),
        ),
        microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
        microscopeTransferDioProvider.overrideWithValue(
          Dio()..httpClientAdapter = transferAdapter,
        ),
      ],
    );
    addTearDown(container.dispose);
    const args = MicroscopeUploadArgs(
      batchId: 'batch-1',
      bagId: 'bag-1',
      editStateVersion: 2,
      contentRevision: 7,
    );
    final subscription = container.listen(
      microscopeUploadProvider(args),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(microscopeUploadProvider(args).notifier);
    notifier.addFiles([file('Sample-001.tif'), file('Sample-001.txt')]);

    await notifier.uploadReady();

    var state = container.read(microscopeUploadProvider(args));
    expect(state.issue?.source, MicroscopeUploadIssueSource.concurrency);
    expect(state.sessionId, isNull);
    expect(state.sets.single.activity.phase, MicroscopeUploadPhase.paused);
    expect(
      apiAdapter.requests.where((request) => request.path.endsWith('/cancel')),
      isEmpty,
    );

    apiAdapter.rejectFinalizeStale = false;
    await notifier.uploadReady();

    state = container.read(microscopeUploadProvider(args));
    expect(state.sets.single.uploaded, isTrue);
    expect(apiAdapter.createAttempts, 2);
    expect(apiAdapter.finalizeAttempts, 2);
  });

  test('stale target refresh detaches and rebinds without looping', () async {
    final apiAdapter = _ApiAdapter(rejectRefreshStale: true);
    final transferAdapter = _TransferAdapter(forbiddenFirst: true);
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient.withDio(
            Dio(BaseOptions(baseUrl: 'https://api.invalid'))
              ..httpClientAdapter = apiAdapter,
          ),
        ),
        microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
        microscopeTransferDioProvider.overrideWithValue(
          Dio()..httpClientAdapter = transferAdapter,
        ),
      ],
    );
    addTearDown(container.dispose);
    const args = MicroscopeUploadArgs(
      batchId: 'batch-1',
      bagId: 'bag-1',
      editStateVersion: 2,
      contentRevision: 7,
    );
    final subscription = container.listen(
      microscopeUploadProvider(args),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(microscopeUploadProvider(args).notifier);
    notifier.addFiles([file('Sample-001.tif'), file('Sample-001.txt')]);

    await notifier.uploadReady();

    var state = container.read(microscopeUploadProvider(args));
    expect(state.issue?.title, 'Campaign changed on another client');
    expect(state.issue?.source, MicroscopeUploadIssueSource.concurrency);
    expect(state.sessionId, isNull);
    expect(state.sets.single.activity.phase, MicroscopeUploadPhase.paused);
    expect(
      apiAdapter.requests.where((request) => request.path.endsWith('/cancel')),
      isEmpty,
    );

    apiAdapter.rejectRefreshStale = false;
    await notifier.uploadReady();

    state = container.read(microscopeUploadProvider(args));
    expect(state.sets.single.uploaded, isTrue);
    final creates = apiAdapter.requests
        .where(
          (request) => request.path.endsWith('/microscope-upload-sessions'),
        )
        .toList();
    expect(creates, hasLength(2));
    expect(creates.last.headers['If-Match'], '"campaign-edit-2-content-9"');
  });

  test(
    'server concurrency conflict is never reported as an internet failure',
    () async {
      final apiAdapter = _MultipartApiAdapter(
        includeRecoveredPart: false,
        rejectCompleteAsStale: true,
      );
      final transferAdapter = _MultipartTransferAdapter();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient.withDio(
              Dio(BaseOptions(baseUrl: 'https://api.invalid'))
                ..httpClientAdapter = apiAdapter,
            ),
          ),
          microscopeFileSourceProvider.overrideWithValue(_RangeSource()),
          microscopeTransferDioProvider.overrideWithValue(
            Dio()..httpClientAdapter = transferAdapter,
          ),
        ],
      );
      addTearDown(container.dispose);
      const args = MicroscopeUploadArgs(
        batchId: 'batch-1',
        bagId: 'bag-1',
        editStateVersion: 2,
        contentRevision: 7,
      );
      final subscription = container.listen(
        microscopeUploadProvider(args),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final notifier = container.read(microscopeUploadProvider(args).notifier);
      notifier.addFiles(const [
        MicroscopeLocalFile(
          path: '/tmp/Sample-001.tif',
          name: 'Sample-001.tif',
          sizeBytes: 4,
        ),
        MicroscopeLocalFile(
          path: '/tmp/Sample-001.txt',
          name: 'Sample-001.txt',
          sizeBytes: 3,
        ),
      ]);

      await notifier.uploadReady();

      final state = container.read(microscopeUploadProvider(args));
      expect(state.issue?.title, 'Campaign changed on another client');
      expect(state.issue?.source, MicroscopeUploadIssueSource.concurrency);
      expect(state.error, contains('latest operator changes'));
      expect(state.error?.toLowerCase(), isNot(contains('internet')));
      expect(state.sets.single.activity.phase, MicroscopeUploadPhase.paused);
      expect(state.sessionId, isNull);
      expect(
        apiAdapter.requests.where(
          (request) => request.path.endsWith('/cancel'),
        ),
        isEmpty,
      );

      apiAdapter.rejectCompleteAsStale = false;
      apiAdapter.recoverSinglePart = true;
      await notifier.uploadReady();

      final resumed = container.read(microscopeUploadProvider(args));
      expect(resumed.sets.single.uploaded, isTrue);
      expect(transferAdapter.requests, hasLength(1));
      final creates = apiAdapter.requests
          .where(
            (request) => request.path.endsWith('/microscope-upload-sessions'),
          )
          .toList();
      expect(creates, hasLength(2));
      expect(creates.last.headers['If-Match'], '"campaign-edit-2-content-9"');
    },
  );

  test(
    'does not retry a multipart 4xx and gives actionable recovery',
    () async {
      final apiAdapter = _MultipartApiAdapter(includeRecoveredPart: false);
      final transferAdapter = _MultipartTransferAdapter(
        failuresBeforeSuccess: 5,
        failureStatus: 400,
      );
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient.withDio(
              Dio(BaseOptions(baseUrl: 'https://api.invalid'))
                ..httpClientAdapter = apiAdapter,
            ),
          ),
          microscopeFileSourceProvider.overrideWithValue(_RangeSource()),
          microscopeTransferDioProvider.overrideWithValue(
            Dio()..httpClientAdapter = transferAdapter,
          ),
        ],
      );
      addTearDown(container.dispose);
      const args = MicroscopeUploadArgs(
        batchId: 'batch-1',
        bagId: 'bag-1',
        editStateVersion: 2,
        contentRevision: 7,
      );
      final subscription = container.listen(
        microscopeUploadProvider(args),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final notifier = container.read(microscopeUploadProvider(args).notifier);
      notifier.addFiles(const [
        MicroscopeLocalFile(
          path: '/tmp/Sample-001.tif',
          name: 'Sample-001.tif',
          sizeBytes: 4,
        ),
        MicroscopeLocalFile(
          path: '/tmp/Sample-001.txt',
          name: 'Sample-001.txt',
          sizeBytes: 3,
        ),
      ]);

      await notifier.uploadReady();

      expect(transferAdapter.attempts, 1);
      final error = container
          .read(microscopeUploadProvider(args))
          .sets
          .single
          .uploadError!;
      expect(error.toLowerCase(), contains('resume'));
      expect(error, isNot(contains('upload.invalid')));
      expect(
        container
            .read(microscopeUploadProvider(args))
            .sets
            .single
            .activity
            .phase,
        MicroscopeUploadPhase.paused,
      );
    },
  );

  test('reuses the create key after a lost create response', () async {
    final apiAdapter = _ApiAdapter(loseFirstCreate: true);
    final apiDio = Dio(BaseOptions(baseUrl: 'https://api.invalid'))
      ..httpClientAdapter = apiAdapter;
    final transferAdapter = _TransferAdapter();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient.withDio(apiDio)),
        microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
        microscopeTransferDioProvider.overrideWithValue(
          Dio()..httpClientAdapter = transferAdapter,
        ),
      ],
    );
    addTearDown(container.dispose);
    const args = MicroscopeUploadArgs(
      batchId: 'batch-1',
      bagId: 'bag-1',
      editStateVersion: 2,
      contentRevision: 7,
    );
    final subscription = container.listen(
      microscopeUploadProvider(args),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(microscopeUploadProvider(args).notifier);
    notifier.addFiles([file('Sample-001.tif'), file('Sample-001.txt')]);

    await notifier.uploadReady();
    await notifier.uploadReady();

    final creates = apiAdapter.requests
        .where(
          (request) => request.path.endsWith('/microscope-upload-sessions'),
        )
        .toList();
    expect(creates, hasLength(2));
    expect(
      creates[0].headers['Idempotency-Key'],
      creates[1].headers['Idempotency-Key'],
    );
    expect(
      container.read(microscopeUploadProvider(args)).sets.single.uploaded,
      isTrue,
    );
  });

  test('reconciles a committed finalize after its response is lost', () async {
    final apiAdapter = _ApiAdapter(loseFirstFinalize: true);
    final apiDio = Dio(BaseOptions(baseUrl: 'https://api.invalid'))
      ..httpClientAdapter = apiAdapter;
    final transferAdapter = _TransferAdapter();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient.withDio(apiDio)),
        microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
        microscopeTransferDioProvider.overrideWithValue(
          Dio()..httpClientAdapter = transferAdapter,
        ),
      ],
    );
    addTearDown(container.dispose);
    const args = MicroscopeUploadArgs(
      batchId: 'batch-1',
      bagId: 'bag-1',
      editStateVersion: 2,
      contentRevision: 7,
    );
    final subscription = container.listen(
      microscopeUploadProvider(args),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(microscopeUploadProvider(args).notifier);
    notifier.addFiles([file('Sample-001.tif'), file('Sample-001.txt')]);

    await notifier.uploadReady();
    await notifier.uploadReady();

    expect(apiAdapter.finalizeAttempts, 1);
    expect(transferAdapter.requests, hasLength(2));
    final recovered = container
        .read(microscopeUploadProvider(args))
        .sets
        .single;
    expect(recovered.uploaded, isTrue);
    expect(recovered.imageId, 'image-1');
  });

  test(
    'refreshes failed transfers with the backend sets-and-roles schema',
    () async {
      final apiAdapter = _ApiAdapter();
      final apiDio = Dio(BaseOptions(baseUrl: 'https://api.invalid'))
        ..httpClientAdapter = apiAdapter;
      final transferAdapter = _TransferAdapter(forbiddenFirst: true);
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient.withDio(apiDio)),
          microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
          microscopeTransferDioProvider.overrideWithValue(
            Dio()..httpClientAdapter = transferAdapter,
          ),
        ],
      );
      addTearDown(container.dispose);
      const args = MicroscopeUploadArgs(
        batchId: 'batch-1',
        bagId: 'bag-1',
        editStateVersion: 2,
        contentRevision: 7,
      );
      final subscription = container.listen(
        microscopeUploadProvider(args),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final notifier = container.read(microscopeUploadProvider(args).notifier);
      notifier.addFiles([file('Sample-001.tif'), file('Sample-001.txt')]);

      await notifier.uploadReady();
      await notifier.uploadReady();

      final refresh = apiAdapter.requests.singleWhere(
        (request) => request.path.endsWith('/targets'),
      );
      final refreshBody = refresh.data as Map;
      expect(refreshBody.keys, contains('sets'));
      expect(refreshBody['upload_protocol'], 'multipart-v1');
      expect(refreshBody['sets'][0]['set_id'], 'set-1');
      expect(refreshBody['sets'][0]['roles'], ['tiff', 'txt']);
    },
  );

  test(
    'expired secure target refreshes once and keeps completed work',
    () async {
      final apiAdapter = _ApiAdapter();
      final transferAdapter = _RejectFirstTargetAdapter();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient.withDio(
              Dio(BaseOptions(baseUrl: 'https://api.invalid'))
                ..httpClientAdapter = apiAdapter,
            ),
          ),
          microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
          microscopeTransferDioProvider.overrideWithValue(
            Dio()..httpClientAdapter = transferAdapter,
          ),
        ],
      );
      addTearDown(container.dispose);
      const args = MicroscopeUploadArgs(
        batchId: 'batch-1',
        bagId: 'bag-1',
        editStateVersion: 2,
        contentRevision: 7,
      );
      final subscription = container.listen(
        microscopeUploadProvider(args),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final notifier = container.read(microscopeUploadProvider(args).notifier);
      notifier.addFiles([file('Sample-001.tif'), file('Sample-001.txt')]);

      await notifier.uploadReady();

      final state = container.read(microscopeUploadProvider(args));
      expect(state.sets.single.uploaded, isTrue);
      expect(transferAdapter.requests, hasLength(3));
      final refreshes = apiAdapter.requests
          .where((request) => request.path.endsWith('/targets'))
          .toList();
      expect(refreshes, hasLength(1));
      expect((refreshes.single.data as Map)['sets'], [
        {
          'set_id': 'set-1',
          'roles': ['tiff', 'txt'],
        },
      ]);
    },
  );

  test('storage 403 does not blame the operator role', () async {
    final apiAdapter = _ApiAdapter();
    final apiDio = Dio(BaseOptions(baseUrl: 'https://api.invalid'))
      ..httpClientAdapter = apiAdapter;
    final transferAdapter = _TransferAdapter(forbidden: true);
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient.withDio(apiDio)),
        microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
        microscopeTransferDioProvider.overrideWithValue(
          Dio()..httpClientAdapter = transferAdapter,
        ),
      ],
    );
    addTearDown(container.dispose);
    const args = MicroscopeUploadArgs(
      batchId: 'batch-1',
      bagId: 'bag-1',
      editStateVersion: 2,
      contentRevision: 7,
    );
    final subscription = container.listen(
      microscopeUploadProvider(args),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(microscopeUploadProvider(args).notifier);
    notifier.addFiles([file('Sample-001.tif'), file('Sample-001.txt')]);

    await notifier.uploadReady();

    final failed = container.read(microscopeUploadProvider(args)).sets.single;
    expect(failed.issue?.title, 'Secure upload permission was rejected');
    expect(failed.uploadError, contains('secure target'));
    expect(failed.uploadError, contains('Resume'));
    expect(failed.uploadError, isNot(contains('permission')));
  });

  test(
    'resumes an interrupted set by normalized identity after restart',
    () async {
      final apiAdapter = _RecoveryApiAdapter(changedFingerprint: false);
      final transferAdapter = _TransferAdapter();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient.withDio(
              Dio(BaseOptions(baseUrl: 'https://api.invalid'))
                ..httpClientAdapter = apiAdapter,
            ),
          ),
          microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
          microscopeTransferDioProvider.overrideWithValue(
            Dio()..httpClientAdapter = transferAdapter,
          ),
        ],
      );
      addTearDown(container.dispose);
      const args = MicroscopeUploadArgs(
        batchId: 'batch-1',
        bagId: 'bag-1',
        editStateVersion: 2,
        contentRevision: 7,
      );
      final subscription = container.listen(
        microscopeUploadProvider(args),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final notifier = container.read(microscopeUploadProvider(args).notifier);
      notifier.addFiles([file('Sample-001.tif'), file('Sample-001.txt')]);

      await notifier.uploadReady();

      final state = container.read(microscopeUploadProvider(args));
      expect(state.sets.single.uploaded, isTrue);
      expect(state.notice, contains('exact unfinished upload'));
      expect(transferAdapter.requests, hasLength(2));
    },
  );

  test('finalizing recovery reconciles without issuing new PUTs', () async {
    final apiAdapter = _RecoveryApiAdapter(
      changedFingerprint: false,
      finalizing: true,
    );
    final transferAdapter = _TransferAdapter();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient.withDio(
            Dio(BaseOptions(baseUrl: 'https://api.invalid'))
              ..httpClientAdapter = apiAdapter,
          ),
        ),
        microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
        microscopeTransferDioProvider.overrideWithValue(
          Dio()..httpClientAdapter = transferAdapter,
        ),
      ],
    );
    addTearDown(container.dispose);
    const args = MicroscopeUploadArgs(
      batchId: 'batch-1',
      bagId: 'bag-1',
      editStateVersion: 2,
      contentRevision: 7,
    );
    final subscription = container.listen(
      microscopeUploadProvider(args),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(microscopeUploadProvider(args).notifier);
    notifier.addFiles([file('Sample-001.tif'), file('Sample-001.txt')]);

    await notifier.uploadReady();

    final state = container.read(microscopeUploadProvider(args));
    expect(state.sets.single.uploaded, isTrue);
    expect(transferAdapter.requests, isEmpty);
    expect(
      apiAdapter.requests.any((request) => request.path.endsWith('/finalize')),
      isTrue,
    );
  });

  test(
    'changed retry offers discard previous upload and retries safely',
    () async {
      final apiAdapter = _RecoveryApiAdapter(changedFingerprint: true);
      final transferAdapter = _TransferAdapter();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient.withDio(
              Dio(BaseOptions(baseUrl: 'https://api.invalid'))
                ..httpClientAdapter = apiAdapter,
            ),
          ),
          microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
          microscopeTransferDioProvider.overrideWithValue(
            Dio()..httpClientAdapter = transferAdapter,
          ),
        ],
      );
      addTearDown(container.dispose);
      const args = MicroscopeUploadArgs(
        batchId: 'batch-1',
        bagId: 'bag-1',
        editStateVersion: 2,
        contentRevision: 7,
      );
      final subscription = container.listen(
        microscopeUploadProvider(args),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final notifier = container.read(microscopeUploadProvider(args).notifier);
      notifier.addFiles([file('Sample-001.tif'), file('Sample-001.txt')]);

      await notifier.uploadReady();
      var state = container.read(microscopeUploadProvider(args));
      expect(state.recoverySessionId, 'previous-session');
      expect(state.error, contains('earlier unfinished upload'));

      await notifier.discardPreviousAndRetry();

      state = container.read(microscopeUploadProvider(args));
      expect(state.recoverySessionId, isNull);
      expect(state.sets.single.uploaded, isTrue);
      expect(
        apiAdapter.requests.any(
          (request) => request.path.endsWith('/previous-session/cancel'),
        ),
        isTrue,
      );
    },
  );

  test('later selections merge into one ready row', () {
    final container = ProviderContainer(
      overrides: [
        microscopeFileSourceProvider.overrideWithValue(_FakeSource()),
      ],
    );
    addTearDown(container.dispose);
    const args = MicroscopeUploadArgs(
      batchId: 'batch-1',
      bagId: 'bag-1',
      editStateVersion: 2,
      contentRevision: 7,
    );
    final subscription = container.listen(
      microscopeUploadProvider(args),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(microscopeUploadProvider(args).notifier);
    notifier.addFiles([file('Sample-002.tif')]);
    final firstId = container
        .read(microscopeUploadProvider(args))
        .sets
        .single
        .clientSetId;
    notifier.addFiles([file('Sample-002.txt')]);

    final set = container.read(microscopeUploadProvider(args)).sets.single;
    expect(set.clientSetId, firstId);
    expect(set.selectionStatus, MicroscopeSetSelectionStatus.ready);
  });
}
