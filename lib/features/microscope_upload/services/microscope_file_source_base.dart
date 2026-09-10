import '../models/microscope_file_set.dart';

abstract class MicroscopeFileSource {
  Future<List<MicroscopeLocalFile>> pickFiles({bool allowMultiple = true});

  Future<MicroscopeLocalFile> hashFile(MicroscopeLocalFile file);

  Stream<List<int>> openRead(MicroscopeLocalFile file, {int? start, int? end});

  void releaseFiles(Iterable<MicroscopeLocalFile> files) {}
}
