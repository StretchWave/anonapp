/// Web / fallback implementation of temporary file deletion.
Future<void> deleteTempFileImpl(String? path) async {
  // No-op on platforms without a direct file system (e.g. Web).
}
