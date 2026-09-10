import 'microscope_file_source_base.dart';
import 'microscope_file_source_stub.dart'
    if (dart.library.js_interop) 'microscope_file_source_web.dart'
    as platform;

export 'microscope_file_source_base.dart';

MicroscopeFileSource createMicroscopeFileSource() =>
    platform.createMicroscopeFileSource();
