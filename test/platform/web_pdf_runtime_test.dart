import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web index installs the pdf.js runtime required by pdfx', () {
    final index = File('web/index.html').readAsStringSync();
    final versions = RegExp(r'/pdfjs/(\d+\.\d+\.\d+)/')
        .allMatches(index)
        .map((match) => match.group(1))
        .whereType<String>()
        .toSet();

    expect(index, contains('/pdf.min.mjs'));
    expect(index, contains('GlobalWorkerOptions.workerSrc'));
    expect(index, contains('/pdf.worker.mjs'));
    expect(index, contains('pdfRenderOptions'));
    expect(versions, hasLength(1));
    final runtime = 'web/pdfjs/${versions.single}';
    expect(File('$runtime/pdf.min.mjs').lengthSync(), greaterThan(0));
    expect(File('$runtime/pdf.worker.mjs').lengthSync(), greaterThan(0));
    expect(Directory('$runtime/cmaps').listSync(), isNotEmpty);
    expect(index, isNot(contains('https://cdn.')));
  });
}
