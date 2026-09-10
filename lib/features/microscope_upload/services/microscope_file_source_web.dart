import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:web/web.dart' as web;

import '../models/microscope_file_set.dart';
import 'microscope_file_source_base.dart';

const _multipartPartSize = 8 * 1024 * 1024;
const _readChunkSize = 1024 * 1024;

typedef BrowserFilePicker =
    Future<List<web.File>> Function({required bool allowMultiple});

/// Browser-backed source for repeatable, range-addressable microscope reads.
///
/// Browser file paths are intentionally unavailable. Selected [web.File]
/// objects remain bound to opaque in-memory identifiers for this app session,
/// allowing hashing and multipart retries to reopen exact byte ranges without
/// loading an entire large TIFF into Dart memory.
class WebMicroscopeFileSource implements MicroscopeFileSource {
  WebMicroscopeFileSource({BrowserFilePicker? picker})
    : _picker = picker ?? _pickBrowserFiles;

  final BrowserFilePicker _picker;
  final Map<String, web.File> _files = {};
  int _nextId = 0;

  @override
  Future<List<MicroscopeLocalFile>> pickFiles({
    bool allowMultiple = true,
  }) async {
    final selected = await _picker(allowMultiple: allowMultiple);
    return [for (final file in selected) _bind(file)];
  }

  MicroscopeLocalFile _bind(web.File file) {
    final id = 'browser-file:${_nextId++}:${file.lastModified}';
    _files[id] = file;
    return MicroscopeLocalFile(path: id, name: file.name, sizeBytes: file.size);
  }

  @override
  Future<MicroscopeLocalFile> hashFile(MicroscopeLocalFile file) async {
    final wholeOutput = _DigestSink();
    final wholeSink = sha256.startChunkedConversion(wholeOutput);
    var partOutput = _DigestSink();
    var partSink = sha256.startChunkedConversion(partOutput);
    var partBytes = 0;
    final partChecksums = <String>[];

    await for (final chunk in openRead(file)) {
      wholeSink.add(chunk);
      var offset = 0;
      while (offset < chunk.length) {
        final take = min(_multipartPartSize - partBytes, chunk.length - offset);
        partSink.add(chunk.sublist(offset, offset + take));
        offset += take;
        partBytes += take;
        if (partBytes == _multipartPartSize) {
          partSink.close();
          partChecksums.add(base64Encode(partOutput.value!.bytes));
          partOutput = _DigestSink();
          partSink = sha256.startChunkedConversion(partOutput);
          partBytes = 0;
        }
      }
    }
    wholeSink.close();
    if (partBytes > 0) {
      partSink.close();
      partChecksums.add(base64Encode(partOutput.value!.bytes));
    } else {
      partSink.close();
    }
    return file.copyWith(
      sha256: wholeOutput.value.toString(),
      multipartChecksums: List.unmodifiable(partChecksums),
    );
  }

  @override
  void releaseFiles(Iterable<MicroscopeLocalFile> files) {
    for (final file in files) {
      _files.remove(file.path);
    }
  }

  @override
  Stream<List<int>> openRead(
    MicroscopeLocalFile file, {
    int? start,
    int? end,
  }) async* {
    final browserFile = _files[file.path];
    if (browserFile == null) {
      throw StateError(
        'The browser no longer has access to this file. Select the exact file again.',
      );
    }
    final first = start ?? 0;
    final last = end ?? browserFile.size;
    if (first < 0 || last < first || last > browserFile.size) {
      throw RangeError.range(last, first, browserFile.size, 'end');
    }
    var offset = first;
    while (offset < last) {
      final chunkEnd = min(offset + _readChunkSize, last);
      final buffer = await browserFile
          .slice(offset, chunkEnd)
          .arrayBuffer()
          .toDart;
      yield buffer.toDart.asUint8List();
      offset = chunkEnd;
    }
  }
}

Future<List<web.File>> _pickBrowserFiles({required bool allowMultiple}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.tif,.tiff,.txt'
    ..multiple = allowMultiple
    ..style.display = 'none';
  final completer = Completer<List<web.File>>();
  var finished = false;

  void finish(List<web.File> files) {
    if (finished) return;
    finished = true;
    input.remove();
    completer.complete(files);
  }

  input.onchange = ((web.Event _) {
    final files = input.files;
    if (files == null) {
      finish(const []);
      return;
    }
    final selected = <web.File>[];
    for (var index = 0; index < files.length; index++) {
      final file = files.item(index);
      if (file != null) selected.add(file);
    }
    finish(selected);
  }).toJS;
  input.oncancel = ((web.Event _) => finish(const [])).toJS;
  web.document.body?.append(input);
  input.click();
  return completer.future;
}

MicroscopeFileSource createMicroscopeFileSource() => WebMicroscopeFileSource();

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
