import 'package:web/web.dart' as web;

bool hasSessionItem(String key) {
  try {
    return web.window.sessionStorage.getItem(key) != null;
  } catch (_) {
    return false;
  }
}

String? getSessionItem(String key) {
  try {
    return web.window.sessionStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void setSessionItem(String key, String value) {
  try {
    web.window.sessionStorage.setItem(key, value);
  } catch (_) {}
}

void removeSessionItem(String key) {
  try {
    web.window.sessionStorage.removeItem(key);
  } catch (_) {}
}

bool hasLocalItem(String key) {
  try {
    return web.window.localStorage.getItem(key) != null;
  } catch (_) {
    return false;
  }
}

String? getLocalItem(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void setLocalItem(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}

void removeLocalItem(String key) {
  try {
    web.window.localStorage.removeItem(key);
  } catch (_) {}
}
