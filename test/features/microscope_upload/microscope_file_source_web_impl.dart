import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:crystalapp/features/microscope_upload/services/microscope_file_source_web.dart';

void runWebMicroscopeFileSourceTests() {
  test(
    'hashes whole browser file and exact 8 MiB multipart ranges',
    () async {
      final data = Uint8List(8 * 1024 * 1024 + 37);
      for (var index = 0; index < data.length; index++) {
        data[index] = index % 251;
      }
      final browserFile = web.File(<JSAny>[data.toJS].toJS, 'Bag 120-002.tif');
      final source = WebMicroscopeFileSource(
        picker: ({required allowMultiple}) async => [browserFile],
      );

      final selected = await source.pickFiles();
      expect(selected, hasLength(1));
      expect(selected.single.path, startsWith('browser-file:'));
      expect(selected.single.name, 'Bag 120-002.tif');
      expect(selected.single.sizeBytes, data.length);

      final hashed = await source.hashFile(selected.single);
      expect(hashed.sha256, sha256.convert(data).toString());
      expect(hashed.multipartChecksums, [
        base64Encode(sha256.convert(data.sublist(0, 8 * 1024 * 1024)).bytes),
        base64Encode(sha256.convert(data.sublist(8 * 1024 * 1024)).bytes),
      ]);

      final firstRead = await source
          .openRead(
            selected.single,
            start: 8 * 1024 * 1024 - 5,
            end: 8 * 1024 * 1024 + 7,
          )
          .expand((chunk) => chunk)
          .toList();
      final repeatedRead = await source
          .openRead(
            selected.single,
            start: 8 * 1024 * 1024 - 5,
            end: 8 * 1024 * 1024 + 7,
          )
          .expand((chunk) => chunk)
          .toList();
      final expected = data.sublist(8 * 1024 * 1024 - 5, 8 * 1024 * 1024 + 7);
      expect(firstRead, expected);
      expect(repeatedRead, expected);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'releases browser file bindings when upload state is discarded',
    () async {
      final browserFile = web.File(
        <JSAny>[
          Uint8List.fromList([1, 2, 3]).toJS,
        ].toJS,
        'Sample.txt',
      );
      final source = WebMicroscopeFileSource(
        picker: ({required allowMultiple}) async => [browserFile],
      );
      final selected = (await source.pickFiles()).single;

      source.releaseFiles([selected]);

      await expectLater(
        source.openRead(selected).drain<void>(),
        throwsA(isA<StateError>()),
      );
    },
  );
}
