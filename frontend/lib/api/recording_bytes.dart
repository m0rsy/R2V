// Reads the bytes of a recording produced by the `record` package.
//
// On native platforms `record` writes to a file path; on web it returns a
// `blob:` URL. The conditional import picks the right implementation so
// `dart:io` never reaches the web build.
export 'recording_bytes_io.dart'
    if (dart.library.html) 'recording_bytes_web.dart';
