import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/env.dart';
import '../../../../core/services/session_storage_service.dart';

/// Provider that exposes and manages the "Remember Login" setting.
///
/// When true: The user's session is stored persistently across browser restarts.
/// When false: The session is ephemeral (sessionStorage on web). Closing the tab
/// or exiting the website forgets the login immediately.
final rememberLoginProvider =
    AsyncNotifierProvider<RememberLoginNotifier, bool>(
      RememberLoginNotifier.new,
    );

class RememberLoginNotifier extends AsyncNotifier<bool> {
  @override
  FutureOr<bool> build() async {
    return SessionStorageService.isRememberLoginEnabled();
  }

  /// Toggles the current remember-login state.
  Future<void> toggle() async {
    final current = state.valueOrNull ?? true;
    await setRememberLogin(!current);
  }

  /// Sets remember-login to the specified [enabled] value and migrates active tokens.
  Future<void> setRememberLogin(bool enabled) async {
    state = AsyncData(enabled);
    final sessionKey = SessionStorageService.computeSessionKey(Env.supabaseUrl);
    await SessionStorageService.setRememberLogin(
      enabled,
      persistSessionKey: sessionKey,
    );
  }

  /// Instantly purges all local session tokens.
  Future<void> purgeLocalTokens() async {
    final sessionKey = SessionStorageService.computeSessionKey(Env.supabaseUrl);
    await SessionStorageService.purgeAllSessions(sessionKey);
  }
}
