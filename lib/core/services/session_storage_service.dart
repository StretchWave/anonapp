import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_storage_stub.dart'
    if (dart.library.js_interop) 'session_storage_web.dart'
    as platform;

/// Service for managing remember-login preferences and session token storage.
///
/// When "Remember Login" is enabled (default), sessions are stored persistently
/// in browser localStorage (Web) or SharedPreferences (Mobile/Desktop).
///
/// When "Remember Login" is disabled, sessions are kept in ephemeral
/// sessionStorage (Web) or in-memory (Mobile/Desktop). As soon as the user
/// closes the browser tab or exits the website, the login is completely forgotten.
abstract final class SessionStorageService {
  /// Local key for saving the remember-login boolean preference.
  static const String rememberLoginKey = 'anonapp_remember_login';

  /// Computes the exact Supabase auth token session key based on project URL.
  static String computeSessionKey(String supabaseUrl) {
    try {
      final host = Uri.parse(supabaseUrl).host;
      final projectRef = host.split('.').first;
      return 'sb-$projectRef-auth-token';
    } catch (_) {
      return 'sb-anonapp-auth-token';
    }
  }

  /// Checks whether "Remember Login" is enabled (defaults to true).
  static Future<bool> isRememberLoginEnabled() async {
    if (kIsWeb) {
      final val = platform.getLocalItem(rememberLoginKey);
      if (val == null) return true;
      return val.toLowerCase() == 'true';
    } else {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(rememberLoginKey) ?? true;
    }
  }

  /// Synchronously checks if remember login is enabled on web if available.
  static bool isRememberLoginEnabledSync() {
    if (kIsWeb) {
      final val = platform.getLocalItem(rememberLoginKey);
      if (val == null) return true;
      return val.toLowerCase() == 'true';
    }
    return true;
  }

  /// Updates the "Remember Login" preference and migrates the active session.
  static Future<void> setRememberLogin(
    bool enabled, {
    required String persistSessionKey,
  }) async {
    if (kIsWeb) {
      platform.setLocalItem(rememberLoginKey, enabled.toString());
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(rememberLoginKey, enabled);

    if (enabled) {
      // Migrate from ephemeral to persistent storage
      if (kIsWeb) {
        final token = platform.getSessionItem(persistSessionKey);
        if (token != null && token.isNotEmpty) {
          platform.setLocalItem(persistSessionKey, token);
          platform.removeSessionItem(persistSessionKey);
        }
      } else {
        final token = platform.getSessionItem(persistSessionKey);
        if (token != null && token.isNotEmpty) {
          await prefs.setString(persistSessionKey, token);
          platform.removeSessionItem(persistSessionKey);
        }
      }
    } else {
      // Migrate from persistent to ephemeral storage
      if (kIsWeb) {
        final token = platform.getLocalItem(persistSessionKey);
        if (token != null && token.isNotEmpty) {
          platform.setSessionItem(persistSessionKey, token);
          platform.removeLocalItem(persistSessionKey);
        }
      } else {
        final token = prefs.getString(persistSessionKey);
        if (token != null && token.isNotEmpty) {
          platform.setSessionItem(persistSessionKey, token);
          await prefs.remove(persistSessionKey);
        }
      }
    }
  }

  /// Clears stored sessions from both persistent and ephemeral storage.
  static Future<void> purgeAllSessions(String persistSessionKey) async {
    if (kIsWeb) {
      platform.removeLocalItem(persistSessionKey);
      platform.removeSessionItem(persistSessionKey);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(persistSessionKey);
    platform.removeSessionItem(persistSessionKey);
  }
}

/// Custom [LocalStorage] implementation for Supabase that supports
/// both persistent and ephemeral sessions.
class AnonAppLocalStorage extends LocalStorage {
  AnonAppLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;
  SharedPreferences? _preferences;

  @override
  Future<void> initialize() async {
    if (!kIsWeb) {
      _preferences = await SharedPreferences.getInstance();
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    final remember = await SessionStorageService.isRememberLoginEnabled();
    if (kIsWeb) {
      if (remember) {
        return platform.hasLocalItem(persistSessionKey);
      } else {
        // In ephemeral mode: if there's an old persistent token, wipe it.
        if (platform.hasLocalItem(persistSessionKey)) {
          platform.removeLocalItem(persistSessionKey);
        }
        return platform.hasSessionItem(persistSessionKey);
      }
    } else {
      if (remember) {
        _preferences ??= await SharedPreferences.getInstance();
        return _preferences!.containsKey(persistSessionKey);
      } else {
        return platform.hasSessionItem(persistSessionKey);
      }
    }
  }

  @override
  Future<String?> accessToken() async {
    final remember = await SessionStorageService.isRememberLoginEnabled();
    if (kIsWeb) {
      if (remember) {
        return platform.getLocalItem(persistSessionKey);
      } else {
        return platform.getSessionItem(persistSessionKey);
      }
    } else {
      if (remember) {
        _preferences ??= await SharedPreferences.getInstance();
        return _preferences!.getString(persistSessionKey);
      } else {
        return platform.getSessionItem(persistSessionKey);
      }
    }
  }

  @override
  Future<void> removePersistedSession() async {
    if (kIsWeb) {
      platform.removeLocalItem(persistSessionKey);
      platform.removeSessionItem(persistSessionKey);
    } else {
      _preferences ??= await SharedPreferences.getInstance();
      await _preferences!.remove(persistSessionKey);
      platform.removeSessionItem(persistSessionKey);
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    final remember = await SessionStorageService.isRememberLoginEnabled();
    if (kIsWeb) {
      if (remember) {
        platform.setLocalItem(persistSessionKey, persistSessionString);
        platform.removeSessionItem(persistSessionKey);
      } else {
        // Ephemeral: only stored in sessionStorage, never in localStorage!
        platform.setSessionItem(persistSessionKey, persistSessionString);
        platform.removeLocalItem(persistSessionKey);
      }
    } else {
      if (remember) {
        _preferences ??= await SharedPreferences.getInstance();
        await _preferences!.setString(persistSessionKey, persistSessionString);
        platform.removeSessionItem(persistSessionKey);
      } else {
        platform.setSessionItem(persistSessionKey, persistSessionString);
        _preferences ??= await SharedPreferences.getInstance();
        await _preferences!.remove(persistSessionKey);
      }
    }
  }
}
