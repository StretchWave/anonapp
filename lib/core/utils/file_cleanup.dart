import 'file_cleanup_stub.dart' if (dart.library.io) 'file_cleanup_io.dart';

/// Safely deletes a temporary file at [path] on native platforms,
/// safely doing nothing on web.
Future<void> deleteTempFile(String? path) => deleteTempFileImpl(path);
