import 'dart:io';

/// Native (Android, iOS, macOS, Windows, Linux) implementation of file deletion.
Future<void> deleteTempFileImpl(String? path) async {
  if (path == null || path.isEmpty) return;
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Ignore errors if file doesn't exist or is already locked/deleted
  }
}
