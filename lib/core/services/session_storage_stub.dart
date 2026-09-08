/// In-memory storage used for ephemeral sessions on non-web platforms (Dart VM)
/// or unit tests where window.sessionStorage is not available.
final Map<String, String> _ephemeralMemory = <String, String>{};

bool hasSessionItem(String key) => _ephemeralMemory.containsKey(key);

String? getSessionItem(String key) => _ephemeralMemory[key];

void setSessionItem(String key, String value) {
  _ephemeralMemory[key] = value;
}

void removeSessionItem(String key) {
  _ephemeralMemory.remove(key);
}

// Fallback stubs for localStorage on non-web
bool hasLocalItem(String key) => false;

String? getLocalItem(String key) => null;

void setLocalItem(String key, String value) {}

void removeLocalItem(String key) {}
