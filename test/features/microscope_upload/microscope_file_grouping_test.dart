import 'package:crystalapp/features/microscope_upload/models/microscope_file_set.dart';
import 'package:crystalapp/features/microscope_upload/services/microscope_file_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

MicroscopeLocalFile file(String name, [int size = 10]) =>
    MicroscopeLocalFile(path: '/tmp/$name', name: name, sizeBytes: size);

void main() {
  test('groups the required TIFF and TXT files by logical base name', () {
    final sets = groupMicroscopeFiles([
      file('Sample-001.tif'),
      file('Sample-001.txt'),
    ]);

    expect(sets, hasLength(1));
    expect(sets.single.logicalBaseName, 'Sample-001');
    expect(sets.single.selectionStatus, MicroscopeSetSelectionStatus.ready);
    expect(sets.single.files.keys, containsAll(MicroscopeFileRole.values));
  });

  test('matches case-insensitive TIFF and TXT extensions', () {
    final sets = groupMicroscopeFiles([
      file('Image-A.TIFF'),
      file('image-a.TXT'),
    ]);

    expect(sets, hasLength(1));
    expect(sets.single.selectionStatus, MicroscopeSetSelectionStatus.ready);
  });

  test('uses the dots-versus-spaces fallback after exact matching', () {
    final sets = groupMicroscopeFiles([
      file('MS.CN.IO.GM.60.MX Bag 001-1.tif'),
      file('MS CN IO GM 60 MX Bag 001-1.txt'),
    ]);

    expect(sets, hasLength(1));
    expect(sets.single.selectionStatus, MicroscopeSetSelectionStatus.ready);
  });

  test('never guesses when normalized names have competing roles', () {
    final sets = groupMicroscopeFiles([
      file('A.B.tif'),
      file('A B.tif'),
      file('A  B.txt'),
    ]);

    expect(sets, hasLength(1));
    expect(sets.single.selectionStatus, MicroscopeSetSelectionStatus.ambiguous);
    expect(sets.single.issues.single, contains('more than one'));
  });

  test('a later selection completes the existing row and preserves its id', () {
    final first = groupMicroscopeFiles([file('Sample-002.tif')]);
    final second = groupMicroscopeFiles([
      ...first.single.allFiles,
      file('Sample-002.txt'),
    ], existing: first);

    expect(
      first.single.selectionStatus,
      MicroscopeSetSelectionStatus.incomplete,
    );
    expect(second, hasLength(1));
    expect(second.single.selectionStatus, MicroscopeSetSelectionStatus.ready);
    expect(second.single.clientSetId, first.single.clientSetId);
  });

  test('groups 200 files into 100 complete rows', () {
    final files = <MicroscopeLocalFile>[];
    for (var index = 1; index <= 100; index++) {
      final stem = 'Sample-${index.toString().padLeft(3, '0')}';
      files.addAll([file('$stem.tif'), file('$stem.txt')]);
    }

    final stopwatch = Stopwatch()..start();
    final sets = groupMicroscopeFiles(files);
    stopwatch.stop();

    expect(sets, hasLength(100));
    expect(
      sets.every(
        (set) => set.selectionStatus == MicroscopeSetSelectionStatus.ready,
      ),
      isTrue,
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
  });
}
