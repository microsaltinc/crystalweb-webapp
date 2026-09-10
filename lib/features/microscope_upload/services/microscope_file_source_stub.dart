import '../models/microscope_file_set.dart';
import 'microscope_file_source_base.dart';

class UnsupportedMicroscopeFileSource implements MicroscopeFileSource {
  Never _unsupported() => throw UnsupportedError(
    'Direct microscope upload requires the browser runtime.',
  );

  @override
  Future<List<MicroscopeLocalFile>> pickFiles({bool allowMultiple = true}) =>
      _unsupported();

  @override
  Future<MicroscopeLocalFile> hashFile(MicroscopeLocalFile file) =>
      _unsupported();

  @override
  void releaseFiles(Iterable<MicroscopeLocalFile> files) {}

  @override
  Stream<List<int>> openRead(
    MicroscopeLocalFile file, {
    int? start,
    int? end,
  }) => _unsupported();
}

MicroscopeFileSource createMicroscopeFileSource() =>
    UnsupportedMicroscopeFileSource();
