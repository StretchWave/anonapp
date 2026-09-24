import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/foreground_service.dart';
import '../../../../core/services/presence/presence_provider.dart';
import '../../../../core/services/push_notification_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../data/auth_repository_impl.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/repositories/auth_repository.dart';

/// Provides the [AuthRepository] singleton.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AuthRepositoryImpl(client);
});

/// Stream of authentication state (true = authenticated).
final authStateProvider = StreamProvider<bool>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges();
});

/// The current user's profile, refreshed on auth state change.
final currentProfileProvider = FutureProvider<UserProfile?>((ref) async {
  // Re-fetch whenever auth state changes.
  ref.watch(authStateProvider);
  final repo = ref.watch(authRepositoryProvider);
  return repo.getCurrentProfile();
});

/// Notifier that handles sign-up / sign-in / sign-out mutations.
final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, UserProfile?>(
  AuthNotifier.new,
);

class AuthNotifier extends AsyncNotifier<UserProfile?> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  FutureOr<UserProfile?> build() async {
    return _repo.getCurrentProfile();
  }

  /// Sign up and set state.
  Future<void> signUp({
    required String username,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repo.signUp(username: username, password: password),
    );
  }

  /// Sign in and set state.
  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repo.signIn(username: username, password: password),
    );
  }

  /// Sign out and clear state.
  Future<void> signOut() async {
    try {
      final client = ref.read(supabaseClientProvider);
      final userId = client.auth.currentUser?.id;
      if (userId != null) {
        await PushNotificationService.instance.deactivateDevice(client, userId);
      }
      await AppForegroundService.instance.stop();
      await ref.read(presenceServiceProvider).setOffline();
      await ref.read(presenceServiceProvider).disposeChannelOnly();
    } catch (_) {}
    await _repo.signOut();
    state = const AsyncData(null);
  }
}

/// Provider to check username availability.
final usernameAvailabilityProvider = FutureProvider.family<bool, String>((
  ref,
  username,
) async {
  if (username.length < 3) return true; // Too short, don't check yet.
  final repo = ref.watch(authRepositoryProvider);
  final taken = await repo.isUsernameTaken(username);
  return !taken; // true = available
});
